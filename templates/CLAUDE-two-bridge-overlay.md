## Two-bridge mode (overlay)

Append this file to the bottom of a copy of `templates/CLAUDE.md` when only
two bridges are available — no Codex subscription, only Claude Code and
Antigravity. This project runs two-bridge mode: **do not install**
`openai/codex-plugin-cc`. Same pipeline shape, same checkpoint discipline,
but QA and Security no longer have a dedicated bridge each: both fold into
Antigravity, run as two separately-framed, separately-pinned, backgrounded
`agy_run` calls instead of two `codex:codex-rescue` calls.

### Role table override

Replace the QA Engineer and Security Engineer rows from the core `CLAUDE.md`
Roles table with:

| Role | Bridge (MCP server) | Model | Job |
|---|---|---|---|
| QA (lens) | `antigravity` | QA lens pin (see `skills/delegation-pipeline/two-bridge.md`, "Model pins") — not the Antigravity pin | Reviews the diff for correctness/edge cases/regressions, framed explicitly as a QA pass |
| Security (lens) | `antigravity` | Security lens pin (different model family from the QA lens pin) — not the Antigravity pin | Reviews the diff for exploitable issues, framed explicitly as a security pass |

### Why this is weaker, and what compensates

The three-bridge pipeline's QA/Security value came from two independent
things: a different model family reviewing the code (not the one that
wrote it), and two *separate* reviewers with no shared blind spot between
them. Explicit per-lens pins let two-bridge mode keep both, if you choose
pins from genuinely different model families (the templates default to
one Google model and one Anthropic model) — that is a real improvement
over the old `adversarial_review` chain, which always resolved both lenses
to the same model and so never gave you the second property at all.

What explicit pins do **not** fix: all three roles — Coder, QA lens,
Security lens — still run through one `agy` account, one CLI, one process
family. If that account's quota is exhausted, the underlying model
provider has an outage, or `agy` itself is broken, all three fail
together. Three-bridge mode doesn't have this exposure, because Codex runs
on entirely separate vendor infrastructure with its own quota. That
shared-infrastructure risk is the part of "weaker than three-bridge" that
no model-pin choice compensates for.

Given that, your own Review step (step 3) still carries more weight than
in three-bridge mode, but for a narrower reason than before: not because
the lenses share a blind spot with the Coder (they may not, if pinned to a
different family), but because a single infrastructure failure can take
out your only two independent checks at once. Don't treat a clean QA/
Security pass as proof the account itself was healthy when they ran it.

### Pipeline mechanics

The step-4 replacement, the model exception, example prompts, and the
parallelism/failure/verification deltas live in
`skills/delegation-pipeline/two-bridge.md` — load it alongside
`skills/delegation-pipeline/SKILL.md` for any unit in this project. Steps
0–3 and 6 are unchanged from the core skill.

### Upgrading back to three-bridge mode

If a Codex subscription becomes available later: delete this overlay from
the bottom of `CLAUDE.md`, delete `skills/delegation-pipeline/two-bridge.md`,
and install `openai/codex-plugin-cc` per `docs/SETUP.md`.
Nothing about steps 0–3 or 6 changes — only step 4 moves from two `agy_run`
lens calls to two `codex:codex-rescue` calls (QA pin, then Security pin).
