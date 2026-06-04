#!/usr/bin/env bash
fail(){
    echo "$*" 1>&2; exit 1;
}

set -euo pipefail
set -a

CI="${CI:-false}"
DEBUG="${DEBUG:-false}"
if [ "$CI" = "true" ]; then
  set -x
  DEBUG=true
fi

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

function fmt {
  if [ "$DEBUG" = "true" ]; then
    cat
    return
  fi
  while read -r line; do
    tput cr
    tput el
    echo "$line" | cut -c -"$(tput cols)" | tr -d '\r\n'
  done
  echo
}

function info {
  echo "# $@"
}

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

MAX_WAIT_SECONDS=300

TEST_DIR="$(dirname $(readlink -f $0))"
TESTNODE_LOG_FILE=$(mktemp -t nitro-test-node-logs-XXXXXXXX)
ESPRESSO_DEVNODE_LOG_FILE=$(mktemp -t espresso-dev-node-logs-XXXXXXXX)
TESTNODE_DIR="$(dirname "$TEST_DIR")"
ORBIT_ACTIONS_DIR="$TESTNODE_DIR/orbit-actions"
ORBIT_MIGRATION_ACTION_DIR="contracts/parent-chain/espresso-migration/"
ENV_FILE="$TEST_DIR/.env"
export COMPOSE_IGNORE_ORPHANS=true

ESPRESSO_NITRO_CONTRACTS_BRANCH=fix-mock-v2.1.3-6c81804

info Ensuring docker compose project is stopped
run docker compose down -v --remove-orphans

cd "$ORBIT_ACTIONS_DIR"

info "Ensuring submodules are checked out"
run git submodule update --init --recursive

info "Ensuring nodejs dependencies are installed"
run yarn --ignore-scripts

cd "$TESTNODE_DIR"

# ── Phase 1: Start legacy Espresso stack with validation + AnyTrust ──

info "Phase 1: Deploying legacy Espresso stack with validation and AnyTrust"
emph "ESPRESSO_NITRO_CONTRACTS_BRANCH=$ESPRESSO_NITRO_CONTRACTS_BRANCH ./test-node.bash --espresso --latest-espresso-image --validate --l2-anytrust --init-force --detach"
if [ "$DEBUG" = "true" ]; then
  ESPRESSO_VERSION=ghcr.io/espressosystems/nitro-espresso-integration/nitro-node:integration-v3.9.9 \
  ESPRESSO_NITRO_CONTRACTS_BRANCH=$ESPRESSO_NITRO_CONTRACTS_BRANCH \
    ./test-node.bash --espresso --latest-espresso-image --validate --l2-anytrust --init-force --detach
else
  info "This starts up the entire legacy Espresso stack. It takes a long time."
  info "Run \`tail -f $TESTNODE_LOG_FILE\` to see logs, if necessary."
  echo
  ESPRESSO_VERSION=ghcr.io/espressosystems/nitro-espresso-integration/nitro-node:integration-v3.9.9 \
  ESPRESSO_NITRO_CONTRACTS_BRANCH=$ESPRESSO_NITRO_CONTRACTS_BRANCH \
    ./test-node.bash --espresso --latest-espresso-image --validate --l2-anytrust --init-force --detach > "$TESTNODE_LOG_FILE" 2>&1
fi

info "Load environment variables in $ENV_FILE"
emph . "$TEST_DIR/.env"
. "$TEST_DIR/.env"
echo
info "Loaded env vars:"
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

# ── Phase 2: Capture pre-migration state ──

info "Phase 2: Capturing pre-migration state"

ROLLUP_ADDRESS=$(get-addr /config/deployed_chain_info.json '.[0].rollup.rollup')
declare -p ROLLUP_ADDRESS

SEQUENCER_INBOX_ADDRESS=$(get-addr /config/deployed_chain_info.json '.[0].rollup["sequencer-inbox"]')
declare -p SEQUENCER_INBOX_ADDRESS

PARENT_CHAIN_UPGRADE_EXECUTOR=$(get-addr /config/deployed_chain_info.json '.[0].rollup["upgrade-executor"]')
declare -p PARENT_CHAIN_UPGRADE_EXECUTOR

ESPRESSO_TEE_VERIFIER_ADDRESS=$(get-addr /config/deployed_chain_info.json '.[0]["chain-config"].arbitrum.EspressoTEEVerifierAddress')
declare -p ESPRESSO_TEE_VERIFIER_ADDRESS

