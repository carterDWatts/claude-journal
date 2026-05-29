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

### Prerequisites

- `bash`, `jq`, `python3` on `PATH` (all preinstalled on macOS / standard Linux)
- A working headless LLM call. By default the plugin shells out to `claude -p --bare --model opus --output-format text`; set `JOURNAL_SUMMARIZER_CMD` to swap in any other command that reads a prompt on stdin and writes a response to stdout.

### From this repo

In a Claude Code session:

```
/plugin marketplace add carterDWatts/claude-journal
/plugin install claude-journal@claude-journal
```

Or pin to a specific commit / branch:

```
/plugin marketplace add https://github.com/carterDWatts/claude-journal.git@<ref>
```

### Local development install

To install from a local clone (useful while iterating):

```
git clone https://github.com/carterDWatts/claude-journal.git ~/dev/claude-journal
```

Then in Claude Code:

```
/plugin marketplace add ~/dev/claude-journal
/plugin install claude-journal@claude-journal
```

### Verify

Open a fresh Claude Code session and confirm:

- `/plugins` lists `claude-journal` as enabled
- `/journal`, `/standup`, `/accomplishments` appear in the slash-command picker
- After ending a non-trivial session, a markdown file appears under `<JOURNAL_ROOT>/sessions/YYYY/MM/YYYY-MM-DD/`

### Where data lives

The journal data lives at `~/.claude/journal/` by default. To relocate, set `JOURNAL_ROOT` in your shell environment before launching Claude Code. The data directory is created on first session start by the plugin's `SessionStart` hook — nothing is committed to this repo.

### Uninstall

```
/plugin uninstall claude-journal
```

Your captured journal data at `<JOURNAL_ROOT>/` is preserved. Delete it manually if you want a clean slate.

## Configuration

Environment variables (all optional):

| Variable | Default | Purpose |
|---|---|---|
| `JOURNAL_ROOT` | `~/.claude/journal` | Where the index, sessions, and rollups live |
| `JOURNAL_SUMMARIZER_CMD` | `claude -p --bare --model opus --output-format text` | Headless command that consumes a prompt on stdin and returns JSON on stdout |

## Security & threat model

This plugin captures, summarizes, and persists session transcripts. A few things to be aware of before you install it on a machine that touches sensitive code or data:

### What gets written to disk

- **Full first user prompt** of every non-trivial session (truncated to ~500 bytes), in the per-session markdown file.
- **An LLM-generated summary, tags, and bullet list** derived from up to 40 KB of raw transcript text (user + assistant messages). The transcript itself is not persisted by this plugin, only the summary.
- **Git facts** (repo name, branch, your authored commits in the last 24 h, diff shortstat) for any session whose `cwd` was a git repo.

All artifacts are written to `<JOURNAL_ROOT>` (default `~/.claude/journal/`) on the local filesystem only. Nothing is sent to any remote service by this plugin. If your transcripts contain secrets, those secrets may end up in the summary — treat `<JOURNAL_ROOT>` as you would your shell history.

### Prompt injection in the summarizer

The summarizer prompt embeds raw transcript content. **Anything in a session transcript is untrusted input** and may attempt to manipulate the summary. Sources of injected content include:

- Pasted text, URLs you visited, or files you `Read` during the session
- Tool output from MCP servers, internal docs, or third-party APIs
- Prior journal summaries, if you query them and the assistant echoes them back

The plugin's mitigations:

- The summarizer runs in a separate, single-shot LLM call with no tools available.
- Output is parsed as a single balanced JSON object. Anything outside that object is discarded.
- The fallback path (when parsing fails) hard-codes empty arrays and uses your first prompt as the title — bounding the worst-case to "summary is wrong" rather than "summary contains arbitrary text."

What this **does not** prevent: a successfully-injected summary can still mislead anyone (or any future LLM) reading the journal back. If you extend the journal to post outbound (Slack, github, email), an injected summary becomes an exfiltration vector. Treat journal content as untrusted on read-back.

### Plugin sandboxing

The Claude Code adapter installs as a plugin and runs hooks on `SessionStart` (idempotent `mkdir -p`) and `SessionEnd` (capture). Plugin code lives in the Claude Code plugin cache and is governed by Claude Code's plugin permission model.

### Reporting issues

If you find a security issue, please open a GitHub issue with `[security]` in the title rather than emailing or DMing. Sensitive details can follow in a private thread once acknowledged.

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
