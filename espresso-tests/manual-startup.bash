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
NITRO_CONTRACTS_SCRIPTS_DIR="ORBIT_ACTIONS_DIR/lib/nitro-contracts/scripts"

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
# A similar env file should be supplied for whatever 
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
# These commands are exclusive to the test.
# * Essential migration sub step * These addresses are likely known addresses to operators in the event of a real migration
PRIVATE_KEY="$(docker compose run scripts print-private-key --account l2owner | tail -n 1 | tr -d '\r\n')"
OWNER_ADDRESS="$(docker compose run scripts print-address --account l2owner | tail -n 1 | tr -d '\r\n')"

cd "$ORBIT_ACTIONS_DIR"
forge script --chain $PARENT_CHAIN_CHAIN_ID ../espresso-tests/DeployMockVerifier.s.sol:DeployMockVerifier --rpc-url $PARENT_CHAIN_RPC_URL --broadcast -vvvv
MOCK_TEE_VERIFIER_ADDRESS=$(cat broadcast/DeployMockVerifier.s.sol/1337/run-latest.json | jq -r '.transactions[0].contractAddress')

echo $MOCK_TEE_VERIFIER_ADDRESS
