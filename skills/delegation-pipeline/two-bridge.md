# Two-bridge mode deltas

Read this alongside `SKILL.md` when this project runs two-bridge mode (no
`codex-qa`/`codex-security` registered — `CLAUDE.md` carries the two-bridge
overlay). It replaces step 4 and overrides the QA/Security material in
`SKILL.md`; everything else in `SKILL.md` (steps 0–3, 6, Macro-Delegation for
Analyzer/Coder/Release Writer, Shared skills, the optional second opinion,
Orchestration rules) applies unchanged.

## Step 4 replacement — QA + Security lenses, sequentially

**QA + Security lenses, sequentially** (`antigravity`, `adversarial_review`).
Antigravity is one server/process — these two calls cannot run concurrently
the way `codex-qa`/`codex-security` did. Run QA framing first, then Security
framing, each as its own fresh session (not a `follow_up` of each other or of
the Coder session) so one framing doesn't bias the other's findings.

## Model exception

Every other Antigravity call still specifies `model:` set to the Antigravity
pin explicitly. The QA and Security lens calls are the one exception: they use
`adversarial_review` and let its own model chain apply (Gemini 3.1 Pro high →
Claude Opus 4.6 → Flash) — do not force the Antigravity pin onto those two
calls, that would defeat the point of using a different model chain than the
Coder role.

Every QA/Security lens call must specify:
1. The diff plus the original plan/acceptance criteria it's being checked
   against.
2. The specific framing: QA gets "does this work, what breaks it"; Security
   gets "what's exploitable here" — state the framing explicitly in the
   prompt each time, since both calls hit the same tool.
3. Request **structured findings with `file:line` citations** — a
   pass/fail-style table, not prose.

## Example delegation prompts (QA/Security lenses)

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

(Document Analyzer, Coder, and Release Writer prompts are identical to
`SKILL.md`'s examples.)

## Parallelism, failures, and verification — deltas

- **QA and Security lenses run sequentially**, not in parallel — they're
  the same server. Don't fire them concurrently; Antigravity's own session
  handling isn't built for that and you'd risk cross-talk between the two
  framings.
- **On bridge failure** (timeout, disconnect, unusable output): retry once.
  On a second failure, do the check yourself — there is no fallback bridge
  in two-bridge mode at all — and record the failure in the progress file.
- Verification bar (structured findings, `file:line` citations, spot-check
  before recording) is unchanged from `SKILL.md`.

## Checkpoint tally delta

Spell out which Antigravity role/lens each checkpoint entry is (Analyzer /
Coder / QA lens / Security lens / Release Writer) — all five share one server
in the tally, so a QA lens or Security lens count of 0 on a unit marked
SELESAI is a red flag the same way a missing QA/Security count would be in
three-bridge mode.
