# Full setup

The README covers step 0 (install the plugin), which is enough to get the
MCP bridges, skills, and Gate hook registered. Everything below is the
remaining manual configuration — see
[Architecture → Repo layout](ARCHITECTURE.md#repo-layout) for why this
part can't be plugin-automated.

`templates/CLAUDE.md`'s "Model pins" table is the source of truth for
every model value.

### 0b. Make the plugin skills visible to Antigravity (optional)

Installing the plugin makes `delegation-pipeline`/`learning-curator`
available to **Claude Code only** — Claude Code's plugin cache
(`~/.claude/plugins/cache/…`) isn't a path Antigravity or Codex know to
read. Antigravity has its own global discovery path, `~/.agents/skills/`
(the user-level counterpart of the project-level `.agents/skills` — see
[Architecture → Centralizing memory](ARCHITECTURE.md#centralizing-memory-across-harnesses)),
so symlinking the plugin's cached skill folders into it makes both
harnesses trigger the same two skills:

```bash
AGENT_BRIDGES_SRC="$(ls -td ~/.claude/plugins/cache/agent-bridges/agent-bridges/*/ 2>/dev/null | head -1)"
if [ -z "$AGENT_BRIDGES_SRC" ]; then
  echo "agent-bridges plugin not found in cache — install it first (README, Setup step 0)" >&2
else
  mkdir -p ~/.agents/skills
  ln -sfn "${AGENT_BRIDGES_SRC}skills/delegation-pipeline" ~/.agents/skills/delegation-pipeline
  ln -sfn "${AGENT_BRIDGES_SRC}skills/learning-curator" ~/.agents/skills/learning-curator
  echo "Linked $(readlink ~/.agents/skills/delegation-pipeline)"
fi
```

The cache path is **versioned** (`.../agent-bridges/agent-bridges/<version>/…`)
and the old version directory is swept away ~14 days after an update, so
this symlink goes stale on every plugin update — re-run this snippet after
`/plugin install agent-bridges@agent-bridges --update` (the `ln -sfn`
commands are safe to re-run any time; they just repoint the link).

**Codex gets nothing from this and there's no command that changes that.**
Codex has no per-task skill loader at all — no directory it discovers
skills from, plugin or otherwise (see `skills/delegation-pipeline/SKILL.md`,
"Shared skills"). Both skills are orchestrator-facing by design and were
never pasted into a Codex prompt even before the plugin conversion, so
nothing here is a regression for Codex specifically — but don't expect a
symlink to fix it, because there's no discovery mechanism on the other end
to point at.

### 0c. Upgrading from an install that predates `openai/codex-plugin-cc`

If you installed `agent-bridges` before it dropped its own Codex MCP
server (versions before 0.2.0 — see `docs/ARCHITECTURE.md`, "Why a
plugin, not an MCP server"), updating the plugin alone is **not**
enough. Three things are cached outside the plugin and none of them
self-heal on update:

1. **`~/.claude.json` still lists the old `codex-qa`/`codex-security`
   MCP servers for this project**, and they show up as **failed** at
   session start. Claude Code caches each project's *resolved* MCP
   servers into `~/.claude.json` the first time it reads `.mcp.json`;
   it does not prune entries that later disappear from `.mcp.json`. The
   commands those entries ran (`codex --profile qa mcp-server` /
   `codex --profile security mcp-server`) no longer exist in current
   Codex CLI versions, hence the failures. Fix: open `~/.claude.json`,
   find this project's entry, delete the `codex-qa` and `codex-security`
   keys under its `mcpServers` (leave `antigravity`), save, and restart
   Claude Code. (`claude mcp remove codex-qa` / `claude mcp remove
   codex-security` from the project root does the same thing without
   hand-editing JSON.)
2. **`~/.agents/skills/delegation-pipeline/SKILL.md` is stale and still
   describes the two MCP servers.** That symlink (step 0b) points into
   a *versioned* plugin cache directory
   (`~/.claude/plugins/cache/agent-bridges/agent-bridges/<old-version>/…`);
   updating the plugin adds a new version directory but doesn't repoint
   symlinks into it, and the old one isn't swept for ~14 days. Re-run
   the step 0b snippet after every update — it's idempotent (`ln -sfn`
   just repoints the link to whatever version is newest).
3. **Your project/global `CLAUDE.md` still names `codex-qa`/
   `codex-security`.** You copied `templates/CLAUDE.md` into your own
   `CLAUDE.md` at some point (step 4 below) — that's *your* copy, and
   the plugin update doesn't touch it. The "Roles" table, "Model pins"
   table, and Security-pin row now describe the `codex:codex-rescue`
   subagent instead, distinguished by `--model`/framing rather than by
   separate servers. Re-diff your `CLAUDE.md` against the current
   `templates/CLAUDE.md` and re-merge those sections.

### Remaining steps (still manual)

1. Prerequisites: `agy` CLI installed and authenticated (1.1.15 or newer —
   a hard floor for the `agy-mcp` bridge below it, not a recommendation),
   and the `agy-mcp` binary itself installed separately (it is not bundled
   with this plugin): `brew install tphakala/tap/agy-mcp` or
   `go install github.com/tphakala/agy-mcp/v2@latest`. Verify with
   `agy-mcp --help` (there is no `-v`/`--version` flag — the binary
   printing its own usage on an unrecognized flag is expected, not a
   sign it's missing). **Three-bridge mode only:** `codex` CLI installed
   and authenticated (`codex login`), Node.js 18.18+.
2. **Three-bridge mode only** — install the
   [`openai/codex-plugin-cc`](https://github.com/openai/codex-plugin-cc)
   plugin (separate from `agent-bridges` — it's what actually provides
   Codex QA/Security, this project no longer runs its own Codex MCP
   server):
   ```
   /plugin marketplace add openai/codex-plugin-cc
   ```
   ```
   /plugin install codex@openai-codex
   ```
   ```
   /reload-plugins
   ```
   ```
   /codex:setup
   ```
   There is no separate QA/Security profile to configure — the QA pin
   (`5.6 Terra`) and Security pin (`5.6 Sol`) from `CLAUDE.md`'s "Model
   pins" table are passed as `--model` on each individual
   `codex:codex-rescue` call (see `skills/delegation-pipeline/SKILL.md`),
   not set once via `~/.codex/config.toml`.
3. Verify: `claude mcp list` shows `antigravity` **Connected**. **Three-
   bridge mode only:** also confirm `/agents` lists the `codex:codex-rescue`
   subagent and `/codex:setup` reports Codex installed and authenticated.
4. Copy `templates/CLAUDE.md` into the target project's `CLAUDE.md` (or
   merge it in) — keep the `@AGENTS.md` import line at the top.
   **Two-bridge mode:** also append `CLAUDE-two-bridge-overlay.md`.
5. Copy `templates/AGENTS.md` into the project's root `AGENTS.md` (or
   merge it in).
6. **(Optional, project-owned skills only)** If this project has its own
   custom skills beyond `delegation-pipeline`/`learning-curator` (which the
   plugin already provides), create/move them into `skills/<name>/SKILL.md`
   at the project root, then symlink:
   `ln -s skills .claude/skills && ln -s skills .agents/skills`. Keep the
   "Available skills" list in `AGENTS.md` in sync.
7. **(Team sharing)** Commit `templates/AGENTS.md`/`CLAUDE.md` (merged into
   your project's own copies) so the whole team gets the pipeline just by
   installing the plugin — no per-teammate MCP/hook setup needed.
8. **Enable the learning curator (optional, recommended) — machine-side
   only**, once per machine: create `~/.agents/skills/` and
   `~/.agent-bridges/learning/` (with `skills-pending/` and an empty
   `skills-log.md`) — nothing here is project-specific or ever committed.
   Symlink `~/.agents/skills/<name>` into `~/.claude/skills/<name>` per
   skill so Claude Code discovers it too. (Project-side: create an empty,
   committed `.agent-bridges/learning/log.md`, and gitignore
   `.agent-bridges/learning/pending/` only.)

## Operational notes

- **Cold start:** Antigravity's first call takes ~40–50s; later calls in
  the same session are faster.
- **Delegation calls don't block.** `agy_run` returns a `job_id`
  immediately; you're woken via the plugin's `PostToolUse` hook when the
  job lands (see `docs/MIGRATION.md`, "Completion wake"). There is no
  timeout ceiling to race against the way there was under `agy-bridge` —
  a slow job is just a slow job, not a hang. If a job runs long, the wake
  still fires (reporting "still running") rather than being lost silently.
- **Output shape:** there is no fixed truncation cap — use `json_schema`
  on any Antigravity call whose output you'll parse or spot-check
  structurally (a requirement matrix, a findings table), rather than
  relying on prose framing alone.
- **(Three-bridge)** QA and Security calls both go through the same
  `codex:codex-rescue` subagent — a `/codex:status`/`/codex:result` task id
  from one call is meaningless for the other; always pass `--fresh` on a
  QA/Security call rather than letting it offer to resume the other role's
  thread.
- **(Two-bridge)** QA and Security lenses now run as backgrounded,
  concurrent `agy_run` jobs (each its own `job_id`) — you don't wait for
  one before starting the other, same as three-bridge mode's two
  `codex:codex-rescue` calls. They still share one `agy` account/CLI with
  the Coder role — see `templates/CLAUDE-two-bridge-overlay.md`, "Why this
  is weaker."
- **Macro-delegation:** send the full plan and every touched file to
  Antigravity in one call, and the full diff plus acceptance criteria to
  QA/Security in one call each, rather than fragmenting into single-file
  delegations.

## Verifying it works

After restarting Claude Code, run `claude mcp list` — confirm `antigravity`
shows the `agy-mcp` command, not `npx ... agy-bridge` (see the pre-0.3.0
upgrade note in the README if it still shows the old command after
updating).

- **Three-bridge mode:** `antigravity` connected, and `codex:codex-rescue`
  runnable (see step 3 above). An Antigravity `agy_run` call returns a
  `job_id`; a QA or Security `codex:codex-rescue` call returns a task id
  you poll via `/codex:status`/`/codex:result` — confirm a QA call and a
  Security call on the same diff come back as independent ids with
  different findings (see `docs/ARCHITECTURE.md`, "Why a plugin, not an
  MCP server").
- **Two-bridge mode:** `antigravity` connected (no Codex entries). Run one
  `agy_run` call framed as QA (with the QA lens pin) and one framed as
  Security (with the Security lens pin) — confirm they return different
  `job_id` values and don't need to wait on each other.
- **Gate hook (plugin step 0):** ask Claude Code to `Edit`/`Write` an
  application-code file directly. A permission prompt quoting the Gate
  rule should appear first. If not, confirm the plugin is enabled for this
  project (`/plugin`) or open `/hooks` once and restart.
- **Learning-curator storage (step 8):** after a MEMORY proposal, `git
  status` should **not** show `.agent-bridges/learning/pending/` as
  untracked, but should show a normal diff for a promoted/auto-applied
  change to `AGENTS.md`/`log.md`. After a CREATE_SKILL, confirm the skill
  exists at `~/.agents/skills/<name>/SKILL.md`, that
  `~/.claude/skills/<name>` symlinks to it, and that `git status` inside
  the project shows nothing related to it.
