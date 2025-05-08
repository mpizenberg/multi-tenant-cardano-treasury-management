use aiken/builtin
use aiken/collection/list
use aiken/crypto.{ScriptHash}
use cardano/address.{Credential, Script}
use cardano/assets.{PolicyId}
use cardano/certificate.{Certificate}
use cardano/transaction.{OutputReference, Transaction}
use cardano/transaction as tx
use logic/scope
use types.{ScopeMint, ScopeSpend}

pub type MintRedeemer {
  badges_redeemer_index: Int,
  action: ScopeMint,
}

validator treasury_scope(
  treasury_validator: ScriptHash,
  badges_validator: ScriptHash,
) {
  mint(redeemer: MintRedeemer, policy_id: PolicyId, tx: Transaction) {
    // Retrieve the badges being presented to the badges validator
    expect Some(Pair(tx.Withdraw(cred), withdraw_redeemer_data)) =
      list.at(tx.redeemers, redeemer.badges_redeemer_index)
    expect cred == Script(badges_validator)
    expect badges_redeemer: Pairs<PolicyId, Data> = withdraw_redeemer_data
    let badges = list.map(badges_redeemer, builtin.fst_pair)

    // Call the mint logic
    scope.mint_burn(redeemer.action, policy_id, tx, treasury_validator, badges)

    True
  }

  spend(
    _datum: Option<Data>,
    redeemer: ScopeSpend,
    utxo: OutputReference,
    tx: Transaction,
  ) {
    scope.spend(redeemer, tx, utxo)
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
