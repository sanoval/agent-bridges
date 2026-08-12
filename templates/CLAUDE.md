# Delegation rules: role-based pipeline (Planner/Reviewer → Coder → QA + Security)

You have three MCP delegation bridges, each pinned to a fixed role and a
fixed model. Roles are **not** task-fit swapped the way earlier revisions of
this template did it — each bridge always plays the same part:

| Role | Bridge (MCP server) | Model | Job |
|---|---|---|---|
| Planner & Code Reviewer | You (Claude Code) | Chosen by you, per plan — no fixed pin | Plan the work, hand it to Antigravity to implement, then review the resulting diff before it goes to QA/Security |
| Coder / Executor | `antigravity` | Gemini 3.6 Flash | Implements the plan: writes/edits code, runs it, iterates until it works |
| QA Engineer | `codex-qa` | 5.6 Terra | Tests the diff: correctness, edge cases, regressions |
| Security Engineer | `codex-security` | 5.6 Sol | Reviews the diff for security issues: injection, auth, secrets, unsafe deserialization, etc. |

You are the only party with repo write access to *decide* — Antigravity
writes the code, but you review it before it ships, and QA/Security only
ever see a diff you've already looked at once.

## Pipeline

1. **Plan** (you). Break the task into a concrete implementation spec:
   files/modules touched, the change itself, acceptance criteria. This is
   your job alone — do not delegate planning to Antigravity or Codex.
2. **Implement** (`antigravity`, model `Gemini 3.6 Flash`). Send the full
   plan plus every file/module it touches in one call — see
   "Macro-Delegation" below. Antigravity does the actual edit/execution;
   use a writable/execution tool call, not a read-only analysis one.
3. **Review** (you). Read the resulting diff yourself before it goes
   further. This is your Code Reviewer duty — catch anything you wouldn't
   want a QA/Security pass to have to discover for you, and reject/send
   back to Antigravity if the diff doesn't match the plan.
4. **QA + Security in parallel** (`codex-qa` model `5.6 Terra`,
   `codex-security` model `5.6 Sol`). Once you're satisfied with the diff,
   send it to both in parallel — they're independent, unrelated servers.
   QA checks correctness/edge cases/regressions; Security checks for
   exploitable issues. Neither sees the other's output.
5. **Reconcile** (you). Merge QA and Security findings. Anything either
   flags gets fixed (by you directly for small fixes, or sent back to
   Antigravity with the finding attached for larger ones) before you
   consider the unit done. Disagreement between QA and Security about
   priority is yours to resolve, not theirs.

Never let Antigravity call Codex directly, or vice versa — you are always
the one relaying the diff between roles. No bidirectional delegation, no
ping-pong.

## Claude subagents are not bridge delegation

Your own subagents (the `Agent`/`Task` tool — `Explore`, `general-purpose`,
etc.) still run as Claude and still count against Claude's own usage limit.
Only `antigravity`, `codex-qa`, and `codex-security` calls run on a separate
vendor's quota. Reserve Claude subagents for work that genuinely needs a
tool, permission, or piece of session state only Claude Code has (e.g.
reading your own conversation state, running local git commands as part of
review) — not for coding, QA, or security work, which the three bridges
above own.

## Macro-Delegation

Both bridges have high-capacity context (Antigravity/Gemini: 1M–2M tokens;
Codex: 128k+ tokens). Package a whole plan plus every file it touches into a
single high-payload call rather than fragmenting into single-file requests.

Every call to Antigravity must specify:
1. The full implementation plan (from step 1) and every file/directory it
   touches (`cwd` set to project root).
2. Acceptance criteria — what "done" looks like, including any tests to run.
3. `model: "Gemini 3.6 Flash"` explicitly on the call (do not rely on a
   default — see Setup for why).

Every call to `codex-qa` or `codex-security` must specify:
1. The diff (or the touched files, if the diff alone lacks context) plus the
   original plan/acceptance criteria it's being checked against.
2. The specific question: QA gets "does this work, what breaks it"; Security
   gets "what's exploitable here."
3. Request **structured findings with `file:line` citations** — a
   pass/fail-style table, not prose.

## Session continuity

