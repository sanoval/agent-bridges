# agent-bridges

Config and templates for pairing **Claude Code** with three MCP delegation
bridges in a fixed-role pipeline: **Antigravity** (run via the `agy-bridge`
MCP server), which plays three roles at different pipeline stages —
**Document Analyzer**, **Coder/Executor**, and **Release/Changelog
Writer** — and two pinned instances of Codex's built-in MCP server —
**`codex-qa`** as **QA Engineer** and **`codex-security`** as **Security
Engineer**. Claude Code itself plays **Planner and Code Reviewer**, on
whichever model you choose per plan — it stays the single agent harness
with sole authority to execute, verify, and integrate the result. A lean
context window is a consequence of that routing, not the goal itself.

Which model each bridge is pinned to is deliberately **not** repeated in
this README: the pin table in `templates/CLAUDE.md` is the single source of
truth for that, and everything else — skill, overlay, prompt examples —
refers to pins by name (the *Antigravity pin*, the *QA pin*, the *Security
pin*, the *lens chain*). The only literal values outside that table are in
the Setup commands below, because config files can't hold a reference.

## Why

Sending everything through one model, even when it's "free" against that
model's own limit, is still wasteful if a different provider is better
suited to a specific role. Rather than routing task-by-task, this setup
pins each bridge to a fixed job: Antigravity ingests specs into a
requirement matrix, then writes the code, then drafts the release notes;
Codex QA always tests the diff; Codex Security always reviews it for
exploitable issues; and Claude Code always plans, does the first review
pass before either Codex role ever sees a diff, and has final say on every
Antigravity output — including the docs it drafts.

