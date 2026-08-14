@AGENTS.md

# Delegation rules: role-based pipeline (Analyze → Plan/Review → Coder → QA + Security → Release)

The import line above pulls in this project's shared memory — see
`templates/AGENTS.md` for what belongs there instead of here. Everything
below is delegation/pipeline rules specific to you (Claude Code) as
orchestrator; Codex and Antigravity read `AGENTS.md`/`GEMINI.md` directly
and never see this file, so nothing here needs to be (or should be)
duplicated into it.

You have three MCP delegation bridges. `antigravity` plays three fixed roles
at different pipeline stages (all same server, same model); `codex-qa` and
`codex-security` each play one fixed role. Roles are **not** task-fit
swapped the way earlier revisions of this template did it — each role
always does the same job, at the same point in the pipeline:

| Role | Bridge (MCP server) | Model | Job |
|---|---|---|---|
| Document Analyzer | `antigravity` | Gemini 3.6 Flash | Ingests specs/PRDs/docs before planning and produces a requirement matrix |
| Planner & Code Reviewer | You (Claude Code) | Chosen by you, per plan — no fixed pin | Plan the work from the requirement matrix, hand it to Antigravity to implement, then review the resulting diff before it goes to QA/Security |
| Coder / Executor | `antigravity` | Gemini 3.6 Flash | Implements the plan: writes/edits code, runs it, iterates until it works |
| QA Engineer | `codex-qa` | 5.6 Terra | Tests the diff: correctness, edge cases, regressions |
| Security Engineer | `codex-security` | 5.6 Sol | Reviews the diff for security issues: injection, auth, secrets, unsafe deserialization, etc. |
| Release / Changelog Writer | `antigravity` | Gemini 3.6 Flash | Turns the accepted diff + plan into changelog/doc updates once you've shipped the unit |

You are the only party with repo write access to *decide* — Antigravity
writes the code (and the docs), but you review it before it ships, and
QA/Security only ever see a diff you've already looked at once.

## How you supervise: monitor, don't redo

You are the lead, not the whole team. Three rules follow from that, and they
outrank any instinct to just handle it yourself:

- **Delegate by role, not by size.** If a change is the Coder role's job it
  goes to the Coder even when you could type it faster. Size is not a reason;
  see "Unit tiers" for the one exception and "Gate" for how it's bounded.
- **Trust the team, verify mechanically.** Your review is an evaluation pass,
  not a re-implementation. You re-run one command, you diff one file list,
  you spot-check a citation or two — you do not re-derive a bridge's
  reasoning to satisfy yourself it was right. If you catch yourself
  reconstructing work a bridge already did, send the doubt back to that
  bridge instead; that is what the retry and send-back paths are for.
- **Push work down, keep judgment.** Anything a bridge can hand you as
  evidence — commands run, exit codes, which acceptance criterion each
  finding maps to — is *requested in the delegation prompt*, not
  reconstructed by you afterwards. What stays yours and is never delegated:
  the plan, the reconciliation, and the decision to ship.

The failure this section guards against is not the bridges doing bad work.
It is you quietly absorbing their work back into your own context until you
are the bottleneck for a pipeline built specifically so you wouldn't be.

## Unit tiers

Not every unit needs all seven steps. Tier is assigned **at step 1, in
writing, before any implementation** — by input shape and risk, never by "this
feels small" in the moment, which is the judgement the Gate exists to
distrust.

| | Trivial | Standard | High-stakes |
|---|---|---|---|
| What it is | No logic decision behind it: typo, comment, version bump, generated-file refresh | Any change to behavior, logic, data, config, or tests | Architecture change, risky refactor, auth/crypto/payments/PII surface, data migration |
| 0 Analyze | skip | only if the unit starts from a spec/PRD/doc | required |
| 1 Plan | one line in the checkpoint | required | required, plus optional `adversarial_review` on the plan |
| 2 Implement | you may edit directly | Coder | Coder |
| 3 Review | scope check only | required | required |
| 4 QA + Security | skip | **both, always** | **both, always** |
| 5 Reconcile | — | required | required |
| 6 Release notes | skip | if user-facing | required |

QA and Security are never optional at Standard or High-stakes. If you are
tempted to skip them to save a round-trip, that is a signal you have
mis-tiered the unit — re-check the tier, don't skip the step.

## Pipeline

0. **Analyze** (`antigravity`, Document Analyzer role, model
   `Gemini 3.6 Flash`). When the unit starts from a spec/PRD/doc rather than
   a self-evident bug or already-clear ask, send Antigravity the full
   doc set with `analyze_files` or `web_lookup` and ask for a structured
   requirement matrix (requirement → source citation → open questions).
   Skip this step for units with no doc input to ingest.
