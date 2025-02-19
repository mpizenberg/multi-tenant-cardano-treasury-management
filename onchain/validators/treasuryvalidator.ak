use aiken/builtin
use aiken/collection/list
use aiken/crypto.{Blake2b_256, Hash}
use cardano/address.{Credential, Script, VerificationKey}
use cardano/assets.{AssetName, PolicyId, Value}
use cardano/certificate.{Certificate}
use cardano/governance.{ProposalProcedure, Voter}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction,
}
use cred.{Badge, KeySignature, ScriptWithdrawal, TokenProof}
use treasury

pub type Datum {
  previous_input_index: Int,
  scope: treasury.Scope,
}

pub type Redeemer {
  /// List of badges presented in the redeemer.
  /// The list may contain variants granting the same permissions,
  /// so their count is not sufficient to check for all owners credentials.
  presented_badges: List<Badge>,
  /// Index of the input being spent.
  spent_input_index: Int,
  /// Index of the next output to be created.
  next_output_index: Int,
  /// Action to be performed.
  action: Action,
}

pub type Action {
  rationale: Rationale,
  action_type: ActionType,
}

pub type ActionType {
  Spend(treasury.Spending)
}

pub type Rationale {
  url: String,
  hash: Hash<Blake2b_256, ByteArray>,
}

validator placeholder {
  mint(_redeemer: Data, _policy_id: PolicyId, _tx: Transaction) {
    fail
  }

  spend(
    datum: Option<Datum>,
    Redeemer { presented_badges, spent_input_index, next_output_index, action }: Redeemer,
    utxo: OutputReference,
    tx: Transaction,
  ) {
    // Check that all presented badges are valid
    list.for_each(presented_badges, check_badge(tx, _))

    // TODO: Count the number of scope owners having presented a badge.
    // If all present, anything is allowed.
    // Above a certain threshold, a contestation period starts.
    // After repeated contestations, the threshold is enough to unblock the situation.
    //
    // Otherwise, in the normal case
    when datum is {
      None -> todo @"handle logic with no datum"
      Some(old_datum) -> {
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

        // Make sure the new utxo links to the previous utxo (prevent double satisfaction)
        expect Datum { previous_input_index, scope } = new_datum
        expect previous_input_index == spent_input_index

        when action.action_type is {
          Spend(spending) -> {
            // Check that the value difference matches the spending amount
            let value_spent = from_assets_with_zeros(spending.amounts)
            expect assets.merge(new_value, value_spent) == spent_output.value

            // Check all other spending rules
            treasury.spend(
              presented_badges,
              spending,
              tx.validity_range,
              old_datum.scope,
              scope,
            )
          }
        }
      }
    }
  }

  withdraw(_redeemer: Data, _account: Credential, _tx: Transaction) {
    todo @"withdraw logic goes here"
  }

  publish(_redeemer: Data, _certificate: Certificate, _tx: Transaction) {
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

/// Check that all presented badges are valid.
/// Doesn’t check that they are also part of the scope owners, just valid.
fn check_badge(tx: Transaction, badge: Badge) {
  // The following code is checked for each badge
  when badge is {
    KeySignature { token, key } -> {
      // Check that the key signature is present
      expect list.has(tx.extra_signatories, key)
      // When a token is presented, check its legitimacy
      when token is {
        None -> Void
        Some(token_proof) -> {
          let cred <- check_token_legitimacy(tx, token_proof)
          cred == VerificationKey(key)
        }
      }
    }
    ScriptWithdrawal { token, script_hash, withdrawal_index } -> {
      // Check that the script withdrawal is legitimate to validate the script
      expect Some(withdrawal) = list.at(tx.withdrawals, withdrawal_index)
      expect Script(withdrawal_script_hash) = builtin.fst_pair(withdrawal)
      expect withdrawal_script_hash == script_hash
      // When a token is presented, check its legitimacy
      when token is {
        None -> Void
        Some(token_proof) -> {
          let cred <- check_token_legitimacy(tx, token_proof)
          cred == Script(script_hash)
        }
      }
    }
  }
}

/// Check that the token is legitimate:
/// - located in the advertised reference input
/// - with the correct policy ID
/// - owned by the advertised credential
fn check_token_legitimacy(
  tx: Transaction,
  token: TokenProof,
  check_payment_cred: fn(Credential) -> Bool,
) -> Void {
  // Extract the ref input at the given index
  expect Some(Input { output, .. }) =
    list.at(tx.reference_inputs, token.ref_input_index)
  // Check that the ref input contains the token
  expect list.has(assets.policies(output.value), token.policy_id)
  // Check that the ref input is owned by the correct credential
  expect check_payment_cred(output.address.payment_credential)
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
