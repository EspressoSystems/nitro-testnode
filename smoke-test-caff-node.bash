#!/usr/bin/env bash
set -euo pipefail

check_nonce_increase() {
    local address=$1
    local initial_nonce=$2
    while true; do
        currentNonce=$(cast nonce "$address" --rpc-url ws://127.0.0.1:8552)
        if [ "$currentNonce" -eq "$((initial_nonce + 1))" ]; then
            break
        fi
        sleep 1
    done
}

user=user_l2user
funnel=funnel
caff_url="ws://caff-node:8548"

source ./regression-tests/common.bash

./test-node.bash --espresso $(get_espresso_image_flag) --validate --tokenbridge --init-force --detach --caff-node

# Start the caff node
docker compose up -d caff-node --wait --detach

echo "Sending L2 transaction through sequencer 1"
./test-node.bash script send-l2 --ethamount 10 --to $user --wait

# Check the balance from caff node's api
userAddress=$(docker compose run scripts print-address --account $user | tail -n 1 | tr -d '\r\n')
funnelAddress=$(docker compose run scripts print-address --account $funnel | tail -n 1 | tr -d '\r\n')

while true; do
    # Check if the balance on Caff node is greater than 0
    balance=$(cast balance $userAddress --rpc-url ws://127.0.0.1:8552)
    # Using bc here because it supports bigint
    if [ "$(echo "$balance > 0" | bc)" -eq 1 ]; then
        break
    fi
    sleep 1
done

nonce=$(cast nonce $funnelAddress --rpc-url ws://127.0.0.1:8552)

echo "Sending L2 transaction through caff node 1"
./test-node.bash script send-l2 --ethamount 10 --to $user --l2url $caff_url --wait

check_nonce_increase "$funnelAddress" "$nonce"
nonce=$((nonce + 1))

echo "Sending L2 transaction through sequencer 2"
./test-node.bash script send-l2 --ethamount 10 --to $user --wait

check_nonce_increase "$funnelAddress" "$nonce"
nonce=$((nonce + 1))

echo "Sending L2 transaction through caff node 2"
./test-node.bash script send-l2 --ethamount 10 --to $user --l2url $caff_url --wait

check_nonce_increase "$funnelAddress" "$nonce"

echo "Smoke test succeeded."
docker compose down
