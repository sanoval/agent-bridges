# agent-bridges

Config and templates for a fixed-role delegation pipeline that pairs
**Claude Code** with three MCP bridges:

- **Antigravity** (`agy-bridge` MCP server, pinned to the Antigravity pin)
  plays three roles across the pipeline: **Document Analyzer**,
  **Coder/Executor**, **Release/Changelog Writer**.
- **Codex QA** (`codex-qa`, QA pin) — **QA Engineer**.
- **Codex Security** (`codex-security`, Security pin) — **Security Engineer**.
- **Claude Code** is **Planner and Code Reviewer**, on whatever model you
  pick per plan. It's the only agent with tool access, repo/session state,
  and write permission — it plans, reviews first, and has final say on
  every bridge output.

## Why

Routing everything through one model is wasteful when another provider
fits a role better. Instead of routing task-by-task, each bridge gets a
fixed job: Antigravity ingests specs, writes the code, then drafts release
notes; Codex QA always tests the diff; Codex Security always reviews it
for exploits; Claude Code always plans, reviews before either Codex role
sees a diff, and has final say — including over the docs Antigravity
drafts.

Claude Code owns verification: a delegated finding is never the sole basis
for an edit until checked (see "Parallelism, failures, and verification"
in `templates/CLAUDE.md`). Reading a large file, diffing a big repo, or
running QA/security burns context fast — often only the *answer* is
needed, not the investigation — so the bridges return results without
Claude Code carrying that context itself.

## Architecture

- **One direction only.** Claude Code calls all three bridges; none of
  them call back into Claude Code or each other. Execution authority stays
  at one point.
- **Claude Code = MCP host.** Antigravity (`antigravity` server, running
  `agy-bridge`) and two separate Codex instances — `codex-qa` and
  `codex-security` — are three independent MCP servers over JSON-RPC 2.0.
  Both Codex instances run the same binary but under different profiles
  and don't share sessions.
- **Session continuity.** Antigravity uses `follow_up` with its
  `session_id`. Each Codex instance uses its own `codex-reply` with the
  `threadId` *that instance* returned — not valid across instances.

## Repo layout

```
templates/
  AGENTS.md                     — shared project memory, read by all three harnesses
  CLAUDE.md                     — always-on core: role/pin table, the Gate, "Do NOT delegate", checkpoint discipline
  CLAUDE-two-bridge-overlay.md  — appended when no Codex subscription is available (two-bridge mode)
  review-topic-template.md      — structure for a persistent review-<topic>.md progress file
  settings.hooks.json           — PreToolUse hook enforcing the CLAUDE.md Gate mechanically
  hooks/
    agent-bridges-gate.sh       — the Gate-enforcement script referenced by settings.hooks.json
  skills/delegation-pipeline/
    SKILL.md                    — pipeline steps, payload contracts, session continuity, example prompts
    two-bridge.md                — two-bridge deltas: step 4 replacement, adversarial_review lens calls
  skills/learning-curator/
    SKILL.md                    — post-verification learning: classification, evidence scoring, hard gates
    proposal-template.md        — format for a pending learning proposal
```

## Centralizing memory across harnesses

Each harness reads its own memory file, so without coordination you get
three copies of the same facts drifting apart. Instead:

- **Codex** reads `AGENTS.md` natively.
- **Claude Code** reads `CLAUDE.md`, which opens with `@AGENTS.md` so it
  pulls in the same content.
- **Antigravity** reads `AGENTS.md` natively too (as of its CLI migration
  from Gemini CLI) — no symlink needed.

Edit `AGENTS.md` once, all three harnesses see it. Put project facts
(build/test commands, code style, layout) in `AGENTS.md`; keep
delegation/routing rules in `CLAUDE.md` below the import line.

**Skills** work the same way between Claude Code and Antigravity, since
their skill formats match almost exactly (YAML frontmatter + markdown
body). They just look in different places:

- Claude Code: `.claude/skills/<name>/SKILL.md`
- Antigravity: `.agents/skills/<name>/SKILL.md`

Keep one canonical `skills/<name>/SKILL.md` at the project root and
symlink both paths to it:
```bash
ln -s skills .claude/skills
ln -s skills .agents/skills
```
Codex has no skill loader, so it can't discover `skills/` — the
"Available skills" list in `AGENTS.md` at least tells it what exists.

Two skills ship with this repo, orchestrator-facing only (never pasted
into a Codex call): `delegation-pipeline` and `learning-curator`.

## Learning-curator storage: memory vs. skills

`learning-curator` splits what it learns across two stores:

