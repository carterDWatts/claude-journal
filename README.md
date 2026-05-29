# claude-journal

Auto-capture coding-assistant sessions to a personal work journal. Query via slash commands.

When you end a session, a hook captures the transcript, summarizes it with a headless LLM call, and writes a structured markdown entry plus an index line. Slash commands let you query the log, generate standup summaries, and produce monthly accomplishments rollups.

## What it does

- **Captures** every non-trivial session as a markdown file under `<JOURNAL_ROOT>/sessions/YYYY/MM/YYYY-MM-DD/<session-id>.md`
- **Indexes** each session as one line in `<JOURNAL_ROOT>/index.jsonl` (date, time, repo, summary, tags, path)
- **Queries** via three slash commands:
  - `/journal [day|week|month|year|YYYY-MM-DD|<keyword>]` — raw query
  - `/standup [YYYY-MM-DD]` — daily standup-ready summary (defaults to previous workday)
  - `/accomplishments [YYYY-MM|YYYY|Qn]` — performance-doc-ready rollup
- **Rolls up** months into a single page at `<JOURNAL_ROOT>/monthly/YYYY-MM.md`

## Layout

```
core/                       # tool-agnostic recorder + rollup. Source of truth.
adapters/
  claude/                   # Claude Code plugin
    .claude-plugin/
      plugin.json
    hooks/hooks.json        # SessionStart bootstrap, SessionEnd recorder
    commands/               # /journal, /standup, /accomplishments
    scripts/                # adapter shims
    core/                   # synced from /core via bin/sync-core.sh
.claude-plugin/
  marketplace.json          # install via Claude Code from this repo URL
bin/
  sync-core.sh              # copy /core into each adapter (run after editing core)
```

## Install (Claude Code)

```
/plugin marketplace add wattsdca/claude-journal
/plugin install claude-journal@claude-journal
```

The journal data lives at `~/.claude/journal/` by default. To relocate, set `JOURNAL_ROOT` in your shell environment before launching Claude Code.

## Configuration

Environment variables (all optional):

| Variable | Default | Purpose |
|---|---|---|
| `JOURNAL_ROOT` | `~/.claude/journal` | Where the index, sessions, and rollups live |
| `JOURNAL_SUMMARIZER_CMD` | `claude -p --bare --model opus --output-format text` | Headless command that consumes a prompt on stdin and returns JSON on stdout |

## Adapter contract

The core recorder reads a normalized JSON payload on stdin:

```json
{
  "session_id":      "<unique session id>",
  "transcript_path": "<jsonl transcript file>",
  "cwd":             "<working dir>",
  "end_reason":      "<string>"
}
```

Adapters for other tools (Codex, Kiro, etc.) just need to translate that tool's session-end signal into this shape and pipe it to `core/record-session.sh`.

The transcript file must be JSONL where each line has `type` (`user` or `assistant`) and `message.content` (string or array of `{type:"text",text}`). This matches Claude Code's transcript format; adapters for other formats need a transformer.

## Development

After editing anything under `core/`, run:

```
bin/sync-core.sh
```

This copies `core/` into each adapter's bundled `core/` so the plugin is self-contained (Claude Code plugins can't reference files outside their own directory).
