#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "starting nodes"
../test-node.bash --init-force --espresso --validate --latest-espresso-image --caff-node --detach

# This e2e test is largly based on the state checker
# We set the error tolerance duration to 1m
docker compose run scripts update-config-value --path /config/caff_sequencer_config.json --property node.espresso-caff-node.state-checker.error-tolerance-duration --value "1m"

echo "starting tx spammer"
docker compose run --detach scripts send-l2 --ethamount 10 --to user_l2user --times 50 --delay 200 --wait

for i in {1..20}; do
    docker compose run scripts send-l2-delayed --ethamount 10000 --to user_delayed_user --wait
    sleep 5
done

# Wait for all the transactions to be processed
sleep 60

user_l2user_address=$(docker compose run scripts print-address --account user_l2user | tail -n 1 | tr -d '\r\n')
balance1=$(cast balance $user_l2user_address --rpc-url http://127.0.0.1:8550)
echo $balance1

user_delayed_user_address=$(docker compose run scripts print-address --account user_delayed_user | tail -n 1 | tr -d '\r\n')
balance2=$(cast balance $user_delayed_user_address --rpc-url http://127.0.0.1:8550)
echo $balance2
