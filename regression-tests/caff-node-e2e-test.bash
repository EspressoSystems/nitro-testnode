#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "starting nodes"
../test-node.bash --init-force --espresso --validate --latest-espresso-image --caff-node --detach

# This e2e test is largly based on the state checker
# We set the error tolerance duration to 1m

echo "starting tx spammer"
docker compose run --detach scripts send-l2 --ethamount 10 --to user_l2user --times 50 --delay 200 --wait

for i in {1..20}; do
    echo "sending delayed tx"
    docker compose run scripts send-l2-delayed --ethamount 10 --to user_delayed_user --wait
    sleep 5
done

echo "waiting for all transactions to be processed by the caff node"
sleep 60

export http_proxy=""
export https_proxy=""
export all_proxy=""

user_l2user_address=$(docker compose run scripts print-address --account user_l2user | tail -n 1 | tr -d '\r\n')
balance1=$(cast balance $user_l2user_address --rpc-url http://127.0.0.1:8550)
actualBalance1=$(cast balance $user_l2user_address --rpc-url http://127.0.0.1:8247)
if [ "$balance1" != "$actualBalance1" ]; then
    echo "Error: balance1 ($balance1) does not match actualBalance1 ($actualBalance1)"
    exit 1
fi

user_delayed_user_address=$(docker compose run scripts print-address --account user_delayed_user | tail -n 1 | tr -d '\r\n')
balance2=$(cast balance $user_delayed_user_address --rpc-url http://127.0.0.1:8550)
actualBalance2=$(cast balance $user_delayed_user_address --rpc-url http://127.0.0.1:8247)
if [ "$balance2" != "$actualBalance2" ]; then
    echo "Error: balance2 ($balance2) does not match actualBalance2 ($actualBalance2)"
    exit 1
fi

blockNumber=$(cast block-number --rpc-url http://localhost:8247)
echo "blockNumber: $blockNumber"
trustedState=$(cast block $blockNumber --rpc-url http://localhost:8247 --json | jq -r .stateRoot)
caffState=$(cast block $blockNumber --rpc-url http://localhost:8550 --json | jq -r .stateRoot)
if [ "$trustedState" != "$caffState" ]; then
    echo "Error: trustedState ($trustedState) does not match caffState ($caffState)"
    exit 1
fi
docker compose down
