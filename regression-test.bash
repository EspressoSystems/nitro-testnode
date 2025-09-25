#!/usr/bin/env bash
set -euo pipefail

echo "Running regression tests..."
cd "$(dirname "$0")"

cd regression-tests
scripts=$(find . -maxdepth 1 -name '*.bash' ! -name 'common.bash' | sort)

for script in $(find . -maxdepth 1 -name '*.bash' ! -name 'common.bash' | sort); do
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
