use aiken/collection/list
use cardano/address.{Address, Script}
use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{InlineDatum, Output}
use env

/// Apply a function to the zipped list created from the two lists.
pub fn for_each_2(l1: List<a>, l2: List<b>, do: fn(a, b) -> Void) {
  // TODO: optimize this function
  let zipped = list.zip(l1, l2)
  list.for_each(zipped, fn((x1, x2)) { do(x1, x2) })
}

/// Fold over two lists.
pub fn fold_2(l1: List<a>, l2: List<b>, init: c, step: fn(a, b, c) -> c) -> c {
  // TODO: optimize this function
  let zipped = list.zip(l1, l2)
  list.foldl(zipped, init, fn((x1, x2), acc) { step(x1, x2, acc) })
}

/// Helper function checking the exact shape of an output,
/// which must only contain a single unique token,
/// and returns the inline datum for a continuation check
pub fn check_output_single_token(
  output: Output,
  policy_id: PolicyId,
  asset_name: AssetName,
  min_ada: Int,
  check_datum: fn(Data) -> Void,
) {
  // Check that the output address is the treasury address
  expect output.address.payment_credential == Script(policy_id)

  // Check that the stake credential is empty if not allowed to stake
  expect output.address.stake_credential == None || env.stake_allowed

  // Check that there is no ref script in the output
  expect output.reference_script == None

  // Check that the output contains only some ada and the NFT for the scope
  let expected_value =
    assets.from_lovelace(min_ada)
      |> assets.add(policy_id, asset_name, 1)
  expect output.value == expected_value

  // Check that the datum is exactly this scope
  expect InlineDatum(data) = output.datum
  check_datum(data)
}