Claude Code stays the harness because it's the only party with tool access,
repo/session state, and write permission — a bridge can implement or review,
but only Claude Code decides what ships. That also means Claude Code owns
verification: a delegated finding is not trusted until checked, and is never
the sole basis for an edit without that check (see "Parallelism, failures,
and verification" in the `delegation-pipeline` skill). Reading a 2,000-line file,
diffing a large repo, or running a QA/security pass all burn context fast,
and often the *content* isn't needed, only the *answer* — so as a side
effect, the bridges also return the delegated result without making Claude
Code carry the full investigation in its own context.

## Architecture

- **One direction only.** Claude Code calls all three bridges. Neither
  Antigravity nor either Codex instance calls back into Claude Code or
  another bridge — no bidirectional delegation and no ping-pong loops. This
  follows directly from Claude Code being the harness: execution authority
  has to stay at one point, not just avoiding ping-pong for its own sake.
- **Claude Code = MCP Host** (with an internal MCP client). **Antigravity**
  (registered as the `antigravity` MCP server, running the `agy-bridge`
  package) and **two separate Codex MCP Server instances** — `codex-qa` and
  `codex-security`, each pinned to its model by a Codex profile — are three
  separate MCP servers exposed over JSON-RPC 2.0. `codex-qa` and
  `codex-security` are independent processes even though both run the
  `codex` binary; they do not share sessions.
- **Session continuity.** Antigravity uses `follow_up` with its
  `session_id`. Each Codex instance uses its own `codex-reply` with the
  `threadId` *that same instance* returned — a `codex-qa` threadId is not
  valid on `codex-security`.

## Repo layout

```
templates/
  AGENTS.md                    — shared project memory, read by all three harnesses (see "Centralizing memory" below)
  CLAUDE.md                    — always-on core: pin table, Gate, "do NOT delegate", skill trigger. Small on purpose
  CLAUDE-two-bridge.overlay.md — two-bridge mode: the deltas to apply on top of CLAUDE.md, not a second copy of it
  skills/
    delegation-pipeline/
      SKILL.md                 — the pipeline itself (steps, payloads, sessions, checkpoints) — loads on demand
      two-bridge.md            — pipeline-level deltas read alongside SKILL.md in two-bridge mode
  review-topic-template.md     — structure for a persistent review-<topic>.md progress file, shared by both modes
  settings.hooks.json          — PreToolUse hook config that enforces the CLAUDE.md "Gate" mechanically (see Setup step 8)
  hooks/
    agent-bridges-gate.sh      — the Gate-enforcement hook script referenced by settings.hooks.json
```

### Why the core/skill split

`CLAUDE.md` is loaded into every single session, whether or not that
session ever calls a bridge. So it carries only what has to be true before
you know what the task is — the bridge/model pins, the Gate, the narrow
"do NOT delegate" list, and the instruction to load the skill. The pipeline
mechanics (steps, delegation payloads, session continuity, prompt examples,
checkpoint discipline) live in `skills/delegation-pipeline/SKILL.md` and
load only when a unit of work actually needs them.

That skill sits in the same canonical `skills/` directory as every other
project skill, so the `.claude/skills` and `.agents/skills` symlinks from
Setup step 7 already expose it — no extra plumbing. Antigravity therefore
sees it too; its opening paragraph tells any non-orchestrator reader that
the file is instructions *about* calling them, not instructions *for* them.

## Centralizing memory across harnesses

Each harness reads its own memory file at session/subprocess start, and
without coordination that becomes three copies of the same project facts
drifting apart. They don't need to, because the three formats compose:

- **Codex** reads `AGENTS.md` natively — no configuration needed, it just
  looks for that file.
- **Claude Code** reads `CLAUDE.md`, which opens with an `@AGENTS.md`
  import line, so Claude Code pulls in the same content Codex reads
  directly.
- **Antigravity** (`agy`) reads `AGENTS.md` natively too — as of the
  Antigravity CLI migration from Gemini CLI, `agy` parses and enforces
  both `GEMINI.md` and `AGENTS.md` in a directory with no configuration
  needed. No symlink required; just make sure the project has an
  `AGENTS.md`.

The result: edit `AGENTS.md` once, and all three harnesses see the change
— Codex directly, Claude Code via import, Antigravity natively. Put
project facts (build/test commands, code style, directory layout, things
not to touch) in `AGENTS.md`; keep delegation/pipeline/model-routing rules
in `CLAUDE.md` below the import line, since Codex and Antigravity executing
as Coder/QA/Security don't need to know how Claude Code decided to call
them. See `templates/AGENTS.md` for the section structure.

**Skills centralize between Claude Code and Antigravity; Codex is the
remaining gap.** Antigravity's native skill format (confirmed via `agy`
docs) turns out to match Claude Code's almost exactly — YAML frontmatter
(`description` required, `name` optional), a markdown body loaded only on
a matching task, optional `scripts/`/`resources/` subfolders. The only real
difference is *where* each harness looks for them:

- Claude Code discovers skills in `.claude/skills/<name>/SKILL.md`.
- Antigravity discovers workspace skills in `.agents/skills/<name>/SKILL.md`.

Same fix as `AGENTS.md`/`GEMINI.md`, one level up: keep one canonical
`skills/<name>/SKILL.md` directory at the project root, and make
`.claude/skills` and `.agents/skills` **symlinks** to it
(`ln -s skills .claude/skills`, `ln -s skills .agents/skills`) rather than
two copies. Write a skill once, both harnesses can trigger it natively.

Codex has no per-task skill loader — nothing to symlink to. It can't
discover `skills/` on its own, so a skill only reaches Codex when Claude
Code (already composing every delegation prompt) pastes the matching
skill's body into a `codex-qa`/`codex-security` call. `templates/AGENTS.md`
carries a plain-list "Available skills" section so Codex at least knows
what exists, even though it can't trigger one itself — that's the one part
of this that stays a workaround rather than a real fix, since it's a
structural gap in Codex, not a format mismatch this repo can paper over.

## Which mode do I need?

Both modes use the same `templates/CLAUDE.md` core and the same
`delegation-pipeline` skill. Two-bridge mode is not a fork of them — it's a
short overlay of deltas.

