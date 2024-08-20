#!/usr/bin/env bash
set -euo pipefail

./test-node.bash --espresso --latest-espresso-image --validate --tokenbridge --init-force --detach

# Sending L2 transaction
./test-node.bash script send-l2 --ethamount 100 --to user_l2user --wait

rollupAddress=$(docker compose run --entrypoint sh poster -c "jq -r '.[0].rollup.rollup' /config/deployed_chain_info.json | tail -n 1 | tr -d '\r\n'")
while true; do
  confirmed=$(cast call --rpc-url http://localhost:8545 $rollupAddress 'latestConfirmed()(uint256)')
  echo "Number of confirmed staking nodes: $confirmed"
  if [ "$confirmed" -gt 0 ]; then
    break
  else
    echo "Waiting for more confirmed nodes ..."
  fi
  sleep 5
done

docker compose down

# Testing the l3node
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
