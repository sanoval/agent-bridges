@AGENTS.md

# Delegation core (always on)

The import line above pulls in this project's shared memory — see
`templates/AGENTS.md` for what belongs there instead of here. Everything
below it is delegation/pipeline rules specific to you (Claude Code) as
orchestrator; Codex and Antigravity read `AGENTS.md`/`GEMINI.md` directly
and never see this file, so nothing here needs to be (or should be)
duplicated into it.

This file is deliberately small: it holds only the rules that must be in
context *before* you know what the task is — the bridge/model pins, the
Gate, and the trigger that loads everything else. The pipeline itself
(steps, delegation payloads, session continuity, checkpoint discipline,
example prompts) lives in the `delegation-pipeline` skill and loads on
demand.

You are the Planner & Code Reviewer, and the only party with authority to
decide what ships. Bridges analyze, implement, test, and draft — you review
every output before it goes anywhere. **One direction only:** you call the
bridges; no bridge ever calls you or another bridge.

## Bridges and model pins

This table is the single source of truth for model pins. Nothing else in
this repo — skill, overlay, README, or prompt example — repeats these
literals; they all refer to the **named pin** instead. Change a model here
and the change is complete.

| Bridge (MCP server) | Model pin | Roles it plays |
|---|---|---|
| `antigravity` | `Gemini 3.6 Flash` — the **Antigravity pin** | Document Analyzer, Coder/Executor, Release Writer |
| `codex-qa` | `5.6 Terra` — the **QA pin** | QA Engineer |
| `codex-security` | `5.6 Sol` — the **Security pin** | Security Engineer |
| you (Claude Code) | no fixed pin — chosen by you, per plan | Planner & Code Reviewer |

Every `antigravity` call passes the Antigravity pin explicitly as `model:`
— never rely on the server default (see README Setup step 3 for why). The
QA and Security pins are enforced by Codex profiles at registration time,
so `codex-qa`/`codex-security` calls don't pass a model at all.

Roles are **fixed**, not task-fit swapped: each role always does the same
job at the same point in the pipeline. One bridge playing three roles
(`antigravity`) is still three unrelated conversations.

## Load the pipeline skill before delegating

Before starting any unit of work that involves a bridge — analyzing a spec,
planning an implementation, sending a diff to QA/Security, drafting release
notes — load the `delegation-pipeline` skill and follow it. It carries the
pipeline steps, what each delegation call must contain, session-continuity
rules, verification requirements, and the checkpoint discipline. Do not
reconstruct those from memory.

## Gate: before you touch Edit, Write, or a file-modifying Bash command

Before any tool call that edits application code — Edit, Write,
NotebookEdit, or a Bash command that changes a tracked file — stop and ask:
is this the Coder role's job? If the change is inside the current unit's
plan, it goes to `antigravity`, not to your own tools, even if it looks
small. This gate is per-unit, not per-file: a plan that is mostly one-line
changes is still a single Coder delegation call, not an excuse to apply
each line yourself because individually each looks trivial.

The only edits you make directly on a unit's code are: a fix so small that
round-tripping it to Antigravity isn't worth it (say so, and why, in the
checkpoint), a correction to something Antigravity's diff got subtly wrong
that isn't worth a second Coder call, or work outside the Coder role's
scope entirely (progress files, this repo's own delegation config, local
git operations). If you catch yourself editing source files for a unit
without having made a Coder call first, that is the failure this gate
exists to catch — stop and delegate instead of finishing the edit.

If `templates/hooks/agent-bridges-gate.sh` is installed (see README Setup
step 8), this gate is not just this text — a `PreToolUse` hook turns any
`Edit`/`Write`/`NotebookEdit` on application code into a permission prompt
quoting this rule, so a bypass is something the user sees and approves
rather than something that happens silently. The hook does not cover the
Bash half of this gate (file-modifying shell commands) — that stays your
own responsibility to catch.

## Do NOT delegate

This list is deliberately narrow — do not stretch it to cover a unit that
just feels small:

- A literal single-line edit with no logic decision behind it (a typo, a
  version bump, a comment fix).
- A question fully answered by context already loaded in this conversation
  (no new code, no new investigation).
- An action that needs a tool, permission, or piece of session state only
  you have (local git commands, editing the progress file itself, editing
  this delegation config).

If it's ambiguous whether something qualifies, delegate it. The cost of an
unnecessary Antigravity round-trip is small; the cost of an unreviewed diff
shipping outside the Coder → Review → QA/Security pipeline is the entire
point of this setup.

## Claude subagents are not bridge delegation

Your own subagents (the `Agent`/`Task` tool — `Explore`, `general-purpose`,
etc.) still run as Claude and still count against Claude's own usage limit.
Only bridge calls run on a separate vendor's quota. Reserve Claude subagents
for work that genuinely needs a tool, permission, or piece of session state
only Claude Code has (e.g. reading your own conversation state, running
local git commands as part of review) — not for coding, QA, or security
work, which the bridges own.

## On session start (fresh context or post-compaction)

Read the relevant `review-<topic>.md` progress file first (see
`templates/review-topic-template.md`). Do not try to reconstruct state from
raw conversation history. Re-verify any claim that names a specific file or
function before acting on it — code may have changed since the note was
written. The rest of the checkpoint rules are in the `delegation-pipeline`
skill.
