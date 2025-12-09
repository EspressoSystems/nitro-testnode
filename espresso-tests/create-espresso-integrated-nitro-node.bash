#!/usr/bin/env bash
set -euo pipefail
# set -x # print each command before executing it, for debugging

ESPRESSO_VERSION=ghcr.io/espressosystems/nitro-espresso-integration/nitro-node:v3.8.0-2495bf4
lightClientAddr=0xb6eb235fa509e3206f959761d11e3777e16d0e98
simpleWithValidator=false

# docker pull and tag the espresso integration nitro node.
docker pull $ESPRESSO_VERSION --platform linux/amd64

docker tag $ESPRESSO_VERSION espresso-integration-testnode

# write the espresso configs to the config volume
echo == Writing configs
docker compose run --rm --build scripts-espresso write-config --simple --simpleWithValidator $simpleWithValidator --espresso true --lightClientAddress $lightClientAddr

# do whatever other espresso setup is needed.

# run Espresso integrated nitro node for sequencing.
docker compose up sequencer-on-espresso --detach
