#!/usr/bin/env bash
set -euo pipefail

# check that the relay is working
listen_to_sequencer_feed() {
    #  Listen to the sequencer feed and check if the sender address is detected
    while read -r message; do
        # Check if the message contains the specific sender address
        if [[ "$message" == *"\"sender\":\"0xdd6bd74674c356345db88c354491c7d3173c6806\""* ]]; then
            echo "Sender address detected"
            break
        fi
    done < <(wscat -c ws://127.0.0.1:9652)
}


#  Run caldera with batch poster, sequencer, full node, validator and an anytrust chain which runs the dasserver
./test-node.bash --init-force --validate --batchposters 1 --latest-espresso-image --detach --l2-anytrust
docker compose up -d full-node --detach

# Sending L2 transaction through the full-node's api
user=user_l2user
./test-node.bash script send-l2 --l2url ws://full-node:8548 --ethamount 100 --to $user --wait

# Check the balance from full-node's api
userAddress=$(docker compose run scripts print-address --account $user | tail -n 1 | tr -d '\r\n')

while true; do
    balance=$(cast balance $userAddress --rpc-url http://127.0.0.1:8947)
    if [ ${#balance} -gt 0 ]; then
        break
    fi
    sleep 1
done

listen_to_sequencer_feed

echo "Smoke test succeeded."
# docker compose down
