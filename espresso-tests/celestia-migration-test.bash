#!/usr/bin/env bash
# This is a utility function for creating assertions at the end of this test.
fail(){
    echo "$*" 1>&2; exit 1;
}

set -euo pipefail
set -a # automatically export all variables
set -x # print each command before executing it, for debugging



# Find directory of this script, the project, and the orbit-actions submodule
TEST_DIR="$(dirname $(readlink -f $0))"
TESTNODE_DIR="$(dirname "$TEST_DIR")"
ORBIT_ACTIONS_DIR="$TESTNODE_DIR/orbit-actions"

# Change to orbit actions directory, update the submodule, and install any dependencies for the purposes of the test.
cd "$ORBIT_ACTIONS_DIR"

git submodule update --init
forge update
yarn

# Change to the top level directory for the purposes of the test.
cd "$TESTNODE_DIR"

# Initialize a standard network not compatible with espresso to simulate a pre-upgrade orbit network e.g. not needed for the real migration
./test-node.bash --simple --init-force --detach --no-build-utils

# Start espresso sequencer node for the purposes of the test e.g. not needed for the real migration.
docker compose up espresso-dev-node --detach

# Export environment variables in .env file
# A similar env file should be supplied for whatever
. "$TEST_DIR/.env"

# Overwrite the ROLLUP_ADDRESS for this test, it might not be the same as the one in the .env file
#* Essential migration sub step * This address (the rollup proxy address) is likely a known address to operators.
export ROLLUP_ADDRESS=$(docker compose run --entrypoint cat scripts /config/deployed_chain_info.json | jq -r '.[0].rollup.rollup' | tail -n 1 | tr -d '\r\n')

# A convoluted way to get the address of the child chain upgrade executor, maybe there's a better way?
# These steps below are just for the purposes of the test. In a real deployment operators will likely already know their child-chain's upgrade executor address, and it should be included in a .env file for the migration run.
export INBOX_ADDRESS=$(docker compose run --entrypoint cat scripts /config/deployed_chain_info.json | jq -r '.[0].rollup.inbox' | tail -n 1 | tr -d '\r\n')
# L1_TOKEN_BRIDGE_CREATOR_ADDRESS=$(docker compose run --entrypoint cat scripts /tokenbridge-data/network.json | jq -r '.l1TokenBridgeCreator' | tail -n 1 | tr -d '\r\n')
# CHILD_CHAIN_UPGRADE_EXECUTOR_ADDRESS=$(cast call $L1_TOKEN_BRIDGE_CREATOR_ADDRESS 'inboxToL2Deployment(address)(address,address,address,address,address,address,address,address,address)' $INBOX_ADDRESS | tail -n 2 | head -n 1 | tr -d '\r\n')

# Export l2 owner private key and address
# These commands are exclusive to the test.
# * Essential migration sub step * These addresses are likely known addresses to operators in the event of a real migration
export PRIVATE_KEY="$(docker compose run scripts print-private-key --account l2owner | tail -n 1 | tr -d '\r\n')"
export OWNER_ADDRESS="$(docker compose run scripts print-address --account l2owner | tail -n 1 | tr -d '\r\n')"

cd $ORBIT_ACTIONS_DIR
forge update
echo "Deploying mock espresso tee verifier"
forge script --chain $PARENT_CHAIN_CHAIN_ID ../espresso-tests/DeployMockVerifier.s.sol:DeployMockVerifier --rpc-url $PARENT_CHAIN_RPC_URL --broadcast -vvvv

export ESPRESSO_TEE_VERIFIER_ADDRESS=$(cat broadcast/DeployMockVerifier.s.sol/1337/run-latest.json | jq -r '.transactions[0].contractAddress' | cast to-checksum)
echo "Mock TEE Address:"
echo $ESPRESSO_TEE_VERIFIER_ADDRESS

# Echo for debug
echo "Deploying and initializing Espresso SequencerInbox"
# ** Essential migration step ** Forge script to deploy the new SequencerInbox. We do this to later point the rollups challenge manager to the espresso integrated OSP.
forge script --chain $PARENT_CHAIN_CHAIN_ID scripts/foundry/contract-upgrades/celestia-2.1.3/DeployCelestiaNitroContracts2Point1Point3UpgradeAction.s.sol:DeployCelestiaNitroContracts2Point1Point3UpgradeActionScript --rpc-url $PARENT_CHAIN_RPC_URL --broadcast -vvvv --sender $OWNER_ADDRESS --private-key $PRIVATE_KEY

