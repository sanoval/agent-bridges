@AGENTS.md

# Delegation rules: two-bridge mode (Analyze → Plan/Review → Coder → QA + Security → Release)

The import line above pulls in this project's shared memory — see
`templates/AGENTS.md` for what belongs there instead of here. Antigravity
reads `AGENTS.md` natively too, no symlink needed; nothing below this
point needs duplicating into either file.

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
things: a different model reviewing the code than the one that wrote it, and
two *separate* reviewers with no shared blind spot.

In two-bridge mode you keep the first — `adversarial_review`'s chain leads
with Gemini 3.1 Pro, a different model than the Coder role's Gemini 3.6
Flash — but you lose the second outright. Both lenses are the same tool, on
the same server, dispatched through the same chain in the same order,
separated only by the framing text you write. That is one reviewer asked two
questions, not two reviewers: a blind spot in the chain's lead model is
present in both passes, and the Claude Opus 4.6 step only enters when the
lead fails, so you cannot count on it being the reviewer at all on any given
call.

This means your own Review step (step 3) is no longer just "catch what you
wouldn't want QA/Security to have to find" — it is the only check in the
pipeline that isn't Antigravity reviewing Antigravity's own work. Treat it
accordingly: read the diff as if no downstream check exists, not as a
first pass before a second opinion. The mechanical checks in step 3 (scope
and evidence) matter more here than in three-bridge mode for the same
reason — they're the part of the review that doesn't depend on a model
catching what another model missed.

## How you supervise: monitor, don't redo

You are the lead, not the whole team. Three rules follow from that, and they
outrank any instinct to just handle it yourself:

- **Delegate by role, not by size.** If a change is the Coder role's job it
  goes to the Coder even when you could type it faster. Size is not a reason;
  see "Unit tiers" for the one exception and "Gate" for how it's bounded.
- **Trust the team, verify mechanically.** Your review is an evaluation pass,
  not a re-implementation. You re-run one command, you diff one file list,
  you spot-check a citation or two — you do not re-derive a bridge's
  reasoning to satisfy yourself it was right. Send the doubt back to the
  bridge instead.
- **Push work down, keep judgment.** Anything a bridge can hand you as
  evidence — commands run, exit codes, which acceptance criterion each
  finding maps to — is *requested in the delegation prompt*, not
  reconstructed by you afterwards. What stays yours: the plan, the
  reconciliation, the decision to ship.

This matters more in two-bridge mode, not less. Step 3 being the primary
defense is an argument for *sharper mechanical checks*, not for you
personally re-doing the QA and Security lenses' work in your own context —
that road ends with you as the bottleneck for a pipeline built so you
wouldn't be.

## Unit tiers

Same tiering as the three-bridge template. Tier is assigned **at step 1, in
writing, before any implementation** — by input shape and risk, never by
"this feels small" in the moment.

| | Trivial | Standard | High-stakes |
|---|---|---|---|
| What it is | No logic decision behind it: typo, comment, version bump, generated-file refresh | Any change to behavior, logic, data, config, or tests | Architecture change, risky refactor, auth/crypto/payments/PII surface, data migration |
| 0 Analyze | skip | only if the unit starts from a spec/PRD/doc | required |
| 1 Plan | one line in the checkpoint | required | required, plus optional `adversarial_review` on the plan |
| 2 Implement | you may edit directly | Coder | Coder |
| 3 Review | scope check only | required | required |
| 4 QA + Security lenses | skip | **both, always** | **both, always** |
| 5 Reconcile | — | required | required |
| 6 Release notes | skip | if user-facing | required |

Both lenses are mandatory at Standard and High-stakes. They're sequential
here, so skipping one saves real wall-clock time — which is exactly why the
rule has to be absolute rather than left to judgement under time pressure.

## Pipeline

0. **Analyze** (`antigravity`, Document Analyzer role, model
   `Gemini 3.6 Flash`). Same as the three-bridge template — ingest
   specs/PRDs/docs into a requirement matrix before planning. Skip for
   units with no doc input.
1. **Plan** (you). Same as the three-bridge template: Touch list, acceptance
   criteria, the exact command that proves the unit works, and the tier.
2. **Implement** (`antigravity`, Coder role, model `Gemini 3.6 Flash`).
   Same as the three-bridge template — new session, not a continuation of
   the Analyze session, and require the **execution report** back (commands
   run, exit codes, tail of any failing output).
3. **Review** (you). This is now the pipeline's primary defense, not a first
   pass — see "Why this is weaker" above. Two mechanical checks, then read:
   a. **Scope check.** `git diff --name-only` against the plan's Touch list.
      A file outside the list is a rejection by default, not a judgement
      call, unless the Coder's report explains it and you accept the reason.
   b. **Evidence check.** Re-run **the one** acceptance-criteria command from
      step 1 and read its exit code. One command, not the whole suite — you
      are confirming the Coder's report, not reproducing it. A claim of green
      with no command you can re-run is UNVERIFIED and does not advance.
   c. **Read the diff** as if no downstream check exists.
   Reject back to the Coder if any of the three fails. **Bounded:** two
   rejected Coder attempts on the same plan means the plan is the problem —
   stop, return to step 1, and log both attempts in the progress file's
   "Pendekatan yang sudah dicoba & gagal" section. No third round, and no
   quietly finishing it yourself instead.
4. **QA + Security lenses, sequentially** (`antigravity`,
   `adversarial_review`). Antigravity is one server/process — these two
   calls cannot run concurrently the way `codex-qa`/`codex-security` did.
   Run QA framing first, then Security framing, each as its own fresh
   session (not a `follow_up` of each other or of the Coder session) so one
   framing doesn't bias the other's findings. Both must report **what they
   examined, not only what they found**: files/functions actually read,
   mapped to acceptance criteria. A clean pass without that coverage
   statement does not verify itself — see "Verification".
