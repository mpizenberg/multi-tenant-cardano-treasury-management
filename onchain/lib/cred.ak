use aiken/builtin
use aiken/collection/list
use aiken/crypto.{ScriptHash, VerificationKeyHash}
use cardano/address.{Credential, Script, VerificationKey}
use cardano/assets.{PolicyId}
use cardano/transaction.{Input, Output, Transaction}

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

/// Check that the presented badge is valid.
/// Doesn’t check that they are also part of the scope owners, just valid.
pub fn check_badge_validity(tx: Transaction, badge: Badge) {
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

/// Check that the presented badge matches the owner credential
pub fn badge_matches_owner(owner: ScopeOwnerCred, badge: Badge) -> Bool {
  when owner is {
    KeyCred(owner_key) ->
      when badge is {
        KeySignature { key, .. } -> key == owner_key
        _ -> False
      }
    ScriptCred(owner_script_hash) ->
      when badge is {
        ScriptWithdrawal { script_hash, .. } -> script_hash == owner_script_hash
        _ -> False
      }
    TokenCred(owner_policy_id) ->
      when badge is {
        KeySignature { token: Some(TokenProof { policy_id, .. }), .. } ->
          policy_id == owner_policy_id
        _ -> False
      }
  }
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
