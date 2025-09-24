
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

source ./common.bash

echo "starting nodes"
../test-node.bash --init-force --espresso $(get_espresso_image_flag) --no-simple --caff-node --detach

docker compose run --detach scripts send-l2 --ethamount 10 --to user_l2user --times 10000 --delay 200 --wait

sequencer_inbox=$(docker compose run --entrypoint sh poster -c "jq -r '.[0].rollup.\"sequencer-inbox\"' /config/deployed_chain_info.json | tail -n 1 | tr -d '\r\n'")
echo "sequencer inbox: $sequencer_inbox"
new_batcher_addr=0x0000000000000000000000000000000000000000

docker compose run scripts set-is-batch-poster --batchPoster $new_batcher_addr --isBatchPoster true --seqInboxAddr $sequencer_inbox --wait

while true; do
    if docker compose logs caff-node | grep "adding event" | grep "Addr:$new_batcher_addr IsBatcher:true"; then
        break
    fi
    sleep 1
done

# Should be same as the one in `config.ts`
batcher_addr=0xe2148eE53c0755215Df69b2616E552154EdC584f
docker compose run scripts set-is-batch-poster --batchPoster $batcher_addr --isBatchPoster false --seqInboxAddr $sequencer_inbox --wait

while true; do
    if docker compose logs caff-node | grep "adding event" | grep "Addr:$batcher_addr IsBatcher:false"; then
        break
    fi
    sleep 1
done

echo "wait for consumption of all messages"
sleep 120

# From this point, caff node should not create any blocks.
now_block=$(cast block-number --rpc-url http://localhost:8550)
echo "nowBlock: $now_block"
count=0
while true; do
    if [ $(cast block-number --rpc-url http://localhost:8550) -gt $now_block ]; then
        echo "Error: caff node created a block"
        exit 1
    fi
    count=$((count + 1))
    if [ $count -gt 10 ]; then
        break
    fi
    sleep 5
done

docker compose down --remove-orphans