PROXY_ADMIN_ADDRESS="0x2A1f38c9097e7883570e0b02BFBE6869Cc25d8a3"
declare -p PROXY_ADMIN_ADDRESS

PRIVATE_KEY="$(docker compose run scripts print-private-key --account l2owner 2>/dev/null | trim-last)"
declare -p PRIVATE_KEY

OWNER_ADDRESS="$(docker compose run scripts print-address --account l2owner 2>/dev/null | trim-last)"
declare -p OWNER_ADDRESS

info "Disabling validator whitelist"
run cast send $PARENT_CHAIN_UPGRADE_EXECUTOR "executeCall(address,bytes)" $ROLLUP_ADDRESS "$(cast calldata 'setValidatorWhitelistDisabled(bool)' true)" --rpc-url $PARENT_CHAIN_RPC_URL --private-key $PRIVATE_KEY

BATCH_COUNT_START=$(cast call --rpc-url $PARENT_CHAIN_RPC_URL $SEQUENCER_INBOX_ADDRESS 'batchCount()(uint256)')
info "Initial batch count: $BATCH_COUNT_START"

NUM_CONFIRMED_START=$(cast call --rpc-url $PARENT_CHAIN_RPC_URL $ROLLUP_ADDRESS 'latestConfirmed()(uint256)')
info "Initial latest confirmed: $NUM_CONFIRMED_START"

info "Verifying chain is functional pre-migration"
RECIPIENT_ADDRESS=0xAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
BALANCE_ORIG=$(cast balance $RECIPIENT_ADDRESS -e --rpc-url $CHILD_CHAIN_RPC_URL)
run cast send $RECIPIENT_ADDRESS --value 1ether --rpc-url $CHILD_CHAIN_RPC_URL --private-key $PRIVATE_KEY
BALANCE_AFTER=$(cast balance $RECIPIENT_ADDRESS -e --rpc-url $CHILD_CHAIN_RPC_URL)
if [ "$BALANCE_AFTER" == "$BALANCE_ORIG" ]; then
  fail "Pre-migration: balance of $RECIPIENT_ADDRESS should have changed but remained: $BALANCE_ORIG"
fi
info "Pre-migration chain is functional"

info "Waiting for at least two batches to be posted before migration"
START=$SECONDS
while true; do
  BATCH_COUNT_NOW=$(cast call --rpc-url $PARENT_CHAIN_RPC_URL $SEQUENCER_INBOX_ADDRESS 'batchCount()(uint256)')
  if [ $(( BATCH_COUNT_NOW - BATCH_COUNT_START )) -ge 2 ]; then
    info "Pre-migration batch count progressed by at least two: $BATCH_COUNT_START -> $BATCH_COUNT_NOW"
    break
  fi
  if [ $(( SECONDS - START )) -ge $MAX_WAIT_SECONDS ]; then
    fail "Pre-migration batch count did not increase by at least two within ${MAX_WAIT_SECONDS}s (start=$BATCH_COUNT_START current=$BATCH_COUNT_NOW)"
  fi
  # Send L2 transactions to ensure the batch poster has non-empty batches to post.
  # Without this, the poster's max-empty-batch-delay (1h) prevents timely empty batch posting.
  cast send $RECIPIENT_ADDRESS --value 0.001ether --rpc-url $CHILD_CHAIN_RPC_URL --private-key $PRIVATE_KEY > /dev/null 2>&1 || true
  sleep 5
  echo "Waited $(( SECONDS - START ))s for pre-migration batch posting (start=$BATCH_COUNT_START current=$BATCH_COUNT_NOW)..."
done

info "Waiting for staker to confirm at least one new node before migration"
START=$SECONDS
while true; do
  NUM_CONFIRMED_NOW=$(cast call --rpc-url $PARENT_CHAIN_RPC_URL $ROLLUP_ADDRESS 'latestConfirmed()(uint256)')
  if [ "$NUM_CONFIRMED_NOW" != "$NUM_CONFIRMED_START" ]; then
    info "Pre-migration latest confirmed progressed: $NUM_CONFIRMED_START -> $NUM_CONFIRMED_NOW"
    break
  fi
  if [ $(( SECONDS - START )) -ge $MAX_WAIT_SECONDS ]; then
    fail "Pre-migration latest confirmed did not increase within ${MAX_WAIT_SECONDS}s (stuck at $NUM_CONFIRMED_START)"
  fi
  sleep 5
  echo "Waited $(( SECONDS - START ))s for pre-migration staker progress..."
