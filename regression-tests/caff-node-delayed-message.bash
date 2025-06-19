#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "starting nodes"
../test-node.bash --init-force --espresso --no-simple --latest-espresso-image --caff-node --mock-sequencer --detach

export http_proxy=""
export https_proxy=""
export all_proxy=""

echo "starting tx spammer"
docker compose run --detach scripts send-l2 --ethamount 10 --to user_l2user --times 500000 --delay 20000 --wait

sleep 10

curl -X POST --fail --silent http://127.0.0.1:10000/send-invalid-delayed-messages
sleep 5

user=user_delayed_user
address=$(docker compose run scripts print-address --account $user | tail -n 1 | tr -d '\r\n')
beforeBalance=$(cast balance $address --rpc-url http://127.0.0.1:8550)

if [ "$beforeBalance" != "0" ]; then
    echo "failed to get balance for user $user"
    exit 1
fi

beforeL1=$(cast block-number --rpc-url http://127.0.0.1:8545)
echo "before sending delayed transaction, l1 block number: $beforeL1"
docker compose run scripts send-l2-delayed --ethamount 10000 --to $user --wait

while true; do
    echo "checking balance through the caff node"
    balance=$(cast balance $address --rpc-url http://127.0.0.1:8550)
    echo "balance: $balance"
    if [ -n "$balance" ] && [ "$(echo "$balance > 0" | bc)" -eq 1 ]; then
        break
    fi
    sleep 1
done

finalizedL1=$(cast block-number finalized --rpc-url http://127.0.0.1:8545)
echo "after getting delayed message, finalized block number: $finalizedL1"

if [ "$finalizedL1" -lt "$beforeL1" ]; then
    echo "delayed transaction get included before block being finalized"
    exit 1
fi

docker compose down
