#!/usr/bin/env bash
set -euo pipefail

./test-node.bash --init-force --simple --detach

docker compose up -d full-node --detach

# Sending L2 transaction through the full-node's api
user=user_l2user
./test-node.bash script send-l2 --l2url ws://full-node:8548 --ethamount 100 --to $user --wait

# Check the balance from full-node's api
userAddress=$(docker compose run scripts print-address --account $user | tail -n 1 | tr -d '\r\n')

while true; do
    balance=$(cast balance $userAddress --rpc-url http://localhost:8947)
    if [ ${#balance} -gt 0 ]; then
        break
    fi
    sleep 1
done

echo "Smoke test succeeded."
docker compose down
