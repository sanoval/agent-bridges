# Usage

Setup (README/[SETUP.md](SETUP.md)) gets the pipeline installed and wired
in. This doc is the other half: what you, the human, actually do once
that's done — starting a unit, what happens automatically, what you're
expected to check yourself, and what a session looks like end to end.

If you haven't finished setup, stop here and go run
[SETUP.md](SETUP.md) → "Verifying it works" first — everything below
assumes `claude mcp list` already shows the bridges connected.

## The short version

You talk to Claude Code, same as always. You never call `antigravity`,
`codex-qa`, or `codex-security` yourself — Claude Code does, as the
Planner/Reviewer role in `templates/CLAUDE.md`. Your job is to give it a
unit of work and then do the two things only you can do: approve the Gate
prompt when it asks, and read the diff/findings it hands back before
telling it to keep going.

## Starting a unit of work

Just ask, in plain language, the way you would without this pipeline —
"add idempotency key checking to the refund endpoint," "fix the race
condition in the retry queue," "implement the CSV export from
`docs/export-spec.md`." Claude Code loads the `delegation-pipeline` skill
and runs the numbered pipeline from `SKILL.md`:

1. **Analyze** — only if you pointed it at a spec/PRD/doc. Skipped for a
   self-evident bug or an already-clear ask.
2. **Plan** — Claude Code breaks the task down itself; this step never
   leaves the conversation.
3. **Implement** — handed to Antigravity (Coder role). This is the step
   that actually writes code.
4. **Review** — Claude Code reads the resulting diff before anything else
   sees it.
5. **QA + Security** — sent to `codex-qa`/`codex-security` in parallel
   (or Antigravity's two `adversarial_review` lenses, in two-bridge mode).
6. **Reconcile** — findings get fixed or dispatched back to Antigravity.
7. **Release notes** — Antigravity drafts a changelog entry once the unit
   ships; you still review and commit it.
8. **Learn** — non-blocking; see "What happens automatically" below.

You don't need to name these steps yourself — describing the task is
enough to trigger the skill.

## What you'll be asked to do mid-run

- **The Gate prompt.** The moment Claude Code (not Antigravity) tries to
  `Edit`/`Write` a file that isn't a progress file, memory file, or config,
  the bundled `PreToolUse` hook stops it and shows you the Gate rule from
  `templates/CLAUDE.md`. This is the pipeline working correctly, not a
  bug — approve it only if the situation actually matches one of the
  three documented exceptions (tiny fix not worth round-tripping, a small
  correction to Antigravity's own diff, or work outside the Coder role's
  scope like a progress file). If you're unsure why it fired, ask Claude
  Code to explain before approving.
- **Reviewing what comes back.** Claude Code reviews the diff itself
  before QA/Security see it, and reconciles their findings afterward — but
  the pipeline's own verification bar (see `SKILL.md`, "Parallelism,
  failures, and verification") only requires spot-checking one or two
  `file:line` citations per pass, not every claim. Skim the diff and the
  findings table yourself for anything that matters to you specifically;
  don't treat "the pipeline ran" as equivalent to "I read the change."
- **Resolving disagreement.** If QA and Security findings conflict on
  priority, or Claude Code rejects an Antigravity diff and sends it back,
  that's recorded in the progress file's "Pendekatan yang sudah dicoba &
  gagal" section — worth reading if a unit is taking longer than expected.

## What happens automatically (you don't need to prompt for it)

- **Checkpointing.** After every pipeline step and every major decision,
  Claude Code updates the active `review-<topic>.md` file — which role
  ran, the session/thread id, and the verified outcome. You can open this
  file any time to see exactly where a unit stands without asking.
  Cross-session continuity relies on this file being read at the start of
  a fresh conversation, not on conversation history.
- **Learning (step 7).** Once a unit passes verification, the
  `learning-curator` skill classifies it as NOOP, MEMORY, PATCH_SKILL, or
  CREATE_SKILL. A MEMORY fact lands in `AGENTS.md` (strong evidence) or
  waits for your approval in `.agent-bridges/learning/pending/` (weaker
  evidence — check there periodically if you enabled this in setup step
  8). A learned skill goes to `~/.agents/skills/` and is never part of
  the project's git history. This never blocks or changes a unit's
  outcome, so you can ignore it entirely if you don't care to curate.

## A typical session, narrated

```
you:  Add idempotency key checking to post_invoice per docs/refund-idempotency.md
claude: (loads delegation-pipeline) → Analyze via Antigravity → drafts a plan → shows it to you
you:  looks right, go
claude: → Implement via Antigravity (Coder)
        [Gate prompt fires if Claude Code's own tools try to touch the diff directly]
you:  approve/deny based on which exception, if any, applies
claude: → reviews the diff → sends it to codex-qa + codex-security in parallel
        → reconciles findings, fixes what's flagged
        → checkpoints review-<topic>.md
you:  skim the diff and the findings table
claude: → drafts release notes via Antigravity
        → (non-blocking) runs learning-curator
you:  /compact, then start the next unit
```

## Two-bridge mode differences

If you're running without a Codex subscription (see README → "Which mode
do I need?"), step 4 above is two `adversarial_review` calls on the same
Antigravity server instead of two independent bridges — weaker
independence, since both lenses share a model family. Nothing about how
*you* interact with the pipeline changes; `two-bridge.md` inside the
`delegation-pipeline` skill only changes what Claude Code does internally.

## Troubleshooting

- **Gate never fires / fires on files it shouldn't.** Confirm the plugin
  is enabled for this project (`/plugin`) and, if you just changed
  something, restart Claude Code or open `/hooks` once — see SETUP.md
  "Verifying it works."
- **A bridge looks stuck.** Antigravity's first call in a session is slow
  (~40–50s cold start); later calls are faster. If a call genuinely times
  out, the pipeline's own rule is retry once, then Claude Code does the
  check itself and records the skip in the progress file — you shouldn't
  need to intervene manually.
- **Picking up a unit in a new session.** Just say so — "continue the
  refund-idempotency unit" is enough; Claude Code is expected to read the
  matching `review-<topic>.md` first rather than guessing from memory.

For *why* the pipeline is shaped this way (topology, session continuity
rules, memory sharing across harnesses), see
[ARCHITECTURE.md](ARCHITECTURE.md). For getting the bridges installed and
connected in the first place, see [SETUP.md](SETUP.md).
