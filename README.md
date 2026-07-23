# claude-antigravity-workflow

Config and templates for pairing **Claude Code** with the **agy-bridge** MCP
server, which delegates heavy work to the Antigravity CLI (Gemini). The goal:
keep Claude Code's context window lean by pushing large file reads, repo-wide
searches, web lookups, and adversarial reviews out to a second model, while
Claude Code stays the single orchestrator.

## Why

Claude Code's context is the scarce resource. Reading a 2,000-line file,
diffing a large repo, or running a second-opinion review all burn it fast —
and often the *content* isn't needed in context, only the *answer*. agy-bridge
routes those tasks to Antigravity/Gemini and returns just the result.

## Architecture

- **One direction only.** Claude Code always calls agy-bridge tools. Antigravity
  never calls back into Claude Code — no bidirectional delegation, no
  ping-pong loops.
- **Claude Code = MCP Host** (with an internal MCP Client). **agy-bridge = MCP
  Server**, exposing tools over JSON-RPC 2.0.
- **Session continuity via `follow_up`.** Every agy-bridge call returns a
  `session_id`. Follow-up questions reuse it instead of resending context —
  verified live in [docs/smoke-test-log.md](docs/smoke-test-log.md).

## Repo layout

```
templates/
  CLAUDE.md                  — drop-in delegation + checkpoint rules for a project's CLAUDE.md
  review-topic-template.md   — structure for a persistent review-<topic>.md progress file

docs/
  setup-log.md                — how agy-bridge MCP was registered on this machine
  smoke-test-log.md           — proof delegation + follow_up continuity work
  superpowers/plans/          — Spec-Driven Development plans (Superpowers skill output)
  superpowers/specs/          — specs backing those plans

.superpowers/sdd/
  progress.md                 — task-by-task ledger for the SDD run that built this repo
  task-N-brief.md / task-N-report.md — per-task input/output
  review-<range>.diff         — adversarial-review diffs checkpointed per task
```

## Setup

1. Prerequisites: `agy` CLI installed and authenticated, Node + npx available.
   (Verified via `agy --version` / `agy models` with no auth prompt.)
2. Register the MCP server (user scope — available in every project on the
   machine):
   ```bash
   claude mcp add-json -s user agy-bridge '{"command":"npx","args":["-y","agy-bridge"],"timeout":600000}'
   ```
3. Verify: `claude mcp list` should show `agy-bridge` as **Connected**.
4. Copy `templates/CLAUDE.md` into a target project's `CLAUDE.md` (or merge
   its rules into an existing one) to turn on delegation behavior there.

Full trace of step 1–3 as run on this machine: [docs/setup-log.md](docs/setup-log.md).

## Using the templates

**`templates/CLAUDE.md`** — delegation rules for Claude Code:

| Situation | Delegate to |
|---|---|
| Any file >200 lines | `analyze_files` |
| >3 files in one analysis/comparison | `analyze_files` |
| Git history / repo-wide search | `deep_search` |
| Web or documentation lookup | `web_lookup` |
| Plan critique or code review | `adversarial_review` |
| Follow-up on a prior delegation | `follow_up` (with the returned `session_id`) |

Plus orchestration rules: checkpoint the progress file after every
delegation and every major decision, and read the relevant
`review-<topic>.md` first thing on a fresh/post-compaction session instead
of reconstructing state from conversation history.

**`templates/review-topic-template.md`** — the structure for that
`review-<topic>.md` progress file: context, per-unit status with cited
requirements and delegation session IDs, a gap list, a "failed approaches"
log (so dead ends aren't rediscovered), and a "not yet done" list for the
next session.

## Verifying it works

[docs/smoke-test-log.md](docs/smoke-test-log.md) records a live run: a
`web_lookup` call returning a `session_id`, then a `follow_up` call on that
same session answering a question that only makes sense with the prior
context — confirming agy-bridge preserves context server-side without
Claude Code resending it.

## Status

Built via Spec-Driven Development; see `.superpowers/sdd/progress.md` for the
task ledger. All 4 planned tasks (MCP registration, delegation-rules
template, progress-notes template, end-to-end smoke test) are complete.
