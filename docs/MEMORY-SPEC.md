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
- Sharing raw session rationale with the team through git (see "Team sharing").

## Design decision: rationale lives outside the repo tree

QA and Security run in the repo as cwd and read the working tree themselves
(`skills/delegation-pipeline/SKILL.md`, Codex call item 4; two-bridge lenses
likewise run `agy_run` with `cwd` = repo). Their `read-only` mode
(`mode: "plan"` for agy, no `--write` for Codex) was assumed to block
**writes**, not reads. **For agy that assumption is false**: `mode: "plan"` does
not block writes (see "Information isolation").
Anything inside the repo tree is therefore readable by the roles that must stay
independent. A worktree or sparse checkout does not fix this for tracked files
(they exist in every checkout) and conflicts with reading the real working tree.

So: **notes that carry rationale are stored outside the repo tree.** The repo
tree holds facts only.

## Storage tiers

| Tier | Location | Git | Holds | Readable by |
|---|---|---|---|---|
| Repo facts | `AGENTS.md`, `.agent-bridges/learning/log.md` | tracked | Project facts, env pointers, curator audit trail. **No rationale narratives.** | all roles |
| Project notes | `~/.agent-bridges/projects/<repo-id>/notes/` | n/a (outside repo) | Session notes, digests, drafts, index | role-scoped (see isolation) |
| Personal | `~/.agent-bridges/personal/` | n/a | Cross-project pointers and preferences (e.g. which vault holds my keys). Facts-level only — no rationale | all roles via each harness's global entry |
| None | not persisted | n/a | Secret values, PII, customer data | — |

`<repo-id>`: slug of the normalized `origin` URL, falling back to the root
commit hash, so every worktree and clone of one repo shares one notes dir.
(Open question 2.)

Decision rule, first match wins:

1. Secret or PII? **Not stored.** A *pointer* (env var name, vault item name) may be.
2. Is it a fact any role may know (build command, env pointer, layout)?
   **`AGENTS.md`**, via `learning-curator`.
3. Is it decision rationale, rejected options, or open items? **Project notes.**
4. Is it derived from a source and regenerable? **Project notes, `digest/`**,
   carrying `source_hash`.
5. Only relevant to me across projects, and a fact/pointer? **Personal.**

## Information isolation (role independence)

QA and Security run on independently chosen model families so their review
is independent. Letting them read the author's rationale defeats that. Access
is scoped **by role**, not by harness. Note the same harness appears in both
columns: agy is a permitted reader as Analyzer/Coder/Release Writer and a
**non-reader** as a two-bridge QA/Security lens.

| Content | Claude Code | agy: Analyzer / Coder / Release Writer | agy: QA/Security lens | Codex: QA / Security |
|---|---|---|---|---|
| Project facts, env pointers (`AGENTS.md`) | yes | yes | yes | yes |
| Personal pointers | yes | yes | yes | yes |
| Session notes (decisions, rationale) | yes | yes | **no** | **no** |
| Document digests | yes | yes | only excerpts relevant to the diff, in payload | only excerpts relevant to the diff, in payload |

Enforcement (layered; none is a mechanical guarantee, see residual risk below):

1. **Out-of-tree storage.** Roles that must not read notes start in the repo
   and nothing inside the repo refers to the notes path.
2. **No pointers in shared files.** `AGENTS.md` and anything else Codex or a lens
   reads natively must never mention `~/.agent-bridges/projects/` or the index.
3. **No symlinks into the notes dir from inside the repo.**
4. **Payload hygiene.** Claude Code never includes the notes path in a Codex or
   lens payload, only deliberately chosen excerpts.
5. **Single writer.** Claude Code decides what any payload contains.

**VERIFIED — residual risk (tested by the project owner).** Codex's
`read-only` run *can* read files outside its cwd. Out-of-tree storage therefore
provides **isolation by non-discoverability, not by enforcement**: nothing
points a QA/Security run at the notes, but a run that explores `$HOME` could
find them. This is accepted, not solved. Mitigations:

