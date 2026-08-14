# Two-bridge overlay

Use this when only two bridges are available — no Codex subscription, only
Claude Code and Antigravity. It is an **overlay on `templates/CLAUDE.md`,
not a replacement for it**: copy the core template as usual, then apply the
two edits below. Everything the core says that isn't contradicted here —
the Gate, the "Do NOT delegate" list, the subagent rule, session-start
behaviour — applies unchanged and is not restated.

## Applying the overlay

1. In the core's **Bridges and model pins** table, delete the `codex-qa`
   and `codex-security` rows (those servers aren't registered) and add:

   | Bridge (MCP server) | Model pin | Roles it plays |
   |---|---|---|
   | `antigravity` via `adversarial_review` | chain: `Gemini 3.1 Pro high` → `Claude Opus 4.6` → `Flash` — the **lens chain**, applied by the tool itself | QA lens, Security lens |

   The lens chain is the one pin you never pass explicitly: `adversarial_review`
   applies it, and forcing the Antigravity pin onto those calls would defeat
   the point of reviewing with a different model than the Coder role used.

2. Append the section below to the copied `CLAUDE.md`.

---

## Two-bridge mode

QA and Security do not have a dedicated bridge each. Both fold into
Antigravity as two separately-framed `adversarial_review` passes. When the
`delegation-pipeline` skill loads, also read `two-bridge.md` from that
skill's directory — it carries the pipeline-level deltas (step 4, lens
prompts, sequential execution, session rules between lenses).

### Why this is weaker, and what compensates

The three-bridge pipeline's QA/Security value came from two independent
things: a different model family reviewing the code (not the one that
wrote it), and two *separate* reviewers with no shared blind spot. In
two-bridge mode you keep the first (the lens chain leads with a different
model than the Antigravity pin the Coder role runs on, with Claude Opus as
a fallback) but lose the second — both lenses ultimately come from the same
vendor's model family behind one server, so a systemic blind spot in that
family isn't caught by running it twice with different framing.

This means your own Review step (step 3) is no longer just "catch what you
wouldn't want QA/Security to have to find" — it is the only check in the
pipeline that isn't Antigravity reviewing Antigravity's own work. Treat it
accordingly: read the diff as if no downstream check exists, not as a first
pass before a second opinion.

### Upgrading back to three-bridge mode

If a Codex subscription becomes available later, remove this overlay
section, restore the two `codex-*` rows in the pin table, and register
`codex-qa`/`codex-security` per README Setup steps 2–3. Nothing about
pipeline steps 0–3 or 6 changes — only step 4 moves from two
`adversarial_review` lens calls to two independent MCP servers.
