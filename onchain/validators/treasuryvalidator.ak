use aiken/collection/dict
use aiken/collection/list
use aiken/collection/pairs
use aiken/crypto.{Blake2b_256, Hash}
use aiken/primitive/string
use cardano/address.{Credential, Script}
use cardano/assets.{AssetName, PolicyId, Value}
use cardano/certificate.{Certificate, RegisterCredential, UnregisterCredential}
use cardano/governance.{ProposalProcedure, Voter}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction,
}
use cred.{Badge}
use env
use treasury

// Initialization ----------------------------------------------------

pub type InitialMintRedeemer {
  scopes: List<treasury.Scope>,
  register_cert_index: Int,
}

pub type WithdrawRedeemer {
  /// Index of the ref input containing the treasury root NFT.
  root_ref_index: Int,
  /// Action to be performed.
  action_type: WithdrawActionType,
}

pub type WithdrawActionType {
  FundingViaWithdrawal(List<ScopeFunding>)
}

pub type ScopeFunding {
  /// Index of the spent input for the scope UTxO
  spent_index: Int,
  /// Index of the newly created output for the scope UTxO
  new_output_index: Int,
  /// Badge specifying how to check the owner's credentials.
  badge: Badge,
}

// Spending ----------------------------------------------------------

pub type SpendRedeemer {
  /// List of badges presented in the redeemer.
  /// The list may contain variants granting the same permissions,
  /// so their count is not sufficient to check for all owners credentials.
  presented_badges: List<Badge>,
  /// Index of the ref input containing the treasury root NFT.
  root_ref_index: Int,
  /// Index of the input being spent.
  spent_input_index: Int,
  /// Index of the next output to be created.
  next_output_index: Int,
  /// Rationale for the action.
  rationale: Rationale,
  /// Action to be performed.
  action_type: SpendActionType,
}

pub type SpendActionType {
  /// Normal spending.
  Spend(treasury.Spending)
  /// Start recovering funds with a contestation period.
  StartRecover
}

pub type Rationale {
  url: String,
  hash: Hash<Blake2b_256, ByteArray>,
}

// Recovery ----------------------------------------------------------

type RecoveryDatum {
  /// Index of the previous input being spent.
  previous_input_index: Int,
  /// Counter for the number of times the recovery process was contested.
  contestation_count: Int,
}

type ContestationDatum {
  /// Index of the previous input being spent.
  previous_input_index: Int,
  /// Counter for the number of times the recovery process was contested.
  contestation_count: Int,
}

// Validator ---------------------------------------------------------

/// Apply a function to the zipped list created from the two lists.
fn for_each_2(l1: List<a>, l2: List<b>, do: fn(a, b) -> Void) {
  // TODO: optimize this function
  let zipped = list.zip(l1, l2)
  list.for_each(zipped, fn((x1, x2)) { do(x1, x2) })
}

