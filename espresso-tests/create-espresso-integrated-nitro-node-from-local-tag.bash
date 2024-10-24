#!/usr/bin/env bash
set -euo pipefail
set -x # print each command before executing it, for debugging

lightClientAddr=0xb6eb235fa509e3206f959761d11e3777e16d0e98
espresso=true
simpleWithValidator=false
migration=true

# docker pull and tag the espresso integration nitro node.

# write the espresso configs to the config volume
echo == Writing configs
docker compose run scripts-espresso write-config --simple --simpleWithValidator $simpleWithValidator --espresso $espresso --lightClientAddress $lightClientAddr --switchDelayThreshold 20

docker compose run scripts-espresso write-l2-chain-config --migration $migration

docker compose run --entrypoint sh rollupcreator -c "jq [.[]] /config/deployed_chain_info.json > /espresso-config/l2_chain_info.json"

# do whatever other espresso setup is needed.

# run esprsso-integrated nitro node for sequencing.
docker compose up sequencer-on-espresso --detach