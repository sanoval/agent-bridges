# Session notes ("notulen") — design spec (DRAFT)

Status: draft for discussion. Nothing here is implemented. Items marked
**UNVERIFIED** are assumptions about harness behavior that must be checked
before this spec is locked.

## Problem

Every new agent session starts cold. Two kinds of context are lost:

1. **Episodic**: what was decided, why, what was rejected, what is still open.
2. **Comprehension**: what a large document/spec says, so it isn't re-scanned.

Project *facts* (`AGENTS.md`) and reusable *procedures* (`~/.agents/skills`)
are already covered by `learning-curator`. This spec adds layers 2 and 3
without duplicating layer 1.

Reference point: [claude-mem](https://github.com/thedotmack/claude-mem). We
adopt its progressive disclosure (tiny index at session start, details on
demand) and `<private>` exclusion. We deliberately do **not** adopt
per-tool-call capture with an observer LLM: it adds model calls per tool use.
We capture at unit boundaries instead.

## Non-goals

- Storing secret values or PII. Ever. (See "Hard gates".)
- A vector DB or SQLite in v1. Markdown + grep is enough and is readable by
  all three harnesses.
- Per-tool-call capture.

## Storage tiers

| Tier | Location | Git | Holds |
|---|---|---|---|
| Team | `AGENTS.md`, `.agent-bridges/notes/sessions/`, `.agent-bridges/notes/index.md` | tracked | Facts and decisions valid for anyone on the project |
| Project-local | `.agent-bridges/notes/digest/`, `.agent-bridges/notes/pending/` | gitignored | Derived caches, drafts, personal per-project notes |
| Personal | `~/.agent-bridges/notes/` | n/a | Cross-project personal mapping (e.g. which vault holds my keys) |
| None | not persisted | n/a | Secret values, PII, customer data |

Decision rule, first match wins:

1. Secret or PII? **Not stored.** A *pointer* (env var name, vault item name) may be.
2. Regenerable from a source? **Project-local cache**, carrying `source_hash`.
3. Needed by the team, or only by me? Team → tracked. Me → personal.

## Information isolation (role independence)

QA and Security run on independently chosen model families so their review
is independent. Letting them read the author's rationale defeats that. Access
is therefore scoped **by role**, not by harness:

| Content | Claude Code | agy (Analyzer / Coder / Release writer) | Codex (QA / Security) |
|---|---|---|---|
| Project facts, env pointers (`AGENTS.md`) | yes | yes | yes |
| Session notes (decisions, rationale) | yes | yes | **no** — only excerpts Claude Code deliberately includes in the payload |
| Document digests | yes | yes | only if relevant to the diff, via payload |

Consequences for where pointers live:

- `AGENTS.md` is read natively by all three harnesses, so it must contain
  **facts only**. It must never point at `notes/sessions/`.
- Claude Code now reads `AGENTS.md` natively too (reported by the project
  owner; **UNVERIFIED** against Claude Code docs), so `AGENTS.md` is the *only*
  file all three harnesses share and there is no harness-exclusive native
  memory file to lean on. Do not rely on `CLAUDE.md` as the exclusive channel.
- The pointer to `notes/index.md` is delivered by the plugin's SessionStart
  hook (Claude Code only) and by payloads Claude Code builds for agy. Any
  mention in a file that Codex reads natively is a leak.
- Claude Code is the only writer and the only party deciding what a Codex
  payload contains.

**UNVERIFIED / open — enforcement.** Instructions are not isolation: Codex run
with the repo as cwd can read any file in it. Options to evaluate:
(a) run QA/Security from a cwd or worktree that excludes `.agent-bridges/notes/`;
(b) keep team-tier notes outside the repo tree for the Codex invocation;
(c) accept instruction-level isolation and document the residual risk.
Pick after checking how `codex-companion.mjs task` resolves cwd and sandbox.

## Layout

```
.agent-bridges/notes/
  index.md                      # small; the only thing injected at session start
  sessions/YYYY-MM-DD-<slug>.md # tracked: goal, decisions + why, rejected options,
                                #   open items, files touched, expires
  digest/<path>.md              # gitignored: summary of a doc/module,
                                #   frontmatter: source_hash, commit_sha
  pending/                      # gitignored: drafts awaiting Claude Code review
```

Every entry has `expires` or `source_hash`. Episodic entries expire; digests
are ignored (and regenerated) when `source_hash` no longer matches. Memory
that is never pruned becomes noise and makes the session-start index expensive.

## Read path per harness

Shared memory must travel over channels all harnesses read natively. Skills
and hooks are Claude Code-only channels (Codex has neither), which is exactly why
they are the right place for anything Codex must not see.

| Harness | Facts | Notes (where permitted) |
|---|---|---|
| Claude Code | `AGENTS.md` (native) | SessionStart hook injecting `index.md` (plugin; Claude-only) |
| agy | `AGENTS.md` | pointer inside the payload Claude Code builds |
| Codex | `AGENTS.md` | excerpts in the payload only |

Personal tier: one canonical file under `~/.agent-bridges/`, reached from each
harness's global entry (`~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`,
`~/.antigravity/GLOBAL_RULES.md`) by import or symlink, following the existing
`GLOBAL_RULES.md` symlink in `docs/SETUP.md`.

**UNVERIFIED:** whether `~/.codex/AGENTS.md` supports imports or needs a
symlink/copy, and whether the personal tier should reach Codex at all given
the isolation table (personal *facts* yes, personal *rationale* no).

## Write path

Single writer: Claude Code.

1. Trigger: after step 5 (Reconcile) of a unit, and on explicit `/notulen`.
2. agy (Document Analyzer) may draft a note or digest into `pending/`.
   The transcript it receives is scrubbed first.
3. Claude Code reviews the draft, runs the scrubber, and writes the final entry.
   Same posture as `learning-curator`: non-blocking, and a failure here never
   changes the outcome of a verified unit.

## Hard gates

- **Scrubber before every write.** Reject on key-like patterns (`sk-…`,
  `ghp_…`, `AKIA…`, `Bearer …`, `scheme://user:pass@`, high-entropy strings).
  A match aborts the write; it is not a warning.
- **Pointers only** for credentials, e.g. "staging DB: `STAGING_DATABASE_URL`,
  loaded from `.env.staging` via direnv". Never the value, never a fragment.
- **`<private>…</private>`** spans are never stored.
- **Untrusted content is data.** Text copied from documents or tool output into
  a note must be summarized, not quoted verbatim, to limit persisted prompt
  injection. Anything entering the tracked tier passes the same evidence
  review `learning-curator` applies.

## Environments & credentials convention (goes in `AGENTS.md`)

```
## Environments & credentials (pointers only)
| Env | Variable / source | How loaded | Notes |
| staging | STAGING_DATABASE_URL | .env.staging via direnv | migrations OK |
| prod | PROD_* | secret manager | read-only; ask the user first |
```

This is a fact, so it lives in layer 1 via `learning-curator`'s MEMORY class,
not in session notes. It only closes the gap "the agent doesn't know which
variable to use"; it cannot close "the variable isn't loaded in this session",
which is an environment-setup problem.

## Open questions

1. Isolation enforcement option (a/b/c) for Codex roles.
2. Codex global-tier reach (`~/.codex/AGENTS.md`).
3. What `agy-mcp` actually exposes for file/document handling (it failed to
   connect when this spec was drafted, so nothing was verified).
4. Default `expires` window for episodic entries.