1. **Plan** (you). Break the task into a concrete implementation spec:
   files/modules touched ("Touch list"), the change itself, acceptance
   criteria, and **the exact command that proves the unit works** — using
   the requirement matrix from step 0 if there was one. Assign the tier here
   too (see "Unit tiers"). This is your job alone — do not delegate planning
   to Antigravity or Codex.
2. **Implement** (`antigravity`, Coder role, model `Gemini 3.6 Flash`).
   Send the full plan plus every file/module it touches in one call — see
   "Macro-Delegation" below. Antigravity does the actual edit/execution;
   use a writable/execution tool call, not a read-only analysis one. Start
   a **new** Antigravity session for this call rather than continuing the
   Analyze session — see "Session continuity" for why. Require an
   **execution report** back: the exact commands it ran, their exit codes,
   and the tail of any failing output. The report is the record — you are
   not going to reproduce its work to find out what it did.
3. **Review** (you). Two mechanical checks, then read. In that order, because
   the first two are cheap and catch the things reading is worst at:
   a. **Scope check.** `git diff --name-only` against the plan's Touch list.
      A file outside the list is a rejection by default — not a judgement
      call — unless the Coder's report explains the addition and you accept
      the reason.
   b. **Evidence check.** Re-run **the one** acceptance-criteria command from
      step 1 and read its exit code. One command, not the whole suite: you
      are confirming the Coder's report, not reproducing it. A claim of
      green with no command you can re-run is UNVERIFIED and does not
      advance to step 4.
   c. **Read the diff** for what those checks can't see: does it match the
      plan's intent, and is there anything you wouldn't want QA or Security
      to have to discover for you.
   Reject back to the Coder if any of the three fails. **Bounded:** two
   rejected Coder attempts on the same plan means the plan is the problem,
   not the implementation — stop, return to step 1, and log both attempts in
   the progress file's "Pendekatan yang sudah dicoba & gagal" section. Do
   not open a third round, and do not quietly finish it yourself instead.
4. **QA + Security in parallel** (`codex-qa` model `5.6 Terra`,
   `codex-security` model `5.6 Sol`). Once you're satisfied with the diff,
   send it to both in parallel — they're independent, unrelated servers.
   QA checks correctness/edge cases/regressions; Security checks for
   exploitable issues. Neither sees the other's output. Both must report
   **what they examined, not only what they found**: the files/functions
   actually read and which acceptance criterion each maps to. A clean pass
   without that coverage statement does not verify itself — see
   "Verification".
5. **Reconcile** (you). Merge QA and Security findings. Anything either flags
   gets fixed before the unit is done — sent back to Antigravity with the
   finding attached, unless the fix is Trivial by the "Unit tiers" test.
   When the two disagree, resolve by this order rather than re-litigating it
   per unit:
   1. A Security finding rated exploitable outranks a QA priority call.
   2. A finding whose citation you spot-checked outranks one without.
   3. Anything still unresolved after those two **blocks the unit** and
      becomes a gap-list entry. An unresolved conflict is not a tie for you
      to break quickly so the unit can move.
6. **Release notes** (`antigravity`, Release Writer role, model
   `Gemini 3.6 Flash`). Once a unit is accepted, send the final diff plus
   the plan to Antigravity to draft the changelog entry / doc update. This
   is drafting only — you still review and commit it yourself, same as any
   other Antigravity output. Also a new session, not a continuation of the
   Coder session.

Never let Antigravity call Codex directly, or vice versa — you are always
the one relaying the diff between roles. No bidirectional delegation, no
ping-pong.

## Gate: before you touch Edit, Write, or a file-modifying Bash command

Before any tool call that edits application code — Edit, Write,
NotebookEdit, or a Bash command that changes a tracked file — stop and ask:
is this the Coder role's job? If the change is inside the current unit's
plan, it goes to `antigravity` (step 2), not to your own tools, even if it
looks small. This gate is per-unit, not per-file: a plan that is mostly
one-line changes is still a single Coder delegation call, not an excuse to
apply each line yourself because individually each looks trivial.

The only edits you make directly on a unit's code are:

1. A unit you tiered **Trivial** at step 1 (see "Unit tiers") — no logic
   decision behind the change. Trivial is a tier you assigned *before*
   implementing and wrote into the checkpoint, not a conclusion you reach
   with the edit already drafted. If you didn't tier it Trivial before you
   started, it isn't Trivial now.
2. A correction to something the Coder's own diff got subtly wrong, where
   the correction itself passes the same Trivial test. Anything larger goes
   back to the Coder with the finding attached.
3. Work outside the Coder role's scope entirely: progress files, this
   repo's delegation config, local git operations.

