# agent-bridges

Config and templates for pairing **Claude Code** with three MCP delegation
bridges in a fixed-role pipeline: **Antigravity** (run via the `agy-bridge`
MCP server, pinned to the Antigravity pin — see "Model pins" below), which
plays three roles at different pipeline stages — **Document Analyzer**,
**Coder/Executor**, and **Release/Changelog Writer** — and two pinned
instances of Codex's built-in MCP server — **`codex-qa`** (QA pin) as
**QA Engineer** and **`codex-security`** (Security pin) as **Security
Engineer**. Claude Code itself plays **Planner and Code Reviewer**, on
whichever model you choose per plan — it stays the single agent harness
with sole authority to execute, verify, and integrate the result. A lean
context window is a consequence of that routing, not the goal itself.

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
and verification" in `templates/CLAUDE.md`). Reading a 2,000-line file,
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
  package, pinned to the Antigravity pin) and **two separate Codex MCP
  Server instances** — `codex-qa` (profile pinned to the QA pin) and
  `codex-security` (profile pinned to the Security pin) — are three separate
  MCP servers exposed over JSON-RPC 2.0. `codex-qa` and `codex-security` are
  independent processes even though both run the `codex` binary; they do not
  share sessions.
- **Session continuity.** Antigravity uses `follow_up` with its
  `session_id`. Each Codex instance uses its own `codex-reply` with the
  `threadId` *that same instance* returned — a `codex-qa` threadId is not
  valid on `codex-security`.

## Repo layout

```
templates/
  AGENTS.md                     — shared project memory, read by all three harnesses (see "Centralizing memory" below)
  CLAUDE.md                     — always-on core: role/pin table, the Gate, "Do NOT delegate", checkpoint discipline (both modes)
  CLAUDE-two-bridge-overlay.md  — two-bridge mode: appended to the bottom of a copied CLAUDE.md when no Codex subscription is available
  review-topic-template.md      — structure for a persistent review-<topic>.md progress file, shared by both modes
  settings.hooks.json           — PreToolUse hook config that enforces the CLAUDE.md "Gate" mechanically (see Setup step 8)
  hooks/
    agent-bridges-gate.sh       — the Gate-enforcement hook script referenced by settings.hooks.json
  skills/delegation-pipeline/
    SKILL.md                    — on-demand: pipeline steps, payload contracts, session continuity, example prompts (both modes)
    two-bridge.md                — two-bridge deltas to SKILL.md: step 4 replacement, adversarial_review lens calls
  skills/learning-curator/
    SKILL.md                    — on-demand: post-verification learning — classification, evidence scoring, hard gates, local staging/promote-on-approval, security controls (pipeline step 7, both modes)
    proposal-template.md        — format for a pending learning proposal staged under .agent-bridges/learning/pending/ in the target project
```

## Centralizing memory across harnesses

Each harness reads its own memory file at session/subprocess start, and
without coordination that becomes three copies of the same project facts
drifting apart. They don't need to, because the three formats compose:

- **Codex** reads `AGENTS.md` natively — no configuration needed, it just
  looks for that file.
- **Claude Code** reads `CLAUDE.md`, which opens with an `@AGENTS.md` import
  line (the two-bridge overlay, appended below it, doesn't repeat the
  import), so Claude Code pulls in the same content Codex reads directly.
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

Two skills ship with this repo itself — see "Using the templates" below.
Both are orchestrator-facing (Claude Code/Antigravity only) and are never
pasted into a Codex call: `delegation-pipeline` and `learning-curator`.

## Learning-curator staging

`learning-curator` (see "Using the templates") writes to two places in a
target project, and they carry deliberately different git visibility —
worth understanding before Setup step 10 below:

- **`AGENTS.md` / `skills/<name>/SKILL.md`** — the same git-tracked,
  shared-with-every-harness files `templates/AGENTS.md` and `skills/`
  already are. A mutation lands here only once it's either auto-applied
  (evidence score ≥5, every hard gate passed) or a human has approved a
  pending proposal. Once it's here, it's exactly as trusted as any other
  project fact or skill — it's what all three harnesses read.
