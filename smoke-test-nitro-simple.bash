#!/usr/bin/env bash
set -euo pipefail

./test-node.bash --init-force --simple --detach

rollupAddress=$(docker compose run --entrypoint sh poster -c "jq -r '.[0].rollup.rollup' /config/deployed_chain_info.json | tail -n 1 | tr -d '\r\n'")
previousConfirmed=$(cast call --rpc-url http://localhost:8545 $rollupAddress 'latestConfirmed()(bytes32)')
echo "latest confirmed hash: $previousConfirmed"
# Sending L2 transaction
./test-node.bash script send-l2 --ethamount 100 --to user_l2user --wait

while true; do
  confirmed=$(cast call --rpc-url http://localhost:8545 $rollupAddress 'latestConfirmed()(bytes32)')
  if [ -n "$confirmed" ] && [ "$confirmed" != "$previousConfirmed" ]; then
    break
  else
    echo "Waiting for more confirmed nodes ...$confirmed"
  fi
  sleep 5
done

docker compose down