- **Have a Codex subscription too?** Use `templates/CLAUDE.md` as-is
  (three-bridge mode). QA and Security get their own independent
  model/process each.
- **Only Claude Code + Antigravity subscriptions?** Use
  `templates/CLAUDE.md` plus `templates/CLAUDE-two-bridge.overlay.md`. Same
  pipeline shape, but QA and Security fold into two separately-framed
  Antigravity `adversarial_review` passes instead of two dedicated bridges
  — weaker independence, since both lenses ultimately come from one
  vendor's model family; the overlay's "Why this is weaker, and what
  compensates" section explains what that costs and why your own Review
  step has to work harder as a result.

## Setup

1. Prerequisites: the `agy` CLI installed and authenticated; Node + npx
   available; and — **three-bridge mode only** — the `codex` CLI installed
   and authenticated. Two-bridge mode needs only `agy`.
2. **Three-bridge mode only** — pin the two Codex roles to their models via
   Codex profiles. Add to `~/.codex/config.toml`, using the **QA pin** and
   **Security pin** values from the pin table in `templates/CLAUDE.md`
   (a config file can't reference the table, so these two literals have to
   be kept in step with it — they're the only Codex-side copy):
   ```toml
   [profiles.qa]
   model = "<QA pin>"

   [profiles.security]
   model = "<Security pin>"
   ```
   Skip this step entirely in two-bridge mode — there's no Codex to profile.
3. Register the MCP server(s) at user scope (available in every project on
   the machine). The Antigravity alias is `antigravity` — the `agy-bridge`
   npm package is just what runs behind it.
   Substitute the **Antigravity pin** from the `templates/CLAUDE.md` pin
   table for `<Antigravity pin>` below — same reason as step 2, an env var
   can't reference the table.
   - **Two-bridge mode** — register Antigravity only:
     ```bash
     claude mcp add-json -s user antigravity '{"command":"npx","args":["-y","agy-bridge"],"env":{"AGY_DEFAULT_MODEL":"<Antigravity pin>"},"timeout":600000}'
     ```
   - **Three-bridge mode** — register Antigravity plus the two pinned Codex
     instances:
     ```bash
     claude mcp add-json -s user antigravity '{"command":"npx","args":["-y","agy-bridge"],"env":{"AGY_DEFAULT_MODEL":"<Antigravity pin>"},"timeout":600000}'
     claude mcp add-json -s user codex-qa '{"command":"codex","args":["--profile","qa","mcp-server"],"timeout":600000}'
     claude mcp add-json -s user codex-security '{"command":"codex","args":["--profile","security","mcp-server"],"timeout":600000}'
     ```
   `AGY_DEFAULT_MODEL` is only a fallback for calls that omit `model` — the
   pipeline still has every Coder/Analyzer/Release-Writer Antigravity call
   pass the Antigravity pin explicitly (QA/Security lens calls in two-bridge
   mode intentionally don't — they let the lens chain apply), since that's
   the only guarantee the bridge honors it (see `agy-bridge`'s per-tool
   model chain).
4. Verify: `claude mcp list` should show `antigravity` **Connected**
   (two-bridge mode), or `antigravity`, `codex-qa`, and `codex-security`
   **all three Connected** (three-bridge mode).
5. Copy `templates/CLAUDE.md` into the target project's `CLAUDE.md` (or
   merge its rules into an existing one) to turn on the role pipeline
   there. It starts with an `@AGENTS.md` import — do not strip that line.
   **Two-bridge mode:** then apply `templates/CLAUDE-two-bridge.overlay.md`
   — two edits, both described at the top of that file (drop the `codex-*`
   rows from the pin table, append the overlay section). Don't copy the
   overlay file itself into the project; it's instructions for editing the
   core, not a second memory file.
6. Centralize project memory: copy `templates/AGENTS.md` into the target
   project's root `AGENTS.md` (or merge it into an existing one — Codex and
   Antigravity both already read this file natively if the project has
   one, no extra step needed). See "Centralizing memory across harnesses"
   above.
