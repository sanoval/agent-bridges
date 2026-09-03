# Architecture

Design notes and reference material for how agent-bridges is put together.
For "how do I install/set this up," see the main [README](../README.md) and
[SETUP.md](SETUP.md).

## Topology

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
  two-bridge.md                  — two-bridge deltas: step 4 replacement, adversarial_review lens calls
skills/learning-curator/
  SKILL.md                       — post-verification learning: classification, evidence scoring, hard gates
  proposal-template.md           — format for a pending learning proposal
hooks/
  hooks.json                     — PreToolUse hook enforcing the CLAUDE.md Gate mechanically
  agent-bridges-gate.sh          — the Gate-enforcement script referenced by hooks.json
.mcp.json                        — antigravity/codex-qa/codex-security server definitions, auto-registered on enable
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
