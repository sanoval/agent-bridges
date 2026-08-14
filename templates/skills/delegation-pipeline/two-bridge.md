# Two-bridge deltas

Read this alongside `SKILL.md` when the project runs in two-bridge mode
(the `CLAUDE.md` two-bridge overlay is applied; no `codex-qa` /
`codex-security` rows in the pin table). It restates **only what changes**
— roles 0–3 and 6, Macro-Delegation payload contents, verification, and the
checkpoint rules are exactly as `SKILL.md` describes them.

## Roles that change

| Role | Bridge | Job |
|---|---|---|
| Planner & Code Reviewer | you | As in `SKILL.md`, but your Review pass is now the pipeline's primary backstop, not a first pass — see "Why this is weaker" in `CLAUDE.md` |
| QA lens | `antigravity` `adversarial_review` (lens chain) | Reviews the diff for correctness/edge cases/regressions, framed explicitly as a QA pass |
| Security lens | `antigravity` `adversarial_review` (lens chain) | Reviews the diff for exploitable issues, framed explicitly as a security pass |

## Pipeline step 4 (replaces the three-bridge step 4)

4. **QA + Security lenses, sequentially** (`antigravity`,
   `adversarial_review`). Antigravity is one server/process — these two
   calls cannot run concurrently the way `codex-qa`/`codex-security` did.
   Run QA framing first, then Security framing, each as its own fresh
   session (not a `follow_up` of each other or of the Coder session) so one
   framing doesn't bias the other's findings.

## Macro-Delegation

Same single high-payload call per role. Every Antigravity call still passes
the Antigravity pin explicitly, **except** the QA and Security lens calls —
those use `adversarial_review` and let the lens chain apply (see the pin
table).

Every QA/Security lens call must specify:
1. The diff plus the original plan/acceptance criteria it's being checked
   against.
2. The specific framing: QA gets "does this work, what breaks it"; Security
   gets "what's exploitable here" — state the framing explicitly in the
   prompt each time, since both calls hit the same tool.
3. Request **structured findings with `file:line` citations** — a
   pass/fail-style table, not prose.

## Session continuity

Antigravity: `follow_up` with the `session_id` returned, **only within the
same role**. Analyze, Coder, QA lens, Security lens, and Release Writer are
five unrelated conversations sharing one server — always start a fresh call
when the pipeline moves to a different role, and always start fresh between
the QA lens and Security lens calls specifically (never `follow_up` one
into the other). There are no Codex threads in this mode.

## Shared skills

No Codex means no paste-the-skill-body workaround: both you and Antigravity
trigger `skills/` natively.

## Example lens prompts

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

(Document Analyzer, Coder, and Release Writer prompts are unchanged — see
`SKILL.md`.)

## Parallelism and failures

- **QA and Security lenses run sequentially**, not in parallel — they're
  the same server. Don't fire them concurrently; Antigravity's own session
  handling isn't built for that and you'd risk cross-talk between the two
  framings.
- **On bridge failure:** retry once, then do the check yourself — there is
  no fallback bridge in two-bridge mode at all — and record the failure in
  the progress file.

## Checkpoints

Same discipline as `SKILL.md`, but spell out which of the five Antigravity
roles/lenses each entry is (Analyzer / Coder / QA lens / Security lens /
Release Writer), since all five share one server in the tally.
