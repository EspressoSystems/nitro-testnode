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
    done < <(wscat ws://127.0.0.1:9642)
}


./test-node.bash --espresso --latest-espresso-image --validate --tokenbridge --init-force --detach --espresso-finality-node

# Start the espresso finality node
docker compose up -d sequencer-espresso-finality --wait --detach 

# Sending L2 transaction
./test-node.bash script send-l2 --ethamount 100 --to user_l2user --wait

listen_to_sequencer_feed

docker compose down