5. **Reconcile** (you). Merge both lenses' findings; fix by sending back to
   Antigravity with the finding attached, unless the fix is Trivial by the
   "Unit tiers" test. When the lenses disagree, resolve by this order rather
   than re-litigating per unit:
   1. A Security finding rated exploitable outranks a QA priority call.
   2. A finding whose citation you spot-checked outranks one without.
   3. Anything still unresolved after those two **blocks the unit** and
      becomes a gap-list entry — not a tie for you to break quickly so the
      unit can move.
6. **Release notes** (`antigravity`, Release Writer role, model
   `Gemini 3.6 Flash`). Same as the three-bridge template.

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
4. Request a **coverage statement**: which files/functions it actually
   examined and which acceptance criterion each maps to. Without this a
   clean pass is unverifiable (see "Verification") — and asking costs one
   line in the prompt, versus you reconstructing it by hand afterwards.

## Session continuity

- Antigravity: `follow_up` with the `session_id` returned, **only within
  the same role**. Analyze, Coder, QA lens, Security lens, and Release
  Writer are five unrelated conversations sharing one server — always start
  a fresh call when the pipeline moves to a different role, and always
  start fresh between the QA lens and Security lens calls specifically
  (never `follow_up` one into the other).

## Shared skills

This project's custom skills live in `skills/<name>/SKILL.md`, symlinked
into both `.claude/skills` and `.agents/skills` (see `templates/AGENTS.md`).
Both you (Claude Code) and Antigravity trigger these natively — same file
format, same description-matching mechanism, no workaround needed in
two-bridge mode since there's no Codex to leave out.

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

Antigravity `adversarial_review` (QA lens):
> Diff: <paste diff>. Original plan/acceptance criteria: <paste from step 1>.
> Framing: you are a QA engineer. Question: does this satisfy the
> acceptance criteria? What edge cases or regressions does it miss? Output:
> (a) pass/fail table with `file:line` citations for each finding, and (b) a
> coverage statement — which files/functions you actually examined, mapped
> to the acceptance criterion each one covers. If you find nothing, (b) is
> the only evidence I have that the pass was real, so it is not optional.

Antigravity `adversarial_review` (Security lens):
> Diff: <paste diff>. Framing: you are a security engineer. Question:
> what's exploitable here — injection, auth bypass, unsafe
> deserialization, secret handling, race conditions with security impact?
> Output: (a) severity-ranked findings table with `file:line` citations, and
> (b) a coverage statement — which files/functions you examined and which
> attack surface each was checked against. A clean report without (b) will
> be recorded as unverified.

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
- **Verification is two checks, both deliberately cheap** — you are
  evaluating the lenses' output, not redoing it:
  1. **Findings** get `file:line` citations, demanded in every lens prompt;
     spot-check one or two before recording. A citation that doesn't resolve
     invalidates that *whole* report — request it again rather than keeping
     the findings you happened to like.
  2. **Clean passes don't verify themselves.** A pass with no findings is
     the highest-risk output in this pipeline and citation spot-checks can't
     touch it — there's nothing to cite. Accept one only with the coverage
     statement step 4 requires (files/functions examined, mapped to
     acceptance criteria), checked against the diff's own file list. A clean
     pass that doesn't name the files the diff touched is UNVERIFIED. This
     bites harder in two-bridge mode: both lenses can come back clean for
     the same reason, since it's the same chain twice.
- Anything recorded UNVERIFIED must not be the sole basis for shipping a
  unit. Antigravity truncates output (~50k chars) — always request
  structured findings, never content dumps.

## Orchestration rules (project-specific, layered on top of the above)

- **One direction only.** You (Claude Code) always call Antigravity. Never
  configure or invoke a path where Antigravity calls back into Claude Code.
- **Checkpoint the progress file after every pipeline step**, same as the
  three-bridge template — spell out which Antigravity role/lens each entry
  is (Analyzer / Coder / QA lens / Security lens / Release Writer), since
  all five share one server in the tally. Record the unit's **tier**, the
  **scope-check** result, and the **acceptance-criteria command + exit
  code** you re-ran.
- **Compaction is a boundary you mark, not a command you run.** `/compact`
  and `/clear` are the user's to type — you cannot invoke them yourself.
  Once a unit is checkpointed, say plainly that this is a clean compaction
  point and that the progress file carries state across it.
- **Checkpoint after every major decision.** Same as the three-bridge
  template.
- **On session start (fresh context or post-compaction):** read the
  relevant `review-<topic>.md` first, same as the three-bridge template.
- **Keep the progress file lean.** Same as the three-bridge template.
- **Self-audit before marking a unit SELESAI.** Three questions, answered
  against your own tool calls for this unit, not from memory of intent:
  1. Did Edit/Write/NotebookEdit touch source files without a prior
     Coder-role call for that change? That's a gate violation (see "Gate").
  2. For a Standard or High-stakes unit: did **both** lenses run, in
     separate sessions, and is each recorded VERIFIED rather than
     UNVERIFIED? A zero count for either on a SELESAI unit is a violation,
     not an oversight.
  3. Is the acceptance-criteria command and its exit code in the checkpoint?
  Record any "no" in the progress file rather than letting it pass silently.
  A unit that fails 2 does not get marked SELESAI — it goes back to step 4.

## Upgrading back to three-bridge mode

If a Codex subscription becomes available later, switch back to
`templates/CLAUDE.md` and register `codex-qa`/`codex-security` per its
Setup section. Nothing about steps 0–3 or 6 changes — only step 4 moves
from two `adversarial_review` lens calls to two independent MCP servers.
