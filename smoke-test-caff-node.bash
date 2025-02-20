#!/usr/bin/env bash
set -euo pipefail

listen_to_sequencer_feed() {
    #  Listen to the sequencer feed and check if the sender address is detected
    while read -r message; do
        # Check if the message contains the specific sender address
        if [[ "$message" == *"\"sender\":\"0xdd6bd74674c356345db88c354491c7d3173c6806\""* ]]; then
            echo "Sender address detected"
            break
        fi
    done < <(wscat -c ws://127.0.0.1:9642) # sequencer feed
}

user=user_l2user
url="http://host.docker.internal:8550"

./test-node.bash --espresso --latest-espresso-image --validate --tokenbridge --init-force --detach --espresso-finality-node

# Start the caff node
docker compose up -d caff-node --wait --detach

# Sending L2 transaction through caff node
./test-node.bash script send-l2 --ethamount 10 --to $user --l2url $url --wait

listen_to_sequencer_feed

# Sending L2 transaction
./test-node.bash script send-l2 --ethamount 10 --to $user --l2url $url --wait

./test-node.bash script print-address --account $user

# Check the balance from caff node's api
userAddress=$(docker compose run scripts print-address --account $user | tail -n 1 | tr -d '\r\n')

while true; do
    balance=$(cast balance $userAddress --rpc-url http://127.0.0.1:8949)
    if [ ${#balance} -gt 0 ]; then
        break
    fi
    sleep 1
done

echo "Smoke test succeeded."
docker compose down
