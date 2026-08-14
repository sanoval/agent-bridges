# <Project Name>

This file is the **single source of truth for project memory** — the facts
about this codebase that any harness executing code in it needs, regardless
of which one it is. It is read three different ways by the three harnesses
in this pipeline, without being duplicated three times:

- **Codex** (`codex-qa`, `codex-security`) reads this file natively — Codex
  looks for `AGENTS.md` on its own, no setup needed.
- **Claude Code** reads it via the `@AGENTS.md` import line at the top of
  `CLAUDE.md` (see `templates/CLAUDE.md`) — everything below that import
  line in `CLAUDE.md`, plus the `delegation-pipeline` skill it points to,
  is orchestrator-only routing that stays out of this file.
- **Antigravity** (`agy`) reads this file natively too — since the
  Antigravity CLI migration off Gemini CLI, `agy` parses and enforces both
  `GEMINI.md` and `AGENTS.md` in a directory with no configuration or
  symlink needed.

Editing this file once updates what all three harnesses know. Do **not**
put delegation/pipeline/model-routing rules here — those live in
`CLAUDE.md` below the import line, since Codex and Antigravity executing as
Coder/QA/Security don't need to know how Claude Code decided to call them.

## Skills

This project's custom skills live in one canonical `skills/<name>/SKILL.md`
directory at the project root (same file format Claude Code and Antigravity
both use — YAML frontmatter `description`/`name`, markdown body, optional
`scripts/`/`resources/`). Two directories are symlinks to it, not copies:

- `.claude/skills` → `../skills` (Claude Code's discovery path)
- `.agents/skills` → `../skills` (Antigravity's workspace discovery path)

Codex has no per-task skill loader, so it can't discover `skills/` on its
own — it only ever sees a skill if Claude Code pastes the matching one's
body into a `codex-qa`/`codex-security` prompt. The list below exists so
Codex (reading this file natively) at least knows what's available, even
though it can't trigger one itself:

- `delegation-pipeline` — how Claude Code routes work across the bridges.
  Orchestrator-only: it is instructions *about* calling you, not
  instructions *for* you, and is never pasted into a Codex prompt.
<one line per skill: `name` — one-sentence description, kept in sync with
each skill's own frontmatter>

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
