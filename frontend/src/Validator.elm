module Validator exposing (WithdrawActionType(..), WithdrawRedeemer, initializeTreasury)

import Bytes.Comparable as Bytes exposing (Bytes)
import Bytes.Map
import Cardano exposing (CredentialWitness(..), TxIntent)
import Cardano.Address as Address exposing (Address, Credential(..), NetworkId(..))
import Cardano.Data as Data exposing (Data)
import Cardano.MultiAsset as MultiAsset exposing (AssetName)
import Cardano.Script as Script exposing (PlutusScript)
import Cardano.Transaction exposing (Certificate(..))
import Cardano.Utxo as Utxo exposing (Output, OutputReference)
import Cardano.Value as Value
import Cred exposing (ScopeOwner(..))
import Integer
import List.Extra
import Natural exposing (Natural)
import Treasury exposing (Scope, ScopeAuth)



-- Initialization ----------------------------------------------------


type alias InitialMintRedeemer =
    { scopes : List Scope
    , registerCertIndex : Int
    }


initialMintRedeemerToData : InitialMintRedeemer -> Data
initialMintRedeemerToData { scopes, registerCertIndex } =
    Data.Constr Natural.zero
        [ Data.List <| List.map Treasury.scopeToData scopes
        , Data.Int <| Integer.fromSafeInt registerCertIndex
        ]


type alias WithdrawRedeemer =
    -- Index of the ref input containing the treasury root NFT
    { rootRefIndex : Int

    -- Action to be performed
    , actionType : WithdrawActionType
    }


type WithdrawActionType
    = FundingViaWithdrawal (List ( ScopeAuth, Int ))
    | CheckBadges (List ScopeAuth)


rootAssetName : Bytes AssetName
rootAssetName =
    -- Configured in the default.ak file
    Bytes.fromText "Treasury Root"


rootMinAda : Natural
rootMinAda =
    -- Configured in the default.ak file
    Natural.fromSafeInt 100000000


scopeMinAda : Natural
scopeMinAda =
    -- Configured in the default.ak file
    Natural.fromSafeInt 2000000


initializeTreasury : Address -> OutputReference -> PlutusScript -> List Scope -> List TxIntent
initializeTreasury walletAddress uniqueUtxo script scopes =
    let
        spendFromWallet value guaranteedUtxos =
            Cardano.Spend <|
                Cardano.FromWallet
                    { address = walletAddress
                    , value = value
                    , guaranteedUtxos = guaranteedUtxos
                    }

        networkId =
            Address.extractNetworkId walletAddress
                |> Maybe.withDefault Testnet

        scriptHash =
            Script.hash <| Script.Plutus script

        -- TODO: potentially add staking credentials
        scriptAddress =
            Address.script networkId scriptHash

        -- Mint the treasury root NFT,
        -- as well as each scope NFT
        mintIntent : TxIntent
        mintIntent =
            Cardano.MintBurn
                { policyId = scriptHash
                , assets =
                    Bytes.Map.fromList <|
                        List.concat
                            -- Mint the treasury root NFT
                            [ [ ( rootAssetName, Integer.one ) ]

                            -- Also mint each scope NFT
                            , List.map (\scope -> ( Bytes.fromText scope.name, Integer.one )) scopes
                            ]
                , scriptWitness = Cardano.PlutusWitness mintWitness
                }

        mintWitness =
            { script =
                ( Script.plutusVersion script
                , Cardano.WitnessByValue <| Script.cborWrappedBytes script
                )
            , redeemerData =
                \txBody ->
                    InitialMintRedeemer scopes (registerCertIndex txBody.certificates)
                        |> initialMintRedeemerToData
            , requiredSigners = scopeKeySigners
            }

        registerCertIndex certificates =
            List.Extra.findIndex isTreasuryReg certificates
                |> Maybe.withDefault 0

        isTreasuryReg cert =
            case cert of
                StakeRegistrationCert { delegator } ->
                    delegator == ScriptHash scriptHash

                RegCert { delegator } ->
                    delegator == ScriptHash scriptHash

                _ ->
                    False

        -- Register the treasury contract to later enable withdrawals
        registerIntent : TxIntent
        registerIntent =
            Cardano.IssueCertificate <|
                Cardano.RegisterStake
                    { delegator = WithScript scriptHash <| Cardano.PlutusWitness registerWitness
                    , deposit = deposit
                    }

        deposit =
            Natural.fromSafeInt 2000000

        registerWitness =
            { script =
                ( Script.plutusVersion script
                , Cardano.WitnessByValue <| Script.cborWrappedBytes script
                )
            , redeemerData = \_ -> Data.Int Integer.zero
            , requiredSigners = scopeKeySigners
            }

        scopeKeySigners =
            List.filterMap extractScopeSigner scopes

        extractScopeSigner scope =
            case scope.owner of
                KeyCred key ->
                    Just key

                _ ->
                    Nothing

        outputWithRootNftAndScriptRef : Output
        outputWithRootNftAndScriptRef =
            { address = scriptAddress
            , amount =
                { lovelace = rootMinAda
                , assets = MultiAsset.onlyToken scriptHash rootAssetName Natural.one
                }
            , datumOption = Just <| Utxo.datumValueFromData <| scopeNamesAsData
            , referenceScript = Just <| Script.refFromScript <| Script.Plutus script
            }

        scopeNamesAsData =
            Data.List <|
                List.map (Data.Bytes << Bytes.fromText << .name) scopes

        createScopeOutput : Scope -> Output
        createScopeOutput scope =
            { address = scriptAddress
            , amount =
                { lovelace = scopeMinAda
                , assets = MultiAsset.onlyToken scriptHash (Bytes.fromText scope.name) Natural.one
                }
            , datumOption = Just <| Utxo.datumValueFromData <| spendDatum scope
            , referenceScript = Nothing
            }

        spendDatum scope =
            Data.Constr Natural.zero
                [ Data.Constr Natural.one [] -- Nothing for previousInputIndex
                , Treasury.scopeToData scope
                ]
    in
    List.concat
        -- Spend the UTxO parameterizing the treasury contract
        [ [ spendFromWallet Value.zero [ uniqueUtxo ]

          -- Mint the treasury root NFT,
          -- as well as each scope NFT
          , mintIntent

          -- The first output contains the treasury root NFT
          -- as well as the script reference
          , spendFromWallet (Value.onlyLovelace rootMinAda) []
          , Cardano.SendToOutput outputWithRootNftAndScriptRef
          ]

        -- Add an output for each scope
        , List.map (\_ -> spendFromWallet (Value.onlyLovelace scopeMinAda) []) scopes
        , List.map (Cardano.SendToOutput << createScopeOutput) scopes

        -- Register the treasury contract to later enable withdrawals
        , [ spendFromWallet (Value.onlyLovelace deposit) []
          , registerIntent
          ]
        ]
