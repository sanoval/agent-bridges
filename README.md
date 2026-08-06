# agent-bridges

Config and templates for pairing **Claude Code** with two MCP delegation
bridges: **agy-bridge** for Antigravity (Gemini), and Codex's built-in MCP
server. The goal: keep Claude Code's context window lean by sending large file
reads, repo-wide searches, web lookups, and second-opinion reviews to the
appropriate second model, while Claude Code stays the single orchestrator.

## Why

Claude Code's context is the scarce resource. Reading a 2,000-line file,
diffing a large repo, or running a second-opinion review all burn it fast —
and often the *content* isn't needed in context, only the *answer*. The two
bridges return the delegated result without making Claude Code carry the full
investigation in its own context.

## Architecture

- **One direction only.** Claude Code calls both bridges. Neither Antigravity
  nor Codex calls back into Claude Code or the other bridge — no bidirectional
  delegation and no ping-pong loops.
- **Claude Code = MCP Host** (with an internal MCP client). **agy-bridge** and
  **Codex MCP Server** are separate MCP servers exposed over JSON-RPC 2.0.
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
   machine):
   ```bash
   claude mcp add-json -s user agy-bridge '{"command":"npx","args":["-y","agy-bridge"],"timeout":600000}'
   claude mcp add-json -s user codex '{"command":"codex","args":["mcp-server"],"timeout":600000}'
   ```
3. Verify: `claude mcp list` should show **both** `agy-bridge` and `codex` as
   **Connected**.
4. Copy `templates/CLAUDE.md` into a target project's `CLAUDE.md` (or merge
   its rules into an existing one) to turn on delegation behavior there.

## Using the templates

**`templates/CLAUDE.md`** — delegation rules and provider selection for Claude
Code:

| Situation | Delegate to |
|---|---|
| Large file analysis, broad search, or web/docs lookup | Antigravity (`analyze_files`, `deep_search`, or `web_lookup`) |
| Code-level second opinion, implementation investigation, or review | Codex (`codex`) with `sandbox: read-only` unless a write is explicitly delegated |
| Follow-up on Antigravity work | `follow_up` with the returned `session_id` |
| Follow-up on Codex work | `codex-reply` with the returned `threadId` |

Plus orchestration rules: checkpoint the progress file after every
delegation and every major decision, and read the relevant
`review-<topic>.md` first thing on a fresh/post-compaction session instead
of reconstructing state from conversation history.

**`templates/review-topic-template.md`** — the structure for that
`review-<topic>.md` progress file: context, per-unit status with cited
requirements and delegation session IDs, a gap list, a "failed approaches"
log (so dead ends aren't rediscovered), and a "not yet done" list for the
next session.

## Verifying it works

After restarting Claude Code, run `claude mcp list`. Both bridges must be
connected. A Codex delegation should return a `threadId`; use that value in a
`codex-reply` call to continue the same Codex session.

## Status

The delegation template supports this topology:

```text
Claude Code -> Antigravity (agy-bridge)
            -> Codex (codex mcp-server)
```

## Acknowledgements

This repository is an original configuration and template repository; it is
not a fork and does not include source code from its MCP dependencies.

The Antigravity integration uses
[agy-bridge](https://github.com/sshahzaiib/agy-bridge) by Shahzaib Akram as an
external MCP dependency. `agy-bridge` is distributed under the MIT License.

## License

Copyright (c) 2026 Sanovalaw. Licensed under the [MIT License](LICENSE).
