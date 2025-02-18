use aiken/collection/list
use aiken/crypto.{Blake2b_256, Hash}
use cardano/address.{Credential}
use cardano/assets.{AssetName, PolicyId, Value}
use cardano/certificate.{Certificate}
use cardano/governance.{ProposalProcedure, Voter}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction,
}
use cred.{PresentedCred}
use treasury.{Scope, Spending}

pub type Datum {
  previous_input_index: Int,
  scope: Scope,
}

pub type Redeemer {
  presented_credentials: List<PresentedCred>,
  spent_input_index: Int,
  next_output_index: Int,
  action: Action,
}

pub type Action {
  rationale: Rationale,
  action_type: ActionType,
}

pub type ActionType {
  Spend(Spending)
}

pub type Rationale {
  url: String,
  hash: Hash<Blake2b_256, ByteArray>,
}

validator placeholder {
  mint(_redeemer: Data, _policy_id: PolicyId, _self: Transaction) {
    fail
  }

  spend(
    datum: Option<Datum>,
    Redeemer {
      presented_credentials,
      spent_input_index,
      next_output_index,
      action,
    }: Redeemer,
    utxo: OutputReference,
    self: Transaction,
  ) {
    // Check that all presented credentials are valid
    check_presented_credentials(presented_credentials)

    when datum is {
      None -> todo @"handle logic with no datum"
      Some(old_datum) -> {
        // Retrieve the consumed output
        expect Some(Input { output_reference, output: spent_output }) =
          list.at(self.inputs, spent_input_index)
        expect output_reference == utxo

        // Make sure the new utxo stays at the same address
        expect Some(Output {
          address,
          value: new_value,
          datum: InlineDatum(new_datum),
          ..
        }) = list.at(self.outputs, next_output_index)
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
              presented_credentials,
              spending,
              self.validity_range,
              old_datum.scope,
              scope,
            )
          }
        }
      }
    }
  }

  withdraw(_redeemer: Data, _account: Credential, _self: Transaction) {
    todo @"withdraw logic goes here"
  }

  publish(_redeemer: Data, _certificate: Certificate, _self: Transaction) {
    todo @"publish logic goes here"
  }

  vote(_redeemer: Data, _voter: Voter, _self: Transaction) {
    todo @"vote logic goes here"
  }

  propose(_redeemer: Data, _proposal: ProposalProcedure, _self: Transaction) {
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

/// Check that all presented credentials are valid.
fn check_presented_credentials(credentials: List<PresentedCred>) {
  let cred <- list.for_each(credentials)
  todo @"Check that cred is valid"
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
