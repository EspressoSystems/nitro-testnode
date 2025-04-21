#!/usr/bin/env bash
set -euo pipefail

# This script is like smoke-test-caff-node.bash except that it does not run the tests nor shut down the docker containers.
# It is used by the Hyperlane Integration PoC (see https://github.com/EspressoSystems/hyperlane-integration-poc) project.

user=user_l2user
caff_url="ws://caff-node:8548"

./test-node.bash --espresso --latest-espresso-image --validate --tokenbridge --init-force --detach --caff-node

# Start the caff node
docker compose up -d caff-node --wait --detach

echo "*** Caff node launched successfully. ***"
