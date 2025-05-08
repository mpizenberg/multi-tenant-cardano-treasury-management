When initializing the Treasury and minting the root and scope tokens,
- the first output is the one with the root nft
- the following outputs contain each one scope nft, in the same order than the scope names in the root datum

At any point, the list of scopes is available in the root datum.

A scope utxo contains always at least scope_min_ada ada, which is a defined constant.
