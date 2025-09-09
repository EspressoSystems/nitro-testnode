#!/usr/bin/env bash
set -euo pipefail

echo "Running regression tests..."
cd regression-tests

for script in $(find regression-tests -maxdepth 1 -name '*.bash' ! -name 'common.bash' | sort); do
  echo "Running $(basename "$script")"
  attempt=1
  max_attempts=3
  while ! ./$script; do
    if (( attempt >= max_attempts )); then
      echo "Failed $(basename "$script") after $attempt attempts, aborting."
      exit 1
    fi
    attempt=$((attempt+1))
    echo "Retrying $(basename "$script") (attempt $attempt/$max_attempts)..."
  done
  echo "Completed $(basename "$script")"

done

echo "All regression tests completed successfully!"
docker compose down
