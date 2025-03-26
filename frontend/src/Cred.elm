module Cred exposing (Badge(..), ScopeOwnerCred(..), TokenProof)

import Bytes.Comparable exposing (Bytes)
import Cardano.Address exposing (CredentialHash)
import Cardano.MultiAsset exposing (PolicyId)


{-| Credential of one scope owner.

Using a unique token as credential is the most versatile approach,
as it allows for more flexibility in managing ownership,
and prevents the need to change the treasury address when
transferring ownership of one scope.

-}
type ScopeOwnerCred
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
