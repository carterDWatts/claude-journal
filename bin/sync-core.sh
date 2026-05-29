#!/usr/bin/env bash
# Copy /core into each adapter's bundled /core directory.
# Run this after editing core/ to keep adapters in sync. CI should fail if
# the repo is dirty after running this.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
for adapter_core in "${REPO_ROOT}"/adapters/*/core; do
  [ -d "${adapter_core}" ] || continue
  rsync -a --delete "${REPO_ROOT}/core/" "${adapter_core}/"
  echo "synced -> ${adapter_core}"
done
