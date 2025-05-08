use aiken/crypto.{ScriptHash}
use cardano/address.{Address}
use cardano/assets.{PolicyId}

// Root ##############################################################

pub type Root {
  scope_script_hash: ScriptHash,
  scope_names: List<ByteArray>,
  closing: Closing,
}

pub type Closing {
  BackToCardanoTreasury
  BackToAddress(Address)
}

pub type RootMint {
  /// Initialization of the treasury
  RootInit
  /// Close the treasury with all scopes and return the funds
  /// Scope input indexes must be in the same order than in the root datum
  RootBurnToClose
}

pub type RootSpend {
  /// Close the treasury and return all funds
  RootClose { root_mint_redeemer_index: Int }
}

// Scope #############################################################

/// One scope of the multi-tenant treasury
pub type Scope {
  /// The name of the scope, must be unique
  name: ByteArray,
  /// The policy ID of the token (badge) representing the owner
  owner: PolicyId,
}

pub type ScopeMint {
  /// Initialization of the scopes
  ScopeInit
  /// Close the scope and return the funds
  /// Scope input indexes must be in the same order than in the root datum
  ScopeBurnToClose { root_input_index: Int, scope_input_indexes: List<Int> }
}

pub type ScopeSpend {
  /// Add funds into the Scope
  ScopeTopUp
  /// Withdraw funds to pay someone
  ScopePay
  /// Change the owner with agreement of all scope owners
  ScopeChangeOwner
  /// Change owner with N-1 agreements + contestation period
  ScopeRecoverOwner
  /// Close the scope and return all funds
  ScopeClose { scope_mint_redeemer_index: Int }
}
