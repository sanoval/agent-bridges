@AGENTS.md

# Delegation rules: two-bridge mode (Analyze → Plan/Review → Coder → QA + Security → Release)

The import line above pulls in this project's shared memory — see
`templates/AGENTS.md` for what belongs there instead of here. Antigravity
reads the same content via a `GEMINI.md` symlink to `AGENTS.md`; nothing
below this point needs duplicating into either file.

Use this variant instead of `templates/CLAUDE.md` when only two bridges are
available — no Codex subscription, only Claude Code and Antigravity. Same
pipeline shape, same checkpoint discipline, but QA and Security no longer
have a dedicated bridge each: both fold into Antigravity, run as two
separately-framed `adversarial_review` passes instead of two independent
MCP servers. Read "Why this is weaker, and what compensates" below before
using this — it changes what your own Review step (step 3) has to catch.

| Role | Bridge (MCP server) | Model | Job |
|---|---|---|---|
| Document Analyzer | `antigravity` | Gemini 3.6 Flash | Ingests specs/PRDs/docs before planning and produces a requirement matrix |
| Planner & Code Reviewer | You (Claude Code) | Chosen by you, per plan — no fixed pin | Plan the work from the requirement matrix, hand it to Antigravity to implement, then review the resulting diff — this is now the primary backstop, not just a first pass |
| Coder / Executor | `antigravity` | Gemini 3.6 Flash | Implements the plan: writes/edits code, runs it, iterates until it works |
| QA (lens) | `antigravity` | `adversarial_review` model chain (Gemini 3.1 Pro high → Claude Opus 4.6 → Flash) | Reviews the diff for correctness/edge cases/regressions, framed explicitly as a QA pass |
| Security (lens) | `antigravity` | `adversarial_review` model chain (Gemini 3.1 Pro high → Claude Opus 4.6 → Flash) | Reviews the diff for exploitable issues, framed explicitly as a security pass |
| Release / Changelog Writer | `antigravity` | Gemini 3.6 Flash | Turns the accepted diff + plan into changelog/doc updates once you've shipped the unit |

## Why this is weaker, and what compensates

The three-bridge pipeline's QA/Security value came from two independent
things: a different model family reviewing the code (not the one that
wrote it), and two *separate* reviewers with no shared blind spot. In
two-bridge mode you keep the first (`adversarial_review`'s chain leads with
Gemini 3.1 Pro, a different model than the Coder role's Gemini 3.6 Flash,
with Claude Opus as a fallback) but lose the second — both lenses ultimately
come from the same vendor's model family behind one server, so a systemic
blind spot in that family isn't caught by running it twice with different
framing.

This means your own Review step (step 3) is no longer just "catch what you
wouldn't want QA/Security to have to find" — it is the only check in the
pipeline that isn't Antigravity reviewing Antigravity's own work. Treat it
accordingly: read the diff as if no downstream check exists, not as a
first pass before a second opinion.

## Pipeline

0. **Analyze** (`antigravity`, Document Analyzer role, model
   `Gemini 3.6 Flash`). Same as the three-bridge template — ingest
   specs/PRDs/docs into a requirement matrix before planning. Skip for
   units with no doc input.
1. **Plan** (you). Same as the three-bridge template.
2. **Implement** (`antigravity`, Coder role, model `Gemini 3.6 Flash`).
   Same as the three-bridge template — new session, not a continuation of
   the Analyze session.
3. **Review** (you). Read the diff yourself. This is now the pipeline's
   primary defense, not a first pass — see "Why this is weaker" above.
   Reject/send back to Antigravity if the diff doesn't match the plan or if
   anything looks wrong enough that you wouldn't want to ship it even
   before QA/Security run.
4. **QA + Security lenses, sequentially** (`antigravity`,
   `adversarial_review`). Antigravity is one server/process — these two
   calls cannot run concurrently the way `codex-qa`/`codex-security` did.
   Run QA framing first, then Security framing, each as its own fresh
   session (not a `follow_up` of each other or of the Coder session) so one
   framing doesn't bias the other's findings.
5. **Reconcile** (you). Same as the three-bridge template — merge both
   lenses' findings, fix or send back to Antigravity, resolve any
   disagreement yourself.
