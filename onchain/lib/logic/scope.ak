use aiken/collection/dict
use aiken/collection/list
use aiken/crypto.{ScriptHash}
use cardano/address.{Script}
use cardano/assets.{PolicyId}
use cardano/transaction as tx
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction,
}
use env
use types.{
  Root, Scope, ScopeBurnToClose, ScopeClose, ScopeInit, ScopeMint, ScopeSpend,
}
use utils.{check_output_single_token, for_each_2}

/// Handle mints or burns of the Scope NFTs.
///
/// The policy_id is the one of this scope NFT.
/// The badges are the policy IDs of the token badges present in the badges auth withdraw redeemer,
/// which are guaranteed to be checked by the badges auth script.
pub fn mint_burn(
  action: ScopeMint,
  policy_id: PolicyId,
  tx: Transaction,
  treasury_validator: ScriptHash,
  badges: List<PolicyId>,
) {
  when action is {
    ScopeInit -> {
      // Check that the root contract is aware of this mint.
      // The first output must contain the root UTxO.
      expect [output_0, ..other_outputs] = tx.outputs
      expect
        assets.quantity_of(
          output_0.value,
          treasury_validator,
          env.root_asset_name,
        ) == 1

      // Extract the scope names from the root datum
      expect InlineDatum(root_as_data) = output_0.datum
      expect Root { scope_script_hash, scope_names, .. } = root_as_data
      expect scope_script_hash == policy_id

      // Check that there is at least one output per scope
      let scope_count = list.length(scope_names)
      expect list.length(other_outputs) >= scope_count

      // Check that amount of minted tokens equals the scope count
      let minted = assets.tokens(tx.mint, policy_id)
      expect dict.size(minted) == scope_count
      expect list.all(dict.values(minted), fn(amount) { amount == 1 })

      // Check each scope
      let output, scope_name <- for_each_2(other_outputs, scope_names)

      // Check the content of the output
      let scope_as_data <-
        check_output_single_token(
          output,
          policy_id,
          scope_name,
          env.scope_min_ada,
        )
      expect scope: Scope = scope_as_data

      // Check that scope owner is checked by the badges auth script
      expect list.has(badges, scope.owner)
    }

    ScopeBurnToClose { root_input_index, scope_input_indexes } -> {
      // Check that the root NFT is burned
      let root_token_burn = assets.tokens(tx.mint, treasury_validator)
      expect dict.to_pairs(root_token_burn) == [Pair(env.root_asset_name, -1)]

      // Extract the root datum
      expect Some(Input { output: root_output, .. }) =
        list.at(tx.inputs, root_input_index)
      expect
        assets.quantity_of(
          root_output.value,
          treasury_validator,
          env.root_asset_name,
        ) == 1

      expect InlineDatum(root_as_data) = root_output.datum
      expect Root { scope_script_hash, scope_names, closing } = root_as_data
      expect scope_script_hash == policy_id
      expect list.length(scope_input_indexes) == list.length(scope_names)

      // Retrieve all policy IDs and total scopes value from spent scope utxos,
      // and use the same loop to verify that scope NFTs are burned.
      let scope_tokens = assets.tokens(tx.mint, policy_id)
      let Pair(all_scope_owners, scope_total_value) = {
        let
          index,
          name,
          Pair(owners, value_sum),
        <- utils.fold_2(scope_input_indexes, scope_names, Pair([], assets.zero))
        expect Some(Input { output, .. }) = list.at(tx.inputs, index)

        // Check that the utxo contains the scope NFT
        expect assets.quantity_of(output.value, policy_id, name) == 1

        // Check that this scope token is burned
        expect Some(-1) = dict.get(scope_tokens, name)

        // Retrieve the scope owner badge policy ID
        expect InlineDatum(scope_as_data) = output.datum
        expect scope: Scope = scope_as_data

        // Remove scope token and min_ada from the scope funds
        let to_remove =
          assets.from_asset(policy_id, name, -1)
            |> assets.add("", "", -env.scope_min_ada)
        // "to_remove" is first in merge for optimization (cf dict.union_with)
        let scope_funds = assets.merge(to_remove, output.value)

        // Accumulate scope owner and value
        // "scope_funds" is first in merge for optimization (cf dict.union_with)
        Pair(
          list.push(owners, scope.owner),
          assets.merge(scope_funds, value_sum),
        )
      }

      // Enable the closing burn if N-1 scope owners have authorized it
      // TODO: optimize list.difference with some Set thing?
      // WARNING: this <=1 check means this treasury setup will not work for single-owner setups, but it doesn’t make sense anyway
      let unchecked_badges = list.difference(all_scope_owners, badges)
      expect list.length(unchecked_badges) <= 1

      // TODO: check that total scope value is sent back to closing address
      // TODO: How to prevent double satisfaction with other protocols?
      // -> I have an idea which requires sending to a "Closing" smart contract with some datum
      // which then can be spent but with stricter rules on utxos counts to prevent fraud.
      //
      // Double satisfaction means 2 scripts satisfied.
      // So one easy solution is forbidding any script other than our scope and root ones.
      // It’s a bit extreme and it fucks up script execution for scope owners.
      //
      // Yeah I think having that intermediate "closing" contract could work.
      // You create a closing utxo at this script address, with a unique identifier,
      // and the Closing Data in its datum.
      Void
    }
  }
}

pub fn spend(action: ScopeSpend, tx: Transaction, utxo_ref: OutputReference) {
  when action is {
    ScopeClose { scope_mint_redeemer_index } -> {
      // Extract the spending credential of the output
      expect Some(Input { output, .. }) = tx.find_input(tx.inputs, utxo_ref)
      let spend_cred = output.address.payment_credential

      // Check that there is a Scope mint with redeemer containing a ScopeBurnToClose action
      // That’s it? all the rest of the logic is in logic.scope.mint_burn redeemer?
      expect Some(Pair(tx.Mint(policy_id), redeemer)) =
        list.at(tx.redeemers, scope_mint_redeemer_index)
      expect Script(policy_id) == spend_cred
      expect ScopeBurnToClose { .. } = redeemer
    }
    _ -> todo
  }
}
