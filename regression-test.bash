#!/usr/bin/env bash
set -euo pipefail

echo "Running regression tests..."
cd "$(dirname "$0")"

SKIP_TESTS=(
  batcher-e2e.bash
  batcher-resubmission.bash
  batcher-shutdown.bash
  batcher-with-malicious-sequencer.bash
  batcher-with-spam-in-hotshot.bash
  caff-node-batcher-addr-monitor.bash
  # caff-node-force-inclusion-test.bash
  caff-node-restart.bash
  caff-node-state-check.bash
)

cd regression-tests
scripts=$(find . -maxdepth 1 -name '*.bash' \
  ! -name 'common.bash' \
  ! -name 'caff-node-batcher-addr-monitor.bash' \
  | sort)

for script in $scripts; do
  name=$(basename "$script")

  for skip in "${SKIP_TESTS[@]}"; do
    if [[ "$name" == "$skip" ]]; then
      echo "⚠️  Skipping $name"
      continue 2
    fi
  done

  echo "Running $(basename "$script")"
  attempt=1
  max_attempts=3
  while ! ./$script; do
    if (( attempt >= max_attempts )); then
      echo "Failed $(basename "$script") after $attempt attempts, aborting."
      exit 1
    fi
    docker compose down --remove-orphans
    attempt=$((attempt+1))
    echo "Retrying $(basename "$script") (attempt $attempt/$max_attempts)..."
  done
  echo "Completed $(basename "$script")"

done

cd ..
echo "All regression tests completed successfully!"
docker compose down --remove-orphans
