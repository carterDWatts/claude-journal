#!/usr/bin/env bash
# SessionStart bootstrap: ensure $JOURNAL_ROOT exists. Cheap and idempotent.
set -euo pipefail
JOURNAL_ROOT="${JOURNAL_ROOT:-${HOME}/.claude/journal}"
mkdir -p "${JOURNAL_ROOT}/sessions" "${JOURNAL_ROOT}/monthly"
[ -f "${JOURNAL_ROOT}/index.jsonl" ] || : >"${JOURNAL_ROOT}/index.jsonl"
exit 0
