use aiken/crypto.{ScriptHash, VerificationKeyHash}
use cardano/assets.{PolicyId}

/// Credential of one scope owner.
pub type OwnerCred {
  KeyCred(VerificationKeyHash)
  MultisigCred(ScriptHash)
  TokenCred(PolicyId)
}

/// Credential presented in the redeemer.
///
/// They must match the different scope owner credentials.
/// For example, when the owner is a MultisigCred,
/// the presented credential must be a MultisigWithdrawal.
pub type PresentedCred {
  KeySignature(VerificationKeyHash)
  MultisigWithdrawal { script_hash: ScriptHash, withdrawal_index: Int }
}
