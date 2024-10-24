#!/usr/bin/env bash

set -euo pipefail
set -a
set -x

start_num=0
num_transactions=10

echo == Simulating l2 traffic

while [ $start_num != $num_transactions ]; do
    docker compose run scripts send-l2 --ethamount 100 --to l2owner --from funnel --l2url ws://sequencer-on-espresso:8548 --wait 
    ((start_num+=1))
done

sleep 10s