# Extract new_osp_entry address from run-latest.json
#  * Essential migration sub step * These addresses are likely known addresses to operators in the event of a real migration after they have deployed the new OSP contracts, however, if operators create a script for the migration, this command is useful.
export UPGRADE_ACTION_ADDRESS=$(cat broadcast/DeployCelestiaNitroContracts2Point1Point3UpgradeAction.s.sol/1337/run-latest.json | jq -r '.transactions[0].contractAddress'| cast to-checksum)
# Echo for debugging.
echo "Deployed Celestia migration action at $UPGRADE_ACTION_ADDRESS"

# Change directories to start nitro node in new docker container with espresso image
cd $TESTNODE_DIR

docker stop nitro-testnode-sequencer-1
docker wait nitro-testnode-sequencer-1
# Start nitro node in new docker container with espresso image
./espresso-tests/create-espresso-integrated-nitro-node.bash
# Use cast to call the upgradeExecutor and execute the L1 upgrade actions.This will point the challenge manager at the new OSP entry, as well as update the wasmModuleRoot for the rollup. ** Essential migration step **
cd $ORBIT_ACTIONS_DIR

forge script --chain $PARENT_CHAIN_CHAIN_ID scripts/foundry/contract-upgrades/celestia-2.1.3/ExecuteCelestiaNitroContracts2Point1Point3Upgrade.s.sol:ExecuteNitroContracts2Point1Point3UpgradeScript --rpc-url $PARENT_CHAIN_RPC_URL --broadcast -vvvv --sender $OWNER_ADDRESS --private-key $PRIVATE_KEY

# cast send $PARENT_CHAIN_UPGRADE_EXECUTOR "execute(address, bytes)" $CELESTIA_MIGRATION_ACTION $(cast calldata "perform(address, address, address)" $ROLLUP_ADDRESS $INBOX $PROXY_ADMIN_ADDRESS ) --rpc-url $PARENT_CHAIN_RPC_URL --private-key $PRIVATE_KEY

echo "Executed SequencerMigrationAction via UpgradeExecutor"

# Get the number of confirmed nodes before the upgrade to ensure the staker is still working.
NUM_CONFIRMED_NODES_BEFORE_UPGRADE=$(cast call --rpc-url $PARENT_CHAIN_RPC_URL $ROLLUP_ADDRESS 'latestConfirmed()(uint256)')


# Wait for CHILD_CHAIN_RPC_URL to be available
# * Essential migration sub step * This is technically essential to the migration, but doesn't usually take long and shouldn't need to be programatically determined during a live migration.
while ! curl -s $CHILD_CHAIN_RPC_URL > /dev/null; do
  echo "Waiting for $CHILD_CHAIN_RPC_URL to be available..."
  sleep 5
done

# Echo for debugging
echo "Adding child chain upgrade executor as an L2 chain owner"
# This step is done for the purposes of the test, as there should already be an upgrade executor on the child chain that is a chain owner
# cast send 0x0000000000000000000000000000000000000070 'addChainOwner(address)' $CHILD_CHAIN_UPGRADE_EXECUTOR_ADDRESS --rpc-url $CHILD_CHAIN_RPC_URL --private-key $PRIVATE_KEY

cd $ORBIT_ACTIONS_DIR
# Check for balance before transfer.
# The following sequence is to check that transactions are still successfully being sequenced on the L2
ORIGINAL_OWNER_BALANCE=$(cast balance $OWNER_ADDRESS -e --rpc-url $CHILD_CHAIN_RPC_URL)

# Send 1 eth as the owner
RECIPIENT_ADDRESS=0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
BALANCE_ORIG=$(cast balance $RECIPIENT_ADDRESS -e --rpc-url $CHILD_CHAIN_RPC_URL)
cast send $RECIPIENT_ADDRESS --value 1ether --rpc-url $CHILD_CHAIN_RPC_URL --private-key $PRIVATE_KEY

# Get the new balance after the transfer.
BALANCE_NEW=$(cast balance $RECIPIENT_ADDRESS -e --rpc-url $CHILD_CHAIN_RPC_URL)

# Assertion that balance should have changed.
if [ $BALANCE_NEW == $BALANCE_ORIG ]; then
  fail "Balance of $RECIPIENT_ADDRESS should have changed but remained: $BALANCE_ORIG"
fi
# Echo successful balance update
echo "Balance of $RECIPIENT_ADDRESS changed from $BALANCE_ORIG to $BALANCE_NEW"

# Check that the staker is making progress after the upgrade
while [ "$NUM_CONFIRMED_NODES_BEFORE_UPGRADE" == "$(cast call --rpc-url $PARENT_CHAIN_RPC_URL $ROLLUP_ADDRESS 'latestConfirmed()(uint256)')" ]; do
  echo "Waiting for confirmed nodes ..."
  sleep 5
done
# Echo to confirm that stakers are behaving normally.
echo "Confirmed nodes have progressed"

# Echo to signal that test has been successful
echo "Migration successfully completed!"

docker compose down
