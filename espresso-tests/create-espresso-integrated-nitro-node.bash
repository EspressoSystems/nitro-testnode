#!/usr/bin/env bash
set -euo pipefail
set -x # print each command before executing it, for debugging

ESPRESSO_VERSION=ghcr.io/espressosystems/nitro-espresso-integration/nitro-node-dev:integration
lightClientAddr=0xb6eb235fa509e3206f959761d11e3777e16d0e98
espresso=true
simpleWithValidator=false

# docker pull and tag the espresso integration nitro node.
docker pull $ESPRESSO_VERSION

docker tag $ESPRESSO_VERSION espresso-integration-testnode

# write the espresso configs to the config volume
echo == Writing configs
docker compose run scripts-espresso write-config --simple --simpleWithValidator $simpleWithValidator --espresso $espresso --lightClientAddress $lightClientAddr

# do whatever other espresso setup is needed.

# run esprsso-integrated nitro node for sequencing.
docker compose up sequencer-on-espresso --detach
