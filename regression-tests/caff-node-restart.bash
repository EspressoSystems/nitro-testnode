#!/usr/bin/env bash

wait_for_block_number() {
    local rpcUrl="$1"
    local targetBlockNumber="$2"
    while true; do
        blockNumber=$(cast block-number --rpc-url $rpcUrl)
        echo "Current caff node block number: $blockNumber"
        if [[ $blockNumber -gt $targetBlockNumber ]]; then
            break
        fi
        sleep 5
    done
}

read_last_log() {
    local container_name="$1"
    local search_string="$2"
    last_log=$(docker compose logs "$container_name" 2>&1 | grep "$search_string" | tail -1)
    echo "$last_log"
}

parse_block_number() {
    local log="$1"
    echo $(echo "$log" | awk -F'blockNumber=' '{print $2}' | awk '{print $1}')
}

get_log_count() {
    local container_name="$1"
    echo $(docker compose logs "$container_name" 2>&1 | wc -l)
}

set -euo pipefail

cd "$(dirname "$0")"

echo "starting nodes"

../test-node.bash --init-force --espresso --validate --latest-espresso-image --caff-node --detach

export http_proxy=""
export https_proxy=""
export all_proxy=""

container_name="caff-node"

while true; do
    curl -sfL http://localhost:41000/v0/status/block-height && break || sleep 5
    echo "waiting for nodes"
done

echo "starting tx spammer"
docker compose run --detach scripts send-l2 --ethamount 10 --to user_l2user --times 500000 --delay 20000 --wait

if [ "$l3_arg" != "" ]; then
    docker compose run --detach scripts send-l3 --ethamount 10 --to user_l3user --times 500000 --delay 20000 --wait
fi

caff_rpc="http://localhost:8550"

wait_for_block_number $caff_rpc 20

docker compose stop $container_name 2>&1

sleep 10

count=$(get_log_count $container_name)
last_log=$(read_last_log $container_name "Produced block")
last_block_num=$(parse_block_number "$last_log")
echo "last log: $last_log"
echo "last block number: $last_block_num"

echo "shutting down caff node"
docker compose start $container_name

sleep 10

next_log=$(docker compose logs $container_name 2>&1 | tail -n +$count | grep "Produced block" | head -1)
echo "next log: $next_log"
next_block_num=$(parse_block_number "$next_log")

echo "last block number: $last_block_num"
echo "next block number: $next_block_num"

if [[ $next_block_num -eq $((last_block_num + 1)) ]]; then
    echo "Caff node restarted successfully"
    exit 0
else
    echo "Caff node restart failed"
    exit 1
fi

docker compose down
