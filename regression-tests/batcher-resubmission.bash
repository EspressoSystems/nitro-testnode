#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")"

echo "starting nodes"
../test-node.bash --init-force --espresso $(get_espresso_image_flag) --validate --detach

source ./common.bash
# Ignore orphaned container output
# Orphaned containers will be removed at the end of the test
export COMPOSE_IGNORE_ORPHANS=1

sequencer_inbox=$(docker compose run --entrypoint sh poster -c "jq -r '.[0].rollup.\"sequencer-inbox\"' /config/deployed_chain_info.json | tail -n 1 | tr -d '\r\n'")
echo "sequencer inbox: $sequencer_inbox"
batch_count=$(cast call $sequencer_inbox "batchCount()(uint256)" --rpc-url http://localhost:8545)
echo "batch count: $batch_count"

docker compose run scripts send-l2 --ethamount 10 --to user_l2user --times 10 --delay 200

sleep 10

echo "pausing espresso-dev-node"
docker compose pause espresso-dev-node

# Transactions are sent after the espresso-dev-node is down
docker compose run scripts send-l2 --ethamount 10 --to user_l2user --times 1500 --delay 200

# Stop the espresso dev node for 2 minutes
sleep 120

docker compose unpause espresso-dev-node

block=0
new_batches=0
# Wait for the validator to catch up
while true; do
    sleep 30
    sequencer_block=$(cast block-number --rpc-url http://localhost:8547)
    validator_block=$(cast block-number --rpc-url http://localhost:8247)
    new_batch_count=$(cast call $sequencer_inbox "batchCount()(uint256)" --rpc-url http://localhost:8545)
    new_batches=$(($new_batch_count - $batch_count))
    echo "new batches: $new_batches"

    if [[ "$validator_block" -gt "$sequencer_block" ]]; then
        echo "Validator block number ($validator_block) is greater than sequencer block number ($sequencer_block)"
        exit 1
    fi
    echo "validator block number: $validator_block"
    echo "sequencer block number: $sequencer_block"
    # this condition is not really necessary but it prevents a case that
    # sequencer doesn't create any blocks at all and it stopped at the genesis block
    if [[ "$validator_block" -lt 100 ]]; then
        continue
    fi

    # The batch poster will post batches after the Hotshot comes into live.
    # It is possible that all batch posting reports are in the pending state.
    # In this case, the validator will not catch up with the sequencer.
    if [[ $(($sequencer_block - $validator_block)) -le $new_batches ]]; then
        echo "block number: $validator_block"
        block=$validator_block
        break
    fi
done

sequencer_root=$(cast block --rpc-url http://localhost:8547 --json $block | jq -r .stateRoot)
validator_root=$(cast block --rpc-url http://localhost:8247 --json $block | jq -r .stateRoot)

echo "sequencer root: $sequencer_root"
echo "validator root: $validator_root"

if [[ "$validator_root" != "$sequencer_root" ]]; then
    echo "Error: validator root ($validator_root) does not match sequencer root ($sequencer_root)"
    exit 1
fi

# Typically, 3 or 4 new batches are sufficient for this test.
# We set the threshold to 10 to avoid flakiness due to timing or network issues.
# If there are more than 10 new batches, it may indicate excessive or unexpected batch posting, which could be costly.
if [[ $new_batches -gt 10 ]]; then
    echo "Error: too many new batches ($new_batches)"
    exit 1
fi

docker compose down --remove-orphans
