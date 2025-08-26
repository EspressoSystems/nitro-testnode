#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")"

echo "starting nodes"
../test-node.bash --init-force --espresso --latest-espresso-image --validate --detach

sleep 30

# Ignore orphaned container output
# Orphaned containers will be removed at the end of the test
export COMPOSE_IGNORE_ORPHANS=1
export http_proxy=""
export https_proxy=""
export all_proxy=""


sequencer_inbox=$(docker compose run --entrypoint sh poster -c "jq -r '.[0].rollup.\"sequencer-inbox\"' /config/deployed_chain_info.json | tail -n 1 | tr -d '\r\n'")
echo "sequencer inbox: $sequencer_inbox"
batch_count=$(cast call $sequencer_inbox "batchCount()(uint256)" --rpc-url http://localhost:8545)
echo "batch count: $batch_count"

block=0
last_validator_block=0
check_validator_catchup_and_compare_roots() {
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

        # The batch poster will post batches after the Hotshot comes into live.
        # It is possible that all batch posting reports are in the pending state.
        # In this case, the validator will not catch up with the sequencer.
        if [[ "$validator_block" -eq "$last_validator_block" && $(($sequencer_block - $validator_block - 1)) -le $new_batches ]]; then
            echo "Validator block ($validator_block) is no longer increasing AND validator has caught up. Breaking out."
            block=$validator_block
            break
        fi
        last_validator_block=$validator_block
    done

    sequencer_root=$(cast block --rpc-url http://localhost:8547 --json $block | jq -r .stateRoot)
    validator_root=$(cast block --rpc-url http://localhost:8247 --json $block | jq -r .stateRoot)

    echo "sequencer root: $sequencer_root"
    echo "validator root: $validator_root"

    if [[ "$validator_root" != "$sequencer_root" ]]; then
        echo "Error: validator root ($validator_root) does not match sequencer root ($sequencer_root)"
        exit 1
    fi
}

# create a background process to send transactions.
# It will take around 2 minutes to finish
docker compose run scripts send-l2 --ethamount 10 --to user_l2user --times 1200 --delay 600 &

echo "stopping batcher gracefully"
docker compose down poster

sleep 60

status=$(docker ps -a --filter "name=poster" --format '{{.Status}}')
if [[ "$status" == Exited* ]]; then
    echo "poster container has shut down."
else
    echo "poster container is still running or restarting."
fi

docker compose up -d poster

echo "waiting for validator to catch up"
check_validator_catchup_and_compare_roots

docker compose run scripts send-l2 --ethamount 10 --to user_l2user --times 1200 --delay 600 &

echo "force kill batch poster"
docker compose kill poster

sleep 20

status=$(docker ps -a --filter "name=poster" --format '{{.Status}}')
if [[ "$status" == Exited* ]]; then
    echo "poster container has shut down."
else
    echo "poster container is still running or restarting."
fi

docker compose up -d poster

echo "waiting for validator to catch up"
check_validator_catchup_and_compare_roots

docker compose down --remove-orphans
