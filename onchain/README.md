# Multi-Tenant Treasury Management

This directory contains the on-chain (Aiken) part of a multi-tenant treasury management system.

## Overview

This treasury contract has the following properties:

- **Multi-tenant**: The treasury is split into "scopes", each having its own credentials and rules.
- **Secure**: Thresholds and oversights in place to ensure the integrity of the treasury.
- **Transparent**: The treasury's state is transparent and verifiable, each operation requiring a rationale.
- **Flexible**: Scope credentials can be rotated and rules adjusted.
- **Configurable**: Thresholds, ability to stake, to vote, etc. are configurable.

## Usage

Setting up the treasury is done in multiple steps.
Offchain libraries and a web app make these steps easy to execute.

1. Initialize the treasury:
   Mint a set of NFTs configuring each scope of the treasury
2. Fund the treasury:
   Transfer funds into the different scopes, for example with a withdrawal
3. Spend funds from the treasury:
   Spend funds from the different scopes following the treasury's rules
4. In the end, close the treasury:
   Transfer all remaining funds and burn the treasury NFTs

## Technical Details

**Initialization**

Initialization of the treasury consists in minting a set of NFTs,
one for each scope of the treasury, and another main one, for tracking purposes.
The main NFT mint is parameterized by a UTxO to consume to guarantee its unicity.
Each scope NFT is configured with an owner credentials
and rules for the corresponding scope, detailed in an updatable datum.

The script is also registered at initialization,
to enable potential subsequent reward account withdrawals.

**Funding**

When funding this treasury, all assets must flow into the pre-defined scopes.

**Spending**

Each scope has its own budget, spending rules, and credentials.
The scope is identified by its NFT, located at a single UTxO,
which must be spent and recreated for each operation.
The spending rules and scope owner credentials are detailed in the datum of that UTxO.
Spending follows the following rules:

- Any spending must be authorized by the scope owner.
- Any spending must provide a rationale.
- Spending must not exceed the scope rolling net limit.
- Any spending above the limit must be authorized by other scope owners:
  - A majority of scope owners for up to 2x the limit (configurable)
  - All scope owners for anything above that.
- Changing the scope spending rules must be authorized by all scope owners.

**Closing**

When closing the treasury, all remaining funds must be transferred
to a designated address or the Cardano treasury, and the treasury NFTs must be burned.

**Credentials**

Each scope has a designated owner with credentials, which can be one of the following:
- a single public key,
- a script,
- or a unique token (NFT).

In the case of a single public key, the proof of ownership is provided
by adding the key hash into the list of required signers.
In the case of a script, the proof of ownership is provided by a withdrawal certificate.
And in the case of an NFT, the proof is provided by both
a reference UTxO containing the NFT and a proof of ownership
for the payment credential of that UTxO, either a key or a script.

The NFT credential is recommended since it makes it easy to rotate the owner credentials,
without the need to update the scope rules in the datum.
Otherwise, changing the scope owner credentials must be authorized by all scope owners.

Each action requiring scope owner credentials must present **badges** in the redeemer.

**Badges**

A "badge" is simply a way to present in a redeemer which credential is being purposely used.
For a key credential, the badge simply states the public key hash.
For a script credential, the badge simply states the script hash.
For an NFT credential, the badge contains the NFT policy ID and asset name,
as well as the index of the reference UTxO containing the NFT.

Presented badges in a redeemer will be verified against the scope owner credentials.
Instead of implicit approval by the presence of a credential in a transaction as a whole,
badges guarantee that the intent of credential owners are explicit.

**Security, Failsafe, and Recovery**

For the security of the treasury, all critical actions must be authorized by all scope owners.
We recommend scope owners to provide an NFT credential,
stored in a multisig to be easily be rotated.

In the case that a scope owner credential is definitively lost,
it is still possible to change it with a majority of the scope owners, and a contestation period.
During the contestation period, any one of the scope owners can cancel the credential change.
It allows to cancel the rotation if the credential is recovered.
It also protects against the unlikely scenario where an attacker gains control
of the majority of the scope credentials.

However, in that extreme situation, attackers will still be able to deplete
scopes of the treasury they have control of.
So this can only protect scopes still under control.

In case a single scope is compromised, a failsafe mechanism can be triggered.
Since that scope credential can contest any recovery attempt,
it cannot be recovered with the regular credentials rotation though.
That’s why the treasury contract has a failsafe account,
which can be used as destination, with N-1 scope owner credentials.
Typically, this can be a donation to the Cardano treasury.
