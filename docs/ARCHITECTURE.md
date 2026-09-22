# Architecture

Design notes and reference material for how agent-bridges is put together.
For "how do I install/set this up," see the main [README](../README.md) and
[SETUP.md](SETUP.md).

## Topology

- **One direction only.** Claude Code calls Antigravity and Codex; neither
  calls back into Claude Code or each other. Execution authority stays at
  one point.
- **Claude Code = MCP host for Antigravity; plugin host for Codex.**
  Antigravity (`antigravity` server, running `agy-mcp`) is a genuine MCP
  server over JSON-RPC 2.0, registered in `.mcp.json`. Unlike a request/
  response MCP call, `agy_run` dispatches an *async job*: it returns a
  `job_id` immediately, the underlying `agy` CLI run continues in the
  background, and a `PostToolUse` hook wakes Claude Code when the job
  lands — there is no blocking call sitting on a timeout ceiling (see
  `docs/MIGRATION.md` for why that distinction mattered enough to change
  bridges over). Codex is different: QA and Security both run through
  `codex-companion.mjs task`, a script provided by the separately-installed
  `openai/codex-plugin-cc` plugin (see "Why a plugin, not an MCP server"
  and `docs/SETUP.md`) — invoked directly via the `Bash` tool
  (`node codex-companion.mjs task ...`), not through that plugin's
  `codex:codex-rescue` subagent or its `/codex:*` slash commands (see
  `skills/delegation-pipeline/SKILL.md`, "Why direct Bash, not the
  subagent," for why: the subagent is itself a Sonnet-run wrapper around
  the same script, and its read-only guarantee depends on the wrapper
  reading your prompt correctly rather than on a flag). Both QA and
  Security drive the *same* script, the same local `codex` binary and
  app-server, distinguished only by the `--model` pin and framing text
  passed in the prompt — not two separate processes.
- **Session continuity.** Antigravity's `agy_run` accepts a
  `conversation_id` from a prior call to continue that same conversation.
  `codex-companion.mjs task` calls are backgrounded jobs tracked by job id
  (`node codex-companion.mjs status <job-id>`, then `result <job-id>`) —
  QA's job id and Security's are unrelated. It also supports resuming its
  own last thread (`--resume-last`), but a QA/Security call should almost
  always pass `--fresh` (omit `--resume-last`) instead (see
  `skills/delegation-pipeline/SKILL.md`, "Session continuity") so one
  role's framing never leaks into the other's context — the same
  discipline `agy_run`'s `conversation_id` needs across Antigravity's own
  three roles.

### Why a plugin, not an MCP server

