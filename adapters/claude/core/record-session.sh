#!/usr/bin/env bash
# Tool-agnostic session recorder for the journal system.
#
# Reads a normalized session-end payload on stdin:
#   {
#     "session_id":      "<unique session id>",
#     "transcript_path": "<jsonl transcript file>",   # required
#     "cwd":             "<working dir>",             # optional
#     "end_reason":      "<string>"                   # optional
#   }
#
# Writes:
#   $JOURNAL_ROOT/sessions/YYYY/MM/YYYY-MM-DD/<session_id>.md
#   $JOURNAL_ROOT/index.jsonl  (one JSON line appended)
#
# Two-phase: front-end stashes payload + double-forks a detached worker so
# the slow summarization survives the parent harness's session-end cleanup.
set -euo pipefail

JOURNAL_ROOT="${JOURNAL_ROOT:-${HOME}/.claude/journal}"
INDEX_FILE="${JOURNAL_ROOT}/index.jsonl"
LOG_FILE="${JOURNAL_ROOT}/record.log"

mkdir -p "${JOURNAL_ROOT}"

log() { printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >>"${LOG_FILE}"; }

# --- Phase 1: front-end. Read stdin, stash payload, fork worker, exit fast.
if [ -z "${JOURNAL_WORKER:-}" ]; then
  PAYLOAD=$(cat)
  log "hook fired (pid=$$, ${#PAYLOAD} bytes)"
  [ -z "${PAYLOAD}" ] && { log "empty payload, skipping"; exit 0; }

  printf '%s' "${PAYLOAD}" >"${JOURNAL_ROOT}/last-payload.json"
  PAYLOAD_FILE=$(mktemp "${JOURNAL_ROOT}/.pending.XXXXXX")
  printf '%s' "${PAYLOAD}" >"${PAYLOAD_FILE}"

  (
    JOURNAL_WORKER=1 JOURNAL_PAYLOAD_FILE="${PAYLOAD_FILE}" \
      nohup bash "$0" </dev/null >>"${LOG_FILE}" 2>&1 &
    disown 2>/dev/null || true
  )
  log "worker forked"
  exit 0
fi

# --- Phase 2: worker. Survives parent exit; does the slow work.
trap 'rc=$?; log "EXIT rc=${rc} line=${LINENO} cmd=${BASH_COMMAND}"' EXIT

PAYLOAD=$(cat "${JOURNAL_PAYLOAD_FILE}")
rm -f "${JOURNAL_PAYLOAD_FILE}"
log "worker started (pid=$$, ${#PAYLOAD} bytes)"

SESSION_ID=$(printf '%s' "${PAYLOAD}" | jq -r '.session_id // empty')
TRANSCRIPT=$(printf '%s' "${PAYLOAD}" | jq -r '.transcript_path // empty')
CWD=$(printf '%s' "${PAYLOAD}" | jq -r '.cwd // empty')
REASON=$(printf '%s' "${PAYLOAD}" | jq -r '.end_reason // .reason // "unknown"')

[ -z "${SESSION_ID}" ] && { log "no session_id, skipping"; exit 0; }

# Wait up to 5s for the transcript to appear (handles end-before-flush race)
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [ -f "${TRANSCRIPT}" ] && break
  sleep 0.5
done
[ ! -f "${TRANSCRIPT}" ] && { log "transcript not found after wait: ${TRANSCRIPT}"; exit 0; }

# Skip trivial sessions: no user messages
USER_MSG_COUNT=$(jq -s '[.[] | select(.type == "user")] | length' "${TRANSCRIPT}" 2>/dev/null || echo 0)
if [ "${USER_MSG_COUNT}" -lt 1 ]; then
  log "skipping ${SESSION_ID}: no user messages"
  exit 0
fi

DATE=$(date +%Y-%m-%d)
TIME=$(date +%H:%M)
YEAR=$(date +%Y)
MONTH=$(date +%m)

SESSION_DIR="${JOURNAL_ROOT}/sessions/${YEAR}/${MONTH}/${DATE}"
mkdir -p "${SESSION_DIR}"
SESSION_FILE="${SESSION_DIR}/${SESSION_ID}.md"

# Idempotency
[ -f "${SESSION_FILE}" ] && { log "already recorded ${SESSION_ID}"; exit 0; }

