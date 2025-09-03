#!/usr/bin/env bash
# This script tests the batcher's behavior when interacting with a malicious sequencer.
# If the sequencer acts maliciously, the batcher will lose liveness.
# Once the sequencer resumes correct behavior, the batcher should automatically recover liveness.

wait_for_block_number() {
    local validator_rpc="$1"
    local target_block_number="$2"
    while true; do
        # Get current message count
        count=$(curl --fail --silent http://127.0.0.1:10000/block-number)
        echo "Current mock sequencer block number: $count"
        block_number=$(cast block-number --rpc-url $validator_rpc)
        echo "Current validated block number: $block_number"
        if [[ $block_number -gt $target_block_number ]]; then
            break
        fi
        sleep 5
    done
}

check_and_recover_liveness() {
    local validator_rpc="$1"
    local current_count="$2"
    local validated_count=0

    local i=0
    while [[ $i -lt 15 ]]; do
        local block_number
        block_number=$(cast block-number --rpc-url "$validator_rpc")
        echo "Current validated number: $block_number, target: $current_count"
        if [[ $block_number -le $current_count ]]; then
            validated_count=$block_number
        fi
        i=$((i+1))
        sleep 15
    done

    echo "sequencer is going to work properly"
    curl -X POST --fail --silent http://127.0.0.1:10000/reset
    echo "restarting batch poster"
    docker compose restart poster

    wait_for_block_number $validator_rpc $validated_count

    echo "$validated_count"
}

set -euo pipefail

cd "$(dirname "$0")"

echo "starting with mock sequencer"

../test-node.bash --init-force --espresso --latest-espresso-image --validate --mock-sequencer --detach

while true; do
    curl -sfL http://localhost:41000/v0/status/block-height && break || sleep 5
    echo "waiting for nodes"
done

validator_rpc="http://localhost:8247"

echo "starting tx spammer"
docker compose run --detach scripts send-l2 --ethamount 10 --to user_l2user --times 500000 --delay 8000 --wait

wait_for_block_number $validator_rpc 20

# This should not break liveness
current_count=$(curl -X POST --fail --silent http://127.0.0.1:10000/send-in-random)
wait_for_block_number $validator_rpc $(($current_count+10))

sleep 10

current_count2=$(curl -X POST --fail --silent http://127.0.0.1:10000/skip-next)
check_and_recover_liveness $validator_rpc $current_count2

sleep 10

current_count3=$(curl -X POST --fail --silent http://127.0.0.1:10000/send-oversized)
check_and_recover_liveness $validator_rpc $current_count3

current_count4=$(curl -X POST --fail --silent http://127.0.0.1:10000/send-messages-at-same-block)
check_and_recover_liveness $validator_rpc $current_count4

sleep 20

block_number=$(cast block-number --rpc-url $validator_rpc)
echo "block number: $block_number"

validator_state=$(cast block $block_number --rpc-url $validator_rpc --json | jq -r .stateRoot)
sequencer_state=$(cast block $block_number --rpc-url http://localhost:8547 --json | jq -r .stateRoot)
echo "validator_state: $validator_state"
echo "sequencer_state: $sequencer_state"
if [ "$validator_state" != "$sequencer_state" ]; then
    echo "Error: validator_state ($validator_state) does not match sequencer_state ($sequencer_state)"
    exit 1
fi

docker compose down --remove-orphans
