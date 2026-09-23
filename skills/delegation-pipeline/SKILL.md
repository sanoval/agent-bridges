---
name: delegation-pipeline
description: Use when starting a unit of implementation work in this project, when delegating to the antigravity MCP bridge or the Codex QA/Security path (`codex-companion.mjs task`, called directly via Bash — not the `codex:codex-rescue` subagent), when composing a bridge prompt, when reviewing a diff a bridge produced, or when checkpointing a review-<topic>.md progress file. Carries the pipeline steps, payload contracts, session-continuity rules, example prompts, and checkpoint format for the fixed-role delegation pipeline defined in CLAUDE.md.
---

# Delegation pipeline mechanics

This skill is orchestrator-facing (Claude Code only) — it is never pasted
into a QA/Security Codex prompt; see "Shared skills" below for what does
get pasted there. If this project runs **two-bridge mode**
(no `openai/codex-plugin-cc` plugin installed — check whether your
`CLAUDE.md` carries the two-bridge overlay), also read `two-bridge.md` in
this directory: it replaces step 4 and the QA/Security material below.

The role table, the Gate, "Do NOT delegate", and the model pins referenced
throughout (Antigravity pin, QA pin, Security pin) live in `CLAUDE.md` — this
file assumes you've already read that.

## Sizing a unit

Decide this once, during step 1 (Plan), before delegating anything, and
record it in the checkpoint — it determines which steps below actually run
for this unit; a step not listed for a size is skipped outright, not just
abbreviated.

- **S** — a small, self-contained change with an obvious shape (one or two
  files, no new architecture decision, acceptance criteria you could state
  in one sentence). Runs: Plan (1) → Implement (2) → Review (3) → **one
  combined QA+Security pass** (4 — a single `codex-companion.mjs task` call
  covering both questions, rather than two separate ones) → Reconcile (5).
  No Analyze (0), no Release notes (6).
- **M** — the default for most units: a real feature or fix with more than
  one plausible approach, or acceptance criteria that need spelling out.
  Runs the full pipeline (0–7), except Analyze (0) stays conditional on
  having doc input to ingest, same rule as always.
- **L** — an architecture-level change, anything security-sensitive by
  nature of the task (not just by what the diff touches), or a unit built
  from a spec/PRD. Runs the full pipeline (0–7), and is the tier where
  "Optional second opinion on your plan" (below) is worth actually
  spending a call on before handing the plan to Antigravity.

Default to **M** when unsure. **S** is for changes you'd genuinely feel
silly running a 7-step pipeline over — not an excuse to skip QA/Security
scrutiny because a diff "looks small." If step 3 (Review) turns up more
than expected once you've started, upgrade the unit to M/L mid-flight and
note the upgrade (and why) in the checkpoint.

## Pipeline

0. **Analyze** (`antigravity`, Document Analyzer role, Antigravity pin).
   **Skipped outright for S-sized units** (see "Sizing a unit" above).
   When the unit starts from a spec/PRD/doc rather than a self-evident bug
   or already-clear ask, send Antigravity the full doc set via `agy_run`
   with `mode: "plan"` and ask for a structured requirement matrix
   (requirement → source citation → open questions). Skip this step
   for units with no doc input to ingest.
1. **Plan** (you). Decide the unit's size first (see "Sizing a unit"
   above) — it determines which steps below run. Then break the task into
   a concrete implementation spec: files/modules touched, the change
   itself, acceptance criteria — using the requirement matrix from step 0
   if there was one. This is your job alone — do not delegate planning to
   Antigravity or Codex.
2. **Implement** (`antigravity`, Coder role, Antigravity pin). Send the full
   plan plus every file/module it touches in one `agy_run` call with
   `mode: "accept-edits"` — see "Macro-Delegation" below. Antigravity does
   the actual edit/execution; `mode: "accept-edits"` is what makes this the
   one role allowed to touch files — every other role runs `mode: "plan"`.
   Start a **new** Antigravity conversation for this call rather than
   continuing the Analyze session — see "Session continuity" for why.
3. **Review** (you). Read the resulting diff yourself before it goes
   further. This is your Code Reviewer duty — catch anything you wouldn't
   want a QA/Security pass to have to discover for you, and reject/send
   back to Antigravity if the diff doesn't match the plan.
