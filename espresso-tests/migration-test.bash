#!/usr/bin/env bash
# This is a utility function for creating assertions at the end of this test.
fail(){
    echo "$*" 1>&2; exit 1;
}

set -euo pipefail
set -a # automatically export all variables
# set -x # print each command before executing it, for debugging

# CI is "true" in the CI
CI="${CI:-false}"

# Output debug information on CI
DEBUG="${DEBUG:-false}"
if [ "$CI" = "true" ]; then
  set -x
  DEBUG=true
fi

# Show the command we are running, then run it. Due to piping this spawns a
# subshell so does not work for command like `cd` or `source`.
function run {
  echo -e "\033[34m>>> $*\033[0m"
  "$@" 2>&1 | fmt
}

function cd {
  emph "cd $*"
  builtin cd "$@"
}

function emph {
  echo -e "\033[34m>>> $*\033[0m\n"
}

# Display only the last line of piped input, continuously updating
function fmt {
  # Leave output unchanged in DEBUG mode
  if [ "$DEBUG" = "true" ]; then
    cat
    return
  fi
  # rewrite the last line to avoid noisy output
  while read -r line; do
    tput cr
    tput el
    echo "$line" | cut -c -"$(tput cols)" | tr -d '\r\n'
  done
  echo
}

# Show something with a comment in front, to distinguish it from console output.
function info {
  echo "# $@"
}

# Remove log files on exit
trap "exit" INT TERM
trap cleanup EXIT
function cleanup {
  exit_code=$?
  if [ $exit_code -ne 0 ]; then
    echo
    echo "An error occurred."
    if [ -s "$ESPRESSO_DEVNODE_LOG_FILE" ]; then
      echo "Espresso dev node logs:"
      cat "$ESPRESSO_DEVNODE_LOG_FILE"
      exit $exit_code
    elif [ -s "$TESTNODE_LOG_FILE" ]; then
      echo "Nitro testnode logs:"
      cat "$TESTNODE_LOG_FILE"
      exit $exit_code
    fi
  else
    rm -vf "$TESTNODE_LOG_FILE"
    rm -vf "$ESPRESSO_DEVNODE_LOG_FILE"
  fi
}

# Find directory of this script, the project, and the orbit-actions submodule
TEST_DIR="$(dirname $(readlink -f $0))"
TESTNODE_LOG_FILE=$(mktemp -t nitro-test-node-logs-XXXXXXXX)
ESPRESSO_DEVNODE_LOG_FILE=$(mktemp -t espresso-dev-node-logs-XXXXXXXX)
TESTNODE_DIR="$(dirname "$TEST_DIR")"
ORBIT_ACTIONS_DIR="$TESTNODE_DIR/orbit-actions"
ENV_FILE="$TEST_DIR/.env"
# Hide docker compose warnings about orphaned containers.
export COMPOSE_IGNORE_ORPHANS=true

info Ensuring docker compose project is stopped
run docker compose down -v --remove-orphans

# Change to orbit actions directory, update the submodule, and install any dependencies for the purposes of the test.
cd "$ORBIT_ACTIONS_DIR"

info "Ensuring submodules are checked out"
run git submodule update --init --recursive

info "Ensuring nodejs dependencies are installed"
run yarn

info "Ensuring we can compile the migration smart contracts"
run forge build

# Change to the top level directory for the purposes of the test.
cd "$TESTNODE_DIR"

# NOTE: the test-node.bash script (or potentially docker compose) does not work
# well with the `fmt` utility function and hangs at the end. I don't know why.
# Furthermore the long warning lines don't work with the `fmt` function but I
# can't work out a way to be able to filter the lines (e. g. grep -v WARN) and
# still have the output show up.

# This commit matches v2.1.0 release of nitro-contracts, with additional support to set arb owner through upgrade executor
NITRO_CONTRACTS_BRANCH="99c07a7db2fcce75b751c5a2bd4936e898cda065"
info Deploying a vanilla Nitro stack locally, to be migrated to Espresso later.
emph ./test-node.bash --simple --init-force --tokenbridge --detach
if [ "$DEBUG" = "true" ]; then
  ./test-node.bash --simple --init-force --tokenbridge --detach
else
  info "This command starts up an entire Nitro stack. It takes a long time."
  info "Run \`tail -f $TESTNODE_LOG_FILE\` to see logs, if necessary."
  echo
  ./test-node.bash --simple --init-force --tokenbridge --detach > "$TESTNODE_LOG_FILE" 2>&1
fi

# Start espresso sequencer node for the purposes of the test e.g. not needed for the real migration.
info "Starting a local Espresso confirmation layer development node"
emph docker compose up espresso-dev-node --detach
if [ "$DEBUG" = "true" ]; then
  docker compose up espresso-dev-node --detach
