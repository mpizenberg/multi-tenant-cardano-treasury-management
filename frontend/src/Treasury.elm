module Treasury exposing (BudgetConfig, FiniteValidityRange, InputIndex(..), Scope, ScopeAuth, Withdrawal)

import Cardano.MultiAsset exposing (MultiAsset)
import Cred exposing (Badge, ScopeOwnerCred)


type alias SpendDatum =
    { previousInputIndex : Maybe Int
    , scope : Scope
    }


{-| One scope of the multi-tenant treasury.
-}
type alias Scope =
    { name : String
    , owner : ScopeOwnerCred
    , budgetConfigs : MultiAsset BudgetConfig
    }


{-| Budget configuration for each token.
For example, the config for Ada, or for USDM.

For each token, the budget config specifies the rolling net limit amount and duration.
It also keeps track of recent withdrawals to enforce the rolling net limit.

-}
type alias BudgetConfig =
    { rollingNetLimitAmount : Int
    , rollingNetLimitDurationMilliseconds : Int
    , recentWithdrawals : List Withdrawal
    }


{-| One withdrawal from the treasury.
It contains the amount withdrawn and when it happened (within a range).
-}
type alias Withdrawal =
    { amount : Int
    , validityRange : FiniteValidityRange
    }


{-| Validity range with finite bounds.
-}
type alias FiniteValidityRange =
    { lowerBound : Int
    , upperBound : Int
    }


{-| Authentication data for a scope UTxO.
This can either be for a scope UTxO being spent or referenced.
When the new output is "None", we consider the input
-}
type alias ScopeAuth =
    -- Badge specifying how to check the scope owner's credentials
    { badge : Badge

    -- Index of the input (spent or ref) for the scope UTxO
    , scopeInputIndex : InputIndex
    }


type InputIndex
    = SpentIndex Int
    | RefIndex Int
