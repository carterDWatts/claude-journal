---
description: Standup summary — defaults to previous workday (Mon includes Fri+weekend); accepts a date arg
argument-hint: "[YYYY-MM-DD]"
---

The journal data lives at `${JOURNAL_ROOT:-~/.claude/journal}` (read the `JOURNAL_ROOT` env var; if unset, default to `~/.claude/journal`).

## Determine target date(s)

If `$ARGUMENTS` is non-empty, treat it as a single `YYYY-MM-DD` and use just that date. Otherwise, compute the default range via Bash:

- Get today's weekday: `date +%u` (1=Mon … 7=Sun).
- If today is **Monday** (`1`): include Friday, Saturday, and Sunday (the previous Fri + weekend).
- If today is **Sunday** (`7`): include Friday and Saturday.
- Otherwise: include just yesterday.

Compute the actual date strings with `date -v-Nd +%Y-%m-%d` (BSD/macOS), where N is the number of days back. Example for Monday:
```
date -v-3d +%Y-%m-%d   # Friday
date -v-2d +%Y-%m-%d   # Saturday
date -v-1d +%Y-%m-%d   # Sunday
```

## Gather entries

Read `<JOURNAL_ROOT>/index.jsonl` and select every entry whose `date` field matches any target date. For each match, read the session markdown at `~/<path>` (the `path` field, relative to `$HOME`).

## Produce the summary

**Worked on** *(label with the date(s) covered, e.g. "Fri 2026-05-22 – Sun 2026-05-24" or "Thu 2026-05-28")*
- Group by `repo`. Under each repo, 1-3 bullets of concrete outcomes (pull from the "What got done" sections, not raw summaries).

**Open threads**
- Any unresolved items from "Open threads" sections.

**Blockers**
- Anything explicitly flagged as blocked.

Keep it under 15 lines total. No filler. If no entries match, say `No journal entries for <date-or-range>.`
