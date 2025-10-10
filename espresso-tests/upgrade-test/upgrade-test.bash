#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

export COMPOSE_IGNORE_ORPHANS=1

export ESPRESSO_NITRO_CONTRACTS_BRANCH=v2.1.3-8e58a9a

# Load env vars for rollupcreator runs without editing docker-compose.yaml
# set -a exports all variables defined in the env file into the shell
set -a
. ./upgrade-test.env
set +a

echo "running an espresso node with branch $ESPRESSO_NITRO_CONTRACTS_BRANCH"
../../test-node.bash --init-force --latest-espresso-image --no-simple --detach --espresso

L1_PRIV_KEY=`docker compose run scripts print-private-key --account l2owner | tail -n 1 | tr -d '\r\n'`
echo "L1_PRIV_KEY: $L1_PRIV_KEY"

sleep 100

echo "starting tx spammer"
docker compose run --detach scripts send-l2 --ethamount 10 --to user_l2user --times 2000 --delay 200 --wait

ROLLUP_ADDRESS=0x4d16C7c301d4233414Efa3fc822F329B53F52b68
EXCUTOR=0x513D9F96d4D0563DEbae8a0DC307ea0E46b10ed7
echo "ROLLUP_ADDRESS: $ROLLUP_ADDRESS"
echo "EXCUTOR: $EXCUTOR"

echo "Disabling validator whitelist to make sure the staker is making nodes"
cast send $EXCUTOR "executeCall(address,bytes)" $ROLLUP_ADDRESS "$(cast calldata 'setValidatorWhitelistDisabled(bool)' true)" --rpc-url http://localhost:8545 --private-key $L1_PRIV_KEY

sleep 120

export NITRO_CONTRACTS_BRANCH=develop
export NITRO_CONTRACTS_REPO=https://github.com/EspressoSystems/nitro-contracts.git

echo "deploying v3.1.0 contracts"
# Values should be put to the `templatesV3.1.ts`
docker compose run --build \
  -e PARENT_CHAIN_RPC="http://geth:8545" \
  -e DEPLOYER_PRIVKEY=$L1_PRIV_KEY \
  -e PARENT_CHAIN_ID=$L1CHAINID \
  -e CHILD_CHAIN_NAME="arb-dev-test" \
  -e MAX_DATA_SIZE=117964 \
  -e OWNER_ADDRESS=$L2OWNER_ADDRESS \
  -e WASM_MODULE_ROOT=$WASMROOT \
  -e SEQUENCER_ADDRESS=$SEQUENCER_ADDRESS \
  -e AUTHORIZE_VALIDATORS=10 \
  -e CHILD_CHAIN_CONFIG_PATH="/config/l2_chain_config.json" \
  -e CHAIN_DEPLOYMENT_INFO="/config/deployment.json" \
  -e CHILD_CHAIN_INFO="/config/deployed_chain_info.json" \
  -e LIGHT_CLIENT_ADDR=$LIGHT_CLIENT_ADDR \
  -e STAKE_TOKEN_ADDRESS="" \
  rollupcreator create-rollup-testnode

echo "running upgrade"
# Use -v to override the settings
docker compose run --build \
  -v "$(pwd)/custom:/workspace/scripts/files/configs/custom.ts:ro" \
  -v "$(pwd)/templatesV3.1:/workspace/scripts/files/templatesV3.1.ts:ro" \
  -e CONFIG_NETWORK_NAME=$CONFIG_NETWORK_NAME \
  -e DEPLOYED_CONTRACTS_DIR=$DEPLOYED_CONTRACTS_DIR \
  -e DISABLE_VERIFICATION=$DISABLE_VERIFICATION \
  -e CUSTOM_RPC_URL=$CUSTOM_RPC_URL \
  -e CUSTOM_CHAINID=$CUSTOM_CHAINID \
  -e L1_PRIV_KEY=$L1_PRIV_KEY \
  --entrypoint sh \
  rollupcreator -lc '
  export PATH="/root/.foundry/bin:$PATH";
  forge --version &&
  yarn script:bold-prepare --network custom &&
  yarn script:bold-populate-lookup --network custom &&
  yarn script:bold-local-execute --network custom'

sequencer_inbox=$(docker compose run --entrypoint sh poster -c "jq -r '.[0].rollup.\"sequencer-inbox\"' /config/deployed_chain_info.json | tail -n 1 | tr -d '\r\n'")
echo "sequencer_inbox: $sequencer_inbox"

parent_chain_upgrade_executor=$(docker compose run --entrypoint sh poster -c "jq -r '.[0].rollup.\"upgrade-executor\"' /config/deployed_chain_info.json | tail -n 1 | tr -d '\r\n'")
echo "parent_chain_upgrade_executor: $parent_chain_upgrade_executor"

tee_verifier=$(cast call $sequencer_inbox "espressoTEEVerifier()(address)" --rpc-url http://localhost:8545)
echo "tee_verifier: $tee_verifier"

cast send $parent_chain_upgrade_executor $(cast calldata "executeCall(address, bytes)" $sequencer_inbox $(cast calldata "setEspressoTEEVerifier(address)" $tee_verifier))  --rpc-url http://localhost:8545 --private-key $L1_PRIV_KEY

docker compose down --remove-orphans
