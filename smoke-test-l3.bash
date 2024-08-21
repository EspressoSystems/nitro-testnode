#!/usr/bin/env bash
set -euo pipefail

./test-node.bash --init-force --espresso --latest-espresso-image --l3node --l3-token-bridge --l3-fee-token --detach

# Sending L3 transaction
user=user_l3
./test-node.bash script send-l3 --ethamount 5 --to $user --wait
userAddress=$(docker compose run scripts print-address --account $user | tail -n 1 | tr -d '\r\n')

balance=$(cast balance $userAddress --rpc-url http://localhost:3347)

if [ "$balance" -gt 0 ]; then
  echo "Smoke test succeeded"
  docker compose down || true
else
  echo "transfer failed in l3 node"
  exit 1
fi