# --- Hard data: git facts (if cwd is a git repo) ---
REPO=""
BRANCH=""
COMMIT_LOG=""
DIFF_STAT=""
if [ -n "${CWD}" ] && git -C "${CWD}" rev-parse --git-dir >/dev/null 2>&1; then
  REPO=$(basename "$(git -C "${CWD}" rev-parse --show-toplevel)")
  BRANCH=$(git -C "${CWD}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  AUTHOR=$(git -C "${CWD}" config user.email 2>/dev/null || echo "")
  if [ -n "${AUTHOR}" ]; then
    COMMIT_LOG=$(git -C "${CWD}" log --author="${AUTHOR}" --since="24 hours ago" --pretty=format:'- %h: %s' 2>/dev/null || echo "")
  fi
  DIFF_STAT=$(git -C "${CWD}" diff HEAD~5..HEAD --shortstat 2>/dev/null || echo "")
fi

# --- Extract first user prompt (skip system reminders) ---
FIRST_PROMPT=$(jq -r '
  select(.type == "user" and (.message.content // "" | tostring | test("system-reminder") | not))
  | .message.content
  | if type == "array" then map(select(.type == "text") | .text) | join(" ") else tostring end
' "${TRANSCRIPT}" 2>/dev/null | head -c 500 | head -1 || echo "")

# --- Compact transcript snippet for the summarizer ---
TRANSCRIPT_SNIPPET=$(jq -r '
  select(.type == "user" or .type == "assistant")
  | select(.message.content != null)
  | "\(.type | ascii_upcase): " + (
      .message.content
      | if type == "array" then map(select(.type == "text") | .text) | join(" ") else tostring end
    )
' "${TRANSCRIPT}" 2>/dev/null | head -c 40000 || echo "")

# --- Generate summary via configurable summarizer ---
SUMMARY_PROMPT=$(cat <<EOF
You are summarizing a coding-assistant session for a personal work journal.

Context (do not echo these back — they are appended to the output by other code):
- Repo: ${REPO:-none}
- Branch: ${BRANCH:-none}
- Commits in last 24h:
${COMMIT_LOG:-(none)}

Transcript excerpt:
${TRANSCRIPT_SNIPPET}

Respond with ONE JSON object and nothing else. No markdown fences, no prose, no metadata block, no trailing text. Your entire response must start with { and end with }.

Schema:
{
  "summary": "one short sentence — what got done",
  "tags": ["3-6 lowercase keywords"],
  "what_got_done": ["3-6 bullet points, concrete outcomes"],
  "why_it_mattered": "1-2 sentences on motivation/context, or empty string",
  "open_threads": ["unfinished items, follow-ups, blockers — empty array if none"]
}

Be terse. Skip filler. Reflect ONLY what actually happened in the transcript.
EOF
)

# Summarizer command is configurable. Default: claude -p --bare opus.
# Override by exporting JOURNAL_SUMMARIZER_CMD as a single string passed to `bash -c`.
if [ -n "${JOURNAL_SUMMARIZER_CMD:-}" ]; then
  SUMMARIZER_CMD="${JOURNAL_SUMMARIZER_CMD}"
else
  CLAUDE_BIN="${HOME}/.toolbox/bin/claude"
  [ -x "${CLAUDE_BIN}" ] || CLAUDE_BIN="$(command -v claude 2>/dev/null || echo claude)"
  SUMMARIZER_CMD="${CLAUDE_BIN} -p --bare --model opus --output-format text"
fi

STDERR_FILE="${JOURNAL_ROOT}/.stderr-${SESSION_ID}.txt"
RAW_OUT=$(printf '%s' "${SUMMARY_PROMPT}" \
  | bash -c "${SUMMARIZER_CMD}" 2>"${STDERR_FILE}")
SUMMARIZER_RC=$?
log "summarizer returned rc=${SUMMARIZER_RC}, ${#RAW_OUT} stdout bytes, $(wc -c <"${STDERR_FILE}" | tr -d ' ') stderr bytes"

# Extract first balanced JSON object from output. Handles fences, raw, or
# JSON with surrounding prose.
SUMMARY_JSON=$(printf '%s' "${RAW_OUT}" | python3 -c '
import sys
s = sys.stdin.read()
i = s.find("{")
if i < 0:
    sys.exit(0)
depth = 0
in_str = False
esc = False
for j in range(i, len(s)):
    c = s[j]
    if in_str:
        if esc:
            esc = False
        elif c == "\\":
            esc = True
        elif c == "\"":
            in_str = False
    else:
        if c == "\"":
            in_str = True
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                sys.stdout.write(s[i:j+1])
                sys.exit(0)
' 2>/dev/null || true)

# Fallback if summarizer failed or returned non-JSON
if ! printf '%s' "${SUMMARY_JSON}" | jq -e . >/dev/null 2>&1; then
  DUMP_OUT="${JOURNAL_ROOT}/.failed-${SESSION_ID}.stdout.txt"
  printf '%s' "${RAW_OUT}" >"${DUMP_OUT}"
  log "summary generation failed for ${SESSION_ID}, using fallback (rc=${SUMMARIZER_RC}, stdout=${DUMP_OUT}, stderr=${STDERR_FILE})"
  SUMMARY_JSON=$(jq -n \
    --arg p "${FIRST_PROMPT}" \
    '{summary: ($p | .[0:140]), tags: [], what_got_done: [], why_it_mattered: "", open_threads: []}')
else
  rm -f "${STDERR_FILE}"
fi

SUMMARY=$(printf '%s' "${SUMMARY_JSON}" | jq -r '.summary // ""')
TAGS_JSON=$(printf '%s' "${SUMMARY_JSON}" | jq -c '.tags // []')
WHAT_DONE=$(printf '%s' "${SUMMARY_JSON}" | jq -r '.what_got_done // [] | .[] | "- " + .')
WHY=$(printf '%s' "${SUMMARY_JSON}" | jq -r '.why_it_mattered // ""')
OPEN_THREADS=$(printf '%s' "${SUMMARY_JSON}" | jq -r '.open_threads // [] | .[] | "- " + .')

COMMIT_COUNT=0
[ -n "${COMMIT_LOG}" ] && COMMIT_COUNT=$(printf '%s\n' "${COMMIT_LOG}" | grep -c '^-' || true)

# --- Layer 2: rich markdown ---
{
  echo "# ${SUMMARY:-Session ${SESSION_ID}}"
  echo
  echo "**Date:** ${DATE} ${TIME}  "
  echo "**Repo:** ${REPO:-(none)}  "
  echo "**Branch:** ${BRANCH:-(none)}  "
  echo "**Session:** ${SESSION_ID}  "
  echo "**End reason:** ${REASON}"
  echo
  if [ -n "${WHAT_DONE}" ]; then
    echo "## What got done"
    echo "${WHAT_DONE}"
    echo
  fi
  if [ -n "${WHY}" ] && [ "${WHY}" != "null" ]; then
    echo "## Why it mattered"
    echo "${WHY}"
    echo
  fi
  if [ -n "${COMMIT_LOG}" ]; then
    echo "## Commits"
    echo "${COMMIT_LOG}"
    echo
  fi
  if [ -n "${OPEN_THREADS}" ]; then
    echo "## Open threads"
    echo "${OPEN_THREADS}"
    echo
  fi
  if [ -n "${DIFF_STAT}" ]; then
    echo "## Diff"
    echo "${DIFF_STAT}"
    echo
  fi
  if [ -n "${FIRST_PROMPT}" ]; then
    echo "## First prompt"
    echo "> ${FIRST_PROMPT}"
  fi
} >"${SESSION_FILE}"

# --- Layer 1: append to index ---
INDEX_LINE=$(jq -nc \
  --arg date "${DATE}" \
  --arg time "${TIME}" \
  --arg session "${SESSION_ID}" \
  --arg repo "${REPO}" \
  --arg branch "${BRANCH}" \
  --arg summary "${SUMMARY}" \
  --argjson tags "${TAGS_JSON}" \
  --argjson commits "${COMMIT_COUNT}" \
  --arg path "${SESSION_FILE#${HOME}/}" \
  '{date:$date, time:$time, session:$session, repo:$repo, branch:$branch, summary:$summary, tags:$tags, commits:$commits, path:$path}')

printf '%s\n' "${INDEX_LINE}" >>"${INDEX_FILE}"

log "recorded ${SESSION_ID} (${REPO:-no-repo}): ${SUMMARY}"
exit 0