That is the whole list, and it is the only definition of "small enough" in
this file — the Gate, "Do NOT delegate", and step 5 all point here rather
than each carrying their own threshold. If you catch yourself editing source
files for a unit without having made a Coder call first, that is the failure
this gate exists to catch — stop and delegate instead of finishing the edit.

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

## Macro-Delegation

Both bridges have high-capacity context (Antigravity/Gemini: 1M–2M tokens;
Codex: 128k+ tokens). Package a whole plan plus every file it touches into a
single high-payload call rather than fragmenting into single-file requests.

Every call to Antigravity must specify `model: "Gemini 3.6 Flash"`
explicitly (do not rely on a default — see Setup for why), plus, depending
on which role it's playing:

- **Document Analyzer:** every doc/spec/PRD relevant to the unit in one
  call (`cwd` set to project root) and the exact requirement question to
  answer.
- **Coder:** the full implementation plan (from step 1), the Touch list, and
  every file/directory it covers, plus acceptance criteria — what "done"
  looks like, including the exact command that proves it. Ask for the
  **execution report** back (commands run, exit codes, tail of any failure);
  that report is what step 3 checks against, so requesting it is what keeps
  step 3 a review rather than a re-run.
- **Release Writer:** the final diff and the plan it implements.

Every call to `codex-qa` or `codex-security` must specify:
1. The diff (or the touched files, if the diff alone lacks context) plus the
   original plan/acceptance criteria it's being checked against.
2. The specific question: QA gets "does this work, what breaks it"; Security
   gets "what's exploitable here."
3. Request **structured findings with `file:line` citations** — a
   pass/fail-style table, not prose.
4. Request a **coverage statement**: which files/functions it actually
   examined and which acceptance criterion each maps to. Without this a
   clean pass is unverifiable (see "Verification") — and asking for it up
   front costs one line in the prompt, versus you reconstructing the same
   thing by hand afterwards.

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
into both `.claude/skills` and `.agents/skills` (see `templates/AGENTS.md`).
You (Claude Code) and Antigravity trigger these natively — same file
format, same description-matching mechanism. Codex cannot: it has no
per-task skill loader, so before a `codex-qa`/`codex-security` call, check
whether a skill in `skills/` matches what you're asking it to do and, if
so, paste that skill's markdown body into the prompt yourself. Note in the
checkpoint which skill (if any) was pasted into a Codex call, since Codex
won't have discovered it on its own.

## Optional second opinion on your plan

Antigravity also exposes `adversarial_review`. Before handing a
high-stakes plan to Antigravity for implementation (architecture-level
change, risky refactor, anything security-sensitive by nature of the
task, not just the code), you may run `adversarial_review` on the plan
itself as a pre-implementation sanity check. This is optional and sits
before step 2 of the pipeline — it does not replace the QA/Security pass
in step 4, which is mandatory for every unit regardless of stakes.

## Do NOT delegate

This list is deliberately narrow — do not stretch it to cover a unit that
just feels small:

- A unit tiered **Trivial** at step 1 (see "Unit tiers" and "Gate" — that
  tier is the single definition of "small enough", assigned in writing
  before implementation, not decided at the moment you reach for Edit).
- A question fully answered by context already loaded in this conversation
  (no new code, no new investigation).
- An action that needs a tool, permission, or piece of session state only
  you have (local git commands, editing the progress file itself, editing
  this delegation config).

If it's ambiguous whether something qualifies, delegate it. The cost of an
unnecessary Antigravity round-trip is small; the cost of an unreviewed diff
shipping outside the Coder → Review → QA/Security pipeline is the entire
point of this setup.

## Example delegation prompts

Antigravity `analyze_files` (Document Analyzer):
> Ingest `docs/billing-spec.md`, `docs/refund-policy.md`, and the linked
> PRD under `docs/prd/refund-idempotency.md`. Question: what are the
> concrete, testable requirements for idempotent refund processing? Output:
> a requirement matrix — requirement, source `file:line` citation, and any
> open question the spec doesn't resolve. model: "Gemini 3.6 Flash".
> cwd: /path/to/repo

Antigravity `delegate` (Implementation):
> Plan: add idempotency key checking to `post_invoice` in `src/billing/refund.py`
> per the acceptance criteria below. Touch: `src/billing/refund.py`,
> `src/common/retry.py`, `tests/billing/test_refund_idempotency.py`.
> Acceptance criteria: `test_refund_idempotency` passes under concurrent
> retries; no new ledger entry without a committed invoice row. Proof
> command: `pytest tests/billing/test_refund_idempotency.py`. Report back:
> the commands you ran, their exit codes, and the tail of any failing
> output. Stay inside the Touch list — if you need a file outside it, say
> which and why rather than editing it silently.
> model: "Gemini 3.6 Flash". cwd: /path/to/repo