6. **Canary (weak detection only).** `index.md` carries a unique token. Claude
   Code scans QA/Security/lens output for it; a hit means the role read the notes
   and its findings are treated as contaminated (re-run fresh, note the breach).
   It only catches leakage that surfaces in the output, so it is not a guarantee.

If this residual risk is unacceptable for a given project, the only hard fixes
are running QA/Security as a different OS user or in a container that does not
mount `~/.agent-bridges/`; both are out of scope for v1.

**VERIFIED — agy reads outside cwd too** (2026-11-27; agy 1.5.18, agy-mcp 2.6.1,
model `gemini-4-hydrogen-medium`, plugin server
`plugin:agent-bridges:antigravity`, `cwd` = this repo). A random token stored in
`~/.agent-bridges/probe/`, given to agy only as an absolute path, came back
verbatim via agy's `read_file` in all three runs:

| `mode` | `sandbox` | `dirs` | Result |
|---|---|---|---|
| `plan` | off | none | read |
| `plan` | on | none | read |
| `accept-edits` | off | none | read |

Negative control: a nonexistent path in the same directory (`plan`) returned
"file does not exist", not invented contents. Consequences: Analyzer/Coder can
be handed absolute note paths without `dirs`; a two-bridge lens carries the same
residual risk as Codex; and neither omitting `dirs` nor `sandbox: true`
restricts these reads, so neither is an isolation control. The runs were told the
path; they did not test whether a run discovers it unprompted.