else
  info "Run \`tail -f $ESPRESSO_DEVNODE_LOG_FILE\` to see logs, if necessary."
  echo
  docker compose up espresso-dev-node --detach > "$ESPRESSO_DEVNODE_LOG_FILE" 2>&1
fi

info "Load environment variables in $ENV_FILE"
# A similar env file should be supplied for whatever
emph . "$TEST_DIR/.env"
. "$TEST_DIR/.env"
echo
info "Loaded env vars:"
echo
cat "$TEST_DIR/.env" | sed 's/^/    /'
echo

function trim-last {
  tail -n 1 | tr -d '\r\n'

}
function get-addr {
  local file="$1"
  local path="$2"
  docker compose run --entrypoint cat scripts $file | jq -r "$path" | trim-last
}

# Overwrite the ROLLUP_ADDRESS for this test, it might not be the same as the one in the .env file
#* Essential migration sub step * This address (the rollup proxy address) is likely a known address to operators.
ROLLUP_ADDRESS=$(get-addr /config/deployed_chain_info.json '.[0].rollup.rollup')
declare -p ROLLUP_ADDRESS

# A convoluted way to get the address of the child chain upgrade executor, maybe there's a better way?
# These steps below are just for the purposes of the test. In a real deployment operators will likely already know their child-chain's upgrade executor address, and it should be included in a .env file for the migration run.
INBOX_ADDRESS=$(get-addr /config/deployed_chain_info.json '.[0].rollup.inbox')
declare -p INBOX_ADDRESS

PARENT_CHAIN_UPGRADE_EXECUTOR=$(get-addr /config/deployed_chain_info.json '.[0].rollup["upgrade-executor"]')
declare -p PARENT_CHAIN_UPGRADE_EXECUTOR

L1_TOKEN_BRIDGE_CREATOR_ADDRESS=$(get-addr /tokenbridge-data/network.json '.l1TokenBridgeCreator')
declare -p L1_TOKEN_BRIDGE_CREATOR_ADDRESS

CHILD_CHAIN_UPGRADE_EXECUTOR_ADDRESS=$(cast call $L1_TOKEN_BRIDGE_CREATOR_ADDRESS 'inboxToL2Deployment(address)(address,address,address,address,address,address,address,address,address)' $INBOX_ADDRESS | tail -n 2 | head -n 1 | tr -d '\r\n')
declare -p CHILD_CHAIN_UPGRADE_EXECUTOR_ADDRESS

# Export l2 owner private key and address
# These commands are exclusive to the test.
# * Essential migration sub step * These addresses are likely known addresses to operators in the event of a real migration
PRIVATE_KEY="$(docker compose run scripts print-private-key --account l2owner 2>/dev/null | trim-last)"
# This is a private key used for testing, save to print
declare -p PRIVATE_KEY

OWNER_ADDRESS="$(docker compose run scripts print-address --account l2owner 2>/dev/null | trim-last)"
declare -p OWNER_ADDRESS

info "Disabling validator whitelist"
run cast send $PARENT_CHAIN_UPGRADE_EXECUTOR "executeCall(address,bytes)" $ROLLUP_ADDRESS "$(cast calldata 'setValidatorWhitelistDisabled(bool)' true)" --rpc-url $PARENT_CHAIN_RPC_URL --private-key $PRIVATE_KEY

cd $ORBIT_ACTIONS_DIR
info "Deploying mock espresso TEE verifier"
run forge script --chain $PARENT_CHAIN_CHAIN_ID ../espresso-tests/DeployMockVerifier.s.sol:DeployMockVerifier --rpc-url $PARENT_CHAIN_RPC_URL --broadcast -vvvv

ESPRESSO_TEE_VERIFIER_ADDRESS=$(cat broadcast/DeployMockVerifier.s.sol/1337/run-latest.json | jq -r '.transactions[0].contractAddress' | cast to-checksum)
declare -p ESPRESSO_TEE_VERIFIER_ADDRESS

# Echo for debug
info "Deploying and initializing Espresso SequencerInbox"
# ** Essential migration step ** Forge script to deploy the new SequencerInbox. We do this to later point the rollups challenge manager to the espresso integrated OSP.
run forge script --chain $PARENT_CHAIN_CHAIN_ID ../espresso-tests/DeployAndInitEspressoSequencerInboxForTest.s.sol:DeployAndInitEspressoSequencerInbox --rpc-url $PARENT_CHAIN_RPC_URL --broadcast -vvvv --skip-simulation