`codex-qa` `codex` (QA pass):
> Diff: <paste diff>. Original plan/acceptance criteria: <paste from step 1>.
> Question: does this satisfy the acceptance criteria? What edge cases or
> regressions does it miss? Output: (a) pass/fail table with `file:line`
> citations for each finding, and (b) a coverage statement — which
> files/functions you actually examined, mapped to the acceptance criterion
> each one covers. If you find nothing, (b) is the only evidence I have that
> the pass was real, so it is not optional.

`codex-security` `codex` (Security pass):
> Diff: <paste diff>. Question: what's exploitable here — injection, auth
> bypass, unsafe deserialization, secret handling, race conditions with
> security impact? Output: (a) severity-ranked findings table with
> `file:line` citations, and (b) a coverage statement — which
> files/functions you examined and which attack surface each was checked
> against. A clean report without (b) will be recorded as unverified.

Antigravity `delegate` (Release Writer):
> Diff: <paste accepted diff>. Plan/acceptance criteria it implements:
> <paste from step 1>. Draft: a changelog entry (one or two lines, user-
> facing framing) and any doc updates the diff makes stale. Output: the
> drafted text plus a list of files it should replace/append to — I will
> review and commit it myself. model: "Gemini 3.6 Flash".

## Parallelism, failures, and verification

- **QA and Security always run in parallel** on the same diff — they're
  independent servers with no shared state.
- **On bridge failure** (timeout, disconnect, unusable output): retry once.
  On a second failure, do the check yourself (there is no same-role
  fallback bridge in this pipeline — each role is single-sourced) and
  record the failure in the progress file so the next session knows that
  role was skipped for this unit.
- **Verification is two checks, both deliberately cheap** — you are
  evaluating the team's output, not redoing it:
  1. **Findings** get `file:line` citations, demanded in every QA/Security
     prompt; spot-check one or two before recording. A citation that doesn't
     resolve invalidates that *whole* report — request it again rather than
     keeping the findings you happened to like.
  2. **Clean passes don't verify themselves.** A pass with no findings is
     the highest-risk output in this pipeline and the cheapest to produce
     without doing the work, and citation spot-checks can't touch it —
     there's nothing to cite. Accept one only with the coverage statement
     step 4 requires (files/functions examined, mapped to acceptance
     criteria), checked against the diff's own file list. A clean pass that
     doesn't name the files the diff actually touched is UNVERIFIED.
- Anything recorded UNVERIFIED must not be the sole basis for shipping a
  unit. Remember Antigravity truncates output (~50k chars) — always request
  structured findings, never content dumps.

## Orchestration rules (project-specific, layered on top of the above)

- **One direction only.** You (Claude Code) always call Antigravity,
  `codex-qa`, and `codex-security`. Never configure or invoke a path where
  any bridge calls Claude Code or another bridge.
- **Checkpoint the progress file after every pipeline step.** Immediately
  after Analyze, Implement, Review, QA, Security, or Release Notes completes
  and you've verified the result, update the active `review-<topic>.md`
  progress file (see `templates/review-topic-template.md`) with: which step,
  which role (spell out the Antigravity role — Analyzer/Coder/Release
  Writer — since all three share one server in the tally), the returned
  session/thread id, and the verified outcome. Do this before starting the
  next unit of work. Record the unit's **tier**, the **scope-check** result,
  and the **acceptance-criteria command + exit code** you re-ran — those
  three are what make the checkpoint auditable by the next session.
- **Compaction is a boundary you mark, not a command you run.** `/compact`
  and `/clear` are the user's to type — you cannot invoke them yourself, so
  don't write as if you will. What you *can* do is make the boundary safe
  and name it: once a unit is checkpointed, say plainly that this is a clean
  compaction point and that the progress file — not conversation history —
  carries state across it. If context gets compacted automatically instead,
  that same checkpoint discipline is what makes it survivable.
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
- **Self-audit before marking a unit SELESAI.** Three questions, answered
  against your own tool calls for this unit, not from memory of intent:
  1. Did Edit/Write/NotebookEdit touch source files without a prior
     Coder-role call for that change? That's a gate violation (see "Gate").
  2. For a Standard or High-stakes unit: did **both** QA and Security run,
     and is each recorded VERIFIED rather than UNVERIFIED? A zero count for
     either on a SELESAI unit is a violation, not an oversight.
  3. Is the acceptance-criteria command and its exit code in the checkpoint?
  Record any "no" in the progress file rather than letting it pass silently,
  same as any other failed-approach entry. A unit that fails 2 does not get
  marked SELESAI — it goes back to step 4.
