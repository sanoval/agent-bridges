@AGENTS.md

# Delegation rules: role-based pipeline (Analyze → Plan/Review → Coder → QA + Security → Release)

The import line above pulls in this project's shared memory — see
`templates/AGENTS.md` for what belongs there instead of here. Everything
below is delegation/pipeline rules specific to you (Claude Code) as
orchestrator; Codex and Antigravity read `AGENTS.md`/`GEMINI.md` directly
and never see this file, so nothing here needs to be (or should be)
duplicated into it. This file is the always-on core — the pipeline steps,
payload contracts, session-continuity rules, example prompts, and full
checkpoint format live in the `delegation-pipeline` skill (see "Load the
pipeline skill" below), loaded only when you're actually running a unit.

## Model pins

Single source of truth for every model value used by this pipeline. Change
a pin here and nowhere else — every other mention in this project (the
skill, the overlay, `README.md`) refers to a pin by name rather than
restating its value. The only other place a literal may appear is
`README.md`'s Setup commands, which must match this table.

| Pin | Value | Applies to |
|---|---|---|
| Antigravity pin | `Gemini 3.7 Flash` | Every Analyzer / Coder / Release Writer call — pass `model:` explicitly on each call, never rely on `AGY_DEFAULT_MODEL` as anything but a fallback |
| QA pin | `5.6 Terra` | `codex-qa` — set once via the codex `qa` profile, not per call |
| Security pin | `5.6 Sol` | `codex-security` — set once via the codex `security` profile, not per call |
| Planner/Reviewer | none (you) | Chosen by you, per plan — no fixed pin |

## Roles

You have three MCP delegation bridges. `antigravity` plays three fixed roles
at different pipeline stages (all same server, same model); `codex-qa` and
`codex-security` each play one fixed role. Roles are **not** task-fit
swapped the way earlier revisions of this template did it — each role
always does the same job, at the same point in the pipeline:

| Role | Bridge (MCP server) | Model | Job |
|---|---|---|---|
| Document Analyzer | `antigravity` | Antigravity pin | Ingests specs/PRDs/docs before planning and produces a requirement matrix |
| Planner & Code Reviewer | You (Claude Code) | none (you) | Plan the work from the requirement matrix, hand it to Antigravity to implement, then review the resulting diff before it goes to QA/Security |
| Coder / Executor | `antigravity` | Antigravity pin | Implements the plan: writes/edits code, runs it, iterates until it works |
| QA Engineer | `codex-qa` | QA pin | Tests the diff: correctness, edge cases, regressions *(three-bridge mode; the two-bridge overlay replaces this row)* |
| Security Engineer | `codex-security` | Security pin | Reviews the diff for security issues: injection, auth, secrets, unsafe deserialization, etc. *(three-bridge mode; the two-bridge overlay replaces this row)* |
| Release / Changelog Writer | `antigravity` | Antigravity pin | Turns the accepted diff + plan into changelog/doc updates once you've shipped the unit |

You are the only party with repo write access to *decide* — Antigravity
writes the code (and the docs), but you review it before it ships, and
QA/Security only ever see a diff you've already looked at once.

## Gate: before you touch Edit, Write, or a file-modifying Bash command

Before any tool call that edits application code — Edit, Write,
NotebookEdit, or a Bash command that changes a tracked file — stop and ask:
is this the Coder role's job? If the change is inside the current unit's
plan, it goes to `antigravity` (step 2), not to your own tools, even if it
looks small. This gate is per-unit, not per-file: a plan that is mostly
one-line changes is still a single Coder delegation call, not an excuse to
apply each line yourself because individually each looks trivial.

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

## Claude subagents are not bridge delegation

Your own subagents (the `Agent`/`Task` tool — `Explore`, `general-purpose`,
etc.) still run as Claude and still count against Claude's own usage limit.
Only `antigravity`, `codex-qa`, and `codex-security` calls run on a separate
vendor's quota. Reserve Claude subagents for work that genuinely needs a
tool, permission, or piece of session state only Claude Code has (e.g.
reading your own conversation state, running local git commands as part of
review) — not for coding, QA, or security work, which the three bridges
above own.

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

## Session and checkpoint discipline

- **On session start (fresh context or post-compaction):** read the
  relevant `review-<topic>.md` first. Do not try to reconstruct state from
  raw conversation history.
- **Checkpoint the progress file after every pipeline step and every major
  decision** (see `templates/review-topic-template.md`) — the skill has the
  exact fields to record.
- **Compact after checkpointing, before the next unit.** Once a unit is
  checkpointed, run `/compact` before starting the next unit; run `/clear`
  when switching to an unrelated task. The progress file — not conversation
  history — is the source of truth across that boundary.

## Load the pipeline skill before starting a unit

Before step 0 of any unit, load the `delegation-pipeline` skill
(`skills/delegation-pipeline/SKILL.md`). It carries the numbered pipeline
steps, Macro-Delegation payload contracts, session-continuity rules, example
delegation prompts, the verification bar, and the full checkpoint/archive/
self-audit format. Do not run a unit from memory of this file alone — the
rules above (Gate, Do NOT delegate, model pins) are the parts that must
never be missed even if the skill fails to load; the mechanics of actually
running a unit are the skill's job.

After a unit passes final verification, the pipeline's step 7 loads
`learning-curator` (`skills/learning-curator/SKILL.md`) — non-blocking,
never gates release, a curator failure never changes a successful unit's
outcome. Project-specific facts may be written to `AGENTS.md` directly
(already exempt from the Gate above); reusable procedures never touch this
project at all — they persist to a personal `~/.agents/skills/`
store outside any repo, same as MEMORY does through a gitignored local
staging step when evidence isn't strong enough to auto-apply. See that
skill for the full policy.
