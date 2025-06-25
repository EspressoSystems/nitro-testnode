#!/usr/bin/env bash

l3_arg=""

if [[ $1 == "--l3" ]]; then
    l3_arg="--l3node"
fi

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
    result=$(echo "$log" | awk -F'blockNumber=' '{print $2}' | awk '{print $1}')
    if [ -n "$result" ]; then
        echo "$result"
        return
    fi
    echo $(echo "$log" | awk -F'\"block number\"=' '{print $2}' | awk '{print $1}')
}

get_log_count() {
    local container_name="$1"
    echo $(docker compose logs "$container_name" 2>&1 | wc -l)
}

set -euo pipefail

cd "$(dirname "$0")"

echo "starting nodes"

../test-node.bash --init-force --espresso --no-simple --latest-espresso-image --caff-node $l3_arg --detach

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

echo "shutting down caff node"
docker compose stop $container_name 2>&1
docker compose stop $container_name 2>&1

sleep 10

count=$(get_log_count $container_name)
last_produced_block_log=$(read_last_log $container_name "Produced block")
last_produced_block_num=$(parse_block_number "$last_produced_block_log")
echo "last log: $last_produced_block_log"
echo "last block number: $last_produced_block_num"

last_processing_hotshot_block_log=$(read_last_log $container_name "processing hotshot block")
last_processing_hotshot_block_num=$(parse_block_number "$last_processing_hotshot_block_log")
echo "last processing hotshot block number: $last_processing_hotshot_block_num"

docker compose start $container_name

sleep 20

next_produced_block_log=$(docker compose logs $container_name 2>&1 | tail -n +$count | grep "Produced block" | head -1)
echo "next log: $next_produced_block_log"
next_produced_block_num=$(parse_block_number "$next_produced_block_log")

next_processing_hotshot_block_log=$(docker compose logs $container_name 2>&1 | tail -n +$count | grep "processing hotshot block" | head -1)
next_processing_hotshot_block_num=$(parse_block_number "$next_processing_hotshot_block_log")

echo "last block number: $last_produced_block_num"
echo "next block number: $next_produced_block_num"

echo "last_hotshot_log: $last_processing_hotshot_block_log"
echo "next_hotshot_log: $next_processing_hotshot_block_log"
echo "last processing hotshot block number: $last_processing_hotshot_block_num"
echo "next processing hotshot block number: $next_processing_hotshot_block_num"

if [[ $next_produced_block_num -eq $((last_produced_block_num + 1)) ]]; then
    echo "caff node next produced block check succeeded"
else
    echo "caff node next produced block check failed"
    exit 1
fi

if [[ $next_processing_hotshot_block_num -le $((last_processing_hotshot_block_num)) ]]; then
    # It is allowed the caff node restarts from a bit earlier hotshot block
    # because the caff node stores the earliest hotshot block number of its buffer
    if [[ $next_processing_hotshot_block_num -ge $((last_processing_hotshot_block_num - 10)) ]]; then
        echo "caff node next processing hotshot block check succeeded"
        docker compose down
        exit 0
    fi
fi

exit 1

