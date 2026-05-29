---
description: Standup summary — defaults to previous workday (Mon includes Fri+weekend); accepts a date arg
argument-hint: "[YYYY-MM-DD]"
---

The journal data lives at `${JOURNAL_ROOT:-~/.claude/journal}` (read the `JOURNAL_ROOT` env var; if unset, default to `~/.claude/journal`).

## Determine target date(s)

If `$ARGUMENTS` is non-empty:
- `today` → today's date (`date +%Y-%m-%d`).
- `yesterday` → yesterday (`date -v-1d +%Y-%m-%d`).
- `YYYY-MM-DD` → that exact date.

Otherwise, compute the default range via Bash:
- Get today's weekday: `date +%u` (1=Mon … 7=Sun).
- If today is **Monday** (`1`): include Friday, Saturday, and Sunday (the previous Fri + weekend).
- If today is **Sunday** (`7`): include Friday and Saturday.
- Otherwise: include just yesterday.

Compute the actual date strings with `date -v-Nd +%Y-%m-%d` (BSD/macOS).

## Gather entries

Read `<JOURNAL_ROOT>/index.jsonl` and select every entry whose `date` field matches any target date. For each match, read the session markdown at `~/<path>` (the `path` field, relative to `$HOME`).

## Cluster sessions into topics

Sessions in a single day often span the same task across multiple short conversations. Do NOT emit one bullet per session — cluster them.

Clustering rules (in order):
1. Two sessions belong to the same topic if their tags overlap meaningfully OR their summaries / "what got done" describe the same artifact, bug, feature, or investigation.
2. `repo` is a hint, not the primary key. Empty-repo sessions still cluster with each other and with same-repo sessions when the topic matches.
3. Each topic gets ONE bullet. Synthesize the cumulative outcome across all sessions in the cluster — what was actually achieved by the end, not a play-by-play.
4. Order topics by importance (biggest concrete shipped/fixed thing first), not chronology.
5. A standalone session with a unique topic gets its own bullet — don't force-cluster.

## Filter open threads

Walk sessions chronologically. For each `Open threads` item from an earlier session, drop it if a later session's "What got done" or summary clearly resolves or supersedes it. Then dedupe near-duplicates across the remaining items. If nothing remains, omit the section entirely (don't print an empty header).

## Produce the summary

**Worked on** *(label with the date(s) covered, e.g. "Fri 2026-05-22 – Sun 2026-05-24" or "today 2026-05-29")*
- One bullet per topic cluster. Lead with the concrete outcome (`shipped`, `fixed`, `diagnosed`, `investigated`). Mention the repo in parens only if it's not obvious from the topic.

**Open threads** *(omit section if empty after filtering)*
- One bullet per unresolved item.

**Blockers** *(omit if empty)*
- Anything explicitly flagged as blocked.

Keep it under 12 lines total. No filler. If no entries match, say `No journal entries for <date-or-range>.`
