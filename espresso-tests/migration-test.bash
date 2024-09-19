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
yarn

# Change to the top level directory for the purposes of the test.
cd "$TESTNODE_DIR"

# Initialize a standard network not compatible with espresso to simulate a pre-upgrade orbit network e.g. not needed for the real migration
./test-node.bash --simple --init-force --tokenbridge --detach

# Start espresso sequencer node for the purposes of the test e.g. not needed for the real migration.
docker compose up espresso-dev-node --detach

# Export environment variables in .env file
. "$TEST_DIR/.env"

# Overwrite the ROLLUP_ADDRESS for this test, it might not be the same as the one in the .env file
#* Essential migration sub step * This address (the rollup proxy address) is likely a known address to operators. 
ROLLUP_ADDRESS=$(docker compose run --entrypoint cat scripts /config/deployed_chain_info.json | jq -r '.[0].rollup.rollup' | tail -n 1 | tr -d '\r\n')

# A convoluted way to get the address of the child chain upgrade executor, maybe there's a better way?
# These steps below are just for the purposes of the test. In a real deployment operators will likely already know their child-chain's upgrade executor address, and it should be included in a .env file for the migration run.
INBOX_ADDRESS=$(docker compose run --entrypoint cat scripts /config/deployed_chain_info.json | jq -r '.[0].rollup.inbox' | tail -n 1 | tr -d '\r\n')
L1_TOKEN_BRIDGE_CREATOR_ADDRESS=$(docker compose run --entrypoint cat scripts /tokenbridge-data/network.json | jq -r '.l1TokenBridgeCreator' | tail -n 1 | tr -d '\r\n')
CHILD_CHAIN_UPGRADE_EXECUTOR_ADDRESS=$(cast call $L1_TOKEN_BRIDGE_CREATOR_ADDRESS 'inboxToL2Deployment(address)(address,address,address,address,address,address,address,address,address)' $INBOX_ADDRESS | tail -n 2 | head -n 1 | tr -d '\r\n')

# Export l2 owner private key and address
# * Essential migration sub step * These addresses are likely known addresses to operators in the event of a real migration
PRIVATE_KEY="$(docker compose run scripts print-private-key --account l2owner | tail -n 1 | tr -d '\r\n')"
OWNER_ADDRESS="$(docker compose run scripts print-address --account l2owner | tail -n 1 | tr -d '\r\n')"

echo "Deploying Espresso Osp"

# Change directory to orbit actions dir for the following commands.
cd $ORBIT_ACTIONS_DIR

# ** Essential migration step ** Forge script to deploy new OSP entry. We do this to later point the rollups challenge manager to the espresso integrated OSP.
forge script --chain $PARENT_CHAIN_CHAIN_ID contracts/parent-chain/espresso-migration/DeployEspressoOsp.s.sol:DeployEspressoOsp --rpc-url $PARENT_CHAIN_RPC_URL --broadcast -vvvv

# Extract new_osp_entry address from run-latest.json
#  * Essential migration sub step * These addresses are likely known addresses to operators in the event of a real migration after they have deployed the new OSP contracts, however, if operators create a script for the migration, this command is useful.
NEW_OSP_ENTRY=$(cat broadcast/DeployEspressoOsp.s.sol/1337/run-latest.json | jq -r '.transactions[4].contractAddress'| cast to-checksum)

echo "Deployed new OspEntry at $NEW_OSP_ENTRY"

echo "Deploying Espresso Osp migration action"

# ** Essential migration step ** Forge script to deploy Espresso OSP migration action
forge script --chain $PARENT_CHAIN_CHAIN_ID contracts/parent-chain/espresso-migration/DeployEspressoOspMigrationAction.s.sol --rpc-url $PARENT_CHAIN_RPC_URL --broadcast -vvvv

# Capture new OSP address
# * Essential migration sub step ** Essential migration sub step * operators will be able to manually determine this address while running the upgrade, but this can be useful if they wish to make a script.
OSP_MIGRATION_ACTION=$(cat broadcast/DeployEspressoOspMigrationAction.s.sol/1337/run-latest.json | jq -r '.transactions[0].contractAddress')

echo "Deployed new OspMigrationAction at $OSP_MIGRATION_ACTION"

# Use cast to call the upgradeExecutor and execute the L1 upgrade actions.This will point the challenge manager at the new OSP entry, as well as update the wasmModuleRoot for the rollup.
# ** Essential migration step **

cast send $PARENT_CHAIN_UPGRADE_EXECUTOR "execute(address, bytes)" $OSP_MIGRATION_ACTION $(cast calldata "perform()") --rpc-url $PARENT_CHAIN_RPC_URL --private-key $PRIVATE_KEY

echo "Executed OspMigrationAction via UpgradeExecutor"

# Get the number of confirmed nodes before the upgrade to ensure the staker is still working.
NUM_CONFIRMED_NODES_BEFORE_UPGRADE=$(cast call --rpc-url $PARENT_CHAIN_RPC_URL $ROLLUP_ADDRESS 'latestConfirmed()(uint256)')

# ** Essential migration step ** The previous sequencer that is not compatible with espresso must be shut down so that we can start a new sequencer node that can have it's ArbOS version updated to signify the upgrade has occurred.
docker stop nitro-testnode-sequencer-1

cd $TESTNODE_DIR

# Start nitro node in new docker container with espresso image
./espresso-tests/create-espresso-integrated-nitro-node.bash

