use cred.{KeyCred, ScriptCred, TokenCred}

const key0 = #"00000000000000000000000000000000000000000000000000000000"

const key1 = #"00000000000000000000000000000000000000000000000000000001"

const key2 = #"00000000000000000000000000000000000000000000000000000002"

const script_hash = #"00000000000000000000000000000000000000000000000000000003"

const token_policy_id =
  #"00000000000000000000000000000000000000000000000000000004"

pub const scope_owners =
  [
    KeyCred(key0),
    KeyCred(key1),
    KeyCred(key2),
    ScriptCred(script_hash),
    TokenCred(token_policy_id),
  ]

pub const publish_allowed = True

pub const stake_allowed = False

/// Asset name used for the root NFT
pub const root_asset_name = "Treasury Root"

/// 5 Ada as minAda for the root utxo (containing the root NFT and the script)
pub const root_min_ada = 5000000

/// 2 Ada as minAda for each scope
pub const scope_min_ada = 2000000
