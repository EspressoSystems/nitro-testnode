#!/usr/bin/env bash
set -euo pipefail

echo "Running regression tests..."
cd regression-tests

echo "1. Running caff-node-batcher-addr-monitor.bash"
./caff-node-batcher-addr-monitor.bash
echo "Completed caff-node-batcher-addr-monitor.bash"

echo "2. Running caff-node-force-inclusion-test.bash"
./caff-node-force-inclusion-test.bash
echo "Completed caff-node-force-inclusion-test.bash"

echo "3. Running caff-node-state-check.bash"
./caff-node-state-check.bash
echo "Completed caff-node-state-check.bash"

echo "4. Running caff-node-restart.bash"
./caff-node-restart.bash
echo "Completed caff-node-restart.bash"

echo "5. Running batcher-with-malicious-sequencer.bash"
./batcher-with-malicious-sequencer.bash
echo "Completed batcher-with-malicious-sequencer.bash"

echo "6. Running batcher-e2e.bash"
./batcher-e2e.bash
echo "Completed batcher-e2e.bash"

echo "7. Running batcher-with-spam-in-hotshot.bash"
./batcher-with-spam-in-hotshot.bash
echo "Completed batcher-with-spam-in-hotshot.bash"

echo "8. Running batcher-shutdown.bash"
./batcher-shutdown.bash
echo "Completed batcher-shutdown.bash"

echo "9. Running batcher-with-multiple-node-client.bash"
./batcher-with-multiple-node-client.bash
echo "Completed batcher-with-multiple-node-client.bash"

echo "10. Running batcher-with-multiple-node-client.bash"
./batcher-with-multiple-node-client.bash
echo "Completed batcher-with-multiple-node-client.bash"

echo "All regression tests completed successfully!"
docker compose down
