#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

source ./common.bash

export COMPOSE_IGNORE_ORPHANS=1

echo "starting nodes"
../test-node.bash --init-force --espresso $(get_espresso_image_flag) --validate --detach

echo "starting tx spammer"
docker compose run --detach scripts send-l2 --ethamount 10 --to user_l2user --times 10000 --delay 200 --wait

sequencer_inbox=$(docker compose run --entrypoint sh poster -c "jq -r '.[0].rollup.\"sequencer-inbox\"' /config/deployed_chain_info.json | tail -n 1 | tr -d '\r\n'")
echo "sequencer inbox: $sequencer_inbox"

# check validator

batcher_addr=0xe2148eE53c0755215Df69b2616E552154EdC584f
docker compose run scripts set-is-batch-poster --batchPoster $batcher_addr --isBatchPoster false --seqInboxAddr $sequencer_inbox --wait

# validator should stop creating blocks after a while (64 l1 blocks)

oldBlockNumber=$(cast block-number --rpc-url http://127.0.0.1:8247)
echo "oldBlockNumber: $oldBlockNumber"

sleep 60

newBlockNumber=$(cast block-number --rpc-url http://127.0.0.1:8247)
echo "newBlockNumber: $newBlockNumber"

if [ "$newBlockNumber" -gt "$oldBlockNumber" ]; then
    echo "Smoke test failed. Blocks created."
    exit 1
fi

batcher_addr=0xe2148eE53c0755215Df69b2616E552154EdC584f
docker compose run scripts set-is-batch-poster --batchPoster $batcher_addr --isBatchPoster true --seqInboxAddr $sequencer_inbox --wait

sleep 60

newBlockNumber=$(cast block-number --rpc-url http://127.0.0.1:8247)
echo "newBlockNumber: $newBlockNumber"

if [ "$newBlockNumber" -eq "$oldBlockNumber" ]; then
    echo "Smoke test failed. No blocks created."
    exit 1
fi