4. **QA + Security** (Codex, QA pin then Security pin, called directly via
   `Bash` — not the `codex:codex-rescue` subagent; see "Why direct Bash, not
   the subagent" below). Once you're satisfied with the diff, launch both
   as `--background` `codex-companion.mjs task` calls — see "Session
   continuity" below for why this is two backgrounded calls you poll, not
   two parallel foreground ones. QA checks correctness/edge cases/
   regressions; Security checks for exploitable issues. Neither sees the
   other's output. **For an S-sized unit, this is one combined call**
   instead — QA and Security questions asked in the same prompt, one
   `--model` (the QA pin), one job to poll — see "Sizing a unit" above.
5. **Reconcile** (you). Merge QA and Security findings. Anything either
   flags gets fixed (by you directly for small fixes, or sent back to
   Antigravity with the finding attached for larger ones) before you
   consider the unit done. Disagreement between QA and Security about
   priority is yours to resolve, not theirs.
6. **Release notes** (`antigravity`, Release Writer role, Antigravity pin).
   **Skipped outright for S-sized units** (see "Sizing a unit" above).
   Once a unit is accepted, send the final diff plus the plan to Antigravity
   via `agy_run` with `mode: "plan"` to draft the changelog entry / doc
   update. This is drafting only, and `mode: "plan"` makes that mechanical
   rather than a matter of asking nicely — you still review and commit it
   yourself, same as any other Antigravity output. Also a new conversation,
   not a continuation of the Coder session.
7. **Learn** (you — non-blocking, no bridge call). Once step 5 (Reconcile)
   confirms final verification passed, load the `learning-curator` skill
   (bundled in this plugin, alongside this one) and let it classify the unit as
   NOOP, MEMORY, PATCH_SKILL, or CREATE_SKILL from a compact trace of what
   you already verified. Order relative to step 6 doesn't matter — this
   never gates release. A curator failure never changes the unit's outcome;
   see that skill's "Failure handling".

Never let Antigravity call Codex directly, or vice versa — you are always
the one relaying the diff between roles. No bidirectional delegation, no
ping-pong.

## Macro-Delegation

Both bridges have high-capacity context (Antigravity/Gemini: 1M–2M tokens;
Codex: 128k+ tokens). Package a whole plan plus every file it touches into a
single high-payload call rather than fragmenting into single-file requests.

Every call to Antigravity is `agy_run` (or `agy_run_sync` if you're willing
to block up to its 10-minute cap for an inline result — prefer `agy_run` for
anything from the Coder role, since that's the payload most likely to run
long) and must specify:

- `model:` set to the Antigravity pin explicitly (do not rely on the
  bridge's own default-model setting as anything but a fallback — see
  `docs/SETUP.md` for why).
- `mode:` — `"plan"` for every role except Coder, `"accept-edits"` for
  Coder alone. This is what makes "read-only" a property the tool enforces,
  not just a convention you ask for in prose.
- `json_schema:` on any call whose output you'll parse or spot-check
  structurally (a requirement matrix, a findings table) — this bounds
  output by shape instead of by character count, so ask for the shape you
  actually want rather than trusting prose framing alone.

Plus, depending on which role it's playing:

- **Document Analyzer:** every doc/spec/PRD relevant to the unit in one
  call (`cwd` set to project root) and the exact requirement question to
  answer.
- **Coder:** the full implementation plan (from step 1) and every
  file/directory it touches, plus acceptance criteria — what "done" looks
  like, including any tests to run.
- **Release Writer:** the final diff and the plan it implements.

Every Codex QA/Security call is `node codex-companion.mjs task` (see "Why
direct Bash, not the subagent" for how to locate the script) and must
specify:
1. `--model` set to the relevant pin (QA pin or Security pin — see
   `CLAUDE.md` "Model pins"), passed as the literal pin value (e.g.
   `--model gpt-5.6-terra`) — `codex-companion.mjs` only aliases `spark`,
   so any other string, including a pin's human-readable name, is passed
   to Codex as-is and fails.
2. `--background` (large diffs; QA/Security payloads almost always
   qualify) and `--fresh` (never `--resume` — see "Session continuity").
3. **No `--write` flag.** Omitting it is what puts the run in
   `codex-companion.mjs`'s `read-only` sandbox — this is how "read-only" is
   enforced by the tool here, not by asking nicely in the prompt. Still add
   an explicit instruction in the prompt text too ("Review only. Do not
   propose edits as a diff.") as a second layer, but the sandbox flag is
   the actual enforcement.
4. The touched files and the base ref to diff against (e.g. "diff against
   `main`, cwd is the repo root") rather than a pasted diff — Codex runs
   inside the repo and can read the real working tree itself, which is
   cheaper and can't go stale against a diff you pasted earlier in the
   conversation. Paste the diff text only if the change isn't committed/
   stashed anywhere Codex's own `git diff` could see it.
5. The original plan/acceptance criteria it's being checked against.
6. The specific question: QA gets "does this work, what breaks it"; Security
   gets "what's exploitable here."
7. Request **structured findings with `file:line` citations** — a
   pass/fail-style table, not prose.

## Why direct Bash, not the subagent

QA and Security calls go through `node codex-companion.mjs task` directly
via the `Bash` tool — **not** the `codex:codex-rescue` subagent (`Agent`
tool, `subagent_type: "codex:codex-rescue"`), even though that subagent
wraps the same script. Two reasons:

- **Model and quota.** `codex:codex-rescue` is itself a Claude subagent
  (`model: sonnet` in its own frontmatter) that reads your prompt and then
  shells out to the script on your behalf. That read-and-forward step runs
  on Claude's quota and burns Claude context on the pasted diff before
  Codex ever sees it. Calling the script directly skips that hop entirely
  — the whole QA/Security pass runs on Codex's quota, not Claude's.
- **Sandbox enforcement.** The subagent's own instructions default to
  adding `--write` "unless the user explicitly asks for read-only," which
  makes the read-only guarantee depend on how your prompt text is phrased
  and how the subagent's model interprets it. Calling the script directly
  and simply never passing `--write` removes that dependency — the
  `read-only` sandbox (`codex-companion.mjs`'s own behavior: no `--write`
  → `sandbox: "read-only"`) is what the tool does, not what a middle model
  decided to do with your phrasing.

Locate the script once per session (it moves when the `openai-codex`
plugin updates, so don't hardcode a version):

```
find ~/.claude/plugins/cache/openai-codex -name codex-companion.mjs 2>/dev/null | sort -V | tail -1
```

Then invoke it as `node <that path> task ...`. The `codex:codex-rescue`
subagent remains fine to use *outside* this pipeline — ad hoc debugging
help, a second opinion mid-conversation — just not for the QA/Security
pipeline role, where the read-only guarantee matters.

## Session continuity

Each bridge is a separate MCP server process with its own session/thread
namespace — do not mix them up:

- Antigravity: pass the `conversation_id` a prior `agy_run` call returned,
  **but only for follow-ups within the same role**. Analyze, Coder, and
  Release Writer are unrelated conversations even though they share one
  server and one model — start a fresh call (omit `conversation_id`) when
  the pipeline moves from one role to the next, so Antigravity's context
  doesn't drag Document-Analyzer framing into a Coder call or vice versa.
  Only reuse `conversation_id` to continue the *same* role's work (e.g.
  Antigravity iterating on its own implementation after a test failure).
  `agy_run` also offers `continue_latest` as a "resume whatever I last ran"
  shortcut (mutually exclusive with `conversation_id`) — avoid it here for
  the same reason: it can silently pick up the wrong role's thread. Name
  the `conversation_id` explicitly instead of relying on "latest."
- QA and Security: launched via `node codex-companion.mjs task
  --background` (`openai/codex-plugin-cc` plugin's own script — see "Why
  direct Bash, not the subagent"; see `docs/SETUP.md` for install). It
  returns a job id immediately; poll it yourself with
  `node codex-companion.mjs status <job-id>` until done, then
  `node codex-companion.mjs result <job-id>` for the findings — these are
  the same commands the plugin's own `/codex:status` and `/codex:result`
  slash commands run, but call the script directly rather than going
  through those commands (they're `disable-model-invocation: true`, so
  you can't invoke them programmatically from inside a skill; typing them
  is a person's shortcut, not something you can trigger). QA's job id and
  Security's job id are unrelated — don't cross them. The script also
  offers `--resume-last` to continue the latest task thread for the repo
  — **always pass `--fresh` (i.e. omit `--resume-last`) for a QA or
  Security call**, since resuming would drag the other role's findings (or
  a prior unit's) into this one's context; only resume deliberately, if a
  QA/Security round genuinely needs to continue its own immediately-prior
  call in the same unit (rare — most rounds should be a fresh, fully
  self-contained call per "Macro-Delegation" above, since a resumed
  thread's earlier framing can bias a second look).

## Shared skills

`delegation-pipeline` and `learning-curator` ship inside the `agent-bridges`
plugin — Claude Code discovers them globally once the plugin is enabled,
they are never copied into a project's own `skills/` directory, and
Antigravity/Codex have no visibility into them at all (neither harness
reads Claude Code's plugin store). Both are orchestrator-facing and are
never pasted into a Codex call.

A project may still keep its *own* hand-authored skills at
`skills/<name>/SKILL.md`, symlinked into both `.claude/skills` and
`.agents/skills` (see `templates/AGENTS.md`) — that convention is unchanged
and is how you keep a project-specific skill visible to Antigravity too.
You (Claude Code) and Antigravity trigger those natively — same file
format, same description-matching mechanism. Codex cannot: it has no
per-task skill loader, so before a QA/Security Codex call, check whether a
skill in the project's `skills/` matches what you're asking it to do and,
if so, paste that skill's markdown body into the prompt text you pass to
`codex-companion.mjs task`. Note in the checkpoint which skill (if any)
was pasted into a Codex call, since Codex won't have discovered it on its
own.

## Optional second opinion on your plan

Before handing a high-stakes plan to Antigravity for implementation
(architecture-level change, risky refactor, anything security-sensitive by
nature of the task, not just the code), you may run the plan itself past
Antigravity as a pre-implementation sanity check — `agy_run`, `mode:
"plan"`, framing the prompt explicitly as an adversarial critique request
("find what's wrong with this plan before it's built," not "review this
code"). There is no dedicated review tool to reach for here — the critique
comes from what you ask for in the prompt, same as the QA/Security lens
framing in two-bridge mode. This is optional and sits before step 2 of the
pipeline — it does not replace the QA/Security pass in step 4, which is
mandatory for every unit regardless of stakes.

## Example delegation prompts

Antigravity `agy_run` (Document Analyzer):
> Ingest `docs/billing-spec.md`, `docs/refund-policy.md`, and the linked
> PRD under `docs/prd/refund-idempotency.md`. Question: what are the
> concrete, testable requirements for idempotent refund processing? Output:
> a requirement matrix — requirement, source `file:line` citation, and any
> open question the spec doesn't resolve. model: <Antigravity pin>.
> mode: "plan". cwd: /path/to/repo

Antigravity `agy_run` (Implementation):
> Plan: add idempotency key checking to `post_invoice` in `src/billing/refund.py`
> per the acceptance criteria below. Touch: `src/billing/refund.py`,
> `src/common/retry.py`, `tests/billing/test_refund_idempotency.py`.
> Acceptance criteria: `test_refund_idempotency` passes under concurrent
> retries; no new ledger entry without a committed invoice row.
> model: <Antigravity pin>. mode: "accept-edits". cwd: /path/to/repo

Codex QA pass (`Bash`, direct script call — no `--write`, so the run gets
`codex-companion.mjs`'s read-only sandbox):
> node codex-companion.mjs task --model gpt-5.6-terra --effort medium
> --background --fresh "Review only. Do not propose edits as a diff.
> Diff against main in this repo covers src/billing/refund.py,
> src/common/retry.py, tests/billing/test_refund_idempotency.py — read it
> yourself with git diff. Original plan/acceptance criteria: <paste from
> step 1>. Question: does this satisfy the acceptance criteria? What edge
> cases or regressions does it miss? Output: pass/fail table with
> file:line citations for each finding."

Codex Security pass (same mechanism, Security pin):
> node codex-companion.mjs task --model gpt-6-sol --effort medium
> --background --fresh "Review only. Do not propose edits as a diff.
> Diff against main in this repo covers src/billing/refund.py,
> src/common/retry.py, tests/billing/test_refund_idempotency.py — read it
> yourself with git diff. Question: what's exploitable here — injection,
> auth bypass, unsafe deserialization, secret handling, race conditions
> with security impact? Output: severity-ranked findings table with
> file:line citations."

Antigravity `agy_run` (Release Writer):
> Diff: <paste accepted diff>. Plan/acceptance criteria it implements:
> <paste from step 1>. Draft: a changelog entry (one or two lines, user-
> facing framing) and any doc updates the diff makes stale. Output: the
> drafted text plus a list of files it should replace/append to — I will
> review and commit it myself. model: <Antigravity pin>. mode: "plan".

## Parallelism, failures, and verification

- **QA and Security both run as `--background` jobs on the same diff**,
  launched one after the other — each returns its own job id immediately,
  so you poll/collect both (`node codex-companion.mjs status <job-id>`,
  then `result <job-id>`) rather than blocking on one before starting the
  other. They're independent `codex-companion.mjs task` invocations with
  no shared state or context between them.
- **On bridge failure:** for Codex, `status <job-id>` shows the job failed,
  timeout, or unusable output — retry once with `--fresh`. For Antigravity,
  the equivalent is an `agy_run` job whose terminal state is `failed`, a
  wake reporting `failure_reason` (e.g. `quota_exhausted`, with a reset
  window in `error`), or unusable output — retry once with a fresh call
  (no `conversation_id`). Either way: on a second failure, do the check
  yourself (there is no same-role fallback bridge in this pipeline — each
  role is single-sourced) and record the failure in the progress file so
  the next session knows that role was skipped for this unit.
- **Verification is defined as:** every QA/Security prompt demands
  `file:line` citations; you spot-check one or two of them before recording
  the result. Claims without citations get recorded as *unverified* and
  must not be the sole basis for shipping a unit. Antigravity has no fixed
  output-size cap here — use `json_schema` to force the shape of findings
  (a structured pass/fail table, not prose you hope stays on-format), same
  intent the old character-count truncation served, enforced differently.

## Orchestration rules (project-specific, layered on top of the above)

- **One direction only.** You (Claude Code) always call Antigravity and
  Codex. Never configure or invoke a path where any bridge calls Claude
  Code or another bridge.
- **Checkpoint the progress file after every pipeline step.** Immediately
  after Analyze, Implement, Review, QA, Security, or Release Notes completes
  and you've verified the result, update the active `review-<topic>.md`
  progress file (see `templates/review-topic-template.md`) with: which step,
  which role (spell out the Antigravity role — Analyzer/Coder/Release
  Writer — since all three share one server in the tally), the returned
  `job_id` (and `conversation_id` if a same-role follow-up is expected), and
  the verified outcome. Do this before starting the
  next unit of work. Step 7 (Learn) gets the same treatment — see
  `learning-curator/SKILL.md`'s "Checkpoint entry" for what to record; a
  NOOP outcome still gets a one-line entry.
- **Checkpoint after every major decision.** If you reject an Antigravity
  diff and send it back, or override a QA/Security finding, write it to the
  progress file's "Pendekatan yang sudah dicoba & gagal" section immediately,
  with the reason. A rejected Coder diff also increments the "Coder
  re-sends" counter at the top of the progress file (see
  `templates/review-topic-template.md`) — this is the running signal for
  whether the Antigravity pin is holding up across units, not just a
  per-unit note.
- **Record the unit's size at Plan time.** Per "Sizing a unit" above, write
  S/M/L into the unit's status block as soon as you decide it in step 1 —
  don't leave a future session to infer which steps ran from which
  `job_id`s are present.
- **Keep the progress file lean.** When a unit is SELESAI and no open gap
  references it, move its full section to `review-<topic>-archive.md` and
  leave a one-line summary behind.
- **Self-audit before marking a unit SELESAI.** Check your own tool calls
  for this unit: if Edit/Write/NotebookEdit touched source files without a
  prior Coder-role Antigravity call for that change, that's a gate
  violation (see `CLAUDE.md` "Gate") — record it in the progress file rather
  than letting it pass silently, same as any other failed-approach entry.
