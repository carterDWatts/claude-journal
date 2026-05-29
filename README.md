# claude-journal

## What it does

A Claude Code plugin that auto-captures every coding session as a journal entry, then lets you query it via slash commands.

On session end, a hook reads the transcript, summarizes it with a headless `claude -p` call, and writes:
- a markdown file at `~/.claude/journal/sessions/YYYY/MM/YYYY-MM-DD/<session-id>.md`
- one indexed line in `~/.claude/journal/index.jsonl`
- a monthly rollup at `~/.claude/journal/monthly/YYYY-MM.md` (on demand)

Set `JOURNAL_ROOT` to relocate the data directory.

## Installation

In a Claude Code session:

```
/plugin marketplace add carterDWatts/claude-journal
/plugin install claude-journal@claude-journal
```

Alternatively, Local clone:

```
git clone https://github.com/carterDWatts/claude-journal.git ~/dev/claude-journal
```
```
/plugin marketplace add ~/dev/claude-journal
/plugin install claude-journal@claude-journal
```

Requires `bash`, `jq`, `python3`, and a `claude` binary on `PATH`.

### Uninstall

```
/plugin uninstall claude-journal
```

Captured journal data at `~/.claude/journal/` is preserved. Delete it manually for a clean slate.

## How to use

- `/journal [day|week|month|year|YYYY-MM-DD|<keyword>]` — query the log
- `/standup [today|yesterday|YYYY-MM-DD]` — standup-ready summary (defaults to previous workday)
- `/accomplishments [YYYY-MM|YYYY|Qn]` — performance-doc rollup
