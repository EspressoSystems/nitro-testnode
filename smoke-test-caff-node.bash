#!/usr/bin/env bash
set -euo pipefail



user=user_l2user
url="http://host.docker.internal:8550"

./test-node.bash --espresso --latest-espresso-image --validate --tokenbridge --init-force --detach --caff-node

# Start the caff node
docker compose up -d caff-node --wait --detach

echo "Sending L2 transaction through caff node"
./test-node.bash script send-l2 --ethamount 10 --to $user --wait

# Sending L2 transaction
./test-node.bash script send-l2 --ethamount 10 --to $user --wait

./test-node.bash script print-address --account $user

# Check the balance from caff node's api
userAddress=$(docker compose run scripts print-address --account $user | tail -n 1 | tr -d '\r\n')

while true; do
    # Check if the balance on Caff node is greater than 0
    balance=$(cast balance $userAddress --rpc-url http://127.0.0.1:8550)
    # Using bc here because it supports bigint
    if [ "$(echo "$balance > 0" | bc)" -eq 1 ]; then
        break
    fi
    sleep 1
done

echo "Smoke test succeeded."
docker compose down
