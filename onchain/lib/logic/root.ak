use aiken/collection/list
use aiken/crypto.{ScriptHash}
use cardano/address.{Script}
use cardano/transaction.{
  Input, OutputReference, Redeemer, ScriptPurpose, Transaction,
}
use cardano/transaction as tx
use types.{
  RootBurnToClose, RootClose, RootInit, RootMint, RootSpend, ScopeBurnToClose,
  ScopeInit,
}

/// Handle mints or burns of the root NFT.
///
/// The policy_id is the one of this root NFT.
/// The scope_validator is the policy ID of the Scope script.
pub fn mint_burn(
  action: RootMint,
  tx_redeemers: Pairs<ScriptPurpose, Redeemer>,
  scope_validator: ScriptHash,
  scope_mint_redeemer_index: Int,
) {
  // Check that there is a Scope mint with redeemer containing a scope.Mint.Init action
  // That’s it? all the rest of the logic is in logic.scope.mint_burn redeemer?
  expect Some(Pair(tx.Mint(scope_id), redeemer)) =
    list.at(tx_redeemers, scope_mint_redeemer_index)
  expect scope_id == scope_validator

  when action is {
    RootInit -> {
      expect ScopeInit = redeemer
    }
    RootBurnToClose -> {
      expect ScopeBurnToClose { .. } = redeemer
    }
  }
}

pub fn spend(action: RootSpend, tx: Transaction, utxo_ref: OutputReference) {
  when action is {
    RootClose { root_mint_redeemer_index } -> {
      // Extract the spending credential of the output
      expect Some(Input { output, .. }) = tx.find_input(tx.inputs, utxo_ref)
      let spend_cred = output.address.payment_credential

      // Check that there is a Scope mint with redeemer containing a ScopeBurnToClose action
      // That’s it? all the rest of the logic is in logic.scope.mint_burn redeemer?
      expect Some(Pair(tx.Mint(policy_id), redeemer)) =
        list.at(tx.redeemers, root_mint_redeemer_index)
      expect Script(policy_id) == spend_cred
      expect ScopeBurnToClose { .. } = redeemer
    }
  }
}
