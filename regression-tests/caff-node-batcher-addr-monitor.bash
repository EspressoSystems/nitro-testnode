
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "starting nodes"

../test-node.bash --init-force --espresso --latest-espresso-image --no-simple --caff-node --detach

docker compose run --detach scripts send-l2 --ethamount 100 --to user_l2user --times 10 --delay 200 --wait

seqInboxAddr=0x06EBC64fDE465bB5569844B81DcfF12ECd9fb419
batcherAddr=0x0000000000000000000000000000000000000000

docker compose run scripts set-is-batch-poster --batchPoster $batcherAddr --isBatchPoster true --seqInboxAddr $seqInboxAddr --wait

while true; do
    if docker compose logs caff-node | grep "adding event" | grep "Addr:0x0000000000000000000000000000000000000000 IsBatcher:true"; then
        break
    fi
sleep 1
done

