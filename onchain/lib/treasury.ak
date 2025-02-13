use aiken/collection/dict.{Dict}
use aiken/crypto.{Blake2b_256, Hash, ScriptHash, VerificationKeyHash}
use cardano/assets.{AssetName, PolicyId, Value}
use cardano/transaction.{Output, OutputReference, Transaction, ValidityRange}

// Treasury

type Treasury {
  identifier: String,
  scopes: List<Scope>,
}

type Scope {
  name: String,
  owner: OwnerCredential,
  budget: Dict<PolicyId, Dict<AssetName, Budget>>,
}

type OwnerCredential {
  KeyCred(VerificationKeyHash)
  MultisigCred(ScriptHash)
  TokenCred(PolicyId)
}

type Budget {
  initial_funding: InitialFunding,
  funds_left: Int,
  rolling_net_limit: Int,
  rolling_net_limit_duration_milliseconds: Int,
  recent_withdrawals: List<Withdrawal>,
}

type InitialFunding {
  amount: Int,
  date_within: Int,
}

type Withdrawal {
  amount: Int,
  date_within: ValidityRange,
}

// Actions

type Action {
  Spend { scopes_spendings: List<Option<Spending>>, rationale: Rationale }
  ChangeScopeOwners {
    scopes_owners: List<Option<ScopeOwnerChange>>,
    rationale: Rationale,
  }
}

type Rationale {
  url: String,
  hash: Hash<Blake2b_256, ByteArray>,
}

type Spending {
  presented_credentials: List<PresentedCredential>,
  amount: Value,
}

type ScopeOwnerChange {
  previous_owner: OwnerCredential,
  new_owner: OwnerCredential,
}

type PresentedCredential {
  KeySignature(VerificationKeyHash)
  MultisigWithdrawal { script_hash: ScriptHash, withdrawal_index: Int }
}

fn spend(
  scopes_spendings: List<Option<Spending>>,
  old_treasury: Treasury,
  new_treasury: Treasury,
) {
  todo @"spend from treasury"
}
