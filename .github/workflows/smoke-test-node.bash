#!/bin/bash
# The script starts up the test node and waits until the timeout (10min) or
# until send-l2 succeeds and the latest confirmation is fetched.

# Start the test node and get PID, to terminate it once send-l2 is done.
cd ${GITHUB_WORKSPACE}

./smoke-test-node.bash --init  --detach

START=$(date +%s)
L2_TRANSACTION_SUCCEEDED=false
LATEST_CONFIRMATION_FETCHED=false
SUCCEEDED=false

while true; do
if [ "$L2_TRANSACTION_SUCCEEDED" = false ]; then
if ${GITHUB_WORKSPACE}/smoke-test-node.bash script send-l2 --ethamount 100 --to user_l2user --wait; then
echo "Sending l2 transaction succeeded"
L2_TRANSACTION_SUCCEEDED=true
fi
fi

if [ "$LATEST_CONFIRMATION_FETCHED" = false ]; then
 rollupAddress=`docker compose run --entrypoint sh poster -c "jq -r '.[0].rollup.rollup' /config/deployed_chain_info.json | tail -n 1 | tr -d '\r\n'"`
 cast call --rpc-url http://localhost:8545  $rollupAddress 'latestConfirmed()(uint256)' | grep "error" > /dev/null
  error=` cast call --rpc-url http://localhost:8545  $rollupAddress 'latestConfirmed()(uint256)' | grep "error"`
     if [ "$error" == "" ]; then
       echo "Lastest confirmation fetched"
       LATEST_CONFIRMATION_FETCHED=true
     fi
fi


if [ "$L2_TRANSACTION_SUCCEEDED" = true ] && [ "$LASTEST_CONFIRMATION_FETCHED" = true ]; then
SUCCEEDED=true
break
fi

# Check if the timeout (10 min) has been reached.
NOW=$(date +%s)
DIFF=$((NOW - START))
if [ "$DIFF" -ge 600 ]; then
echo "Timed out"
break
fi

sleep 10
done

docker-compose stop

if [ "$SUCCEEDED" = false ]; then
docker-compose logs
exit 1
fi

exit 0
