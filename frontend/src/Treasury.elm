module Treasury exposing (BudgetConfig, FiniteValidityRange, InputIndex(..), Scope, ScopeAuth, Withdrawal, scopeToData)

import Bytes.Comparable as Bytes exposing (Bytes)
import Bytes.Map exposing (BytesMap)
import Cardano.Data as Data exposing (Data)
import Cardano.MultiAsset exposing (AssetName, MultiAsset, PolicyId)
import Cred exposing (Badge, ScopeOwner)
import Integer
import Natural exposing (Natural)


type alias SpendDatum =
    { previousInputIndex : Maybe Int
    , scope : Scope
    }


{-| One scope of the multi-tenant treasury.
-}
type alias Scope =
    { name : String
    , owner : ScopeOwner
    , adaBudgetConfig : BudgetConfig
    , otherBudgetConfigs : MultiAsset BudgetConfig
    }


{-| Budget configuration for each token.
For example, the config for Ada, or for USDM.

For each token, the budget config specifies the rolling net limit amount and duration.
It also keeps track of recent withdrawals to enforce the rolling net limit.

-}
type alias BudgetConfig =
    { rollingNetLimitAmount : Natural
    , rollingNetLimitDurationMilliseconds : Natural
    , recentWithdrawals : List Withdrawal
    }


{-| One withdrawal from the treasury.
It contains the amount withdrawn and when it happened (within a range).
-}
type alias Withdrawal =
    { amount : Natural
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



-- Encoders


scopeToData : Scope -> Data
scopeToData scope =
    Data.Constr Natural.zero
        [ Data.Bytes <| Bytes.fromText scope.name
        , Cred.scopeOwnerToData scope.owner
        , budgetConfigsToData scope.adaBudgetConfig scope.otherBudgetConfigs
        ]


budgetConfigsToData : BudgetConfig -> MultiAsset BudgetConfig -> Data
budgetConfigsToData adaBudgetConfig otherBudgetConfigs =
    let
        adaPolicy =
            Bytes.fromHexUnchecked ""

        adaAssetName =
            Bytes.fromHexUnchecked ""

        adaConfigData =
            tokenBudgetConfigToData adaPolicy (Bytes.Map.singleton adaAssetName adaBudgetConfig)

        otherConfigsData =
            Bytes.Map.toList otherBudgetConfigs
                |> List.map (\( policyId, tokenConfigs ) -> tokenBudgetConfigToData policyId tokenConfigs)
    in
    Data.List (adaConfigData :: otherConfigsData)


tokenBudgetConfigToData : Bytes PolicyId -> BytesMap AssetName BudgetConfig -> Data
tokenBudgetConfigToData policyId budgets =
    let
        assetConfigToData assetName config =
            Data.List
                [ Data.Bytes <| Bytes.toAny assetName
                , budgetConfigToData config
                ]
    in
    Data.List
        [ Data.Bytes <| Bytes.toAny policyId
        , Bytes.Map.toList budgets
            |> List.map (\( assetName, config ) -> assetConfigToData assetName config)
            |> Data.List
        ]


budgetConfigToData : BudgetConfig -> Data
budgetConfigToData config =
    Data.Constr Natural.zero
        [ Data.Int <| Integer.fromNatural config.rollingNetLimitAmount
        , Data.Int <| Integer.fromNatural config.rollingNetLimitDurationMilliseconds
        , Data.List <| List.map withdrawalToData config.recentWithdrawals
        ]


withdrawalToData : Withdrawal -> Data
withdrawalToData withdrawal =
    Data.Constr Natural.zero
        [ Data.Int <| Integer.fromNatural withdrawal.amount
        , Data.Int <| Integer.fromSafeInt withdrawal.validityRange.lowerBound
        , Data.Int <| Integer.fromSafeInt withdrawal.validityRange.upperBound
        ]
