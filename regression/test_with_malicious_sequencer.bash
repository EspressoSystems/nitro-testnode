#!/usr/bin/env bash
# This script tests the batcher's behavior when interacting with a malicious sequencer.
# If the sequencer acts maliciously, the batcher will lose liveness.
# Once the sequencer resumes correct behavior, the batcher should automatically recover liveness.

set -euo pipefail

cd "$(dirname "$0")"

echo "starting with mock sequencer"

../test-node.bash --init-force --espresso --latest-espresso-image --validate --mock-sequencer --detach

export all_proxy=
export http_proxy=
export https_proxy=

while true; do
    curl -sfL http://localhost:41000/v0/status/block-height && break || sleep 5
    echo "waiting for nodes"
done

validator_rpc="http://localhost:8247"

echo "starting tx spammer"
docker compose run --detach scripts send-l2 --ethamount 10 --to user_l2user --times 500000 --delay 8000 --wait

while true; do
    # Get current message count
    count=$(curl --fail --silent http://127.0.0.1:10000/block-number)
    echo "Current block number: $count"
    blockNumber=$(cast block-number --rpc-url $validator_rpc)
    echo "Current validated block number: $blockNumber"
    if [[ $count -gt 30 ]]; then
        break
    fi
    sleep 5
done


currentCount=$(curl -X POST --fail --silent http://127.0.0.1:10000/skip-next)
validatedCount=0

# loss liveness
i=0
while [[ $i -lt 5 ]]; do
    blockNumber=$(cast block-number --rpc-url $validator_rpc)
    echo "Current validated number: $blockNumber, target: $currentCount"
    if [[ $blockNumber -le $currentCount ]]; then
        validatedCount=$blockNumber
    fi
    i=$(($i+1))
    sleep 15
done

echo "sequencer is going to work properly"
curl -X POST --fail --silent http://127.0.0.1:10000/reset
echo "restarting batch poster"
docker compose restart poster

while true; do
    echo "waiting for recovery of liveness"
    blockNumber=$(cast block-number --rpc-url $validator_rpc)
    if [[ $blockNumber -gt $validatedCount ]]; then
        break
    fi
    sleep 5
done

docker compose down