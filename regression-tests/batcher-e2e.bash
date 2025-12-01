#!/usr/bin/env bash

# This test we send a lot of transactions to the L2 and delayed messages to L1.
# We expect the validator will eventually catch up with the sequencer.
# This test will take around 20 minutes to finish.

set -euo pipefail

cd "$(dirname "$0")"

source ./common.bash

# Ignore orphaned container output
# Orphaned containers will be removed at the end of the test
export COMPOSE_IGNORE_ORPHANS=1

echo "starting nodes"
../test-node.bash --init-force --espresso $(get_espresso_image_flag) --validate --detach

echo "starting tx spammer"
docker compose run --detach scripts send-l2 --ethamount 10 --to user_l2user --times 2000 --delay 200 --wait

echo "sending delayed tx"
docker compose run --detach scripts send-l2-delayed --ethamount 10 --to user_delayed_user --from espresso-sequencer --times 100 --delay 2000 --wait

check_validator_root_matches_sequencer() {
    local block=$1
    validator_root=$(cast block --rpc-url http://localhost:8247 --json $block | jq -r .stateRoot)
    sequencer_root=$(cast block --rpc-url http://localhost:8547 --json $block | jq -r .stateRoot)
    if [[ "$validator_root" != "$sequencer_root" ]]; then
        echo "Error: validator root ($validator_root) does not match sequencer root ($sequencer_root)"
        exit 1
    fi
    echo "validator block number: $block, validator root: $validator_root, sequencer root: $sequencer_root"
}

sleep 20
validator_block=0
i=0
while [[ $i -lt 5 ]]; do
    sleep 60
    new_validator_block=$(cast block-number --rpc-url http://localhost:8247)
    echo "validator block number: $new_validator_block"
    if [[ "$new_validator_block" -eq "$validator_block" ]]; then
        # validator has caught up
        i=$((i+1))
        continue
    fi

    validator_block=$new_validator_block
    check_validator_root_matches_sequencer $validator_block
done

echo "validator stops creating blocks for the last 60 seconds. validator block number: $validator_block"
sequencer_block=$(cast block-number --rpc-url http://localhost:8547)
sequencer_inbox=$(docker compose run --entrypoint sh poster -c "jq -r '.[0].rollup.\"sequencer-inbox\"' /config/deployed_chain_info.json | tail -n 1 | tr -d '\r\n'")
echo "sequencer inbox: $sequencer_inbox"
batch_count=$(cast call $sequencer_inbox "batchCount()(uint256)" --rpc-url http://localhost:8545)
echo "batch count: $batch_count"

if (( sequencer_block > validator_block + batch_count + 1 )); then
    echo "Error: sequencer block number ($sequencer_block) is greater than validator block number ($validator_block) + batch count ($batch_count)"
    exit 1
fi
echo "validator has caught up. validator block number: $validator_block"

validator_block=$(cast block-number --rpc-url http://localhost:8247)
check_validator_root_matches_sequencer $validator_block

docker compose run scripts update-config-value \
    --path /config/poster_config.json \
    --property node.batch-poster.max-empty-batch-delay \
    --value "30s" \

docker compose restart poster

# Batcher should have created 1 empty batch
sleep 140

validator_block2=$(cast block-number --rpc-url http://localhost:8247)
if (( validator_block2 == validator_block )); then
    echo "Error: validator block number ($validator_block2) is not greater than validator block number ($validator_block)"
    exit 1
fi

check_validator_root_matches_sequencer $validator_block2

docker compose down --remove-orphans
