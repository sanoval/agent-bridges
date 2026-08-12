# agent-bridges

Config and templates for pairing **Claude Code** with three MCP delegation
bridges in a fixed-role pipeline: **Antigravity** (Gemini 3.6 Flash, run via
the `agy-bridge` MCP server) as **Coder/Executor**, and two pinned instances
of Codex's built-in MCP server — **`codex-qa`** (model 5.6 Terra) as **QA
Engineer** and **`codex-security`** (model 5.6 Sol) as **Security
Engineer**. Claude Code itself plays **Planner and Code Reviewer**, on
whichever model you choose per plan — it stays the single agent harness with
sole authority to execute, verify, and integrate the result. A lean context
window is a consequence of that routing, not the goal itself.

## Why

Sending everything through one model, even when it's "free" against that
model's own limit, is still wasteful if a different provider is better
suited to a specific role. Rather than routing task-by-task, this setup
pins each bridge to a fixed job: Antigravity always writes the code, Codex
QA always tests it, Codex Security always reviews it for exploitable
issues, and Claude Code always plans and does the first review pass before
either Codex role ever sees a diff.

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
  package, pinned to model `Gemini 3.6 Flash`) and **two separate Codex MCP
  Server instances** — `codex-qa` (profile pinned to model `5.6 Terra`) and
  `codex-security` (profile pinned to model `5.6 Sol`) — are three separate
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
  CLAUDE.md                  — drop-in delegation + checkpoint rules for a project's CLAUDE.md
  review-topic-template.md   — structure for a persistent review-<topic>.md progress file
```

## Setup

1. Prerequisites: the `agy` CLI installed and authenticated; Node + npx
   available; and the `codex` CLI installed and authenticated.
2. Pin the two Codex roles to their models via Codex profiles. Add to
   `~/.codex/config.toml`:
   ```toml
   [profiles.qa]
   model = "5.6 Terra"

   [profiles.security]
   model = "5.6 Sol"
   ```
3. Register all three MCP servers at user scope (available in every project
   on the machine). The Antigravity alias is `antigravity` — the
   `agy-bridge` npm package is just what runs behind it. The two Codex
   instances are separate registrations, each pinned to its profile:
   ```bash
   claude mcp add-json -s user antigravity '{"command":"npx","args":["-y","agy-bridge"],"env":{"AGY_DEFAULT_MODEL":"Gemini 3.6 Flash"},"timeout":600000}'
   claude mcp add-json -s user codex-qa '{"command":"codex","args":["--profile","qa","mcp-server"],"timeout":600000}'
   claude mcp add-json -s user codex-security '{"command":"codex","args":["--profile","security","mcp-server"],"timeout":600000}'
   ```
   `AGY_DEFAULT_MODEL` is only a fallback for calls that omit `model` — the
   template in `templates/CLAUDE.md` still has every Antigravity call pass
   `model: "Gemini 3.6 Flash"` explicitly, since that's the only guarantee
   the bridge honors it (see `agy-bridge`'s per-tool model chain).
4. Verify: `claude mcp list` should show **all three** — `antigravity`,
   `codex-qa`, `codex-security` — as **Connected**.
5. Copy `templates/CLAUDE.md` into a target project's `CLAUDE.md` (or merge
   its rules into an existing one) to turn on the role pipeline there.
6. (Team sharing) Instead of user-scope registration, a project can commit a
   `.mcp.json` with the same three server entries (and a checked-in
   `codex` profile config, or documented setup step for it) so the config
   travels with the repo.

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
- **`codex-qa` and `codex-security` are independent processes.** Both run
  the same `codex` binary but with different `--profile` values, so they
  hold separate sessions/threads even for the same diff — a `threadId` from
  one is meaningless on the other.
- **Macro-Delegation strategy:** Both Antigravity (Gemini, 1M–2M context) and
  Codex (128k+ context with deep reasoning) possess massive token capacity.
  Send the full plan and every touched file to Antigravity in one call for
  implementation, and the full diff plus plan/acceptance criteria to
  `codex-qa`/`codex-security` in one call each, rather than fragmenting into
  single-file micro-delegations.

## Using the templates

**`templates/CLAUDE.md`** — delegation rules for a fixed-role pipeline:

| Role | Bridge | Model | Job |
|---|---|---|---|
| Planner & Code Reviewer | Claude Code (you) | Chosen per plan, no fixed pin | Plan the unit, hand it to Antigravity, review the diff before QA/Security see it, reconcile findings |
| Coder / Executor | `antigravity` | Gemini 3.6 Flash | Implement the plan — write/edit/run code until it works |
| QA Engineer | `codex-qa` | 5.6 Terra | Test the reviewed diff for correctness, edge cases, regressions |
| Security Engineer | `codex-security` | 5.6 Sol | Review the reviewed diff for exploitable issues |
| Follow-up on Antigravity work | — | — | `follow_up` with the returned `session_id` |
| Follow-up on `codex-qa` work | — | — | `codex-reply` with the `threadId` `codex-qa` returned |
| Follow-up on `codex-security` work | — | — | `codex-reply` with the `threadId` `codex-security` returned |

Roles are pinned, not task-fit routed — Antigravity always implements,
`codex-qa` always tests, `codex-security` always reviews for security. QA
and Security run in parallel on the same diff once Claude Code's own review
pass is done; raw output is never piped bridge-to-bridge, Claude Code always
mediates. Independent units are delegated in parallel.

Only `antigravity`, `codex-qa`, and `codex-security` calls run on a separate
vendor's usage quota. Claude's own subagents (`Agent`/`Task` — Explore,
general-purpose, etc.) still burn Claude's own limit, so the template
reserves them for work that needs a tool, permission, or session state only
Claude Code has — not for coding, QA, or security work, which the three
bridges above own outright.

Plus orchestration rules: checkpoint the progress file after every pipeline
step and every major decision; `/compact` after checkpointing and before the
next unit, `/clear` when switching tasks; require `file:line` citations and
spot-check them before recording results; on bridge failure retry once, then
do the check yourself (there's no same-role fallback bridge in this
pipeline); and read the relevant `review-<topic>.md` first thing on a
fresh/post-compaction session instead of reconstructing state from
conversation history.

**`templates/review-topic-template.md`** — the structure for that
`review-<topic>.md` progress file: context, per-unit status with cited
requirements and delegation session IDs, a gap list, a "failed approaches"
log (so dead ends aren't rediscovered), a "not yet done" list for the
next session, and an archive convention that keeps the file lean (completed
units move to `review-<topic>-archive.md`).

Note: the progress-file template uses Indonesian section headers, and the
CLAUDE.md rules refer to them by exact name — the section names are
load-bearing. If you translate one file, translate both.

## Verifying it works

After restarting Claude Code, run `claude mcp list`. All three bridges —
`antigravity`, `codex-qa`, `codex-security` — must be connected. An
Antigravity call should return a `session_id`; a `codex-qa` or
`codex-security` call should each return their own `threadId` — confirm
they're different values even for calls about the same diff, since that's
the tell that the two Codex instances aren't accidentally sharing a session.

## Status

The delegation template supports this topology:

```text
Claude Code (Planner & Reviewer)
  -> Antigravity (antigravity MCP server, runs agy-bridge, Gemini 3.6 Flash) — Coder/Executor
  -> Codex QA (codex-qa MCP server, profile "qa", model 5.6 Terra) — QA Engineer
  -> Codex Security (codex-security MCP server, profile "security", model 5.6 Sol) — Security Engineer
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