done

BATCH_COUNT_BEFORE=$BATCH_COUNT_NOW
NUM_CONFIRMED_BEFORE=$NUM_CONFIRMED_NOW
info "Migration baseline batch count: $BATCH_COUNT_BEFORE"
info "Migration baseline latest confirmed: $NUM_CONFIRMED_BEFORE"

info "Exporting SEQUENCER_INBOX_ADDRESS for pre-migration AnyTrust sidecar"
export SEQUENCER_INBOX_ADDRESS

info "Starting daprovider-anytrust before migration"
run docker compose up --wait daprovider-anytrust

# ── Phase 3: On-chain contract upgrades ──

info "Phase 3: On-chain contract upgrades"

cd "$ORBIT_ACTIONS_DIR"

info "Deploying and initializing Espresso SequencerInbox for CAS"
run forge script --chain $PARENT_CHAIN_CHAIN_ID \
  contracts/parent-chain/espresso-migration/2.1.3/Deploy2Point1Point3EspressoSequencerInbox.s.sol:Deploy2Point1Point3EspressoSequencerInbox \
  --rpc-url $PARENT_CHAIN_RPC_URL --broadcast -vvvv --skip-simulation

NEW_SEQUENCER_INBOX_IMPL_ADDRESS=$(cat broadcast/Deploy2Point1Point3EspressoSequencerInbox.s.sol/1337/run-latest.json | jq -r '.receipts[0].contractAddress' | cast to-checksum)
declare -p NEW_SEQUENCER_INBOX_IMPL_ADDRESS
info "Deployed new SequencerInbox at $NEW_SEQUENCER_INBOX_IMPL_ADDRESS"

info "Deploying Espresso SequencerInbox migration action"
run forge script --chain $PARENT_CHAIN_CHAIN_ID \
  $ORBIT_MIGRATION_ACTION_DIR/DeployEspressoSequencerMigrationAction.s.sol:DeployEspressoSequencerMigrationAction \
  --rpc-url $PARENT_CHAIN_RPC_URL --broadcast -vvvv

SEQUENCER_MIGRATION_ACTION=$(cat broadcast/DeployEspressoSequencerMigrationAction.s.sol/1337/run-latest.json | jq -r '.transactions[0].contractAddress' | cast to-checksum)
declare -p SEQUENCER_MIGRATION_ACTION
info "Deployed EspressoSequencerMigrationAction at $SEQUENCER_MIGRATION_ACTION"

cd "$TESTNODE_DIR"

info "Executing SequencerMigrationAction via UpgradeExecutor"
run cast send $PARENT_CHAIN_UPGRADE_EXECUTOR "execute(address, bytes)" \
  $SEQUENCER_MIGRATION_ACTION $(cast calldata "perform()") \
  --rpc-url $PARENT_CHAIN_RPC_URL --private-key $PRIVATE_KEY

info "SequencerMigrationAction executed"

# ── Phase 4: Node migration (legacy -> CAS) ──

info "Phase 4: Migrating nodes from legacy Espresso to CAS mode"

info "Stopping legacy services"
run docker compose stop sequencer poster validator staker-unsafe sequencer-on-espresso 2>/dev/null || true

info "Pulling nitro images for CAS mode"
VANILLA_NITRO_VERSION=offchainlabs/nitro-node:v3.9.9-6b0af88
CAS_POSTER_VERSION=ghcr.io/espressosystems/nitro-espresso-integration/nitro-node:pr-1052
CAS_IMAGE=ghcr.io/espressosystems/chain-adjacent-service:integrate-v3.9.9
run docker pull $VANILLA_NITRO_VERSION
run docker pull $CAS_POSTER_VERSION --platform linux/amd64
run docker pull $CAS_IMAGE --platform linux/amd64
run docker tag $VANILLA_NITRO_VERSION nitro-node-dev-testnode

info "Rebuilding scripts container"
run docker compose build --no-cache scripts

info "Writing TEE verifier address for CAS config"
docker compose run --entrypoint sh scripts -c "echo '$ESPRESSO_TEE_VERIFIER_ADDRESS' > /config/tee_verifier_address.txt"

info "Generating CAS config"
run docker compose run -e TEE_VERIFIER_ADDRESS=$ESPRESSO_TEE_VERIFIER_ADDRESS scripts write-cas-config

