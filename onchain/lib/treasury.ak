use aiken/collection/list
use aiken/interval.{Finite, Interval, IntervalBound}
use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{ValidityRange}
use cred.{ScopeOwnerCred}

// Treasury

/// One scope of the multi-tenant treasury
pub type Scope {
  name: String,
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
  expect spending_amount >= 0
  let owners_count = list.length(active_scope_owners)
  let rolling_spending =
    list.foldl(new_recent_withdrawals, 0, fn(w, acc) { acc + w.amount })
  rolling_spending <= owners_count * limit_amount
}