Each bridge is a separate MCP server process with its own session/thread
namespace — do not mix them up:

- Antigravity: `follow_up` with the `session_id` the `antigravity` server
  returned.
- QA: `codex-reply` with the `threadId` the `codex-qa` server returned.
- Security: `codex-reply` with the `threadId` the `codex-security` server
  returned. A `codex-security` threadId is not valid on `codex-qa` and vice
  versa — they are different processes even though both run `codex`.

## Optional second opinion on your plan

Antigravity also exposes `adversarial_review`. Before handing a
high-stakes plan to Antigravity for implementation (architecture-level
change, risky refactor, anything security-sensitive by nature of the
task, not just the code), you may run `adversarial_review` on the plan
itself as a pre-implementation sanity check. This is optional and sits
before step 2 of the pipeline — it does not replace the QA/Security pass
in step 4, which is mandatory for every unit regardless of stakes.

Do NOT delegate: trivial single-line edits, questions answered by
already-loaded context, or tasks needing local tools only you have.

## Example delegation prompts

Antigravity `delegate` (Implementation):
> Plan: add idempotency key checking to `post_invoice` in `src/billing/refund.py`
> per the acceptance criteria below. Touch: `src/billing/refund.py`,
> `src/common/retry.py`, `tests/billing/test_refund_idempotency.py`.
> Acceptance criteria: `test_refund_idempotency` passes under concurrent
> retries; no new ledger entry without a committed invoice row.
> model: "Gemini 3.6 Flash". cwd: /path/to/repo

`codex-qa` `codex` (QA pass):
> Diff: <paste diff>. Original plan/acceptance criteria: <paste from step 1>.
> Question: does this satisfy the acceptance criteria? What edge cases or
> regressions does it miss? Output: pass/fail table with `file:line`
> citations for each finding.

`codex-security` `codex` (Security pass):
> Diff: <paste diff>. Question: what's exploitable here — injection, auth
> bypass, unsafe deserialization, secret handling, race conditions with
> security impact? Output: severity-ranked findings table with `file:line`
> citations.

## Parallelism, failures, and verification

- **QA and Security always run in parallel** on the same diff — they're
  independent servers with no shared state.
- **On bridge failure** (timeout, disconnect, unusable output): retry once.
  On a second failure, do the check yourself (there is no same-role
  fallback bridge in this pipeline — each role is single-sourced) and
  record the failure in the progress file so the next session knows that
  role was skipped for this unit.
- **Verification is defined as:** every QA/Security prompt demands
  `file:line` citations; you spot-check one or two of them before recording
  the result. Claims without citations get recorded as *unverified* and
  must not be the sole basis for shipping a unit. Remember Antigravity
  truncates output (~50k chars) — always request structured findings, never
  content dumps.

## Orchestration rules (project-specific, layered on top of the above)

- **One direction only.** You (Claude Code) always call Antigravity,
  `codex-qa`, and `codex-security`. Never configure or invoke a path where
  any bridge calls Claude Code or another bridge.
- **Checkpoint the progress file after every pipeline step.** Immediately
  after Implement, Review, QA, or Security completes and you've verified the
  result, update the active `review-<topic>.md` progress file (see
  `templates/review-topic-template.md`) with: which step, which bridge/role,
  the returned session/thread id, and the verified outcome. Do this before
  starting the next unit of work.
- **Compact after checkpointing, before the next unit.** Once a unit is
  checkpointed, run `/compact` before starting the next unit; run `/clear`
  when switching to an unrelated task. The progress file — not conversation
  history — is the source of truth across that boundary.
- **Checkpoint after every major decision.** If you reject an Antigravity
  diff and send it back, or override a QA/Security finding, write it to the
  progress file's "Pendekatan yang sudah dicoba & gagal" section immediately,
  with the reason.
- **On session start (fresh context or post-compaction):** read the
  relevant `review-<topic>.md` first. Do not try to reconstruct state from
  raw conversation history. Re-verify any claim that names a specific file
  or function before acting on it — code may have changed since the note
  was written.
- **Keep the progress file lean.** When a unit is SELESAI and no open gap
  references it, move its full section to `review-<topic>-archive.md` and
  leave a one-line summary behind.
