#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")"

source ./common.bash

echo "starting nodes"
../test-node.bash --init-force --espresso $(get_espresso_image_flag) --validate --detach

# modify the `check-batch-correctness` to false
# This is because the message constructed from the `send-l2-to-hotshot` command is not perfectly correct
# and the batcher will reject it. But actually messages are valid and the validator can execute them successfully.
docker compose run scripts update-config-value \
    --path /config/poster_config.json \
    --property node.batch-poster.check-batch-correctness \
    --value false \
    --isBool true

docker compose restart poster

attacker=user_attacker
user=user_l2user
user2=user_l2user2

echo "funding"
docker compose run scripts send-l2 --ethamount 100 --to sequencer --wait
docker compose run scripts send-l2 --ethamount 100 --to $attacker --wait

# Ignore orphaned container output
# Orphaned containers will be removed at the end of the test
export COMPOSE_IGNORE_ORPHANS=1

nowBlock=$(cast block-number --rpc-url http://127.0.0.1:8547)
messagePosition=$(($nowBlock + 1))
nowDelayed=$(cast block --rpc-url http://127.0.0.1:8547 --json | jq -r .nonce | xargs printf "%d")

get_nonce_from_sequencer() {
    local account=$1
    local addr=$(docker compose run scripts print-address --account $account)
    local nonce=$(cast nonce $addr --rpc-url http://127.0.0.1:8547)
    echo "$nonce"
}

send_valid_tx_message_to_hotshot() {
    local account=$1
    local to=$2
    local nonceOffset=$3
    local nonce=$(get_nonce_from_sequencer $account)
    docker compose run scripts send-l2-to-hotshot --to $to --position $messagePosition --signer $account --delayed $nowDelayed --nonce $((nonce+nonceOffset))
}

send_invalid_nonce_message_to_hotshot() {
    local account=$1
    local to=$2
    docker compose run scripts send-l2-to-hotshot --to $to --position $messagePosition --signer $account --delayed $nowDelayed --nonce 999999
}

send_valid_tx_message_to_hotshot sequencer $user 0
messagePosition=$(($messagePosition+1))

while true; do
    balance=$(cast balance $(docker compose run scripts print-address --account $user) --rpc-url http://127.0.0.1:8247)
    echo "$user balance: $balance"
    if [ "$balance" -gt 0 ]; then
        break
    fi
    sleep 1
done

oldBlockNumber=$(cast block-number --rpc-url http://127.0.0.1:8247)
echo "oldBlockNumber: $oldBlockNumber"

for i in {1..10}; do
    ## This is a valid message but signed by invalid signer
    ## Batcher should ignore this message
    send_valid_tx_message_to_hotshot $attacker user_invalid_user $i
    sleep 1

    ## This is an invalid message signed by valid signer.
    ## Batcher should accept this message but validator will create empty block for it
    send_invalid_nonce_message_to_hotshot sequencer $user2 $((i+1))
    sleep 1

    ## This is a valid transaction with a invalid position, signed by valid signer
    ## Batcher should ignore this message since the message position is taken
    send_valid_tx_message_to_hotshot sequencer $user2 $((i+1))
    sleep 1

    messagePosition=$(($messagePosition+1))
done;

echo "sleeping for 60 seconds. Waiting for the validator to create blocks"
sleep 60

newBlockNumber=$(cast block-number --rpc-url http://127.0.0.1:8247)
echo "newBlockNumber: $newBlockNumber"

if [ "$newBlockNumber" -eq "$oldBlockNumber" ]; then
    echo "Smoke test failed. No blocks created."
    exit 1
fi

userAddress=$(docker compose run scripts print-address --account $user2)
invalidUserAddress=$(docker compose run scripts print-address --account user_invalid_user)

balance1=$(cast balance $userAddress --rpc-url http://127.0.0.1:8247)
echo "$user2 balance: $balance1"

balance2=$(cast balance $invalidUserAddress --rpc-url http://127.0.0.1:8247)
echo "user_invalid_user balance: $balance2"

if [ "$balance1" -gt 0 ] || [ "$balance2" -gt 0 ]; then
    echo "Smoke test failed."
    exit 1
else
    echo "Smoke test succeeded."
fi

docker compose down --remove-orphans