**VERIFIED — agy `mode: "plan"` does NOT block writes** (same date and setup;
every file was confirmed on disk, not from agy's report). Each run was asked to
create a file, and each did so with `write_file`, without a refusal:

| `mode` | `sandbox` | Inside `cwd` (this repo) | Outside `cwd` (`~/.agent-bridges/probe/`) |
|---|---|---|---|
| `plan` | off | written | written |
| `plan` | on | written | written |
| `accept-edits` | off | not tested | written |

No `dirs` was passed in any run. The prompts asked for the write explicitly, so
this shows what the mode **permits**, not that an agent writes unprompted. Shell
commands were not tested. `agy --help` describes `--sandbox` as "terminal
restrictions" only, which is consistent with it not stopping `write_file`.

**VERIFIED — Codex `read-only` blocks file-tool writes** (2026-11-27, codex-cli
0.166.0, `codex exec -s read-only` in a throwaway repo): one write inside `cwd`
and one under `~/.agent-bridges/probe/` were both rejected ("writing is blocked
by read-only sandbox"), and neither file existed on disk. Shell-command writes
were not tested, and the `codex-companion.mjs task` path was not tested for
writes.

Consequences:

- A two-bridge lens can **modify or delete** notes, not only read them (only file
  creation was tested). The canary does not detect tampering.
- Drafting into `pending/` works without `dirs`, but agy is not confined to
  `pending/`. "Single writer" is a prompt convention for agy, not a guarantee.
  **Proposed:** agy returns the draft as its result and Claude Code writes the
  file, and prompts never ask agy to write under the notes dir. This does not
  stop a misbehaving run; Claude Code would have to compare the notes dir before
  and after a run to detect that.
- Outside this spec: `skills/delegation-pipeline` described `mode: "plan"` as
  mechanically read-only. The correction is on branch
  `fix/agy-readonly-claims` (not merged when this was written).

**VERIFIED — a custom agent does block writes** (same date and versions;
definition and full results on branch `fix/agy-readonly-claims`:
`agy-agents/agent-bridges-readonly.md` and the delegation-pipeline `SKILL.md`,
"Read-only roles"). The globally installed agent `agent-bridges-readonly` had no
file-write, shell, or MCP call tool, and asked to create a file it created none
(`gemini-4-hydrogen-medium` and `gemini-4-neon-medium`; lens pins not tested).
It also loads **no rules**: neither the repo's `AGENTS.md` nor user rules
(tested with a token in `AGENTS.md` that the default agent did see). A
same-named agent in the repo's `.agents/agents/` overrides it.

What this changes here, for every non-Coder agy role once that branch is merged:

- Lenses cannot modify notes while the agent is in force. It does not restrict
  reads, so non-discoverability still applies.
- Lenses on this agent should not receive `GLOBAL_RULES.md` (inferred from "no
  user rules"), so a pointer there would not reach them. Codex still reads its
  own global file.
- Analyzer and Release Writer no longer get `AGENTS.md` natively: the payload
  must give its absolute path. The "Facts" column under "Read path per harness"
  holds only for the Coder.
- None of this constrains the Coder, which can still write anywhere.

Claude Code reads `AGENTS.md` natively since v2.1.277 (source:
code.claude.com/docs/en/memory, section "AGENTS.md"; relayed, re-check on
upgrade). With default settings, if a `CLAUDE.md` exists in the working
directory or above, **only `CLAUDE.md` is loaded** and `AGENTS.md` arrives
only through an `@AGENTS.md` import. Keep the `@AGENTS.md` import in
`CLAUDE.md` (older builds and some sessions read `CLAUDE.md` only). `CLAUDE.md`
is a valid Claude-only channel but a secondary one, since the
`Project instructions` setting can load both; the SessionStart hook is primary.

## Layout

```
~/.agent-bridges/projects/<repo-id>/notes/
  index.md                      # small; the only thing injected at session start
  sessions/YYYY-MM-DD-<slug>.md # goal, decisions + why, rejected options,
                                #   open items, files touched, expires
  digest/<path>.md              # summary of a doc/module,
                                #   frontmatter: source_hash, commit_sha
  pending/                      # drafts awaiting Claude Code review
~/.agent-bridges/personal/
  pointers.md                   # facts-level, e.g. vault name; no rationale
```

Every entry has `expires` or `source_hash`. Episodic entries expire; digests
are ignored (and regenerated) when `source_hash` no longer matches. Memory
that is never pruned becomes noise and makes the session-start index expensive.

## Read path per harness

Shared memory must travel over channels the permitted readers can reach.
Skills and hooks are Claude Code-only channels (Codex has neither), which is
exactly why they are the right place for anything Codex must not see.

| Harness / role | Facts | Notes (where permitted) |
|---|---|---|
| Claude Code | `CLAUDE.md` (`@AGENTS.md` import; native `AGENTS.md` on v2.1.277+) | SessionStart hook injecting `index.md` (plugin; Claude-only); `CLAUDE.md` pointer as fallback |
| agy Analyzer/Coder/Release Writer | `AGENTS.md` | absolute path to `index.md` plus relevant entries, inside the payload Claude Code builds |
| agy lens, Codex | `AGENTS.md` | none; excerpts in the payload only |

Personal tier: one canonical file under `~/.agent-bridges/personal/`, reached
from each harness's global entry (`~/.claude/CLAUDE.md` — the docs do not say
`~/.claude/AGENTS.md` is read — `~/.codex/AGENTS.md`,
`~/.antigravity/GLOBAL_RULES.md`) by import or symlink, following the existing
`GLOBAL_RULES.md` symlink in `docs/SETUP.md`. Because the personal tier is
facts-level only, reaching Codex is allowed.

**VERIFIED (at project level)** (2026-11-27; codex-cli 0.166.0,
`codex exec --json -s read-only` in throwaway git repos, random token per
source, event stream showed no command or tool items):

| Mechanism in `AGENTS.md` | Token in context? |
|---|---|
| plain text (positive control) | yes |
| `@/absolute/path.md` import | **no** |
| `@relative.md` import | **no** |
| `AGENTS.md` is a symlink to a file outside the repo | yes |

So Codex has no `@` import; a symlink works. The global `~/.codex/AGENTS.md` was
not modified or tested directly.

This breaks "import or symlink" for the Codex entry. `~/.codex/AGENTS.md`
already holds Codex-specific rules, so it cannot become a symlink to
`pointers.md`. Also, any Codex entry that names a path under `~/.agent-bridges/`
(a "read this file" line) tells QA/Security where the parent of `projects/`
is, which weakens non-discoverability. **Proposed, not yet decided:** copy the
personal pointers into a marker-delimited block in `~/.codex/AGENTS.md` (no
path disclosed; cost: the copy can drift). The same concern applies to agy
lenses run on the default agent, which read `GLOBAL_RULES.md` (a symlink to
`~/.claude/CLAUDE.md` on the tested machine); see the custom agent result under
"Information isolation".

## Write path

Single writer: Claude Code.

1. Trigger: after step 5 (Reconcile) of a unit, and on explicit `/notulen`.
2. agy (Document Analyzer) may draft a note or digest into `pending/`.
   The transcript it receives is scrubbed first. (Under review: see the
   write test under "Information isolation".)
3. Claude Code reviews the draft, runs the scrubber, and writes the final entry.
   Same posture as `learning-curator`: non-blocking, and a failure here never
   changes the outcome of a verified unit.

## Team sharing

Raw rationale is not shared through git: one developer's reasoning has no
reason to enter the team's history, and anything in the repo tree is visible to
the independent roles. The promotion path is `learning-curator`: a decision
that has been verified and is useful to others is distilled into a **fact** in
`AGENTS.md` and passes the curator's evidence score and hard gates, with its
audit entry in the tracked `learning/log.md` (facts, no narrative).

Trade-off accepted: a teammate does not automatically get your session notes.
If a team ever needs shared rationale, it requires a deliberate decision on
how to keep it away from QA/Security (for example a separate repo not checked
out in the project tree).

## Hard gates

- **Scrubber before every write.** Reject on key-like patterns (`sk-…`,
  `ghp_…`, `AKIA…`, `Bearer …`, `scheme://user:pass@`, high-entropy strings).
  A match aborts the write; it is not a warning.
- **Pointers only** for credentials, e.g. "staging DB: `STAGING_DATABASE_URL`,
  loaded from `.env.staging` via direnv". Never the value, never a fragment.
- **`<private>…</private>`** spans are never stored.
- **Untrusted content is data.** Text copied from documents or tool output into
  a note must be summarized, not quoted verbatim, to limit persisted prompt
  injection. Anything promoted into `AGENTS.md` passes the same evidence
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

1. ~~Sandbox read scope of Codex outside cwd~~ — tested: it can read outside
   cwd. Residual risk accepted with canary detection (see above). Revisit if a
   per-OS-user or container run becomes practical.
2. `<repo-id>` derivation: origin-URL slug vs root-commit hash; behavior for
   repos with no remote.
3. ~~Codex import mechanism~~ — tested: no `@` import, symlink works (see "Read
   path per harness"). Still to decide: how the personal tier reaches Codex.
4. ~~agy file handling and read scope~~ — agy-mcp 2.6.1 exposes no file or
   document tools (`agy_run`, `agy_run_sync`, `agy_status`, `agy_wait`,
   `agy_cancel`, `list_models`, `list_agents`, `list_sessions`); file access is
   agy's own tools, with `cwd` and `dirs` as the only path parameters. agy reads
   **and writes** outside `cwd`, and `mode: "plan"` does not block writes (see
   "Information isolation").
5. Default `expires` window for episodic entries.
6. The read-path table and the `AGENTS.md`/`CLAUDE.md` paragraph allow a
   `CLAUDE.md` pointer as a fallback channel. A repo `CLAUDE.md` is inside the
   tree, so QA/Security can read it, which contradicts enforcement rule 1. A
   `~/.claude/CLAUDE.md` pointer reaches agy lenses through `GLOBAL_RULES.md`.
   Proposed: drop the fallback and use the SessionStart hook only.
