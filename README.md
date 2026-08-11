# agent-bridges

Config and templates for pairing **Claude Code** with two MCP delegation
bridges: **Antigravity** (Gemini, run via the `agy-bridge` MCP server) and
Codex's built-in MCP server. The goal: route each unit of work to whichever
provider is best suited and best positioned on quota to handle it — broad
retrieval, bounded reasoning, or a second opinion — while Claude Code stays
the single agent harness with sole authority to execute, verify, and
integrate the result. A lean context window is a consequence of that
routing, not the goal itself.

## Why

Sending everything through one model, even when it's "free" against that
model's own limit, is still wasteful if a different provider is better
suited or has more headroom left. Antigravity (broad retrieval, second
opinions) and Codex (bounded, deep code reasoning) each cover a different
class of work well; the two bridges let Claude Code route a task to whichever
one fits, instead of doing everything itself or guessing.

Claude Code stays the harness because it's the only party with tool access,
repo/session state, and write permission — a bridge can investigate and
recommend, but only Claude Code can act on the result. That also means Claude
Code owns verification: a delegated finding is not trusted until checked, and
is never the sole basis for an edit without that check (see "Parallelism,
failures, and verification" in `templates/CLAUDE.md`). Reading a 2,000-line
file, diffing a large repo, or running a second-opinion review all burn
context fast, and often the *content* isn't needed, only the *answer* — so as
a side effect, the bridges also return the delegated result without making
Claude Code carry the full investigation in its own context.

## Architecture

- **One direction only.** Claude Code calls both bridges. Neither Antigravity
  nor Codex calls back into Claude Code or the other bridge — no bidirectional
  delegation and no ping-pong loops. This follows directly from Claude Code
  being the harness: execution authority has to stay at one point, not just
  avoiding ping-pong for its own sake.
- **Claude Code = MCP Host** (with an internal MCP client). **Antigravity**
  (registered as the `antigravity` MCP server, running the `agy-bridge`
  package) and **Codex MCP Server** are separate MCP servers exposed over
  JSON-RPC 2.0.
- **Session continuity.** Antigravity uses `follow_up` with its `session_id`.
  Codex uses `codex-reply` with the `threadId` returned by `codex`.

## Repo layout

```
templates/
  CLAUDE.md                  — drop-in delegation + checkpoint rules for a project's CLAUDE.md
  review-topic-template.md   — structure for a persistent review-<topic>.md progress file
```

## Setup

1. Prerequisites: the `agy` CLI installed and authenticated; Node + npx
   available; and the `codex` CLI installed and authenticated.
2. Register both MCP servers at user scope (available in every project on the
   machine). The alias is `antigravity` — the `agy-bridge` npm package is
   just what runs behind it:
   ```bash
   claude mcp add-json -s user antigravity '{"command":"npx","args":["-y","agy-bridge"],"timeout":600000}'
   claude mcp add-json -s user codex '{"command":"codex","args":["mcp-server"],"timeout":600000}'
   ```
3. Verify: `claude mcp list` should show **both** `antigravity` and `codex` as
   **Connected**.
4. Copy `templates/CLAUDE.md` into a target project's `CLAUDE.md` (or merge
   its rules into an existing one) to turn on delegation behavior there.
5. (Team sharing) Instead of user-scope registration, a project can commit a
   `.mcp.json` with the same two server entries so the config travels with
   the repo.

### Operational notes

- **Cold start:** Antigravity's first call in a session takes ~40–50 s;
  subsequent calls in the same session are faster. A slow first call is not
  a hang.
- **Timeouts:** Antigravity per-tool budgets are overridable via the
  underlying `agy-bridge` package's env vars, `AGY_TIMEOUT_<TOOL_NAME>` (or
  `AGY_TIMEOUT` globally). Keep the MCP client timeout ≥ that budget — the
  `timeout: 600000` in step 2 satisfies the recommended minimum.
