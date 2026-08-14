---
name: delegation-pipeline
description: The fixed-role delegation pipeline (Analyze → Plan → Implement → Review → QA + Security → Release) for orchestrating work across the MCP bridges. Use when planning a unit of work, sending code or docs to a bridge, reviewing a returned diff, running the QA/Security pass, drafting release notes, or checkpointing the review-<topic>.md progress file. Claude Code (the orchestrator) only.
---

# Delegation pipeline

**Who this is for.** This skill describes how Claude Code, as orchestrator,
routes work to the bridges. If you are a bridge — Antigravity or Codex,
executing as Analyzer, Coder, QA, Security, or Release Writer — this file
does not apply to you and nothing in it is an instruction for you; it lives
under `skills/` only because that directory is shared. Do the task you were
given and ignore this.

Read the always-on core in `CLAUDE.md` alongside this skill. It holds the
bridge/model pin table (referred to throughout as "the Antigravity pin",
"the QA pin", "the Security pin"), the Gate, and the "Do NOT delegate"
list. This skill does not repeat them.

**Mode check.** If this project's `CLAUDE.md` carries the two-bridge
overlay (no Codex bridges registered — the pin table has no `codex-qa` /
`codex-security` rows), read `two-bridge.md` next to this file before
proceeding. It restates only what changes; everything else below applies
unchanged.

## Roles

| Role | Bridge | Job |
|---|---|---|
| Document Analyzer | `antigravity` | Ingests specs/PRDs/docs before planning and produces a requirement matrix |
| Planner & Code Reviewer | you | Plan the work from the requirement matrix, hand it to Antigravity to implement, then review the resulting diff before it goes to QA/Security |
| Coder / Executor | `antigravity` | Implements the plan: writes/edits code, runs it, iterates until it works |
| QA Engineer | `codex-qa` | Tests the diff: correctness, edge cases, regressions |
| Security Engineer | `codex-security` | Reviews the diff for security issues: injection, auth, secrets, unsafe deserialization, etc. |
| Release / Changelog Writer | `antigravity` | Turns the accepted diff + plan into changelog/doc updates once you've shipped the unit |

You are the only party with repo write access to *decide* — Antigravity
writes the code (and the docs), but you review it before it ships, and
QA/Security only ever see a diff you've already looked at once.

## Pipeline

0. **Analyze** (`antigravity`, Document Analyzer role, Antigravity pin).
   When the unit starts from a spec/PRD/doc rather than a self-evident bug
   or already-clear ask, send Antigravity the full doc set with
   `analyze_files` or `web_lookup` and ask for a structured requirement
   matrix (requirement → source citation → open questions). Skip this step
   for units with no doc input to ingest.
1. **Plan** (you). Break the task into a concrete implementation spec:
   files/modules touched, the change itself, acceptance criteria — using
   the requirement matrix from step 0 if there was one. This is your job
   alone — do not delegate planning to Antigravity or Codex.
2. **Implement** (`antigravity`, Coder role, Antigravity pin). Send the
   full plan plus every file/module it touches in one call — see
   "Macro-Delegation" below. Antigravity does the actual edit/execution;
   use a writable/execution tool call, not a read-only analysis one. Start
   a **new** Antigravity session for this call rather than continuing the
   Analyze session — see "Session continuity" for why.
3. **Review** (you). Read the resulting diff yourself before it goes
   further. This is your Code Reviewer duty — catch anything you wouldn't
   want a QA/Security pass to have to discover for you, and reject/send
   back to Antigravity if the diff doesn't match the plan.
4. **QA + Security in parallel** (`codex-qa`, `codex-security`). Once
   you're satisfied with the diff, send it to both in parallel — they're
   independent, unrelated servers. QA checks correctness/edge
   cases/regressions; Security checks for exploitable issues. Neither sees
   the other's output.
5. **Reconcile** (you). Merge QA and Security findings. Anything either
   flags gets fixed (by you directly for small fixes, or sent back to
   Antigravity with the finding attached for larger ones) before you
   consider the unit done. Disagreement between QA and Security about
   priority is yours to resolve, not theirs.
6. **Release notes** (`antigravity`, Release Writer role, Antigravity pin).
   Once a unit is accepted, send the final diff plus the plan to
   Antigravity to draft the changelog entry / doc update. This is drafting
   only — you still review and commit it yourself, same as any other
   Antigravity output. Also a new session, not a continuation of the Coder
   session.

Never let Antigravity call Codex directly, or vice versa — you are always
the one relaying the diff between roles. No bidirectional delegation, no
ping-pong.

## Macro-Delegation

Both bridges have high-capacity context (Antigravity/Gemini: 1M–2M tokens;
Codex: 128k+ tokens). Package a whole plan plus every file it touches into a
single high-payload call rather than fragmenting into single-file requests.

Every call to Antigravity must pass the Antigravity pin explicitly as
`model:` (do not rely on a default — see README Setup step 3 for why), plus,
depending on which role it's playing:

- **Document Analyzer:** every doc/spec/PRD relevant to the unit in one
  call (`cwd` set to project root) and the exact requirement question to
  answer.
