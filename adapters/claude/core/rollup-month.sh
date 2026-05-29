#!/usr/bin/env bash
# Generate $JOURNAL_ROOT/monthly/YYYY-MM.md from sessions in that month.
# Usage: rollup-month.sh [YYYY-MM]   (defaults to current month)
set -euo pipefail

JOURNAL_ROOT="${JOURNAL_ROOT:-${HOME}/.claude/journal}"
INDEX_FILE="${JOURNAL_ROOT}/index.jsonl"
LOG_FILE="${JOURNAL_ROOT}/record.log"

TARGET="${1:-$(date +%Y-%m)}"
YEAR="${TARGET%-*}"
MONTH="${TARGET#*-}"
OUT="${JOURNAL_ROOT}/monthly/${TARGET}.md"
mkdir -p "${JOURNAL_ROOT}/monthly"

[ -f "${INDEX_FILE}" ] || { echo "no index file at ${INDEX_FILE}" >&2; exit 1; }

ENTRIES=$(jq -c --arg ym "${TARGET}" 'select(.date | startswith($ym))' "${INDEX_FILE}" 2>/dev/null || true)
COUNT=$(printf '%s\n' "${ENTRIES}" | grep -c '^{' || true)

if [ "${COUNT}" -eq 0 ]; then
  echo "no entries for ${TARGET}" >&2
  exit 0
fi

SESSIONS_DIR="${JOURNAL_ROOT}/sessions/${YEAR}/${MONTH}"
RICH=""
if [ -d "${SESSIONS_DIR}" ]; then
  RICH=$(find "${SESSIONS_DIR}" -name '*.md' -type f -exec cat {} + 2>/dev/null | head -c 80000)
fi

PROMPT=$(cat <<EOF
You are writing a monthly accomplishments report for a personal work journal.
Month: ${TARGET}
Total sessions: ${COUNT}

Index entries (one JSON per session, ordered by date):
${ENTRIES}

Rich session details (concatenated session markdown files):
${RICH}

Produce a clean, scannable markdown report. About one page. Sections:

# ${TARGET} — Accomplishments

## Highlights
3-6 bullets. The biggest things shipped or solved this month. Concrete outcomes only — not "worked on X" but "shipped X" / "fixed Y" / "investigated Z and found W".

## By project
Group sessions by repo. For each repo, 2-4 bullets summarizing what happened there.

## Themes
2-4 bullets describing patterns across sessions (e.g. "heavy oncall load week 2", "kicked off migration to X").

## Open threads
Any open_threads from session entries that still look unresolved.

## Stats
- Sessions: ${COUNT}
- Repos touched: (count distinct repos from index)
- Commits: (sum of commits field)

Be terse. Skip filler. Reflect ONLY what is in the data above.
EOF
)

if [ -n "${JOURNAL_SUMMARIZER_CMD:-}" ]; then
  SUMMARIZER_CMD="${JOURNAL_SUMMARIZER_CMD}"
else
  CLAUDE_BIN="${HOME}/.toolbox/bin/claude"
  [ -x "${CLAUDE_BIN}" ] || CLAUDE_BIN="$(command -v claude 2>/dev/null || echo claude)"
  SUMMARIZER_CMD="${CLAUDE_BIN} -p --bare --model opus --output-format text"
fi

REPORT=$(printf '%s' "${PROMPT}" | bash -c "${SUMMARIZER_CMD}" 2>>"${LOG_FILE}" || echo "")

if [ -z "${REPORT}" ]; then
  echo "rollup generation failed for ${TARGET}" >&2
  exit 1
fi

printf '%s\n' "${REPORT}" >"${OUT}"
echo "wrote ${OUT}"
