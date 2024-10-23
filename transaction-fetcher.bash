#!/usr/bin/env bash

set -euo pipefail
set -a
set -x

chainID=412346
start_block=1
end_block=1000

while [ $start_block != $end_block ]; do
    echo $(curl http://localhost:41000/v0/availability/block/"$start_block"/namespace/$chainID)
    ((start_block+=1))
done