- **MEMORY (project facts) → `AGENTS.md`** in the target project.
  Git-tracked. A mutation lands here once auto-applied (evidence score ≥5,
  every hard gate passed) or human-approved from
  `.agent-bridges/learning/pending/` (gitignored, local only). The audit
  trail `.agent-bridges/learning/log.md` **is** committed.
- **PATCH_SKILL / CREATE_SKILL (reusable procedures) → `~/.agents/skills/`**,
  never in any project repo, at any evidence score — same directory name
  Antigravity already reads for workspace skills, just resolved from
  `$HOME`. Claude Code discovers personal skills at `~/.claude/skills/`,
  so a learned skill gets a one-time symlink there (see
  `skills/learning-curator/SKILL.md`, "Making a learned skill
  discoverable"). Staging/audit trail:
  `~/.agent-bridges/learning/skills-pending/` and `skills-log.md`, both
  outside every project's git tree.

MEMORY is a fact about *this* codebase, so it's versioned with it and
team-reviewable. A skill is a reusable procedure — never something an
auto-apply should inject into a shared codebase without a PR review.
Splitting the store (not just gating the write) is what keeps that
boundary durable.

## Which mode do I need?

- **Have a Codex subscription too?** Use `templates/CLAUDE.md` as-is
  (three-bridge mode). QA and Security get their own independent
  model/process each.
- **Only Claude Code + Antigravity?** Copy `templates/CLAUDE.md` and
  append `templates/CLAUDE-two-bridge-overlay.md` (two-bridge mode). QA
  and Security fold into two separately-framed Antigravity
  `adversarial_review` passes instead of dedicated bridges — weaker
  independence (one vendor's model family for both lenses); the overlay
  explains what that costs and why your own Review step has to work
  harder.

## Setup

`templates/CLAUDE.md`'s "Model pins" table is the source of truth for
every model value. Keep the commands below in sync with it if a pin
changes.

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
3. Register the MCP server(s) at user scope:
   - **Two-bridge mode** (Antigravity only):
     ```bash
     claude mcp add-json -s user antigravity '{"command":"npx","args":["-y","agy-bridge"],"env":{"AGY_DEFAULT_MODEL":"gemini-3.8-flash-medium"},"timeout":600000}'
     ```
   - **Three-bridge mode** (Antigravity + both Codex instances):
     ```bash
     claude mcp add-json -s user antigravity '{"command":"npx","args":["-y","agy-bridge"],"env":{"AGY_DEFAULT_MODEL":"gemini-3.8-flash-medium"},"timeout":600000}'
     claude mcp add-json -s user codex-qa '{"command":"codex","args":["--profile","qa","mcp-server"],"timeout":600000}'
     claude mcp add-json -s user codex-security '{"command":"codex","args":["--profile","security","mcp-server"],"timeout":600000}'
     ```
   `AGY_DEFAULT_MODEL` is only a fallback — `templates/CLAUDE.md` passes
   `model:` explicitly on every Coder/Analyzer/Release-Writer call, since
   that's the only guarantee the bridge honors it.
4. Verify: `claude mcp list` shows `antigravity` **Connected**
   (two-bridge), or all three of `antigravity`, `codex-qa`,
   `codex-security` **Connected** (three-bridge).
5. Copy `templates/CLAUDE.md` into the target project's `CLAUDE.md` (or
   merge it in) — keep the `@AGENTS.md` import line at the top.
   **Two-bridge mode:** also append `CLAUDE-two-bridge-overlay.md`.
6. Copy `templates/AGENTS.md` into the project's root `AGENTS.md` (or
   merge it in).
7. Create/move skills into `skills/<name>/SKILL.md` at the project root,
   then symlink: `ln -s skills .claude/skills && ln -s skills .agents/skills`.
   Copy `templates/skills/delegation-pipeline/` in — keep `two-bridge.md`
   only in two-bridge mode. Keep the "Available skills" list in
   `AGENTS.md` in sync.
8. **Enforce the Gate mechanically (recommended).** The Gate is prose —
   nothing stops Claude Code from editing a file directly. Copy
   `templates/hooks/agent-bridges-gate.sh` to
   `.claude/hooks/agent-bridges-gate.sh` (`chmod +x`), then merge the
   `hooks` block from `templates/settings.hooks.json` into
   `.claude/settings.json`. This adds a `PreToolUse` hook on
   `Edit`/`Write`/`NotebookEdit`: progress files, project memory,
   delegation config, `skills/`, and `.agent-bridges/` pass through;
   everything else (application code) surfaces a permission prompt. Bash
   commands that mutate tracked files aren't covered — that half stays
   honor-system.
