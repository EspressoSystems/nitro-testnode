#!/usr/bin/env bash
# This is a utility function for creating assertions at the end of thie test.

set -euo pipefail

# CI is "true" in the CI
CI="${CI:-false}"

# Output debug information on CI or when DEBUG is set
DEBUG="${DEBUG:-false}"
if [ "$CI" = "true" ]; then
  DEBUG=true
fi

# Simple helpers
info() { echo "# $*"; }


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

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
TESTNODE_LOG_FILE=$(mktemp -t nitro-test-node-logs-XXXXXXXX)
ESPRESSO_DEVNODE_LOG_FILE=$(mktemp -t espresso-dev-node-logs-XXXXXXXX)
TESTNODE_DIR="$(dirname "$TEST_DIR")"
ENV_FILE="$TEST_DIR/.env"
# Hide docker compose warnings about orphaned containers.
export COMPOSE_IGNORE_ORPHANS=true

info "Ensuring docker compose project is stopped"
docker compose down -v --remove-orphans

# source "$TESTNODE_DI R/common.bash"
cd "$(dirname "$0")"

source ./common.bash
info "Deploying an Espresso Nitro stack with caff node enabled"
if [ "$DEBUG" = "true" ]; then
  "$TESTNODE_DIR/test-node.bash" --espresso $(get_espresso_image_flag) --caff-node --tokenbridge --init-force --detach
else
  info "This command starts up an entire Nitro stack. It takes a long time."
  info "Run \`tail -f $TESTNODE_LOG_FILE\` to see logs, if necessary."
  echo
  "$TESTNODE_DIR/test-node.bash" --espresso $(get_espresso_image_flag) --validate --tokenbridge --caff-node --init-force --detach > "$TESTNODE_LOG_FILE" 2>&1
fi

# Start espresso sequencer node for the purposes of the test e.g. not needed for the real migration.
info "Starting a local Espresso confirmation layer development node"
if [ "$DEBUG" = "true" ]; then
  docker compose up espresso-dev-node --detach
else
  info "Run \`tail -f $ESPRESSO_DEVNODE_LOG_FILE\` to see logs, if necessary."
  echo
  docker compose up espresso-dev-node --detach > "$ESPRESSO_DEVNODE_LOG_FILE" 2>&1
fi


info "Load environment variables in $ENV_FILE"
# A similar env file should be supplied for whatever
info "Sourcing $ENV_FILE"
. "$ENV_FILE"
echo
info "Loaded env vars:"
echo
cat "$TEST_DIR/.env" | sed 's/^/    /'
echo

trim-last() { tail -n 1 | tr -d '\r\n'; }
function get-addr {
  local file="$1"
  local path="$2"
  docker compose run --entrypoint cat scripts $file | jq -r "$path" | trim-last
}


PARENT_CHAIN_UPGRADE_EXECUTOR=$(get-addr /config/deployed_chain_info.json '.[0].rollup."upgrade-executor"')
declare -p PARENT_CHAIN_UPGRADE_EXECUTOR

SEQUENCER_INBOX=$(get-addr /config/deployed_chain_info.json '.[0].rollup."sequencer-inbox"')
declare -p SEQUENCER_INBOX

INBOX_ADDRESS=$(get-addr /config/deployed_chain_info.json '.[0].rollup.inbox')
declare -p INBOX_ADDRESS

echo "UPGRADE_EXECUTOR: $PARENT_CHAIN_UPGRADE_EXECUTOR"
echo "SEQUENCER_INBOX: $SEQUENCER_INBOX"
echo "Inbox: $INBOX_ADDRESS"

while true; do
    # Before setting the max delay verify that Caff node is running
    CAFF_NODE_RESPONSE=$(cast balance 0x3f1Eae7D46d88F08fc2F8ed27FCb2AB183EB2d0E --rpc-url http://127.0.0.1:8550)

    if [[ $CAFF_NODE_RESPONSE == "0" ]]; then
        echo "Caff node is catching up, wait"
        sleep 10
    else
        break
    fi
done

PRIVATE_KEY="$(docker compose run scripts print-private-key --account l2owner 2>/dev/null | trim-last)"
# This is a private key used for testing, save to print
declare -p PRIVATE_KEY

# Set the max delay blocks to 10 blocks, future blocks to 120 blocks, delay seconds to 150 seconds, future seconds to 3600 seconds
cast send $PARENT_CHAIN_UPGRADE_EXECUTOR $(cast calldata "executeCall(address, bytes)" $SEQUENCER_INBOX  $(cast calldata "setMaxTimeVariation((uint256,uint256,uint256,uint256))"  "(10,120,150,3600)"))  --rpc-url $PARENT_CHAIN_RPC_URL --private-key $PRIVATE_KEY

#  First call the maxTimeVariation function to get the max time variation
{
  read DELAY_BLOCKS
  read FUTURE_BLOCKS
  read DELAY_SECONDS
  read FUTURE_SECONDS
} < <(
  cast call --rpc-url "$PARENT_CHAIN_RPC_URL" "$SEQUENCER_INBOX" \
    'maxTimeVariation()(uint256,uint256,uint256,uint256)' |
    awk '{print $1}'  # Extract only the first field (in case of extra text like "[8.64e4]")
)

echo "DELAY_BLOCKS: $DELAY_BLOCKS"
echo "FUTURE_BLOCKS: $FUTURE_BLOCKS"
echo "DELAY_SECONDS: $DELAY_SECONDS"
echo "FUTURE_SECONDS: $FUTURE_SECONDS"

# Now we stop the sequencer
docker stop nitro-testnode-sequencer-1 || true

USER_L1_PRIVATE_KEY="$(docker compose run scripts print-private-key --account funnel 2>/dev/null | trim-last)"
# This is a private key used for testing, save to print
declare -p USER_L1_PRIVATE_KEY

# Add retry logic to send delayed message because sometimes it fails on the first attempt
MAX_RETRIES=5
RETRY_DELAY=5  # seconds between retries

# Your original command
CMD="cast send $INBOX_ADDRESS \$(cast calldata \"sendL2MessageFromOrigin(bytes)\" \"0x123456\") --rpc-url $PARENT_CHAIN_RPC_URL --private-key $USER_L1_PRIVATE_KEY --gas-limit 20000000"

# Retry logic
retry_count=0
while [ $retry_count -lt $MAX_RETRIES ]; do
    echo "Attempt $((retry_count + 1)) of $MAX_RETRIES..."

    if eval "$CMD"; then
        echo "Command succeeded!"
        break
    else
        echo "Command failed. Retrying in $RETRY_DELAY seconds..."
        sleep $RETRY_DELAY
        ((retry_count++))
    fi
done

if [ $retry_count -ge $MAX_RETRIES ]; then
    echo "All retries failed. Exiting."
    exit 1
fi

sleep 120


# has_force_inclusion_log() {
#     local container_name="caff-node-1"
#     local search_string="force inclusion is going to happen"
#     if docker logs "$container_name" 2>&1 | grep -q "$search_string"; then
#         return 1
#     else
#         return 0
#     fi
# }


# if has_force_inclusion_log "caff-node-1" "force inclusion is going to happen"; then
#   echo "It printed force inclusion is going to happen log"
#   docker compose down --remove-orphans
#   exit 0
# else
#   echo "Caff node did not print force inclusion log"
#   exit 1
# fi

if docker logs "caff-node-1" 2>&1 | grep -q "force inclusion is going to happen"; then
  echo "It printed force inclusion is going to happen log"
  docker compose down --remove-orphans
  exit 0
else
  echo "Caff node did not print force inclusion log"
  exit 1
fi
