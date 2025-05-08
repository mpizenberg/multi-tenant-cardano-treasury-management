use aiken/crypto.{ScriptHash}
use cardano/address.{Credential}
use cardano/assets.{PolicyId}
use cardano/certificate.{Certificate}
use cardano/transaction.{OutputReference, Transaction}
use logic/root
use types.{RootMint, RootSpend}

pub type MintRedeemer {
  action: RootMint,
  scope_validator: ScriptHash,
  scope_mint_redeemer_index: Int,
}

validator treasury_root {
  mint(redeemer: MintRedeemer, _policy_id: PolicyId, tx: Transaction) {
    root.mint_burn(
      redeemer.action,
      tx.redeemers,
      redeemer.scope_validator,
      redeemer.scope_mint_redeemer_index,
    )
    True
  }

  spend(
    _datum: Option<Data>,
    redeemer: RootSpend,
    utxo: OutputReference,
    tx: Transaction,
  ) {
    root.spend(redeemer, tx, utxo)
    True
  }

  withdraw(redeemer: Data, account: Credential, self: Transaction) {
    todo @"withdraw logic goes here"
  }

  publish(redeemer: Data, certificate: Certificate, self: Transaction) {
    todo @"publish logic goes here"
  }

  else(_ctx: Data) {
    fail @"unsupported purpose"
  }
}
