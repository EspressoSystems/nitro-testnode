#!/usr/bin/env bash
set -euo pipefail

./test-node.bash --init-force --espresso --latest-espresso-image --l3node --l3-token-bridge --l3-fee-token --detach

rollupAddress=$(docker compose run --entrypoint sh poster -c "jq -r '.[0].rollup.rollup' /config/deployed_l3_chain_info.json | tail -n 1 | tr -d '\r\n'")
previousConfirmed=$(cast call --rpc-url http://localhost:8547 $rollupAddress 'latestConfirmed()(bytes32)')
echo "latest confirmed hash: $previousConfirmed"

echo "Sending L3 transaction"
user=user_l3
./test-node.bash script send-l3 --ethamount 5 --to $user --wait
userAddress=$(docker compose run scripts print-address --account $user | tail -n 1 | tr -d '\r\n')

balance=$(cast balance $userAddress --rpc-url http://localhost:3347)

if [ "$balance" -eq 0 ]; then
  echo "Transfer failed in l3 node"
  exit 1
fi

while true; do
  confirmed=$(cast call --rpc-url http://localhost:8547 $rollupAddress 'latestConfirmed()(bytes32)')
  if [ -n "$confirmed" ] && [ "$confirmed" != "$previousConfirmed" ]; then
    break
  else
    echo "Waiting for more confirmed nodes ...$confirmed"
  fi
  sleep 5
done

echo "Smoke test succeeded."
docker compose down
