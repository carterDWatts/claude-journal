---
description: Generate accomplishments report — usage /accomplishments [YYYY-MM|YYYY|quarter]
argument-hint: "[YYYY-MM|YYYY|Qn|quarter]"
---

User argument: $ARGUMENTS

Generate an accomplishments report from the journal. The journal data lives at `${JOURNAL_ROOT:-~/.claude/journal}` (read the `JOURNAL_ROOT` env var; if unset, default to `~/.claude/journal`).

The rollup script is at `${CLAUDE_PLUGIN_ROOT}/core/rollup-month.sh` — invoke via `bash ${CLAUDE_PLUGIN_ROOT}/core/rollup-month.sh <YYYY-MM>`.

Routing:
- `YYYY-MM` → Always run the rollup script if `<arg>` is the **current month** (it may have new sessions since last rollup). For past months, use the cached `<JOURNAL_ROOT>/monthly/<arg>.md` if it exists; otherwise generate it. Then present the file.
- `YYYY` → Find all monthly rollups for that year under `<JOURNAL_ROOT>/monthly/`. Always regenerate the **current month's** rollup. For past months, generate any that are missing AND have index entries. Then synthesize a yearly report:
  - Top accomplishments (5-8 bullets)
  - By project / theme
  - Quarterly arc (Q1-Q4 single sentence each)
  - Stats (total sessions, distinct repos, commit count)
- `Qn` or `quarter` → 3 months. If `Q1` use Jan-Mar, etc. of current year. Same approach as yearly but for those 3 months — always regenerate the current month's rollup if it falls within the quarter.
- No argument or `this month` → current month. Always regenerate before presenting.

**Rule of thumb:** any period that includes today's date must regenerate the current-month rollup before presenting, because new sessions may have landed since the last rollup.

Output should be:
- Concrete and outcome-focused ("shipped X", "fixed Y") — never "worked on" or "looked into"
- Drawn ONLY from data in the journal
- Self-review-ready: the kind of thing you'd paste into a perf doc

If there's no data for the requested period, say so.
