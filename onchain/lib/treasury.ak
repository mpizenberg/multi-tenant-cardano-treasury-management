use aiken/collection/list
use aiken/crypto.{ScriptHash}
use aiken/interval.{Finite, Interval, IntervalBound}
use cardano/address.{Script}
use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{InlineDatum, Input, Output, Transaction, ValidityRange}
use cred.{Badge, ScopeOwnerCred}
use env

// Treasury

pub type SpendDatum {
  previous_input_index: Option<Int>,
  scope: Scope,
}

/// One scope of the multi-tenant treasury
pub type Scope {
  // TODO: probably possible to remove name?
  name: ByteArray,
  owner: ScopeOwnerCred,
  budget_configs: List<(PolicyId, List<(AssetName, BudgetConfig)>)>,
}

/// Budget configuration for each token.
/// For example, the config for Ada, or for USDM.
///
/// For each token, the budget config specifies the rolling net limit amount and duration.
/// It also keeps track of recent withdrawals to enforce the rolling net limit.
pub type BudgetConfig {
  rolling_net_limit_amount: Int,
  rolling_net_limit_duration_milliseconds: Int,
  recent_withdrawals: List<Withdrawal>,
}

/// One withdrawal from the treasury.
/// It contains the amount withdrawn and when it happened (within a range).
pub type Withdrawal {
  amount: Int,
  validity_range: FiniteValidityRange,
}

/// Validity range with finite bounds.
pub type FiniteValidityRange {
  lower_bound: Int,
  upper_bound: Int,
}

/// Authentication data for a scope UTxO.
/// This can either be for a scope UTxO being spent or referenced.
/// When the new output is "None", we consider the input
pub type ScopeAuth {
  /// Badge specifying how to check the scope owner's credentials.
  badge: Badge,
  /// Index of the input (spent or ref) for the scope UTxO
  scope_input_index: InputIndex,
}

pub type InputIndex {
  SpentIndex(Int)
  RefIndex(Int)
}

// Initialization

/// Check that the output containing the root treasury NFT
/// at the treasury initialization is valid.
pub fn validate_root_output(
  scope_names: List<ByteArray>,
  output: Output,
  policy_id: PolicyId,
) {
  // Check that the output address is the treasury address
  expect output.address.payment_credential == Script(policy_id)

  // Check that the stake credential is empty if not allowed to stake
  expect output.address.stake_credential == None || env.stake_allowed

  // Check that the ref script is stored in the root output
  expect output.reference_script == Some(policy_id)

  // Check that the output contains only some ada and the root NFT
  let expected_value =
    assets.from_lovelace(env.root_min_ada)
      |> assets.add(policy_id, env.root_asset_name, 1)
  expect output.value == expected_value

  // Check that the datum contains the scope names
  expect InlineDatum(data) = output.datum
  let scope_names_as_data: Data = scope_names
  expect scope_names_as_data == data
}

/// Check that the output containing this scope NFT
/// at the treasury initialization is valid.
pub fn validate_scope_initialization(
  scope: Scope,
  output: Output,
  policy_id: PolicyId,
) {
  // Check that the output address is the treasury address
  expect output.address.payment_credential == Script(policy_id)

  // Check that the stake credential is empty if not allowed to stake
  expect output.address.stake_credential == None || env.stake_allowed

  // Check that there is no ref script in the output
  expect output.reference_script == None

  // Check that the output contains only some ada and the NFT for the scope
  let expected_value =
    assets.from_lovelace(env.scope_min_ada)
      |> assets.add(policy_id, scope.name, 1)
  expect output.value == expected_value

  // Check that the datum is exactly this scope
  let scope_as_datum: Data = SpendDatum { previous_input_index: None, scope }
  expect InlineDatum(data) = output.datum
  expect data == scope_as_datum
}

// Checking authentication

/// Check that the provided badge is valid and matches the corresponding scope credential.
/// If credential is OK, call a continuation function with further checks,
/// with the scope output and scope value as parameters.
///
/// Remark: the scope output would have been enough,
/// but we also provide the scope itself to avoid the caller to have to extract it again.
pub fn check_auth(
  auth: ScopeAuth,
  tx: Transaction,
  script_hash: ScriptHash,
  further_checks: fn(Output, Scope) -> a,
) -> a {
  let ScopeAuth { badge, scope_input_index } = auth

  // Extract the output for the UTxO at the input index
  expect Some(Input { output: scope_output, .. }) =
    when scope_input_index is {
      RefIndex(idx) -> list.at(tx.reference_inputs, idx)
      SpentIndex(idx) -> list.at(tx.inputs, idx)
    }

  // Check that the utxo at the input index is at the script address
  expect Script(scope_cred) = scope_output.address.payment_credential
  expect scope_cred == script_hash

  // Extract the scope owner cred from that utxo datum
  expect InlineDatum(scope_datum) = scope_output.datum
  expect SpendDatum { scope, .. } = scope_datum

  // Check that the utxo at the input index contains the scope nft (check asset name)
  expect assets.quantity_of(scope_output.value, script_hash, scope.name) == 1

  // Check that the presented badge is valid and matches the scope owner credential
  cred.check_badge_validity(tx, badge)
  expect cred.badge_matches_owner(scope.owner, badge)

  // Call the continuation function
  further_checks(scope_output, scope)
}

