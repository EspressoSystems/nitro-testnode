#!/usr/bin/env bash

set -euo pipefail
set -a
set -x

TESTNODE_DIR="$(dirname $(readlink -f $0))"

source ./espresso-tests/.env

cast send $CHILD_CHAIN_UPGRADE_EXECUTOR_ADDRESS "execute(address, bytes)" 0x0000000000000000000000000000000000000070 $(cast calldata "setChainConfig(string)" "$(cat "$TESTNODE_DIR"/espresso-tests/test-chain-config.json)") --rpc-url $CHILD_CHAIN_RPC_URL --private-key $PRIVATE_KEY

start_num=0
num_transactions=10

echo == Simulating l2 traffic

while [ $start_num != $num_transactions ]; do
    docker compose run scripts send-l2 --ethamount 100 --to l2owner --wait
    ((start_num+=1))
done

sleep 10s

start_block=4100
end_block=4500

while [ $start_block != $end_block ]; do
    echo $(curl http://localhost:41000/v0/availability/block/"$start_block"/namespace/412346)
    ((start_block+=1))
done