- **`.agent-bridges/learning/pending/`** — proposals awaiting human
  review (evidence score 3-4, or a ≥5 that failed a hard gate). This
  directory is **gitignored**, not committed, local working state only.

The split matters because an auto-applied or approved mutation writes
directly into files every harness treats as ground truth, with no PR
review in between — the same trust boundary
[Hermes Agent](https://hermes-agent.nousresearch.com/docs/user-guide/features/skills)
draws between an agent's own procedural memory (`~/.hermes/skills/`, never
committed to any project) and a repo's vendored skills (committed, but
requiring an explicit `hermes skills trust` before they're loaded). Here
that boundary is: unreviewed curator output never touches the git-tracked
surface at all, staying local until a human promotes it — only reviewed
(or hard-gate-cleared) output ever becomes a tracked file. `.agent-bridges/learning/log.md`
sits on the tracked side deliberately — it only ever records mutations
that already hit `AGENTS.md`/`skills/`, so it carries no more exposure
than those mutations already did.

## Which mode do I need?

- **Have a Codex subscription too?** Use `templates/CLAUDE.md` as-is
  (three-bridge mode). QA and Security get their own independent
  model/process each.
- **Only Claude Code + Antigravity subscriptions?** Copy
  `templates/CLAUDE.md` and append
  `templates/CLAUDE-two-bridge-overlay.md` to the bottom of it (two-bridge
  mode). Same pipeline shape, but QA and Security fold into two
  separately-framed Antigravity `adversarial_review` passes instead of two
  dedicated bridges — weaker independence, since both lenses ultimately
  come from one vendor's model family; the overlay's "Why this is weaker,
  and what compensates" section explains what that costs and why your own
  Review step has to work harder as a result.

## Setup

### Model pins

`templates/CLAUDE.md`'s "Model pins" table is the source of truth for every
model value this pipeline uses. The commands below are the only other place
a literal value may appear — keep them in sync with that table if a pin ever
changes.

1. Prerequisites: the `agy` CLI installed and authenticated; Node + npx
   available; and — **three-bridge mode only** — the `codex` CLI installed
   and authenticated. Two-bridge mode needs only `agy`.
2. **Three-bridge mode only** — pin the two Codex roles to their models via
   Codex profiles. Add to `~/.codex/config.toml`:
   ```toml
   [profiles.qa]
   model = "5.6 Terra"

   [profiles.security]
   model = "5.6 Sol"
   ```
   Skip this step entirely in two-bridge mode — there's no Codex to profile.
3. Register the MCP server(s) at user scope (available in every project on
   the machine). The Antigravity alias is `antigravity` — the `agy-bridge`
   npm package is just what runs behind it.
   - **Two-bridge mode** — register Antigravity only:
     ```bash
     claude mcp add-json -s user antigravity '{"command":"npx","args":["-y","agy-bridge"],"env":{"AGY_DEFAULT_MODEL":"Gemini 3.6 Flash"},"timeout":600000}'
     ```
   - **Three-bridge mode** — register Antigravity plus the two pinned Codex
     instances:
     ```bash
     claude mcp add-json -s user antigravity '{"command":"npx","args":["-y","agy-bridge"],"env":{"AGY_DEFAULT_MODEL":"Gemini 3.6 Flash"},"timeout":600000}'
     claude mcp add-json -s user codex-qa '{"command":"codex","args":["--profile","qa","mcp-server"],"timeout":600000}'
     claude mcp add-json -s user codex-security '{"command":"codex","args":["--profile","security","mcp-server"],"timeout":600000}'
     ```
   `AGY_DEFAULT_MODEL` is only a fallback for calls that omit `model` —
   `templates/CLAUDE.md` still has every Coder/Analyzer/Release-Writer
   Antigravity call pass `model:` set to the Antigravity pin explicitly
   (QA/Security lens calls in two-bridge mode intentionally don't — see
   `templates/skills/delegation-pipeline/two-bridge.md`), since that's the
   only guarantee the bridge honors it (see `agy-bridge`'s per-tool model
   chain).
