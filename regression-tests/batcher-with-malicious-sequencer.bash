#!/usr/bin/env bash
# This script tests the batcher's behavior when interacting with a malicious sequencer.
# If the sequencer acts maliciously, the batcher will lose liveness.
# Once the sequencer resumes correct behavior, the batcher should automatically recover liveness.

wait_for_block_number() {
    local validatorRpc="$1"
    local targetBlockNumber="$2"
    while true; do
        # Get current message count
        count=$(curl --fail --silent http://127.0.0.1:10000/block-number)
        echo "Current mock sequencer block number: $count"
        blockNumber=$(cast block-number --rpc-url $validatorRpc)
        echo "Current validated block number: $blockNumber"
        if [[ $blockNumber -gt $targetBlockNumber ]]; then
            break
        fi
        sleep 5
    done
}

check_and_recover_liveness() {
    local validatorRpc="$1"
    local currentCount="$2"
    local validatedCount=0

    local i=0
    while [[ $i -lt 15 ]]; do
        local blockNumber
        blockNumber=$(cast block-number --rpc-url "$validatorRpc")
        echo "Current validated number: $blockNumber, target: $currentCount"
        if [[ $blockNumber -le $currentCount ]]; then
            validatedCount=$blockNumber
        fi
        i=$((i+1))
        sleep 15
    done

    echo "sequencer is going to work properly"
    curl -X POST --fail --silent http://127.0.0.1:10000/reset
    echo "restarting batch poster"
    docker compose restart poster

    wait_for_block_number $validatorRpc $validatedCount

    echo "$validatedCount"
}

set -euo pipefail

cd "$(dirname "$0")"

echo "starting with mock sequencer"

../test-node.bash --init-force --espresso --latest-espresso-image --validate --mock-sequencer --detach

while true; do
    curl -sfL http://localhost:41000/v0/status/block-height && break || sleep 5
    echo "waiting for nodes"
done

validatorRpc="http://localhost:8247"

echo "starting tx spammer"
docker compose run --detach scripts send-l2 --ethamount 10 --to user_l2user --times 500000 --delay 8000 --wait

wait_for_block_number $validatorRpc 20

# This should not break liveness
currentCount=$(curl -X POST --fail --silent http://127.0.0.1:10000/send-in-random)
wait_for_block_number $validatorRpc $(($currentCount+10))

sleep 20

currentCount2=$(curl -X POST --fail --silent http://127.0.0.1:10000/skip-next)
check_and_recover_liveness $validatorRpc $currentCount2

sleep 20

currentCount3=$(curl -X POST --fail --silent http://127.0.0.1:10000/send-oversized)
check_and_recover_liveness $validatorRpc $currentCount3

currentCount4=$(curl -X POST --fail --silent http://127.0.0.1:10000/send-messages-at-same-block)
check_and_recover_liveness $validatorRpc $currentCount4

docker compose down --remove-orphans
