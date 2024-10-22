#!/usr/bin/env bash

set -e

NITRO_NODE_VERSION=offchainlabs/nitro-node:v3.1.0-7d1d84c-dev
DEFAULT_NITRO_CONTRACTS_REPO=https://github.com/EspressoSystems/nitro-contracts.git
NITRO_CONTRACTS_BRANCH=develop

ESPRESSO_VERSION=ghcr.io/espressosystems/nitro-espresso-integration/nitro-node-dev:latest

# Set default versions if not overriden by provided env vars
: ${NITRO_CONTRACTS_REPO:=$DEFAULT_NITRO_CONTRACTS_REPO}
: ${NITRO_CONTRACTS_BRANCH:=$DEFAULT_NITRO_CONTRACTS_VERSION}
export NITRO_CONTRACTS_REPO
export NITRO_CONTRACTS_BRANCH

echo "Running espresso mode"
echo "Using NITRO_CONTRACTS_REPO: $NITRO_CONTRACTS_REPO"
echo "Using NITRO_CONTRACTS_BRANCH: $NITRO_CONTRACTS_BRANCH"


mydir=`dirname $0`
cd "$mydir"

if [[ $# -gt 0 ]] && [[ $1 == "script" ]]; then
    shift
    docker compose run scripts "$@"
    exit $?
fi

num_volumes=`docker volume ls --filter label=com.docker.compose.project=nitro-testnode -q | wc -l`

if [[ $num_volumes -eq 0 ]]; then
    force_init=true
else
    force_init=false
fi


detach=false
init=false
force_build=false
latest_espresso_image=false
lightClientAddr=0xb6eb235fa509e3206f959761d11e3777e16d0e98
l1chainid=1337
while [[ $# -gt 0 ]]; do
    case $1 in
        --detach)
            detach=true
            shift
            ;;
        --init)
            force_init=true
            shift
            ;;
        --build)
            force_build=true
            shift
            ;;
        --latest-espresso-image)
            latest_espresso_image=true  
            shift
            ;;  
        --detach)
            detach=true
            shift
            ;;
        *)
            echo Usage: $0 \[OPTIONS..]
            echo        $0 script [SCRIPT-ARGS]
            echo
            echo OPTIONS:
            echo --detach          detach from nodes after running them
            echo --init            remove all data, rebuild, deploy new rollup
            echo --build           rebuild docker images
            echo --latest-espresso-image use latest espresso image
            echo
            echo script runs inside a separate docker. For SCRIPT-ARGS, run $0 script --help    
            exit 0  
    esac
done



if $force_init; then
  force_build=true
fi


NODES="sequencer redis poster validator"
INITIAL_SEQ_NODES="sequencer validation_node"

if $force_build; then
  echo == Building..
  LOCAL_BUILD_NODES="scripts rollupcreator"
  docker compose build --no-rm $LOCAL_BUILD_NODES
fi

if $force_build; then
    INITIAL_SEQ_NODES="$INITIAL_SEQ_NODES espresso-dev-node"
else
    NODES="$NODES espresso-dev-node"
fi


if $latest_espresso_image; then
    docker pull $ESPRESSO_VERSION 
    docker tag $ESPRESSO_VERSION nitro-node-dev-testnode
else 
    docker pull $NITRO_NODE_VERSION
    docker tag $NITRO_NODE_VERSION nitro-node-dev-testnode
fi

if $force_build; then
    docker compose build --no-rm $NODES scripts 
fi

