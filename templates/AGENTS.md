# <Project Name>

This file is the **single source of truth for project memory** — the facts
about this codebase that any harness executing code in it needs, regardless
of which one it is. It is read three different ways by the three harnesses
in this pipeline, without being duplicated three times:

- **Codex** (`codex-qa`, `codex-security`) reads this file natively — Codex
  looks for `AGENTS.md` on its own, no setup needed.
- **Claude Code** reads it via the `@AGENTS.md` import line at the top of
  `CLAUDE.md` (see `templates/CLAUDE.md`, plus
  `templates/CLAUDE-two-bridge-overlay.md` appended to it in two-bridge mode)
  — everything below that import line in `CLAUDE.md` is delegation/pipeline
  rules that only make sense for the orchestrator and stay out of this file.
- **Antigravity** (`agy`) reads this file natively too — since the
  Antigravity CLI migration off Gemini CLI, `agy` parses and enforces both
  `GEMINI.md` and `AGENTS.md` in a directory with no configuration or
  symlink needed.

Editing this file once updates what all three harnesses know. Do **not**
put delegation/pipeline/model-routing rules here — those live in
`CLAUDE.md` below the import line, since Codex and Antigravity executing as
Coder/QA/Security don't need to know how Claude Code decided to call them.

## Skills

`delegation-pipeline` and `learning-curator` — the pipeline steps, payload
contracts, checkpoint format, and post-verification learning policy this
project's delegation pipeline runs on — ship inside the `agent-bridges`
Claude Code plugin (see `README.md` "Install"), not as files in this
project. Claude Code discovers them globally once the plugin is enabled;
Antigravity and Codex have no visibility into them at all (neither harness
reads Claude Code's plugin store), so neither is ever pasted into a
`codex-qa`/`codex-security` prompt and neither needs listing here for
Codex's benefit.

Any *additional* skill specific to this project still lives in one
canonical `skills/<name>/SKILL.md` directory at the project root (same
file format Claude Code and Antigravity both use — YAML frontmatter
`description`/`name`, markdown body, optional `scripts/`/`resources/`).
Two directories are symlinks to it, not copies:

- `.claude/skills` → `../skills` (Claude Code's discovery path)
- `.agents/skills` → `../skills` (Antigravity's workspace discovery path)

Codex has no per-task skill loader, so it can't discover `skills/` on its
own — it only ever sees a skill if Claude Code pastes the matching one's
body into a `codex-qa`/`codex-security` prompt. The list below exists so
Codex (reading this file natively) at least knows what's available, even
though it can't trigger one itself:

<one line per project skill: `name` — one-sentence description, kept in
sync with each skill's own frontmatter>

## Learning

`learning-curator` (above) persists reusable knowledge to two entirely
different stores depending on what it learned — do not treat them the
same:

- **Project-specific facts (MEMORY)** — appended to this file, right here,
  same as any other project fact. Staged first at
  `.agent-bridges/learning/pending/` (**gitignored** — add
  `.agent-bridges/learning/pending/` to this project's `.gitignore`, never
  commit or push a file from there) if evidence is medium-confidence, or
  applied directly if strong. The audit trail,
  `.agent-bridges/learning/log.md`, **is** committed — it only records
  changes already made to tracked files.
- **Reusable procedures/skills** — never written into this project at all.
  They persist to a personal, cross-project store at
  `~/.agents/skills/` (outside any repo), the same boundary
  [Hermes Agent](https://hermes-agent.nousresearch.com/docs/user-guide/features/skills)
  draws around its own `~/.hermes/skills/`. A skill learned here may still
  trigger automatically for the person who ran the curator (Claude Code
  reads personal skills from `~/.claude/skills/` in addition to this
  project's `skills/`), but it is never part of this project's git history
  and never something a teammate gets just by cloning the repo.

Full policy — evidence scoring, hard gates, the promote-on-approval
workflow, security/poisoning controls, and exactly where each mutation
class lands — lives in `skills/learning-curator/SKILL.md`, not here.

---

## Project overview
<what this project is, in a few sentences — enough for a harness with zero
prior context on this repo to orient itself>

## Build, test, and run
<exact commands — build, run the test suite, run a single test, lint,
typecheck. Every harness that executes code needs these verbatim, not
paraphrased>

## Code style / conventions
<naming, formatting, error-handling patterns, anything a diff should match
to look native to this codebase>

## Directory layout
<where the meaningful code lives, and what's generated/vendored/off-limits>

## Do not touch
<files/directories no harness should edit even if asked — generated code,
vendored deps, migration history, etc.>

## Known gotchas
<footguns specific to this codebase that have bitten a change before —
keep this list short and concrete, not a general engineering advice list>
