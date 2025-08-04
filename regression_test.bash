#!/usr/bin/env bash
set -euo pipefail

echo "Running regression tests..."

echo "1. Running caff-node-batcher-addr-monitor.bash"
./caff-node-batcher-addr-monitor.bash
echo "Completed caff-node-batcher-addr-monitor.bash"

echo "2. Running caff-node-force-inclusion-test.bash"
./caff-node-force-inclusion-test.bash
echo "Completed caff-node-force-inclusion-test.bash"

echo "3. Running caff-node-state-check.bash"
./caff-node-state-check.bash
echo "Completed caff-node-state-check.bash"

echo "All regression tests completed successfully!"
docker compose down
