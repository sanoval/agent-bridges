# Two-bridge mode deltas

Read this alongside `SKILL.md` when this project runs two-bridge mode (no
`openai/codex-plugin-cc` plugin installed — `CLAUDE.md` carries the
two-bridge overlay). It replaces step 4 and overrides the QA/Security
material in `SKILL.md`; everything else in `SKILL.md` (steps 0–3, 6,
Macro-Delegation for Analyzer/Coder/Release Writer, Shared skills, the
optional second opinion, Orchestration rules) applies unchanged.

## Step 4 replacement — QA + Security lenses, backgrounded and parallel

**QA + Security lenses** (`antigravity`, `agy_run`). Launch both as
backgrounded `agy_run` calls, one right after the other — each returns its
own `job_id` immediately, so you don't wait for one before starting the
other, the same independence-of-execution property three-bridge mode gets
from two separate `codex-companion.mjs task` calls. This is new: the old
blocking bridge forced these to run sequentially since one process
couldn't hold two calls open at once. Each call is `mode: "plan"` (read-only,
mechanically enforced) and its own fresh conversation (no
`conversation_id` shared with the other, or with the Coder session), so one
framing doesn't bias the other's findings.

**For an S-sized unit** (see `SKILL.md`, "Sizing a unit" — that section
applies unchanged in two-bridge mode), this is one combined `agy_run` call
instead of two — QA and Security questions asked in the same prompt, one
lens pin (the QA lens pin), one `job_id` to poll.

## Model pins (two-bridge lenses)

Every other Antigravity call specifies `model:` set to the Antigravity Fast pin
or Deep pin. The QA and Security lens calls are the exception — each gets its own pin,
added to your project's `CLAUDE.md` "Model pins" table:

| Pin | Example value | Applies to |
|---|---|---|
| QA lens pin | `gemini-3.1-pro-high` | Every two-bridge QA lens call |
| Security lens pin | `claude-opus-4-6-thinking` | Every two-bridge Security lens call |

Verify both IDs actually appear in your own `agy_run`'s `list_models`
output before relying on them — model availability is per-account, and the
values above are examples from one account, not a guarantee about yours.
Both pins must differ from the Antigravity pin, and from each other.
Picking genuinely different model families (not just different sizes of
the same family) is what gives the two lenses independent blind spots —
see "Why this is weaker" below for why that distinction matters and what
it doesn't fix.

Every QA/Security lens call must specify:
1. The diff plus the original plan/acceptance criteria it's being checked
   against.
2. The specific framing: QA gets "does this work, what breaks it"; Security
   gets "what's exploitable here" — state the framing explicitly in the
   prompt each time, since both calls hit the same tool.
3. Request **structured findings with `file:line` citations** — a
   pass/fail-style table, not prose.

## Example delegation prompts (QA/Security lenses)

Antigravity `agy_run` (QA lens):
> Diff: <paste diff>. Original plan/acceptance criteria: <paste from step 1>.
> Framing: you are a QA engineer. Question: does this satisfy the
> acceptance criteria? What edge cases or regressions does it miss? Output:
> pass/fail table with `file:line` citations for each finding.
> model: <QA lens pin>. mode: "plan".

Antigravity `agy_run` (Security lens):
> Diff: <paste diff>. Framing: you are a security engineer. Question:
> what's exploitable here — injection, auth bypass, unsafe
> deserialization, secret handling, race conditions with security impact?
> Output: severity-ranked findings table with `file:line` citations.
> model: <Security lens pin>. mode: "plan".

(Document Analyzer, Coder, and Release Writer prompts are identical to
`SKILL.md`'s examples.)

## Parallelism, failures, and verification — deltas

- **QA and Security lenses now run as backgrounded, concurrent `agy_run`
  jobs** (see "Step 4 replacement" above) — the same independence of
  execution three-bridge mode gets from two separate `codex-companion.mjs
  task` calls. They still share one underlying `agy` account and CLI process
  family with the Coder role — if that account's quota is exhausted or the
  CLI itself is unreachable, all three roles fail together, unlike
  three-bridge mode where Codex runs on entirely separate vendor
  infrastructure. See "Why this is weaker" below.
- **On bridge failure** (an `agy_run` job whose terminal state is `failed`,
  a wake reporting `failure_reason`, or unusable output): retry once with a
  fresh call (no `conversation_id`). On a second failure, do the check
  yourself — there is no fallback bridge in two-bridge mode at all — and
  record the failure in the progress file.
- Verification bar (structured findings, `file:line` citations, spot-check
  before recording) is unchanged from `SKILL.md`.

## Checkpoint tally delta

Spell out which Antigravity role/lens each checkpoint entry is (Analyzer /
Coder / QA lens / Security lens / Release Writer) — all five share one server
in the tally, so a QA lens or Security lens count of 0 on a unit marked
SELESAI is a red flag the same way a missing QA/Security count would be in
three-bridge mode.
