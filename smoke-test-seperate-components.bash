#!/usr/bin/env bash
set -euo pipefail

# no-simple runs a full 
./test-node.bash --espresso --latest-espresso-image --validate --tokenbridge --init-force --detach --no-simple

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
