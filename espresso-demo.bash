#!/usr/bin/env bash

set -a && source .env && set +a

set -e

NITRO_NODE_VERSION=offchainlabs/nitro-node:v3.0.1-cf4b74e-dev
ESPRESSO_VERSION=ghcr.io/espressosystems/nitro-espresso-integration/nitro-node-dev:integration
NITRO_CONTRACTS_REPO=https://github.com/EspressoSystems/nitro-contracts.git
BLOCKSCOUT_VERSION=offchainlabs/blockscout:v1.0.0-c8db5b1
NITRO_CONTRACTS_BRANCH=develop

export NITRO_CONTRACTS_REPO
export NITRO_CONTRACTS_BRANCH


mydir=`dirname $0`
cd "$mydir"



if [[ $# -gt 0 ]] && [[ $1 == "script" ]]; then
    shift
    docker compose -f $COMPOSE_FILE run scripts "$@"
    exit $?
fi

num_volumes=`docker volume ls --filter label=com.docker.compose.project=nitro-testnode -q | wc -l`

if [[ $num_volumes -eq 0 ]]; then
    force_init=true
else
    force_init=false
fi

run=true
force_build=false
validate=false
detach=false
tokenbridge=true
lightClientAddr=0xb6eb235fa509e3206f959761d11e3777e16d0e98
latest_espresso_image=false
dev_build_nitro=false
dev_build_blockscout=false
batchposters=1
redundantsequencers=0
blockscout=false
devprivkey=$L2_OWNER_PRIVATE_KEY
l1chainid=$L1_CHAIN_ID
while [[ $# -gt 0 ]]; do
    case $1 in
        --init)
            if ! $force_init; then
                echo == Warning! this will remove all previous data
                read -p "are you sure? [y/n]" -n 1 response
                if [[ $response == "y" ]] || [[ $response == "Y" ]]; then
                    force_init=true
                    echo
                else
                    exit 0
                fi
            fi
            shift
            ;;
        --init-force)
            force_init=true
            shift
            ;;
        --dev)
            shift
            if [[ $# -eq 0 || $1 == -* ]]; then
                # If no argument after --dev, set both flags to true
                dev_build_nitro=true
                dev_build_blockscout=true
            else
                while [[ $# -gt 0 && $1 != -* ]]; do
                    if [[ $1 == "nitro" ]]; then
                        dev_build_nitro=true
                    elif [[ $1 == "blockscout" ]]; then
                        dev_build_blockscout=true
                    fi
                    shift
                done
            fi
            ;;
        --latest-espresso-image)
            latest_espresso_image=true
            shift
            ;;
        --build)
            force_build=true
            shift
            ;;
        --validate)
            validate=true
            shift
            ;;
        --blockscout)
            blockscout=true
            shift
            ;;
        --no-tokenbridge)
            tokenbridge=false
            shift
            ;;
        --no-run)
            run=false
            shift
            ;;
        --detach)
            detach=true
            shift
            ;;
        --batchposters)
            batchposters=$2
            if ! [[ $batchposters =~ [0-3] ]] ; then
                echo "batchposters must be between 0 and 3 value:$batchposters."
                exit 1
            fi
            shift
            shift
            ;;
        --redundantsequencers)
            redundantsequencers=$2
            if ! [[ $redundantsequencers =~ [0-3] ]] ; then
                echo "redundantsequencers must be between 0 and 3 value:$redundantsequencers."
                exit 1
            fi
            shift
            shift
            ;;
        --tokenbridge)
            tokenbridge=true
            shift
            ;;
        *)
            echo Usage: $0 \[OPTIONS..]
            echo        $0 script [SCRIPT-ARGS]
            echo
            echo OPTIONS:
            echo --build           rebuild docker images
            echo --dev             build nitro and blockscout dockers from source instead of pulling them. Disables simple mode
            echo --init            remove all data, rebuild, deploy new rollup
            echo --latest-espresso-image
            echo --no-tokenbridge  don\'t build or launch tokenbridge
            echo --detach          detach from nodes after running them
            echo --batchposters    batch posters [0-3]
            echo --redundantsequencers redundant sequencers [0-3]
            echo --simple          run a simple configuration. one node as sequencer/batch-poster/staker \(default unless using --dev\)
            echo --no-simple       run a full configuration with separate sequencer/batch-poster/validator/relayer
            echo
            echo script runs inside a separate docker. For SCRIPT-ARGS, run $0 script --help
            exit 0
    esac
done

if $force_init; then
  force_build=true
fi

if $dev_build_nitro; then
  if [[ "$(docker images -q nitro-node-dev:latest 2> /dev/null)" == "" ]]; then
    force_build=true
  fi
fi

if $dev_build_blockscout; then
  if [[ "$(docker images -q blockscout:latest 2> /dev/null)" == "" ]]; then
    force_build=true
  fi
fi

NODES="sequencer"
INITIAL_SEQ_NODES="sequencer"