7. Centralize skills: create (or move existing custom skills into) a
   `skills/<name>/SKILL.md` directory at the project root, then symlink
   both harnesses' discovery paths to it:
   `ln -s skills .claude/skills && ln -s skills .agents/skills`. Copy
   `templates/skills/delegation-pipeline/` in as one of them — the pipeline
   body `CLAUDE.md` points at (both `SKILL.md` and, in two-bridge mode,
   `two-bridge.md`). Keep the "Available skills" list in `AGENTS.md` in
   sync — Codex reads it there but can't discover `skills/` on its own.
8. **Enforce the Gate mechanically (recommended).** The "Gate" section in
   `templates/CLAUDE.md` is prose — it lives in the always-on core (not the
   skill) precisely so it's in context before the first edit, but it only
   shapes Claude Code's behavior and nothing stops it from editing a file
   directly if it judges a change "small enough." To turn that into a real
   checkpoint instead of an honor system, copy
   `templates/hooks/agent-bridges-gate.sh` into the target project as
   `.claude/hooks/agent-bridges-gate.sh` (`chmod +x` it), then merge the
   `hooks` block from `templates/settings.hooks.json` into the project's
   `.claude/settings.json` (merge, don't overwrite, if hooks already exist
   there). This installs a `PreToolUse` hook on `Edit`/`Write`/
   `NotebookEdit`: edits to progress files (`review-*.md`), project memory
   (`CLAUDE.md`/`AGENTS.md`/`GEMINI.md`), delegation config (`.claude/`,
   `.agents/`), or `skills/` pass through untouched; everything else
   (application code) surfaces a permission prompt quoting the Gate rule,
   so a bypass becomes something the user sees and approves rather than
   something that happens silently. It does not cover Bash commands that
   mutate tracked files — that half of the Gate stays honor-system, since
   reliably detecting arbitrary file-mutating shell commands isn't
   something the hook's matcher syntax can do robustly.
9. (Team sharing) Instead of user-scope registration, a project can commit a
   `.mcp.json` with the same server entries for its mode (and, for
   three-bridge mode, a checked-in `codex` profile config or documented
   setup step for it) so the config travels with the repo. Commit
   `AGENTS.md`, `skills/`, and the `.claude/skills` / `.agents/skills`
   symlinks too — all of it is meant to be checked in, not local-only.

### Operational notes

- **Cold start:** Antigravity's first call in a session takes ~40–50 s;
  subsequent calls in the same session are faster. A slow first call is not
  a hang.
- **Timeouts:** Antigravity per-tool budgets are overridable via the
  underlying `agy-bridge` package's env vars, `AGY_TIMEOUT_<TOOL_NAME>` (or
  `AGY_TIMEOUT` globally). Keep the MCP client timeout ≥ that budget — the
  `timeout: 600000` in step 3 satisfies the recommended minimum.
- **Output cap:** Antigravity truncates responses at `AGY_MAX_OUTPUT_CHARS`
  (default 50,000). Prompts should request high-density, structured findings
  (e.g. a QA pass/fail table) rather than unformatted output.
- **(Three-bridge mode) `codex-qa` and `codex-security` are independent
  processes.** Both run the same `codex` binary but with different
  `--profile` values, so they hold separate sessions/threads even for the
  same diff — a `threadId` from one is meaningless on the other.
- **(Two-bridge mode) QA and Security lenses run sequentially, not in
  parallel** — they're both `adversarial_review` calls on the one
  Antigravity server, so there's no independent process to fire them
  concurrently against.
- **Macro-Delegation strategy:** Both Antigravity (Gemini, 1M–2M context) and
  Codex (128k+ context with deep reasoning) possess massive token capacity.
  Send the full plan and every touched file to Antigravity in one call for
  implementation, and the full diff plus plan/acceptance criteria to the
  QA/Security role(s) in one call each, rather than fragmenting into
  single-file micro-delegations.

## Using the templates