4. Verify: `claude mcp list` should show `antigravity` **Connected**
   (two-bridge mode), or `antigravity`, `codex-qa`, and `codex-security`
   **all three Connected** (three-bridge mode).
5. Copy `templates/CLAUDE.md` into a target project's `CLAUDE.md` (or merge
   its rules into an existing one) to turn on the role pipeline there — it
   starts with an `@AGENTS.md` import, do not strip that line. **Two-bridge
   mode only:** also append `templates/CLAUDE-two-bridge-overlay.md` to the
   bottom of the copied `CLAUDE.md`.
6. Centralize project memory: copy `templates/AGENTS.md` into the target
   project's root `AGENTS.md` (or merge it into an existing one — Codex and
   Antigravity both already read this file natively if the project has
   one, no extra step needed). See "Centralizing memory across harnesses"
   above.
7. Centralize skills: create (or move existing custom skills into) a
   `skills/<name>/SKILL.md` directory at the project root, then symlink
   both harnesses' discovery paths to it:
   `ln -s skills .claude/skills && ln -s skills .agents/skills`. Copy
   `templates/skills/delegation-pipeline/` into that directory — keep
   `two-bridge.md` in two-bridge mode, delete it in three-bridge mode. Keep
   the "Available skills" list in `AGENTS.md` in sync — Codex reads it there
   but can't discover `skills/` on its own.