if [ $redundantsequencers -gt 0 ]; then
    NODES="$NODES sequencer_b"
    INITIAL_SEQ_NODES="$INITIAL_SEQ_NODES sequencer_b"
fi
if [ $redundantsequencers -gt 1 ]; then
    NODES="$NODES sequencer_c"
fi
if [ $redundantsequencers -gt 2 ]; then
    NODES="$NODES sequencer_d"
fi

if [ $batchposters -gt 0 ];then
    NODES="$NODES poster"
fi

if [ $batchposters -gt 1 ]; then
    NODES="$NODES poster_b"
fi

if [ $batchposters -gt 2 ]; then
    NODES="$NODES poster_c"
fi

if $validate; then
    NODES="$NODES validator"
else 
    NODES="$NODES staker-unsafe"
fi

if $blockscout; then
    NODES="$NODES blockscout"
fi

if $force_build; then
  echo == Building..
  if $dev_build_nitro; then
    if ! [ -n "${NITRO_SRC+set}" ]; then
        NITRO_SRC=`dirname $PWD`
    fi
    if ! grep ^FROM "${NITRO_SRC}/Dockerfile" | grep nitro-node 2>&1 > /dev/null; then
        echo nitro source not found in "$NITRO_SRC"
        echo execute from a sub-directory of nitro or use NITRO_SRC environment variable
        exit 1
    fi
    docker build "$NITRO_SRC" -t nitro-node-dev --target nitro-node-dev
  fi
  if $dev_build_blockscout; then
    if $blockscout; then
      docker build blockscout -t blockscout -f blockscout/docker/Dockerfile
    fi
  fi
  LOCAL_BUILD_NODES="scripts rollupcreator"
  if $tokenbridge; then
    LOCAL_BUILD_NODES="$LOCAL_BUILD_NODES tokenbridge"
  fi
  docker compose -f $COMPOSE_FILE build --no-rm $LOCAL_BUILD_NODES
fi

if $dev_build_nitro; then
  docker tag nitro-node-dev:latest nitro-node-dev-testnode
else
  if $latest_espresso_image; then
    docker pull $ESPRESSO_VERSION 
    docker tag $ESPRESSO_VERSION nitro-node-dev-testnode
  else 
     docker pull $NITRO_NODE_VERSION
     docker tag $NITRO_NODE_VERSION nitro-node-dev-testnode
  fi
fi

if $dev_build_blockscout; then
  if $blockscout; then
    docker tag blockscout:latest blockscout-testnode
  fi
else
  if $blockscout; then
    docker pull $BLOCKSCOUT_VERSION
    docker tag $BLOCKSCOUT_VERSION blockscout-testnode
  fi
fi

if $force_build; then
    docker compose -f $COMPOSE_FILE build --no-rm $NODES scripts
fi

if $force_init; then
    echo == Removing old data..
    docker compose -f $COMPOSE_FILE down
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
    docker compose -f $COMPOSE_FILE run scripts write-accounts

    echo == Funding validator, sequencer and l2owner
    docker compose -f $COMPOSE_FILE run scripts send-l1 --ethamount 0.001 --to validator --wait
    docker compose -f $COMPOSE_FILE run scripts send-l1 --ethamount 0.001 --to sequencer --wait
    docker compose -f $COMPOSE_FILE run scripts send-l1 --ethamount 0.001 --to l2owner --wait

    l2ownerAddress=`docker compose -f $COMPOSE_FILE run scripts print-address --account l2owner | tail -n 1 | tr -d '\r\n'`
    echo $l2ownerAddress

    # TODO: should we ask for config from the user here?
    echo == Writing l2 chain config
    docker compose -f $COMPOSE_FILE run scripts --l2owner $l2ownerAddress write-l2-chain-config --espresso $espresso --chainId $L2_CHAIN_ID

    sequenceraddress=`docker compose run scripts print-address --account sequencer | tail -n 1 | tr -d '\r\n'`
    l2ownerKey=`docker compose run scripts print-private-key --account l2owner | tail -n 1 | tr -d '\r\n'`
    wasmroot=`docker compose run --entrypoint sh sequencer -c "cat /home/user/target/machines/latest/module-root.txt"`

    # echo == Initializing redis
    # docker compose up --wait redis
    # docker compose run scripts redis-init --redundancy $redundantsequencers

    # echo == Bridging funds
    # docker compose up --wait $INITIAL_SEQ_NODES
    # docker compose run scripts bridge-funds --ethamount 0.001 --wait

    # if $tokenbridge; then
    #     echo == Deploying L1-L2 token bridge
    # fi
fi


if $run ; then
    UP_FLAG=""
    if $detach; then
        UP_FLAG="--wait"
    fi

    echo == Launching Sequencer
    echo if things go wrong - use --init to create a new chain
    echo

    docker compose -f $COMPOSE_FILE up $UP_FLAG $NODES
fi