Up to Codex CLI ~0.15x, `codex mcp-server` made Codex itself speak MCP,
exposing `codex`/`codex-reply` tools with a resumable `threadId` —
this project originally registered `codex-qa`/`codex-security` as two MCP
servers built on that. Codex CLI 0.154.0 removed that subcommand: Codex now
only ships `codex mcp` (Codex as an MCP *client*, opposite direction) and
`codex app-server` (Codex's own JSON-RPC protocol, not MCP). Rather than
hand-roll a replacement bridge around one-shot `codex exec`, this project
uses OpenAI's own [`codex-plugin-cc`](https://github.com/openai/codex-plugin-cc)
plugin, which wraps the real `codex app-server` and ships
`scripts/codex-companion.mjs` (the underlying task runner) plus a
`codex:codex-rescue` subagent and `/codex:review`, `/codex:status`,
`/codex:result`, etc. as convenience wrappers around it. This pipeline
calls `codex-companion.mjs` directly rather than going through the
subagent or slash commands — see the "Session continuity" bullet above.
The tradeoff versus the old MCP-server design: no resumable `threadId` (a
follow-up is a fresh, fully self-contained call — see "Session continuity"
above), and QA/Security no longer get their own persistent server process
each — both share one script/binary, differentiated per call by `--model`
and prompt framing rather than by which server you called.

## Repo layout

This repo is both a **Claude Code plugin** (installable via `/plugin`, see
the README) and a **marketplace** for itself — `.claude-plugin/` holds
the manifests, everything else at the plugin root ships automatically once
the plugin is enabled:

```
.claude-plugin/
  marketplace.json               — self-hosted marketplace listing this repo's one plugin
  plugin.json                    — plugin manifest (name, version — bump this to ship an update)
skills/delegation-pipeline/
  SKILL.md                       — pipeline steps, payload contracts, session continuity, example prompts
  two-bridge.md                  — two-bridge deltas: step 4 replacement, backgrounded lens calls
skills/learning-curator/
  SKILL.md                       — post-verification learning: classification, evidence scoring, hard gates
  proposal-template.md           — format for a pending learning proposal
hooks/
  hooks.json                     — PreToolUse hook enforcing the CLAUDE.md Gate mechanically
  agent-bridges-gate.sh          — the Gate-enforcement script referenced by hooks.json
.mcp.json                        — antigravity server definition, auto-registered on enable (Codex QA/Security come from the separately-installed openai/codex-plugin-cc plugin, not this file)
templates/
  AGENTS.md                      — shared project memory, read by all three harnesses (you merge this into your project)
  CLAUDE.md                      — always-on core: role/pin table, the Gate, "Do NOT delegate", checkpoint discipline (you merge this into your project)
  CLAUDE-two-bridge-overlay.md   — appended when no Codex subscription is available (two-bridge mode)
  review-topic-template.md       — structure for a persistent review-<topic>.md progress file
```

`skills/`, `hooks/`, and `.mcp.json` are **plugin-owned** — installing the
plugin is all that's needed for those, no copying, and `/plugin update`
picks up new versions. `templates/` is **not** plugin-distributed content:
`CLAUDE.md`/`AGENTS.md` become part of *your* project's own memory files,
and a plugin has no mechanism to inject into a file it doesn't own — that
half still needs the manual copy/merge in [SETUP.md](SETUP.md).

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

**Skills** work the same way between Claude Code and Antigravity for any
skill your *project* owns, since their skill formats match almost exactly
(YAML frontmatter + markdown body). They just look in different places:

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

The two orchestrator skills this repo ships — `delegation-pipeline` and
`learning-curator` — are the one exception to that pattern: they come from
the `agent-bridges` **plugin**, not from a project-local `skills/`
directory, so Claude Code discovers them globally once the plugin is
enabled and neither Antigravity nor Codex ever sees them (by design —
both are orchestrator-facing, never pasted into a Codex call).

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

## Using the templates

See "Repo layout" above for what each file contains. A few notes beyond
that:

- Roles are pinned, not task-fit routed. QA and Security both launch as
  background jobs once Claude Code's own review pass is done; raw output
  is never piped bridge-to-bridge. Independent units are delegated in
  parallel.
- `antigravity` calls (`agy_run`) and Codex QA/Security calls
  (`node codex-companion.mjs task`, direct `Bash` — see "Topology" above)
  are the only two paths that run on a separate vendor's quota; neither
  goes through Claude subagent inference. Every Claude subagent
  (`Explore`, `general-purpose`, and — outside this pipeline —
  `codex:codex-rescue` itself, which is `model: sonnet`) still burns
  Claude's own limit, so subagents are reserved for work needing a tool,
  permission, or session state only Claude Code has — not coding, QA, or
  security, which Antigravity and Codex's own script own outright.
- The progress-file template (`review-topic-template.md`) uses Indonesian
  section headers, and `CLAUDE.md`'s rules refer to them by exact name —
  the section names are load-bearing. If you translate one file, translate
  both.

## Status

Two topologies:

```text
Three-bridge mode:
Claude Code (Planner & Reviewer)
  -> Antigravity (antigravity MCP server, runs agy-mcp, async job per call, Antigravity pin)
       — Document Analyzer (pre-plan) / Coder-Executor (implement) / Release-Changelog Writer (post-ship)
  -> Codex QA (codex-companion.mjs task, direct Bash, --model QA pin, openai/codex-plugin-cc) — QA Engineer
  -> Codex Security (codex-companion.mjs task, direct Bash, --model Security pin, openai/codex-plugin-cc) — Security Engineer

Two-bridge mode:
Claude Code (Planner & Reviewer — also primary defense, see CLAUDE-two-bridge-overlay.md)
  -> Antigravity (antigravity MCP server, runs agy-mcp, async job per call)
       — Document Analyzer / Coder-Executor / Release-Changelog Writer (Antigravity pin)
       — QA lens / Security lens (backgrounded, concurrent agy_run calls — QA lens pin / Security lens pin, independently chosen model families)
```

This is a PoC: a fixed-role pipeline (plan → implement → review → QA +
security in parallel) rather than task-fit routing, and it holds until
quota pressure becomes the binding constraint. If the bottleneck turns out
to be provider-level quota exhaustion rather than pipeline shape, a proxy
like [9Router](https://9router.com/) (account/tier fallback across
providers) is the next thing to evaluate — it solves quota/cost failover,
not role-to-provider fit, and would sit below this routing layer.
