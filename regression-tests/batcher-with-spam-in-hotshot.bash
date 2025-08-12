#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")"

echo "starting nodes"
../test-node.bash --init-force --espresso --latest-espresso-image --validate --detach

export http_proxy=""
export https_proxy=""
export all_proxy=""

# docker compose run scripts send-l2-to-hotshot