8. **Enforce the Gate mechanically (recommended).** The "Gate" section in
   `templates/CLAUDE.md` is prose — it shapes Claude Code's behavior but
   nothing stops it from editing a file directly if it judges a change
   "small enough." To turn that into a real
   checkpoint instead of an honor system, copy
   `templates/hooks/agent-bridges-gate.sh` into the target project as
   `.claude/hooks/agent-bridges-gate.sh` (`chmod +x` it), then merge the
   `hooks` block from `templates/settings.hooks.json` into the project's
   `.claude/settings.json` (merge, don't overwrite, if hooks already exist
   there). This installs a `PreToolUse` hook on `Edit`/`Write`/
   `NotebookEdit`: edits to progress files (`review-*.md`), project memory
   (`CLAUDE.md`/`AGENTS.md`/`GEMINI.md`), delegation config (`.claude/`,
   `.agents/`), `skills/`, or learning-curator working state
   (`.agent-bridges/`) pass through untouched; everything else
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
10. **Enable the learning curator (optional, recommended).** Copy
    `templates/skills/learning-curator/` into the target project's
    `skills/` directory alongside `delegation-pipeline/` (same symlink
    setup from step 7 covers it — nothing extra to link). Create
    `.agent-bridges/learning/log.md` (empty file, committed) in the target
    project, then add this line to the project's `.gitignore`:
    ```
    .agent-bridges/learning/pending/
    ```
    Do **not** gitignore `.agent-bridges/learning/log.md` itself — only the
    `pending/` subdirectory. See "Learning-curator staging" above for why
    the two are treated differently. Keep the "Available skills" entry in
    `AGENTS.md` in sync, same as any other skill (already done if you
    copied `templates/AGENTS.md`'s "Skills"/"Learning" sections as-is).

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

**`templates/CLAUDE.md`** — the always-on core, copied into a target
project's `CLAUDE.md` for both modes. Carries the Model pins table, the
Roles table (see "Which mode do I need?" and the template itself for the
full role/bridge/pin breakdown — it is not repeated here to avoid a second
copy drifting out of sync), the Gate, "Do NOT delegate", "Claude subagents
are not bridge delegation", and the always-on half of checkpoint discipline
(read `review-<topic>.md` first on session start, checkpoint after every
step/decision, `/compact`/`/clear` between units).

Roles are pinned, not task-fit routed — Antigravity always analyzes docs,
implements, and drafts release notes (three separate sessions, same
server); `codex-qa` always tests; `codex-security` always reviews for
security (three-bridge mode). QA and Security run in parallel on the same
diff once Claude Code's own review pass is done; raw output is never piped
bridge-to-bridge, Claude Code always mediates. Independent units are
delegated in parallel.

Only `antigravity`, `codex-qa`, and `codex-security` calls run on a separate
vendor's usage quota. Claude's own subagents (`Agent`/`Task` — Explore,
general-purpose, etc.) still burn Claude's own limit, so the template
reserves them for work that needs a tool, permission, or session state only
Claude Code has — not for coding, QA, or security work, which the three
bridges above own outright.

**`templates/skills/delegation-pipeline/SKILL.md`** — loaded on demand
(both modes) rather than kept always-on: the numbered pipeline steps 0–6,
Macro-Delegation payload contracts, session-continuity rules
(`follow_up`/`codex-reply` scoping), example delegation prompts, the
verification bar (`file:line` citations, spot-checking), and the full
orchestration rules (checkpoint contents, archive convention, self-audit
before marking a unit SELESAI).

**`templates/CLAUDE-two-bridge-overlay.md`** — appended to the bottom of a
copied `CLAUDE.md` in two-bridge mode. Declares the mode, overrides the
QA/Security rows to QA lens / Security lens (both `antigravity` via
`adversarial_review`, model chain Gemini 3.1 Pro high → Claude Opus 4.6 →
Flash — deliberately *not* the Antigravity pin, so the reviewing model
differs from the Coder role's), carries "Why this is weaker, and what
compensates" (your own Review step becomes the pipeline's primary defense,
not a first pass), and points at
`templates/skills/delegation-pipeline/two-bridge.md` for the pipeline-
mechanics deltas: step 4 replaced by two sequential lens calls (not
parallel — same server), each lens call stating its framing explicitly and
running in its own fresh session (never `follow_up` one lens into the
other or into the Coder session).

**`templates/skills/learning-curator/SKILL.md`** — loaded on demand as
step 7 of the delegation pipeline, after a unit passes final verification.
Non-blocking: it never gates release, and a curator failure never turns a
successful unit into a failed one. It classifies the unit's outcome as
NOOP, project memory, a patch to an existing skill, or a new skill, using
an evidence-provenance score (not a model-invented confidence number) to
decide whether a mutation is safe to auto-apply, must be staged for human
review, or dropped. Mutations that reach `AGENTS.md`/`skills/` directly
(auto-applied or human-approved) are git-tracked like any other project
file; proposals still awaiting review are staged locally under
`.agent-bridges/learning/pending/` and are **not** — see "Learning-curator
staging" above for why that boundary exists and what it means for setup.

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
- **Learning-curator staging (if enabled per Setup step 10):** run
  `git status` after a unit where the curator staged a PENDING proposal —
  `.agent-bridges/learning/pending/` should **not** appear as untracked
  (confirms `.gitignore` is catching it), while a staged or promoted change
  to `AGENTS.md`/`skills/`/`.agent-bridges/learning/log.md` should appear
  as a normal tracked diff.

## Status

The delegation template supports two topologies:

```text
Three-bridge mode:
Claude Code (Planner & Reviewer)
  -> Antigravity (antigravity MCP server, runs agy-bridge, Antigravity pin)
       — Document Analyzer (pre-plan) / Coder-Executor (implement) / Release-Changelog Writer (post-ship)
  -> Codex QA (codex-qa MCP server, profile "qa", QA pin) — QA Engineer
  -> Codex Security (codex-security MCP server, profile "security", Security pin) — Security Engineer

Two-bridge mode:
Claude Code (Planner & Reviewer — now also primary defense, see CLAUDE-two-bridge-overlay.md)
  -> Antigravity (antigravity MCP server, runs agy-bridge)
       — Document Analyzer / Coder-Executor / Release-Changelog Writer (Antigravity pin)
       — QA lens / Security lens (adversarial_review chain: Gemini 3.1 Pro high -> Claude Opus 4.6 -> Flash)
```

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
