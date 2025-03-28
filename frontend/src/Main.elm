port module Main exposing (main)

import Browser
import Bytes.Comparable as Bytes exposing (Bytes)
import Cardano
import Cardano.Address as Address exposing (Address, Credential(..), NetworkId(..))
import Cardano.Cip30 as Cip30
import Cardano.MultiAsset as MultiAsset
import Cardano.Script as Script exposing (PlutusScript, PlutusVersion(..), ScriptCbor)
import Cardano.Uplc as Uplc
import Cardano.Utxo as Utxo exposing (Output, OutputReference)
import Cred exposing (ScopeOwner(..))
import Dict.Any
import Html exposing (Html, button, div, text)
import Html.Attributes as HA exposing (height, src)
import Html.Events as HE exposing (onClick)
import Http
import Json.Decode as JD exposing (Decoder, Value)
import Natural
import Validator


main =
    -- The main entry point of our app
    -- More info about that in the Browser package docs:
    -- https://package.elm-lang.org/packages/elm/browser/latest/
    Browser.element
        { init = init
        , update = update
        , subscriptions = \_ -> fromWallet WalletMsg
        , view = view
        }


port toWallet : Value -> Cmd msg


port fromWallet : (Value -> msg) -> Sub msg



-- #########################################################
-- MODEL
-- #########################################################


type Model
    = Startup
    | WalletDiscovered (List Cip30.WalletDescriptor)
    | WalletLoading
        { wallet : Cip30.Wallet
        , utxos : List Cip30.Utxo
        }
    | WalletLoaded LoadedWallet { errors : String }
    | BlueprintLoaded LoadedWallet UnappliedScript { errors : String }
    | ParametersSet AppContext { errors : String }


type alias LoadedWallet =
    { wallet : Cip30.Wallet
    , utxos : Utxo.RefDict Output
    , changeAddress : Address
    }


type alias UnappliedScript =
    { compiledCode : Bytes ScriptCbor }


type alias AppContext =
    { loadedWallet : LoadedWallet
    , pickedUtxo : OutputReference
    , localStateUtxos : Utxo.RefDict Output
    , treasuryScript : PlutusScript
    , scriptAddress : Address
    }


init : () -> ( Model, Cmd Msg )
init _ =
    ( Startup
    , toWallet <| Cip30.encodeRequest Cip30.discoverWallets
    )


setError : String -> Model -> Model
setError e model =
    let
        _ =
            Debug.log "ERROR" e
    in
    case model of
        WalletLoaded loadedWallet _ ->
            WalletLoaded loadedWallet { errors = e }

        BlueprintLoaded loadedWallet unappliedScript _ ->
            BlueprintLoaded loadedWallet unappliedScript { errors = e }

        ParametersSet appContext _ ->
            ParametersSet appContext { errors = e }

        _ ->
            model



-- #########################################################
-- UPDATE
-- #########################################################