- **Coder:** the full implementation plan (from step 1) and every
  file/directory it touches, plus acceptance criteria — what "done" looks
  like, including any tests to run.
- **Release Writer:** the final diff and the plan it implements.

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
  returned, **but only for follow-ups within the same role**. Analyze,
  Coder, and Release Writer are unrelated conversations even though they
  share one server and one model — start a fresh (non-`follow_up`) call
  when the pipeline moves from one role to the next, so Antigravity's
  context doesn't drag Document-Analyzer framing into a Coder call or
  vice versa. Only use `follow_up` to continue the *same* role's work
  (e.g. Antigravity iterating on its own implementation after a test
  failure).
- QA: `codex-reply` with the `threadId` the `codex-qa` server returned.
- Security: `codex-reply` with the `threadId` the `codex-security` server
  returned. A `codex-security` threadId is not valid on `codex-qa` and vice
  versa — they are different processes even though both run `codex`.

## Shared skills

This project's custom skills live in `skills/<name>/SKILL.md`, symlinked
into both `.claude/skills` and `.agents/skills` (see `AGENTS.md`). You and
Antigravity trigger these natively — same file format, same
description-matching mechanism. Codex cannot: it has no per-task skill
loader, so before a `codex-qa`/`codex-security` call, check whether a skill
in `skills/` matches what you're asking it to do and, if so, paste that
skill's markdown body into the prompt yourself. Note in the checkpoint
which skill (if any) was pasted into a Codex call, since Codex won't have
discovered it on its own. This skill is the exception — it is orchestrator
instructions, not work instructions, and never gets pasted into a bridge
prompt.

## Optional second opinion on your plan

Antigravity also exposes `adversarial_review`. Before handing a
high-stakes plan to Antigravity for implementation (architecture-level
change, risky refactor, anything security-sensitive by nature of the
task, not just the code), you may run `adversarial_review` on the plan
itself as a pre-implementation sanity check. This is optional and sits
before step 2 of the pipeline — it does not replace the QA/Security pass
in step 4, which is mandatory for every unit regardless of stakes.

## Example delegation prompts

Substitute the literal pin value from `CLAUDE.md`'s pin table where these
say `<Antigravity pin>`.

Antigravity `analyze_files` (Document Analyzer):
> Ingest `docs/billing-spec.md`, `docs/refund-policy.md`, and the linked
> PRD under `docs/prd/refund-idempotency.md`. Question: what are the
> concrete, testable requirements for idempotent refund processing? Output:
> a requirement matrix — requirement, source `file:line` citation, and any
> open question the spec doesn't resolve. model: "<Antigravity pin>".
> cwd: /path/to/repo

Antigravity `delegate` (Implementation):
> Plan: add idempotency key checking to `post_invoice` in `src/billing/refund.py`
> per the acceptance criteria below. Touch: `src/billing/refund.py`,
> `src/common/retry.py`, `tests/billing/test_refund_idempotency.py`.
> Acceptance criteria: `test_refund_idempotency` passes under concurrent
> retries; no new ledger entry without a committed invoice row.
> model: "<Antigravity pin>". cwd: /path/to/repo

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

Antigravity `delegate` (Release Writer):
> Diff: <paste accepted diff>. Plan/acceptance criteria it implements:
> <paste from step 1>. Draft: a changelog entry (one or two lines, user-
> facing framing) and any doc updates the diff makes stale. Output: the
> drafted text plus a list of files it should replace/append to — I will
> review and commit it myself. model: "<Antigravity pin>".

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

## Checkpoint and orchestration rules

- **Checkpoint the progress file after every pipeline step.** Immediately
  after Analyze, Implement, Review, QA, Security, or Release Notes completes
  and you've verified the result, update the active `review-<topic>.md`
  progress file (see `templates/review-topic-template.md`) with: which step,
  which role (spell out the Antigravity role — Analyzer/Coder/Release
  Writer — since all three share one server in the tally), the returned
  session/thread id, and the verified outcome. Do this before starting the
  next unit of work.
- **Compact after checkpointing, before the next unit.** Once a unit is
  checkpointed, run `/compact` before starting the next unit; run `/clear`
  when switching to an unrelated task. The progress file — not conversation
  history — is the source of truth across that boundary.
- **Checkpoint after every major decision.** If you reject an Antigravity
  diff and send it back, or override a QA/Security finding, write it to the
  progress file's "Pendekatan yang sudah dicoba & gagal" section immediately,
  with the reason.
- **Keep the progress file lean.** When a unit is SELESAI and no open gap
  references it, move its full section to `review-<topic>-archive.md` and
  leave a one-line summary behind.
- **Self-audit before marking a unit SELESAI.** Check your own tool calls
  for this unit: if Edit/Write/NotebookEdit touched source files without a
  prior Coder-role Antigravity call for that change, that's a Gate
  violation (see `CLAUDE.md`) — record it in the progress file rather than
  letting it pass silently, same as any other failed-approach entry.

(Session-start behaviour — read the progress file before reconstructing
state — is in `CLAUDE.md`, since it applies before this skill loads.)