6. **Release notes** (`antigravity`, Release Writer role, model
   `Gemini 3.6 Flash`). Same as the three-bridge template.

## Claude subagents are not bridge delegation

Same rule as the three-bridge template: only `antigravity` calls run on a
separate vendor's quota. Reserve Claude subagents for work that needs a
tool, permission, or session state only Claude Code has.

## Macro-Delegation

Send the full plan/diff/doc set in a single high-payload call per role, same
as the three-bridge template. Every Antigravity call still specifies
`model: "Gemini 3.6 Flash"` explicitly, **except** the QA and Security lens
calls, which use `adversarial_review` and let its own model chain apply —
do not force `Gemini 3.6 Flash` on those two, that would defeat the point of
using a different model chain than the Coder role.

Every QA/Security lens call must specify:
1. The diff plus the original plan/acceptance criteria it's being checked
   against.
2. The specific framing: QA gets "does this work, what breaks it"; Security
   gets "what's exploitable here" — state the framing explicitly in the
   prompt each time, since both calls hit the same tool.
3. Request **structured findings with `file:line` citations** — a
   pass/fail-style table, not prose.

## Session continuity

- Antigravity: `follow_up` with the `session_id` returned, **only within
  the same role**. Analyze, Coder, QA lens, Security lens, and Release
  Writer are five unrelated conversations sharing one server — always start
  a fresh call when the pipeline moves to a different role, and always
  start fresh between the QA lens and Security lens calls specifically
  (never `follow_up` one into the other).

## Do NOT delegate

Trivial single-line edits, questions answered by already-loaded context, or
tasks needing local tools only you have.

## Example delegation prompts

Antigravity `adversarial_review` (QA lens):
> Diff: <paste diff>. Original plan/acceptance criteria: <paste from step 1>.
> Framing: you are a QA engineer. Question: does this satisfy the
> acceptance criteria? What edge cases or regressions does it miss? Output:
> pass/fail table with `file:line` citations for each finding.

Antigravity `adversarial_review` (Security lens):
> Diff: <paste diff>. Framing: you are a security engineer. Question:
> what's exploitable here — injection, auth bypass, unsafe
> deserialization, secret handling, race conditions with security impact?
> Output: severity-ranked findings table with `file:line` citations.

(Document Analyzer, Coder, and Release Writer prompts are identical to the
three-bridge template's examples — see `templates/CLAUDE.md`.)

## Parallelism, failures, and verification

- **QA and Security lenses run sequentially**, not in parallel — they're
  the same server. Don't fire them concurrently; Antigravity's own session
  handling isn't built for that and you'd risk cross-talk between the two
  framings.
- **On bridge failure** (timeout, disconnect, unusable output): retry once.
  On a second failure, do the check yourself — there is no fallback bridge
  in two-bridge mode at all — and record the failure in the progress file.
- **Verification is defined as:** every QA/Security lens prompt demands
  `file:line` citations; you spot-check one or two before recording the
  result. Claims without citations get recorded as *unverified* and must
  not be the sole basis for shipping a unit. Antigravity truncates output
  (~50k chars) — always request structured findings, never content dumps.

## Orchestration rules (project-specific, layered on top of the above)

- **One direction only.** You (Claude Code) always call Antigravity. Never
  configure or invoke a path where Antigravity calls back into Claude Code.
- **Checkpoint the progress file after every pipeline step**, same as the
  three-bridge template — spell out which Antigravity role/lens each entry
  is (Analyzer / Coder / QA lens / Security lens / Release Writer), since
  all five share one server in the tally.
- **Compact after checkpointing, before the next unit.** Same as the
  three-bridge template.
- **Checkpoint after every major decision.** Same as the three-bridge
  template.
- **On session start (fresh context or post-compaction):** read the
  relevant `review-<topic>.md` first, same as the three-bridge template.
- **Keep the progress file lean.** Same as the three-bridge template.

## Upgrading back to three-bridge mode

If a Codex subscription becomes available later, switch back to
`templates/CLAUDE.md` and register `codex-qa`/`codex-security` per its
Setup section. Nothing about steps 0–3 or 6 changes — only step 4 moves
from two `adversarial_review` lens calls to two independent MCP servers.
