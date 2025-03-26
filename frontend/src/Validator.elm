module Validator exposing (InitialMintRedeemer, WithdrawActionType(..), WithdrawRedeemer)

import Treasury exposing (Scope, ScopeAuth)



-- Initialization ----------------------------------------------------


type alias InitialMintRedeemer =
    { scopes : List Scope
    , register_cert_index : Int
    }


type alias WithdrawRedeemer =
    -- Index of the ref input containing the treasury root NFT
    { root_ref_index : Int

    -- Action to be performed
    , action_type : WithdrawActionType
    }


type WithdrawActionType
    = FundingViaWithdrawal (List ( ScopeAuth, Int ))
    | CheckBadges (List ScopeAuth)