type Msg
    = WalletMsg Value
    | ConnectButtonClicked { id : String }
    | LoadBlueprintButtonClicked
    | GotBlueprint (Result Http.Error UnappliedScript)
    | PickUtxoParam
    | InitializeTreasuryButtonClicked


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case ( msg, model ) of
        ( WalletMsg value, _ ) ->
            case ( JD.decodeValue Cip30.responseDecoder value, model ) of
                -- We just discovered available wallets
                ( Ok (Cip30.AvailableWallets wallets), Startup ) ->
                    ( WalletDiscovered wallets, Cmd.none )

                -- We just connected to the wallet, let’s ask for the available utxos
                ( Ok (Cip30.EnabledWallet wallet), WalletDiscovered _ ) ->
                    ( WalletLoading { wallet = wallet, utxos = [] }
                    , toWallet <| Cip30.encodeRequest <| Cip30.getUtxos wallet { amount = Nothing, paginate = Nothing }
                    )

                -- We just received the utxos, let’s ask for the main change address of the wallet
                ( Ok (Cip30.ApiResponse _ (Cip30.WalletUtxos utxos)), WalletLoading { wallet } ) ->
                    ( WalletLoading { wallet = wallet, utxos = utxos }
                    , toWallet (Cip30.encodeRequest (Cip30.getChangeAddress wallet))
                    )

                ( Ok (Cip30.ApiResponse _ (Cip30.ChangeAddress address)), WalletLoading { wallet, utxos } ) ->
                    ( WalletLoaded { wallet = wallet, utxos = Utxo.refDictFromList utxos, changeAddress = address } { errors = "" }
                    , Cmd.none
                    )

                ( Ok (Cip30.ApiError { info }), m ) ->
                    ( setError info m, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        ( ConnectButtonClicked { id }, WalletDiscovered _ ) ->
            ( model, toWallet (Cip30.encodeRequest (Cip30.enableWallet { id = id, extensions = [] })) )

        ( LoadBlueprintButtonClicked, WalletLoaded _ _ ) ->
            ( model
            , let
                blueprintDecoder : Decoder UnappliedScript
                blueprintDecoder =
                    JD.at [ "validators" ]
                        (JD.index 0
                            (JD.map UnappliedScript
                                (JD.field "compiledCode" JD.string |> JD.map Bytes.fromHexUnchecked)
                            )
                        )
              in
              Http.get
                { url = "plutus.json"
                , expect = Http.expectJson GotBlueprint blueprintDecoder
                }
            )

        ( GotBlueprint result, WalletLoaded w _ ) ->
            case result of
                Ok unappliedScript ->
                    ( BlueprintLoaded w unappliedScript { errors = "" }, Cmd.none )

                Err err ->
                    -- Handle error as needed
                    ( WalletLoaded w { errors = Debug.toString err }, Cmd.none )

        ( PickUtxoParam, BlueprintLoaded w unappliedScript { errors } ) ->
            case List.head (Dict.Any.keys w.utxos) of
                Just headUtxo ->
                    let
                        appliedScriptRes =
                            Uplc.applyParamsToScript
                                [ Utxo.outputReferenceToData headUtxo ]
                                (Script.plutusScriptFromBytes PlutusV3 unappliedScript.compiledCode)
                    in
                    case appliedScriptRes of
                        Ok plutusScript ->
                            ( ParametersSet
                                { loadedWallet = w
                                , pickedUtxo = headUtxo
                                , localStateUtxos = w.utxos
                                , treasuryScript = plutusScript
                                , scriptAddress =
                                    Address.Shelley
                                        { networkId = Address.extractNetworkId w.changeAddress |> Maybe.withDefault Testnet
                                        , paymentCredential = ScriptHash <| Script.hash (Script.Plutus plutusScript)
                                        , stakeCredential = Nothing
                                        }
                                }
                                { errors = errors }
                            , Cmd.none
                            )

                        Err err ->
                            ( BlueprintLoaded w unappliedScript { errors = Debug.toString err }
                            , Cmd.none
                            )

                Nothing ->
                    ( BlueprintLoaded w unappliedScript { errors = "Selected wallet has no UTxO." }
                    , Cmd.none
                    )

        ( InitializeTreasuryButtonClicked, ParametersSet ctx _ ) ->
            let
                initializationTxIntents =
                    Validator.initializeTreasury
                        ctx.loadedWallet.changeAddress
                        ctx.pickedUtxo
                        ctx.treasuryScript
                        scopes

                scopes =
                    [ { name = "Consensus"
                      , owner =
                            KeyCred <|
                                Maybe.withDefault (Bytes.fromHexUnchecked "") <|
                                    Address.extractPubKeyHash ctx.loadedWallet.changeAddress
                      , adaBudgetConfig =
                            { rollingNetLimitAmount =
                                -- 100 ada
                                Natural.fromSafeInt <| 100 * 1000000
                            , rollingNetLimitDurationMilliseconds =
                                -- 30 days
                                Natural.fromSafeInt <| 1000 * 60 * 60 * 24 * 30
                            , recentWithdrawals = []
                            }
                      , otherBudgetConfigs = MultiAsset.empty
                      }
                    ]

                txResult =
                    Cardano.finalize ctx.localStateUtxos [] initializationTxIntents
            in
            case txResult of
                Ok { tx } ->
                    Debug.todo ""

                Err err ->
                    ( setError (Debug.toString err) model, Cmd.none )

        _ ->
            ( model, Cmd.none )



-- #########################################################
-- VIEW
-- #########################################################


view : Model -> Html Msg
view model =
    case model of
        Startup ->
            div [] [ div [] [ text "Hello Cardano!" ] ]

        WalletDiscovered availableWallets ->
            div []
                [ div [] [ text "Hello Cardano!" ]
                , div [] [ text "CIP-30 wallets detected:" ]
                , viewAvailableWallets availableWallets
                ]

        WalletLoading _ ->
            div [] [ text "Loading wallet assets ..." ]

        WalletLoaded loadedWallet { errors } ->
            div []
                (viewLoadedWallet loadedWallet
                    ++ [ button [ onClick LoadBlueprintButtonClicked ] [ text "Load Blueprint" ]
                       , displayErrors errors
                       ]
                )

        BlueprintLoaded loadedWallet unappliedScript { errors } ->
            div []
                (viewLoadedWallet loadedWallet
                    ++ [ div [] [ text <| "Unapplied script size (bytes): " ++ String.fromInt (Bytes.width unappliedScript.compiledCode) ]
                       , button [ HE.onClick PickUtxoParam ] [ text "Auto-pick UTxO to be spent for unicity guarantee of the Treasury contract" ]
                       , displayErrors errors
                       ]
                )

        ParametersSet ctx { errors } ->
            let
                scriptHash =
                    Script.hash <| Script.Plutus ctx.treasuryScript

                scriptBytes =
                    Script.cborWrappedBytes ctx.treasuryScript
            in
            div []
                (viewLoadedWallet ctx.loadedWallet
                    ++ [ div [] [ text <| "☑️ Picked UTxO: " ++ (ctx.pickedUtxo |> (\u -> Bytes.toHex u.transactionId ++ "#" ++ String.fromInt u.outputIndex)) ]
                       , div [] [ text <| "Applied Script hash: " ++ Bytes.toHex scriptHash ]
                       , div [] [ text <| "Applied Script size (bytes): " ++ String.fromInt (Bytes.width scriptBytes) ]
                       , button [ onClick InitializeTreasuryButtonClicked ] [ text "Initialize the multi-tenant treasury" ]
                       , displayErrors errors
                       ]
                )


displayErrors : String -> Html msg
displayErrors err =
    if err == "" then
        text ""

    else
        div [ HA.style "color" "red" ] [ Html.b [] [ text <| "ERRORS: " ], text err ]


viewLoadedWallet : LoadedWallet -> List (Html msg)
viewLoadedWallet { wallet, utxos, changeAddress } =
    [ div [] [ text <| "Wallet: " ++ (Cip30.walletDescriptor wallet).name ]
    , div [] [ text <| "Address: " ++ (Address.toBytes changeAddress |> Bytes.toHex) ]
    , div [] [ text <| "UTxO count: " ++ String.fromInt (Dict.Any.size utxos) ]
    ]


viewAvailableWallets : List Cip30.WalletDescriptor -> Html Msg
viewAvailableWallets wallets =
    let
        walletDescription : Cip30.WalletDescriptor -> String
        walletDescription w =
            "id: " ++ w.id ++ ", name: " ++ w.name

        walletIcon : Cip30.WalletDescriptor -> Html Msg
        walletIcon { icon } =
            Html.img [ src icon, height 32 ] []

        connectButton { id } =
            Html.button [ onClick (ConnectButtonClicked { id = id }) ] [ text "connect" ]

        walletRow w =
            div [] [ walletIcon w, text (walletDescription w), connectButton w ]
    in
    div [] (List.map walletRow wallets)