// Actions

pub type Spending {
  /// same size as budget_configs (including zeros)
  amounts: List<(PolicyId, List<(AssetName, Int)>)>,
}

const max_validity_range_1_day = 1000 * 3600 * 24

/// Spending verification logic of the Treasury
pub fn spend(
  /// Scope owners who have presented valid badges
  active_scope_owners: List<ScopeOwnerCred>,
  Spending { amounts }: Spending,
  Interval { lower_bound, upper_bound }: ValidityRange,
  Scope { name, owner, budget_configs: old_budgets }: Scope,
  Scope { name: new_name, owner: new_owner, budget_configs: new_budgets }: Scope,
) -> Bool {
  // Check that this scope owner is present in the active scope owners list
  expect list.has(active_scope_owners, owner)

  // Check that validity range is shorter than 1 full day,
  // to prevent time manipulation attack of the rolling net limit.
  expect IntervalBound { bound_type: Finite(lower_bound), .. } = lower_bound
  expect IntervalBound { bound_type: Finite(upper_bound), .. } = upper_bound
  expect upper_bound > lower_bound
  expect upper_bound - lower_bound <= max_validity_range_1_day

  // The scope name and owner must match
  expect name == new_name
  expect owner == new_owner

  // Spending amounts and budget configs must have the same length
  let spend_len = list.length(amounts)
  let old_len = list.length(old_budgets)
  let new_len = list.length(new_budgets)
  expect spend_len == old_len && old_len == new_len

  // Spendings for each token must follow the treasury rules
  let _ = {
    let
      (spend_policy, spend_assets),
      (old_policy, old_assets),
      (new_policy, new_assets),
    <- list.map3(amounts, old_budgets, new_budgets)
    expect spend_policy == old_policy && old_policy == new_policy
    let
      (spend_asset, spend_amount),
      (old_asset, old_budget),
      (new_asset, new_budget),
    <- list.map3(spend_assets, old_assets, new_assets)
    expect spend_asset == old_asset && old_asset == new_asset
    check_token_spending(
      active_scope_owners,
      FiniteValidityRange { lower_bound, upper_bound },
      spend_amount,
      old_budget,
      new_budget,
    )
  }

  True
}

/// Spending validation
///
/// Check that the spending amount is within the budget config limits.
/// In that case, only the owner credential is required.
/// Otherwise, all scope owners credentials are required.
///
/// The spending amount, when added to the recent withdrawals within the rolling window,
/// must not exceed the budget rolling net limit.
fn check_token_spending(
  /// Scope owners who have presented valid badges
  active_scope_owners: List<ScopeOwnerCred>,
  validity_range: FiniteValidityRange,
  spending_amount: Int,
  old_config: BudgetConfig,
  new_config: BudgetConfig,
) {
  // Extract the old and new budget config limits
  let BudgetConfig {
    rolling_net_limit_amount: limit_amount,
    rolling_net_limit_duration_milliseconds: limit_duration,
    recent_withdrawals,
  } = old_config
  let BudgetConfig {
    rolling_net_limit_amount: new_limit_amount,
    rolling_net_limit_duration_milliseconds: new_limit_duration,
    recent_withdrawals: new_recent_withdrawals,
  } = new_config

  // Check that the budget config limits have not changed
  expect limit_amount == new_limit_amount
  expect limit_duration == new_limit_duration

  // Check that the new_recent_withdrawals is correct:
  //  - contains exactly all withdrawals within the rolling window
  //  - with the most recent withdrawal first, if non-zero
  let cutoff_time = validity_range.lower_bound - limit_duration
  let old_withdrawals_dropped: List<Withdrawal> = {
    let head, accum <- list.foldr(recent_withdrawals, [])
    if head.validity_range.upper_bound >= cutoff_time {
      [head, ..accum]
    } else {
      accum
    }
  }
  if spending_amount == 0 {
    expect new_recent_withdrawals == old_withdrawals_dropped
  } else {
    expect
      new_recent_withdrawals == [
        Withdrawal { amount: spending_amount, validity_range },
        ..old_withdrawals_dropped
      ]
  }

  // Check spending amount against budget limits,
  // proportionally to the number of scope owners who signed the transaction.
  // TODO: proportional spending may result in losses that are square
  // the number of compromised credentials,
  // so maybe a majority check is better up to 2x,
  // then a unanimous signature for anything above that.
  expect spending_amount >= 0
  let owners_count = list.length(active_scope_owners)
  let rolling_spending =
    list.foldl(new_recent_withdrawals, 0, fn(w, acc) { acc + w.amount })
  rolling_spending <= owners_count * limit_amount
}