- **Output cap:** Antigravity truncates responses at `AGY_MAX_OUTPUT_CHARS`
  (default 50,000). Prompts should request high-density, structured analytical findings
  with `file:line` citations (e.g. edge-case matrices, gap tables) rather than unformatted file dumps.
- **Macro-Delegation strategy:** Both Antigravity (Gemini, 1M–2M context) and Codex (128k+ context with deep reasoning) possess massive token capacity. Delegation prompts should send whole feature packages, complete module directories, full spec docs, or entire trace logs at once ("Macro-Delegation") rather than fragmenting work into single-file micro-delegations.

## Using the templates

**`templates/CLAUDE.md`** — delegation rules and provider selection for Claude
Code:

| Situation | Delegate to |
|---|---|
| Whole-module/directory ingestion, broad architecture audit, large log analysis, or web/docs lookup | Antigravity (`analyze_files`, `deep_search`, or `web_lookup`) in a single high-payload call |
| Other heavy self-contained computation (mass summarization, large fixtures) | Antigravity (`delegate`) |
| Cross-module bug tracing, focused review, test-failure analysis, full-feature implementation planning, or bounded refactoring | Codex (`codex`) with `sandbox: read-only` (or `sandbox: workspace` for end-to-end code generation) |
| High-stakes decision (architecture, risky refactor, security-sensitive diff) | Codex **and** Antigravity (`adversarial_review`) — Claude Code reconciles disagreements |
| Follow-up on Antigravity work | `follow_up` with the returned `session_id` |
| Follow-up on Codex work | `codex-reply` with the returned `threadId` |

Raw output is never piped bridge-to-bridge; the encouraged pipeline is
Antigravity gathers (via bulk ingestion) → Claude Code distills → Codex reasons on the distilled
version. Independent units are delegated in parallel.

Only `antigravity` and `codex` calls run on a separate vendor's usage quota.
Claude's own subagents (`Agent`/`Task` — Explore, general-purpose, etc.)
still burn Claude's own limit, so the template treats "should this be a
Claude subagent?" as a real decision, not a default — broad search and
large-file reads route to Antigravity first. When a Claude subagent is
still warranted, it defaults to the orchestrator's model; a cheaper model
is opt-in, reserved for an established pattern of simple, parallelizable,
cheaply-verified work — not a blanket default, since the work left for
Claude subagents after bridge routing skews toward judgment, not mechanics.

Plus orchestration rules: checkpoint the progress file after every
delegation and every major decision; `/compact` after checkpointing and
before the next unit, `/clear` when switching tasks; require `file:line`
citations and spot-check them before recording results; on bridge failure
retry once then fall back; and read the relevant `review-<topic>.md` first
thing on a fresh/post-compaction session instead of reconstructing state
from conversation history.

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

After restarting Claude Code, run `claude mcp list`. Both bridges must be
connected. A Codex delegation should return a `threadId`; use that value in a
`codex-reply` call to continue the same Codex session.

## Status

The delegation template supports this topology:

```text
Claude Code -> Antigravity (antigravity MCP server, runs agy-bridge)
            -> Codex (codex mcp-server)
```

This is the current PoC: route by task-fit at the semantic layer and see how
far it goes before quota pressure becomes the binding constraint. If it turns
out the bottleneck is provider-level quota exhaustion rather than routing
efficiency — i.e. this setup routes correctly but a bridge still runs out of
headroom — a proxy like [9Router](https://9router.com/) (account/tier
fallback across providers, sitting underneath a bridge's own API calls) is
the next thing to evaluate. It solves a different problem (quota/cost
failover) than this repo does (task-to-provider fit) and would sit below,
not replace, this routing layer.

## Acknowledgements

This repository is an original configuration and template repository; it is
not a fork and does not include source code from its MCP dependencies.

The Antigravity integration uses
[agy-bridge](https://github.com/sshahzaiib/agy-bridge) by Shahzaib Akram as an
external MCP dependency, registered locally under the `antigravity` alias (see
Setup). `agy-bridge` is distributed under the MIT License.

## License

Copyright (c) 2026 Sanovalaw. Licensed under the [MIT License](LICENSE).
