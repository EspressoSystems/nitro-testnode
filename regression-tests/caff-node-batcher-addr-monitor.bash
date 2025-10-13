
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

source ./common.bash

echo "starting nodes"
../test-node.bash --init-force --espresso $(get_espresso_image_flag) --no-simple --caff-node --detach

docker compose run --detach scripts send-l2 --ethamount 10 --to user_l2user --times 10000 --delay 200 --wait

seqInboxAddr=0x06EBC64fDE465bB5569844B81DcfF12ECd9fb419
newBatcherAddr=0x0000000000000000000000000000000000000000

docker compose run scripts set-is-batch-poster --batchPoster $newBatcherAddr --isBatchPoster true --seqInboxAddr $seqInboxAddr --wait

while true; do
    if docker compose logs caff-node | grep "adding event" | grep "Addr:$newBatcherAddr IsBatcher:true"; then
        break
    fi
    sleep 1
done

# Should be same as the one in `config.ts`
batcherAddr=0xe2148eE53c0755215Df69b2616E552154EdC584f
docker compose run scripts set-is-batch-poster --batchPoster $batcherAddr --isBatchPoster false --seqInboxAddr $seqInboxAddr --wait

while true; do
    if docker compose logs caff-node | grep "adding event" | grep "Addr:$batcherAddr IsBatcher:false"; then
        break
    fi
    sleep 1
done

echo "wait for consumption of all messages"
sleep 120

# From this point, caff node should not create any blocks.
nowBlock=$(cast block-number --rpc-url http://localhost:8550)
echo "nowBlock: $nowBlock"
count=0
while true; do
    if [ $(cast block-number --rpc-url http://localhost:8550) -gt $nowBlock ]; then
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
