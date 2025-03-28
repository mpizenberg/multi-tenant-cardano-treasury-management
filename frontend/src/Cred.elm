module Cred exposing (Badge(..), ScopeOwner(..), TokenProof, scopeOwnerToData)

import Bytes.Comparable as Bytes exposing (Bytes)
import Cardano.Address exposing (CredentialHash)
import Cardano.Data as Data exposing (Data)
import Cardano.MultiAsset exposing (PolicyId)
import Natural


{-| Credential of one scope owner.

Using a unique token as credential is the most versatile approach,
as it allows for more flexibility in managing ownership,
and prevents the need to change the treasury address when
transferring ownership of one scope.

-}
type ScopeOwner
    = KeyCred (Bytes CredentialHash)
    | ScriptCred (Bytes CredentialHash)
    | TokenCred (Bytes PolicyId)


{-| A badge is a credential description, presented in the redeemer.

Badges must match the different scope owner credentials.
For example, when the owner is a ScriptCred,
the presented credential must be a ScriptWithdrawal.

Unique tokens can be presented as credentials.
In such cases, we must check that the payment cred of the address
owning the token is actually exercised:

  - either by a key in the required signatures
  - or by a script withdrawal

-}
type Badge
    = KeySignature { token : Maybe TokenProof, key : Bytes CredentialHash }
    | ScriptWithdrawal
        { token : Maybe TokenProof
        , scriptHash : Bytes CredentialHash
        , withdrawalIndex : Int
        }


{-| Token policy ID and location in the transaction reference inputs.
-}
type alias TokenProof =
    { policyId : Bytes PolicyId
    , refInputIndex : Int
    }



-- Encoders


scopeOwnerToData : ScopeOwner -> Data
scopeOwnerToData scopeOwner =
    case scopeOwner of
        KeyCred hash ->
            Data.Constr Natural.zero [ Data.Bytes <| Bytes.toAny hash ]

        ScriptCred hash ->
            Data.Constr Natural.one [ Data.Bytes <| Bytes.toAny hash ]

        TokenCred policyId ->
            Data.Constr Natural.two [ Data.Bytes <| Bytes.toAny policyId ]