**`templates/CLAUDE.md`** — the always-on core. It carries the pin table
(single source of truth for which model each bridge runs), the Gate, the
narrow "do NOT delegate" list, the Claude-subagents-aren't-bridges rule,
the session-start rule, and the instruction to load the pipeline skill
before delegating. Nothing else: everything task-specific was moved out so
this stays cheap to keep in every session's context.

**`templates/skills/delegation-pipeline/SKILL.md`** — the fixed-role
pipeline, loaded on demand. Models are referenced by pin name here, never
by literal:

| Role | Bridge | Job |
|---|---|---|
| Document Analyzer | `antigravity` | Ingest specs/PRDs/docs before planning, produce a requirement matrix |
| Planner & Code Reviewer | Claude Code (you) | Plan the unit from the requirement matrix, hand it to Antigravity, review the diff before QA/Security see it, reconcile findings |
| Coder / Executor | `antigravity` | Implement the plan — write/edit/run code until it works |
| QA Engineer | `codex-qa` | Test the reviewed diff for correctness, edge cases, regressions |
| Security Engineer | `codex-security` | Review the reviewed diff for exploitable issues |
| Release / Changelog Writer | `antigravity` | Draft changelog/doc updates from the accepted diff, once shipped |
| Follow-up on Antigravity work | — | `follow_up` with the returned `session_id`, **within the same role only** — start a fresh call when the pipeline moves to a different Antigravity role |
| Follow-up on `codex-qa` work | — | `codex-reply` with the `threadId` `codex-qa` returned |
| Follow-up on `codex-security` work | — | `codex-reply` with the `threadId` `codex-security` returned |

Roles are pinned, not task-fit routed — Antigravity always analyzes docs,
implements, and drafts release notes (three separate sessions, same
server); `codex-qa` always tests; `codex-security` always reviews for
security. QA and Security run in parallel on the same diff once Claude
Code's own review pass is done; raw output is never piped bridge-to-bridge,
Claude Code always mediates. Independent units are delegated in parallel.

Only `antigravity`, `codex-qa`, and `codex-security` calls run on a separate
vendor's usage quota. Claude's own subagents (`Agent`/`Task` — Explore,
general-purpose, etc.) still burn Claude's own limit, so the core reserves
them for work that needs a tool, permission, or session state only Claude
Code has — not for coding, QA, or security work, which the three bridges
above own outright.

The skill also carries the orchestration rules: checkpoint the progress
file after every pipeline step and every major decision; `/compact` after
checkpointing and before the next unit, `/clear` when switching tasks;
require `file:line` citations and spot-check them before recording results;
on bridge failure retry once, then do the check yourself (there's no
same-role fallback bridge in this pipeline).

**`templates/CLAUDE-two-bridge.overlay.md`** + **`.../delegation-pipeline/two-bridge.md`**
— the two-bridge deltas, split the same way: the always-on half (pin-table
edit, why your Review pass now has to work harder) goes in `CLAUDE.md`, the
pipeline half (step 4, lens prompts, sequential execution) is read
alongside the skill. Only these rows change:

| Role | Bridge | Job |
|---|---|---|
| Planner & Code Reviewer | Claude Code (you) | Same as three-bridge mode, but your Review pass is now the pipeline's primary defense, not a first pass — see the overlay's "Why this is weaker, and what compensates" |
| QA lens | `antigravity` `adversarial_review` | Correctness/edge-case/regression pass, framed as QA |
| Security lens | `antigravity` `adversarial_review` | Exploitability pass, framed as Security — run **after** the QA lens, in its own fresh session |

Everything else — Analyzer, Coder, Release Writer, the Gate, the checkpoint
discipline — is inherited unchanged rather than restated. The lens chain
leads with a different model than the Antigravity pin the Coder role runs
on, so two-bridge mode still gets *some* separation between who writes the
code and who reviews it — it just can't get the two-independent-reviewers
separation three-bridge mode gets from Codex being a wholly separate
vendor. Both lens calls must state their framing explicitly in the prompt
(same tool, different ask) and must run in separate sessions from each
other and from the Coder call.