# Wait for CHILD_CHAIN_RPC_URL to be available
# * Essential migration sub step * This is technically essential to the migration, but doesn't usually take long and shouldn't need to be programatically determined during a live migration.
while ! curl -s $CHILD_CHAIN_RPC_URL > /dev/null; do
  echo "Waiting for $CHILD_CHAIN_RPC_URL to be available..."
  sleep 5
done

echo "Adding child chain upgrade executor as an L2 chain owner"
# This step is done for the purposes of the test, as there should already be an upgrade executor on the child chain that is a chain owner
cast send 0x0000000000000000000000000000000000000070 'addChainOwner(address)' $CHILD_CHAIN_UPGRADE_EXECUTOR_ADDRESS --rpc-url $CHILD_CHAIN_RPC_URL --private-key $PRIVATE_KEY

echo "Deploying ArbOS Upgrade action"

cd $ORBIT_ACTIONS_DIR

# Forge script to deploy the Espresso ArbOS upgrade action.
# ** Essential migration step ** the ArbOS upgrade signifies that the chain is now espresso compatible.
forge script --chain $CHILD_CHAIN_CHAIN_NAME contracts/child-chain/arbos-upgrade/DeployArbOSUpgradeAction.s.sol:DeployArbOSUpgradeAction  --rpc-url $CHILD_CHAIN_RPC_URL --broadcast -vvvv

# Get the address of the newly deployed upgrade action.
ARBOS_UPGRADE_ACTION=$(cat broadcast/DeployArbOSUpgradeAction.s.sol/412346/run-latest.json | jq -r '.transactions[0].contractAddress')

echo "Deployed ArbOSUpgradeAction at $ARBOS_UPGRADE_ACTION"

# Grab the pre-upgrade ArbOS version for testing.
ARBOS_VERSION_BEFORE_UPGRADE=$(cast call "0x0000000000000000000000000000000000000064" "arbOSVersion()(uint64)" --rpc-url $CHILD_CHAIN_RPC_URL)

# Use the Upgrde executor on the child chain to execute the ArbOS upgrade to signify that the node is now operating in espresso mode. This is essential for the migration.
# ** Essential migration step ** This step can technically be done before all of the others as it is just scheduling the ArbOS upgrade. The unix timestamp at which the upgrade occurrs can be determined by operators, but for the purposes of the test we use 0 to upgrade immediately.
cast send $CHILD_CHAIN_UPGRADE_EXECUTOR_ADDRESS "execute(address, bytes)" $ARBOS_UPGRADE_ACTION $(cast calldata "perform()") --rpc-url $CHILD_CHAIN_RPC_URL --private-key $PRIVATE_KEY

# Check the upgrade happened

# Grab the post upgrade ArbOS version.
ARBOS_VERSION_AFTER_UPGRADE=$(cast call "0x0000000000000000000000000000000000000064" "arbOSVersion()(uint64)" --rpc-url $CHILD_CHAIN_RPC_URL)

# Wait to observe the ArbOS version update. (potentially add a timeout or max retry number before failing)
while [ $ARBOS_VERSION_BEFORE_UPGRADE == $ARBOS_VERSION_AFTER_UPGRADE ]
do
  sleep 5
  ARBOS_VERSION_AFTER_UPGRADE=$(cast call "0x0000000000000000000000000000000000000064" "arbOSVersion()(uint64)" --rpc-url $CHILD_CHAIN_RPC_URL)
done

# We are upgrading the ArbOS version to 35 so the expect the return value to be 55 + 35 = 90
if [ $ARBOS_VERSION_AFTER_UPGRADE != "90" ]; then
  fail "ArbOS version not updated: Expected 90, Actual $ARBOS_VERSION_AFTER_UPGRADE"
fi

# Cast call to child chain upgrade executor that targets the ArbOwner precompile with the wasm
# The hard code address is the ArbOwner precompile location

cd $TEST_DIR

cast send $CHILD_CHAIN_UPGRADE_EXECUTOR_ADDRESS "execute(address, bytes)" 0x0000000000000000000000000000000000000070 $(cast calldata "setChainConfig(string)" "$(cat ./test-chain-config.json)") --rpc-url $CHILD_CHAIN_RPC_URL --private-key $PRIVATE_KEY

cd $ORBIT_ACTIONS_DIR

# Test for new OSP address
CHALLENGE_MANAGER_OSP_ADDRESS=$(cast call $CHALLENGE_MANAGER_ADDRESS "osp()(address)" --rpc-url $PARENT_CHAIN_RPC_URL)
if [ $NEW_OSP_ENTRY != $CHALLENGE_MANAGER_OSP_ADDRESS ]; then
  fail "OSP has not been set to newly deployed OSP: \n Newly deployed: $NEW_OSP_ENTRY \n Currently set OSP: $CHALLENGE_MANAGER_OSP_ADDRESS"
fi

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
echo "Balance of $RECIPIENT_ADDRESS changed from $BALANCE_ORIG to $BALANCE_NEW"

# Check that the staker is making progress after the upgrade
while [ "$NUM_CONFIRMED_NODES_BEFORE_UPGRADE" == "$(cast call --rpc-url $PARENT_CHAIN_RPC_URL $ROLLUP_ADDRESS 'latestConfirmed()(uint256)')" ]; do
  echo "Waiting for confirmed nodes ..."
  sleep 5
done

echo "Confirmed nodes have progressed"

echo "Migration successfully completed!"

docker compose down
