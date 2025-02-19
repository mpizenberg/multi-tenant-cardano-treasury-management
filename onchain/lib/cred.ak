use aiken/collection/list
use aiken/crypto.{ScriptHash, VerificationKeyHash}
use cardano/assets.{PolicyId}

/// Credential of one scope owner.
///
/// Using a unique token as credential is the most versatile approach,
/// as it allows for more flexibility in managing ownership,
/// and prevents the need to change the treasury address when
/// transferring ownership of one scope.
pub type ScopeOwnerCred {
  KeyCred(VerificationKeyHash)
  ScriptCred(ScriptHash)
  TokenCred(PolicyId)
}

/// A badge is a credential description, presented in the redeemer.
///
/// Badges must match the different scope owner credentials.
/// For example, when the owner is a ScriptCred,
/// the presented credential must be a ScriptWithdrawal.
///
/// Unique tokens can be presented as credentials.
/// In such cases, we must check that the payment cred of the address
/// owning the token is actually exercised:
///  - either by a key in the required signatures
///  - or by a script withdrawal
pub type Badge {
  KeySignature { token: Option<TokenProof>, key: VerificationKeyHash }
  ScriptWithdrawal {
    token: Option<TokenProof>,
    script_hash: ScriptHash,
    withdrawal_index: Int,
  }
}

/// Token policy ID and location in the transaction reference inputs
pub type TokenProof {
  policy_id: PolicyId,
  ref_input_index: Int,
}

/// Check that the owner badge is presented
pub fn owner_badge_is_presented(
  owner: ScopeOwnerCred,
  presented_badges: List<Badge>,
) -> Bool {
  when owner is {
    KeyCred(owner_key) -> {
      let badge <- list.any(presented_badges)
      when badge is {
        KeySignature { key, .. } -> key == owner_key
        _ -> False
      }
    }
    ScriptCred(owner_script_hash) -> {
      let badge <- list.any(presented_badges)
      when badge is {
        ScriptWithdrawal { script_hash, .. } -> script_hash == owner_script_hash
        _ -> False
      }
    }
    TokenCred(owner_policy_id) -> {
      let badge <- list.any(presented_badges)
      when badge is {
        KeySignature { token: Some(TokenProof { policy_id, .. }), .. } ->
          policy_id == owner_policy_id
        ScriptWithdrawal { token: Some(TokenProof { policy_id, .. }), .. } ->
          policy_id == owner_policy_id
        _ -> False
      }
    }
  }
}
