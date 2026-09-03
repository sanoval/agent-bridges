## Two-bridge mode (overlay)

Append this file to the bottom of a copy of `templates/CLAUDE.md` when only
two bridges are available — no Codex subscription, only Claude Code and
Antigravity. This project runs two-bridge mode: **do not register**
`codex-qa`/`codex-security`. Same pipeline shape, same checkpoint discipline,
but QA and Security no longer have a dedicated bridge each: both fold into
Antigravity, run as two separately-framed `adversarial_review` passes instead
of two independent MCP servers.

### Role table override

Replace the QA Engineer and Security Engineer rows from the core `CLAUDE.md`
Roles table with:

| Role | Bridge (MCP server) | Model | Job |
|---|---|---|---|
| QA (lens) | `antigravity` | `adversarial_review` chain (Gemini 3.1 Pro high → Claude Opus 4.6 → Flash) — not the Antigravity pin | Reviews the diff for correctness/edge cases/regressions, framed explicitly as a QA pass |
| Security (lens) | `antigravity` | `adversarial_review` chain (same as above) — not the Antigravity pin | Reviews the diff for exploitable issues, framed explicitly as a security pass |

### Why this is weaker, and what compensates

The three-bridge pipeline's QA/Security value came from two independent
things: a different model family reviewing the code (not the one that
wrote it), and two *separate* reviewers with no shared blind spot. In
two-bridge mode you keep the first (`adversarial_review`'s chain leads with
Gemini 3.1 Pro, a different model than the Coder role's Antigravity pin,
with Claude Opus as a fallback) but lose the second — both lenses ultimately
come from the same vendor's model family behind one server, so a systemic
blind spot in that family isn't caught by running it twice with different
framing.

This means your own Review step (step 3) is no longer just "catch what you
wouldn't want QA/Security to have to find" — it is the only check in the
pipeline that isn't Antigravity reviewing Antigravity's own work. Treat it
accordingly: read the diff as if no downstream check exists, not as a
first pass before a second opinion.

### Pipeline mechanics

The step-4 replacement, the model exception, example prompts, and the
parallelism/failure/verification deltas live in
`skills/delegation-pipeline/two-bridge.md` — load it alongside
`skills/delegation-pipeline/SKILL.md` for any unit in this project. Steps
0–3 and 6 are unchanged from the core skill.

### Upgrading back to three-bridge mode

If a Codex subscription becomes available later: delete this overlay from
the bottom of `CLAUDE.md`, delete `skills/delegation-pipeline/two-bridge.md`,
and register `codex-qa`/`codex-security` per `docs/SETUP.md`.
Nothing about steps 0–3 or 6 changes — only step 4 moves from two
`adversarial_review` lens calls to two independent MCP servers.
