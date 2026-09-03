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

### Remaining steps (still manual)

1. Prerequisites: `agy` CLI installed and authenticated; Node + npx.
   **Three-bridge mode only:** `codex` CLI installed and authenticated.
2. **Three-bridge mode only** — pin QA/Security to models via Codex
   profiles in `~/.codex/config.toml`:
   ```toml
   [profiles.qa]
   model = "5.6 Terra"

   [profiles.security]
   model = "5.6 Sol"
   ```
3. Verify: `claude mcp list` shows `antigravity` **Connected**
   (two-bridge), or all three of `antigravity`, `codex-qa`,
   `codex-security` **Connected** (three-bridge).
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
- **Timeouts:** override Antigravity's per-tool budgets via
  `AGY_TIMEOUT_<TOOL_NAME>` (or `AGY_TIMEOUT` globally). Keep the MCP
  client timeout ≥ that budget.
- **Output cap:** Antigravity truncates at `AGY_MAX_OUTPUT_CHARS` (default
  50,000) — ask for dense, structured output (e.g. a pass/fail table).
- **(Three-bridge)** `codex-qa` and `codex-security` are independent
  processes — a `threadId` from one is meaningless on the other.
- **(Two-bridge)** QA and Security lenses run sequentially, not in
  parallel — both are `adversarial_review` calls on the same server.
- **Macro-delegation:** send the full plan and every touched file to
  Antigravity in one call, and the full diff plus acceptance criteria to
  QA/Security in one call each, rather than fragmenting into single-file
  delegations.

## Verifying it works

After restarting Claude Code, run `claude mcp list`.

- **Three-bridge mode:** all three bridges connected. An Antigravity call
  returns a `session_id`; `codex-qa`/`codex-security` each return their
  own `threadId` — confirm they differ even for the same diff.
- **Two-bridge mode:** `antigravity` connected (no Codex entries). Run one
  `adversarial_review` call framed as QA and one framed as Security —
  confirm they return different `session_id` values.
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