**`templates/review-topic-template.md`** — the structure for that
`review-<topic>.md` progress file, shared by both modes: context, per-unit
status with cited requirements and delegation session IDs, a gap list, a
"failed approaches" log (so dead ends aren't rediscovered), a "not yet
done" list for the next session, and an archive convention that keeps the
file lean (completed units move to `review-<topic>-archive.md`). It carries
a tally line for each mode — delete whichever doesn't apply to your setup.

Note: the progress-file template uses Indonesian section headers, and the
CLAUDE.md rules refer to them by exact name — the section names are
load-bearing. If you translate one file, translate both.

## Verifying it works

After restarting Claude Code, run `claude mcp list`.

- **Three-bridge mode:** all three bridges — `antigravity`, `codex-qa`,
  `codex-security` — must be connected. An Antigravity call should return a
  `session_id`; a `codex-qa` or `codex-security` call should each return
  their own `threadId` — confirm they're different values even for calls
  about the same diff, since that's the tell that the two Codex instances
  aren't accidentally sharing a session.
- **Two-bridge mode:** `antigravity` must be connected (no Codex entries
  expected). Run one `adversarial_review` call framed as QA and a separate
  one framed as Security, and confirm they return different `session_id`
  values — that's the tell that the two lenses aren't accidentally sharing
  a session.
- **Gate hook (if installed per Setup step 8):** ask Claude Code to `Edit`
  or `Write` any application-code file directly (not a progress file,
  `CLAUDE.md`/`AGENTS.md`, or anything under `.claude/`/`.agents/`/
  `skills/`). A permission prompt quoting the Gate rule should appear
  before the edit is allowed to proceed — that's the hook firing. If it
  doesn't fire, the settings watcher may not have picked up the new hooks
  file; open `/hooks` once (reloads config) or restart.

## Status

The delegation template supports two topologies:

```text
Three-bridge mode:
Claude Code (Planner & Reviewer)
  -> Antigravity (antigravity MCP server, runs agy-bridge, Antigravity pin)
       — Document Analyzer (pre-plan) / Coder-Executor (implement) / Release-Changelog Writer (post-ship)
  -> Codex QA (codex-qa MCP server, profile "qa", QA pin) — QA Engineer
  -> Codex Security (codex-security MCP server, profile "security", Security pin) — Security Engineer

Two-bridge mode (same core + skill, plus the overlay):
Claude Code (Planner & Reviewer — now also primary defense, see the two-bridge overlay)
  -> Antigravity (antigravity MCP server, runs agy-bridge)
       — Document Analyzer / Coder-Executor / Release-Changelog Writer (Antigravity pin)
       — QA lens / Security lens (adversarial_review, lens chain)
```

(Pin names resolve in the `templates/CLAUDE.md` pin table.)

This is the current PoC: a fixed-role pipeline (plan → implement → review →
QA + security in parallel) rather than task-fit routing at the semantic
layer, and it holds until quota pressure becomes the binding constraint. If
it turns out the bottleneck is provider-level quota exhaustion rather than
the pipeline shape — i.e. this setup routes correctly but a bridge still
runs out of headroom — a proxy like [9Router](https://9router.com/)
(account/tier fallback across providers, sitting underneath a bridge's own
API calls) is the next thing to evaluate. It solves a different problem
(quota/cost failover) than this repo does (role-to-provider fit) and would
sit below, not replace, this routing layer.

## Acknowledgements

This repository is an original configuration and template repository; it is
not a fork and does not include source code from its MCP dependencies.

The Antigravity integration uses
[agy-bridge](https://github.com/sshahzaiib/agy-bridge) by Shahzaib Akram as an
external MCP dependency, registered locally under the `antigravity` alias (see
Setup). `agy-bridge` is distributed under the MIT License.

## License

Copyright (c) 2026 Sanovalaw. Licensed under the [MIT License](LICENSE).
