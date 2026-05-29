---
description: Query the journal — usage /journal [day|week|month|year|<keyword>|YYYY-MM-DD]
argument-hint: "[day|week|month|year|<keyword>|YYYY-MM-DD]"
---

User argument: $ARGUMENTS

Query the work journal. The journal data lives at `${JOURNAL_ROOT:-~/.claude/journal}` (read the `JOURNAL_ROOT` env var; if unset, default to `~/.claude/journal`).

Routing rules:
- No argument or `day` → entries with today's date in `index.jsonl`
- `week` → entries from the last 7 days
- `month` → entries with date starting with current YYYY-MM
- `year` → entries with date starting with current YYYY
- `YYYY-MM-DD` → entries for that exact date
- `YYYY-MM` → entries for that month (also check `monthly/<arg>.md` first if it exists)
- Anything else → treat as a keyword. Grep `index.jsonl` for the keyword in `summary`, `tags`, `repo`, or `branch` (case-insensitive).

For matched entries, summarize:
1. A quick count and date range
2. Group by repo
3. For each session, one line: `<date> <time> [<repo>] — <summary>`
4. If fewer than 5 matches, also load each session's markdown file (the `path` field, joined to `$HOME`) and include "What got done" bullets inline.

If a monthly rollup file exists for the queried month, read and present it directly instead of regenerating.

Be terse. No filler. If no matches, say so.
