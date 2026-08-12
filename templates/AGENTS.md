# <Project Name>

This file is the **single source of truth for project memory** — the facts
about this codebase that any harness executing code in it needs, regardless
of which one it is. It is read three different ways by the three harnesses
in this pipeline, without being duplicated three times:

- **Codex** (`codex-qa`, `codex-security`) reads this file natively — Codex
  looks for `AGENTS.md` on its own, no setup needed.
- **Claude Code** reads it via the `@AGENTS.md` import line at the top of
  `CLAUDE.md` (see `templates/CLAUDE.md` / `templates/CLAUDE-two-bridge.md`)
  — everything below that import line in `CLAUDE.md` is delegation/pipeline
  rules that only make sense for the orchestrator and stay out of this file.
- **Antigravity** (`agy`) reads `GEMINI.md`, not `AGENTS.md` — make
  `GEMINI.md` a symlink to this file (`ln -s AGENTS.md GEMINI.md`) rather
  than a second copy, so there is exactly one file to keep current.

Editing this file once updates what all three harnesses know. Do **not**
put delegation/pipeline/model-routing rules here — those live in
`CLAUDE.md` below the import line, since Codex and Antigravity executing as
Coder/QA/Security don't need to know how Claude Code decided to call them.

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