9. **(Team sharing)** Commit a `.mcp.json` with the same server entries
   instead of user-scope registration, plus `AGENTS.md`, `skills/`, and
   the symlinks — all meant to be checked in.
10. **Enable the learning curator (optional, recommended):**
    - **Project-side:** copy `templates/skills/learning-curator/` into
      the project's `skills/`. Create an empty, committed
      `.agent-bridges/learning/log.md`, and gitignore
      `.agent-bridges/learning/pending/` only. Keep "Available skills" in
      `AGENTS.md` in sync.
    - **Machine-side (once per machine):** create `~/.agents/skills/` and
      `~/.agent-bridges/learning/` (with `skills-pending/` and an empty
      `skills-log.md`) — nothing here is project-specific or ever
      committed. Symlink `~/.agents/skills/<name>` into
      `~/.claude/skills/<name>` per skill so Claude Code discovers it too.

### Operational notes

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

## Using the templates

See "Repo layout" above for what each file contains. A few notes beyond
that:

- Roles are pinned, not task-fit routed. QA and Security run in parallel
  once Claude Code's own review pass is done; raw output is never piped
  bridge-to-bridge. Independent units are delegated in parallel.
- Only `antigravity`, `codex-qa`, and `codex-security` calls run on a
  separate vendor's quota. Claude's own subagents (`Agent`/`Task`) still
  burn Claude's own limit, so they're reserved for work needing a tool,
  permission, or session state only Claude Code has — not coding, QA, or
  security, which the three bridges own outright.
- The progress-file template (`review-topic-template.md`) uses Indonesian
  section headers, and `CLAUDE.md`'s rules refer to them by exact name —
  the section names are load-bearing. If you translate one file, translate
  both.

## Verifying it works

After restarting Claude Code, run `claude mcp list`.

- **Three-bridge mode:** all three bridges connected. An Antigravity call
  returns a `session_id`; `codex-qa`/`codex-security` each return their
  own `threadId` — confirm they differ even for the same diff.
- **Two-bridge mode:** `antigravity` connected (no Codex entries). Run one
  `adversarial_review` call framed as QA and one framed as Security —
  confirm they return different `session_id` values.
- **Gate hook (step 8):** ask Claude Code to `Edit`/`Write` an
  application-code file directly. A permission prompt quoting the Gate
  rule should appear first. If not, open `/hooks` once or restart.
- **Learning-curator storage (step 10):** after a MEMORY proposal, `git
  status` should **not** show `.agent-bridges/learning/pending/` as
  untracked, but should show a normal diff for a promoted/auto-applied
  change to `AGENTS.md`/`log.md`. After a CREATE_SKILL, confirm the skill
  exists at `~/.agents/skills/<name>/SKILL.md`, that
  `~/.claude/skills/<name>` symlinks to it, and that `git status` inside
  the project shows nothing related to it.

## Status

Two topologies:

```text
Three-bridge mode:
Claude Code (Planner & Reviewer)
  -> Antigravity (antigravity MCP server, runs agy-bridge, Antigravity pin)
       — Document Analyzer (pre-plan) / Coder-Executor (implement) / Release-Changelog Writer (post-ship)
  -> Codex QA (codex-qa MCP server, profile "qa", QA pin) — QA Engineer
  -> Codex Security (codex-security MCP server, profile "security", Security pin) — Security Engineer

Two-bridge mode:
Claude Code (Planner & Reviewer — also primary defense, see CLAUDE-two-bridge-overlay.md)
  -> Antigravity (antigravity MCP server, runs agy-bridge)
       — Document Analyzer / Coder-Executor / Release-Changelog Writer (Antigravity pin)
       — QA lens / Security lens (adversarial_review chain: Gemini 3.1 Pro high -> Claude Opus 4.6 -> Flash)
```

This is a PoC: a fixed-role pipeline (plan → implement → review → QA +
security in parallel) rather than task-fit routing, and it holds until
quota pressure becomes the binding constraint. If the bottleneck turns out
to be provider-level quota exhaustion rather than pipeline shape, a proxy
like [9Router](https://9router.com/) (account/tier fallback across
providers) is the next thing to evaluate — it solves quota/cost failover,
not role-to-provider fit, and would sit below this routing layer.

## Acknowledgements

This is an original configuration/template repository — not a fork, no
source code from its MCP dependencies included.

The Antigravity integration uses
[agy-bridge](https://github.com/sshahzaiib/agy-bridge) by Shahzaib Akram
as an external MCP dependency (registered locally as `antigravity`),
distributed under the MIT License.

## License

Copyright (c) 2026 Sanovalaw. Licensed under the [MIT License](LICENSE).