info "Generating node configs for CAS mode"
das_bls_a=$(docker compose run --entrypoint sh datool -c "cat /das-committee-a/keys/das_bls.pub")
das_bls_b=$(docker compose run --entrypoint sh datool -c "cat /das-committee-b/keys/das_bls.pub")
run docker compose run scripts write-config --cas --anytrust --dasBlsA $das_bls_a --dasBlsB $das_bls_b --lightClientAddress 0xb7fc0e52ec06f125f3afeba199248c79f71c2e3a

info "Starting CAS and waiting for it to be ready"
run docker compose up --wait cas

info "Starting sequencer and validator with vanilla nitro"
run docker compose up -d sequencer validator validation_node

info "Re-tagging poster image to CAS-compatible build"
run docker tag $CAS_POSTER_VERSION nitro-node-dev-testnode

info "Starting poster with CAS-compatible nitro"
run docker compose up -d poster

info "Waiting for sequencer to be healthy"
START=$SECONDS
while ! curl -sf http://localhost:8547 > /dev/null 2>&1; do
  if [ $(( SECONDS - START )) -ge $MAX_WAIT_SECONDS ]; then
    fail "Sequencer did not become healthy within ${MAX_WAIT_SECONDS}s"
  fi
  sleep 5
  echo "Waited $(( SECONDS - START ))s for sequencer..."
done
info "Sequencer is healthy"

# ── Phase 5: Verify post-migration ──

info "Phase 5: Verifying post-migration"

info "Testing chain is functional post-migration"
BALANCE_BEFORE_POST=$(cast balance $RECIPIENT_ADDRESS -e --rpc-url $CHILD_CHAIN_RPC_URL)
run cast send $RECIPIENT_ADDRESS --value 1ether --rpc-url $CHILD_CHAIN_RPC_URL --private-key $PRIVATE_KEY
BALANCE_AFTER_POST=$(cast balance $RECIPIENT_ADDRESS -e --rpc-url $CHILD_CHAIN_RPC_URL)
if [ "$BALANCE_AFTER_POST" == "$BALANCE_BEFORE_POST" ]; then
  fail "Post-migration: balance of $RECIPIENT_ADDRESS should have changed but remained: $BALANCE_BEFORE_POST"
fi
info "Post-migration chain is functional"

info "Waiting for batch count to increase (max ${MAX_WAIT_SECONDS}s)"
START=$SECONDS
while true; do
  BATCH_COUNT_NOW=$(cast call --rpc-url $PARENT_CHAIN_RPC_URL $SEQUENCER_INBOX_ADDRESS 'batchCount()(uint256)')
  if [ "$BATCH_COUNT_NOW" != "$BATCH_COUNT_BEFORE" ]; then
    info "Batch count progressed: $BATCH_COUNT_BEFORE -> $BATCH_COUNT_NOW"
    break
  fi
  if [ $(( SECONDS - START )) -ge $MAX_WAIT_SECONDS ]; then
    fail "Batch count did not increase within ${MAX_WAIT_SECONDS}s (stuck at $BATCH_COUNT_BEFORE)"
  fi
  sleep 5
  echo "Waited $(( SECONDS - START ))s for batch count to increase..."
done

info "Waiting for staker to confirm nodes (max ${MAX_WAIT_SECONDS}s)"
START=$SECONDS
while true; do
  NUM_CONFIRMED_NOW=$(cast call --rpc-url $PARENT_CHAIN_RPC_URL $ROLLUP_ADDRESS 'latestConfirmed()(uint256)')
  if [ "$NUM_CONFIRMED_NOW" != "$NUM_CONFIRMED_BEFORE" ]; then
    info "Confirmed nodes progressed: $NUM_CONFIRMED_BEFORE -> $NUM_CONFIRMED_NOW"
    break
  fi
  if [ $(( SECONDS - START )) -ge $MAX_WAIT_SECONDS ]; then
    fail "Staker did not confirm new nodes within ${MAX_WAIT_SECONDS}s (stuck at $NUM_CONFIRMED_BEFORE)"
  fi
  sleep 5
  echo "Waited $(( SECONDS - START ))s for confirmed nodes..."
done

# ── Phase 6: Cleanup ──

echo
echo "========================================="
echo "  CAS Migration Test PASSED"
echo "========================================="
echo

run docker compose down -v --remove-orphans