validator placeholder(initialization_utxo_ref: OutputReference) {
  mint(redeemer: InitialMintRedeemer, policy_id: PolicyId, tx: Transaction) {
    // Check that the initialization UTXO is spent
    expect
      list.any(
        tx.inputs,
        fn(input) { input.output_reference == initialization_utxo_ref },
      )

    // Check that the script is also registered
    let InitialMintRedeemer { scopes, register_cert_index } = redeemer
    expect Some(RegisterCredential { credential: Script(script_hash), .. }) =
      list.at(tx.certificates, register_cert_index)
    expect script_hash == policy_id

    // Check that scope names are unique
    // TODO: optimize this check
    let scope_names = list.map(scopes, fn(scope) { scope.name })
    expect list.length(scope_names) == list.length(list.unique(scope_names))

    // Check that the first output contains the main treasury NFT.
    expect [output_0, ..other_outputs] = tx.outputs
    treasury.validate_root_output(scope_names, output_0, policy_id)

    // Check that other outputs contain each one of the scopes
    let _ = {
      let scope, output <- for_each_2(scopes, other_outputs)
      treasury.validate_scope_initialization(scope, output, policy_id)
    }

    // Check that only the expected NFTs are minted.
    let minted = assets.tokens(tx.mint, policy_id)
    let just_root = dict.insert(dict.empty, env.root_asset_name, 1)
    let expected_mint = {
      let scope_name, dict_acc <- list.foldl(scope_names, just_root)
      dict.insert(dict_acc, string.to_bytearray(scope_name), 1)
    }
    minted == expected_mint
  }

  spend(
    datum: Option<treasury.SpendDatum>,
    SpendRedeemer {
      presented_badges,
      root_ref_index,
      spent_input_index,
      next_output_index,
      action_type,
      ..
    }: SpendRedeemer,
    utxo: OutputReference,
    tx: Transaction,
  ) {
    // Check that all presented badges are valid.
    // Does not check that the badge is owned by the scope owner,
    // just that the presented credentials are indeed verified in the Tx.
    list.for_each(presented_badges, cred.check_badge_validity(tx, _))

    // Retrieve the consumed output
    expect Some(Input { output_reference, output: spent_output }) =
      list.at(tx.inputs, spent_input_index)
    expect output_reference == utxo

    // Retrieve the script hash of the treasury validator
    expect Script(script_hash) = spent_output.address.payment_credential

    // Retrieve scope owners credentials from the treasury root.
    // TODO: complete credentials check, move it to the withdraw validator
    expect Some(Input { output: root_output, .. }) =
      list.at(tx.reference_inputs, root_ref_index)
    expect
      assets.quantity_of(root_output.value, script_hash, env.root_asset_name) == 1

    // Keep scope owners having presented a badge.
    let active_scope_owners =
      list.filter(
        env.scope_owners,
        cred.owner_badge_is_presented(_, presented_badges),
      )

    // If all scope owners are present, anything is allowed.
    if active_scope_owners == env.scope_owners {
      True
    } else {
      when datum is {
        None ->
          // If no datum is present, for example due to a send mistake,
          // the only action authorized is to recover the funds,
          // with a certain threshold and a contestation period.
          // After repeated contestations, the threshold is enough to unblock the situation.
          todo @"recover the funds"
        Some(old_datum) -> {
          // Make sure the new utxo stays at the same address
          expect Some(Output {
            address,
            value: new_value,
            datum: InlineDatum(new_datum),
            ..
          }) = list.at(tx.outputs, next_output_index)
          expect address == spent_output.address

          // Make sure the new utxo links to the previous utxo (prevent double satisfaction)
          expect treasury.SpendDatum { previous_input_index, scope } = new_datum
          expect previous_input_index == Some(spent_input_index)

          when action_type is {
            Spend(spending) -> {
              // Check that the value difference matches the spending amount
              let value_spent = from_assets_with_zeros(spending.amounts)
              expect assets.merge(new_value, value_spent) == spent_output.value

              // Check all other spending rules
              treasury.spend(
                active_scope_owners,
                spending,
                tx.validity_range,
                old_datum.scope,
                scope,
              )
            }
            // When starting to recover funds, only the UTxO to recover is needed.
            // The goal is to move the utxo into a new one with a dedicated datum,
            // indicating it is supposed to be recovered after the contestation period.
            // Later, after the contestation period has passed,
            // the recovered funds need to be merged into one scope.
            StartRecover -> {
              // Retrieve the consumed output
              expect Some(Input { output_reference, output: spent_output }) =
                list.at(tx.inputs, spent_input_index)
              expect output_reference == utxo

              // Make sure the new utxo stays at the same address
              expect Some(Output {
                address,
                value: new_value,
                datum: InlineDatum(new_datum),
                ..
              }) = list.at(tx.outputs, next_output_index)
              expect address == spent_output.address

              // Make sure the new value is the same as the old one
              expect new_value == spent_output.value

              // Make sure the new datum is a RecoveryDatum
              todo @"recover logic goes here"
            }
          }
        }
      }
    }
  }

  withdraw(
    WithdrawRedeemer { root_ref_index, action_type }: WithdrawRedeemer,
    account: Credential,
    tx: Transaction,
  ) {
    // Retrieve the script hash
    expect Script(script_hash) = account

    // Retrieve the root treasury utxo containing the root NFT
    expect Some(Input { output: root_output, .. }) =
      list.at(tx.reference_inputs, root_ref_index)
    expect
      assets.quantity_of(root_output.value, script_hash, env.root_asset_name) == 1

    // Retrieve the lovelace amount withdrawn
    expect Some(withdrawn_amount) = pairs.get_first(tx.withdrawals, account)

    when action_type is {
      FundingViaWithdrawal(scope_fundings) -> {
        // Retrieve the list of scope names from the root datum
        expect InlineDatum(root_datum) = root_output.datum
        expect scope_names: List<String> = root_datum

        // Check that all scope owners have signed the transaction
        // Also compute the ada amount sent to each scope
        expect list.length(scope_fundings) == list.length(scope_names)
        let fundings_per_scope: List<Int> = {
          let scope_name, funding <- list.map2(scope_names, scope_fundings)
          let ScopeFunding { spent_index, new_output_index, badge } = funding

          // Check that the utxo at the spent index contains the scope nft (check asset name)
          expect Some(Input { output: scope_output, .. }) =
            list.at(tx.inputs, spent_index)
          let asset_name = string.to_bytearray(scope_name)
          expect
            assets.quantity_of(scope_output.value, script_hash, asset_name) == 1

          // Check that the utxo at the spent index is at the script address
          expect Script(scope_cred) = scope_output.address.payment_credential
          expect scope_cred == script_hash

          // Extract the scope owner cred from that utxo datum
          expect InlineDatum(scope_datum) = scope_output.datum
          expect treasury.SpendDatum { scope, .. } = scope_datum

          // Check that the presented badge is valid and matches the scope owner credential
          cred.check_badge_validity(tx, badge)
          expect cred.badge_matches_owner(scope.owner, badge)

          // Retrieve the new scope output
          expect Some(new_scope_output) = list.at(tx.outputs, new_output_index)

          // Check that the address stays the same
          expect new_scope_output.address == scope_output.address

          // Check that the new datum points to the old scope UTxO
          expect InlineDatum(new_scope_datum) = new_scope_output.datum
          expect treasury.SpendDatum { previous_input_index, scope: new_scope } =
            new_scope_datum
          expect previous_input_index == Some(spent_index)

          // Check that the new datum preserves the scope
          expect new_scope == scope

          // Check that there is no ref script
          expect new_scope_output.reference_script == None

          // Compute the value difference (must only be Ada)
          expect assets.match(new_scope_output.value, scope_output.value, >=)
          let previous_ada = assets.lovelace_of(scope_output.value)
          let new_ada = assets.lovelace_of(new_scope_output.value)
          new_ada - previous_ada
        }
        // Check that the withdrawn amount corresponds to the value difference
        let scope_value_diff = list.foldl(fundings_per_scope, 0, +)
        scope_value_diff == withdrawn_amount
      }
    }
  }

  publish(_redeemer: Data, certificate: Certificate, tx: Transaction) {
    when certificate is {
      RegisterCredential { .. } -> {
        // Registering can only be done at initialization
        expect
          list.any(
            tx.inputs,
            fn(input) { input.output_reference == initialization_utxo_ref },
          )
      }
      UnregisterCredential { .. } -> todo @"other publish logic goes here"
      _ -> todo @"unregister when the treasury is closed or its address changes"
    }

    todo @"publish logic goes here"
  }

  vote(_redeemer: Data, _voter: Voter, _tx: Transaction) {
    todo @"vote logic goes here"
  }

  propose(_redeemer: Data, _proposal: ProposalProcedure, _tx: Transaction) {
    todo @"propose logic goes here"
  }

  // // If needs be, remove any of unneeded handlers above, and use:
  //
  // else(_ctx: ScriptContext) {
  //   todo @"fallback logic if none of the other purposes match"
  // }
  //
  // // You will also need an additional import:
  // //
  // // use cardano/script_context.{ScriptContext}
}

/// Convert a list of assets into a Value.
/// Contrary to the assets.from_asset_list function,
/// this function allows for zero amounts in the input list.
fn from_assets_with_zeros(
  amounts: List<(PolicyId, List<(AssetName, Int)>)>,
) -> Value {
  let flattened: List<(PolicyId, AssetName, Int)> = {
    let (policy_id, assets) <- list.flat_map(amounts)
    let (asset_name, amount) <- list.map(assets)
    (policy_id, asset_name, amount)
  }
  list.foldl(
    flattened,
    assets.zero,
    fn((policy_id, asset_name, amount), acc) {
      assets.add(acc, policy_id, asset_name, amount)
    },
  )
}
