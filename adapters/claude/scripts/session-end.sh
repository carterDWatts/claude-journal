#!/usr/bin/env bash
# Claude Code SessionEnd adapter.
#
# Claude's SessionEnd payload is already in the core recorder's accepted shape
# ({session_id, transcript_path, cwd, reason}), so just pipe it through.
set -euo pipefail
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
exec bash "${PLUGIN_ROOT}/core/record-session.sh"