if $force_init; then
  echo == Removing old data...
  docker compose down
  leftoverContainers=`docker container ls -a --filter label=com.docker.compose.project=nitro-testnode -q | xargs echo`
  if [ `echo $leftoverContainers | wc -w` -gt 0 ]; then
      docker rm $leftoverContainers
  fi
  docker volume prune -f --filter label=com.docker.compose.project=nitro-testnode
  leftoverVolumes=`docker volume ls --filter label=com.docker.compose.project=nitro-testnode -q | xargs echo`
  if [ `echo $leftoverVolumes | wc -w` -gt 0 ]; then
      docker volume rm $leftoverVolumes
  fi

  echo == Generating l1 keys
  docker compose run scripts write-accounts
  docker compose run --entrypoint sh geth -c "echo passphrase > /datadir/passphrase"
  docker compose run --entrypoint sh geth -c "chown -R 1000:1000 /keystore"
  docker compose run --entrypoint sh geth -c "chown -R 1000:1000 /config"

   echo == Writing geth configs
   docker compose up --wait geth
   docker compose run scripts write-geth-genesis-config

  echo == Funding validator, sequencer and l2owner
  docker compose run scripts send-l1 --ethamount 1000 --to validator --wait
  docker compose run scripts send-l1 --ethamount 1000 --to sequencer --wait
  docker compose run scripts send-l1 --ethamount 1000 --to l2owner --wait
  docker compose run scripts send-l1 --ethamount 10000 --to espresso-sequencer --wait

  echo == create l1 traffic
  docker compose run scripts send-l1 --ethamount 1000 --to user_l1user --wait
  docker compose run scripts send-l1 --ethamount 0.0001 --from user_l1user --to user_l1user_b --wait --delay 500 --times 1000000 > /dev/null &  

  l2ownerAddress=`docker compose run scripts print-address --account l2owner | tail -n 1 | tr -d '\r\n'`
  echo $l2ownerAddress

  echo == Writing l2 chain config
  docker compose run scripts --l2owner $l2ownerAddress  write-l2-chain-config --espresso

  sequenceraddress=`docker compose run scripts print-address --account sequencer | tail -n 1 | tr -d '\r\n'`
  l2ownerKey=`docker compose run scripts print-private-key --account l2owner | tail -n 1 | tr -d '\r\n'`    
  wasmroot=`docker compose run --entrypoint sh sequencer -c "cat /home/user/target/machines/latest/module-root.txt"`

  echo == Deploying L2 chain
  docker compose run -e PARENT_CHAIN_RPC="http://geth:8545" -e DEPLOYER_PRIVKEY=$l2ownerKey -e PARENT_CHAIN_ID=$l1chainid -e CHILD_CHAIN_NAME="arb-dev-test" -e MAX_DATA_SIZE=117964 -e OWNER_ADDRESS=$l2ownerAddress -e WASM_MODULE_ROOT=$wasmroot -e SEQUENCER_ADDRESS=$sequenceraddress -e AUTHORIZE_VALIDATORS=10 -e CHILD_CHAIN_CONFIG_PATH="/config/l2_chain_config.json" -e CHAIN_DEPLOYMENT_INFO="/config/deployment.json" -e CHILD_CHAIN_INFO="/config/deployed_chain_info.json" -e LIGHT_CLIENT_ADDR=$lightClientAddr  rollupcreator create-rollup-testnode
  docker compose run --entrypoint sh rollupcreator -c "jq [.[]] /config/deployed_chain_info.json > /config/l2_chain_info.json"
  docker compose run --entrypoint sh rollupcreator -c "cat /config/l2_chain_info.json"

  echo == Writing config
  docker compose run scripts write-config --espresso  --lightClientAddress $lightClientAddr
  echo == Initializing redis
  docker compose up --wait redis
  docker compose run scripts redis-init

  echo == Funding l2 funnel and dev key
  docker compose up --wait $INITIAL_SEQ_NODES
  docker compose run scripts bridge-funds --ethamount 100000 --wait 
  docker compose run scripts send-l2 --ethamount 10000 --to espresso-sequencer --wait
  docker compose run scripts send-l2 --ethamount 100 --to l2owner --wait


  echo == Deploy CacheManager on L2
  docker compose run -e CHILD_CHAIN_RPC="http://sequencer:8547" -e CHAIN_OWNER_PRIVKEY=$l2ownerKey rollupcreator deploy-cachemanager-testnode
fi


UP_FLAG=""
if $detach; then
    UP_FLAG="--wait"
fi

echo == Launching Sequencer
echo if things go wrong - use --init to create a new chain
echo $NODES

docker compose up $UP_FLAG $NODES