#  * Essential migration sub step * These addresses are likely known addresses to operators in the event of a real migration after they have deployed the new OSP contracts, however, if operators create a script for the migration, this command is useful.
NEW_SEQUENCER_INBOX_IMPL_ADDRESS=$(cat broadcast/DeployAndInitEspressoSequencerInboxForTest.s.sol/1337/run-latest.json | jq -r '.receipts[0].contractAddress'| cast to-checksum)
declare -p NEW_SEQUENCER_INBOX_IMPL_ADDRESS

# Echo for debugging.
info "Deployed new SequencerInbox at $NEW_SEQUENCER_INBOX_IMPL_ADDRESS"

# Echo for debug
info "Deploying Espresso SequencerInbox migration action"

# ** Essential migration step ** Forge script to deploy Espresso OSP migration action
run forge script --chain $PARENT_CHAIN_CHAIN_ID contracts/parent-chain/espresso-migration/DeployEspressoSequencerMigrationAction.s.sol:DeployEspressoSequencerMigrationAction --rpc-url $PARENT_CHAIN_RPC_URL --broadcast -vvvv

# Capture new OSP address
# * Essential migration sub step ** Essential migration sub step * operators will be able to manually determine this address while running the upgrade, but this can be useful if they wish to make a script.
SEQUENCER_MIGRATION_ACTION=$(cat broadcast/DeployEspressoSequencerMigrationAction.s.sol/1337/run-latest.json | jq -r '.transactions[0].contractAddress' | cast to-checksum)
declare -p SEQUENCER_MIGRATION_ACTION

info "Deployed new EspressoSequencerMigrationAction at $SEQUENCER_MIGRATION_ACTION"

cd $TESTNODE_DIR

run docker stop nitro-testnode-sequencer-1
run docker wait nitro-testnode-sequencer-1

# Start nitro node in new docker container with espresso image
run ./espresso-tests/create-espresso-integrated-nitro-node.bash
# Use cast to call the upgradeExecutor and execute the L1 upgrade actions.This will point the challenge manager at the new OSP entry, as well as update the wasmModuleRoot for the rollup. ** Essential migration step **
run cast send $PARENT_CHAIN_UPGRADE_EXECUTOR "execute(address, bytes)" $SEQUENCER_MIGRATION_ACTION $(cast calldata "perform()") --rpc-url $PARENT_CHAIN_RPC_URL --private-key $PRIVATE_KEY

info "Executed SequencerMigrationAction via UpgradeExecutor"

# Get the number of confirmed nodes before the upgrade to ensure the staker is still working.
NUM_CONFIRMED_NODES_BEFORE_UPGRADE=$(cast call --rpc-url $PARENT_CHAIN_RPC_URL $ROLLUP_ADDRESS 'latestConfirmed()(uint256)')


# Wait for CHILD_CHAIN_RPC_URL to be available
# * Essential migration sub step * This is technically essential to the migration, but doesn't usually take long and shouldn't need to be programmatically determined during a live migration.
while ! curl -s $CHILD_CHAIN_RPC_URL > /dev/null; do
  info "Waiting for $CHILD_CHAIN_RPC_URL to be available..."
  sleep 5
done

info "Testing if the Espresso integration works by doing an Eth transfer."
RECIPIENT_ADDRESS=0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
BALANCE_ORIG=$(cast balance $RECIPIENT_ADDRESS -e --rpc-url $CHILD_CHAIN_RPC_URL)
run cast send $RECIPIENT_ADDRESS --value 1ether --rpc-url $CHILD_CHAIN_RPC_URL --private-key $PRIVATE_KEY

# Get the new balance after the transfer.
BALANCE_NEW=$(cast balance $RECIPIENT_ADDRESS -e --rpc-url $CHILD_CHAIN_RPC_URL)

# Assertion that balance should have changed.
if [ $BALANCE_NEW == $BALANCE_ORIG ]; then
  fail "Balance of $RECIPIENT_ADDRESS should have changed but remained: $BALANCE_ORIG"
fi
# Echo successful balance update
echo "Balance of $RECIPIENT_ADDRESS changed from $BALANCE_ORIG to $BALANCE_NEW"

info Check that the staker is making progress after the upgrade
echo

START=$SECONDS
echo "Waiting for confirmed nodes."
while [ "$NUM_CONFIRMED_NODES_BEFORE_UPGRADE" == "$(cast call --rpc-url $PARENT_CHAIN_RPC_URL $ROLLUP_ADDRESS 'latestConfirmed()(uint256)')" ]; do
  sleep 5
  echo "Waited $(( SECONDS - START )) seconds for confirmed nodes."
done

# Echo to confirm that stakers are behaving normally.
echo "Confirmed nodes have progressed"

# Echo to signal that test has been successful
echo "Migration successfully completed!"

run docker compose down -v --remove-orphans
