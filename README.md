# agent-bridges

A fixed-role delegation pipeline that pairs **Claude Code** with three MCP
bridges, each with one fixed job:

| Role | Bridge |
|---|---|
| Document Analyzer, Coder/Executor, Release-Changelog Writer | **Antigravity** (`agy-bridge` MCP server) |
| QA Engineer | **Codex QA** (`codex-qa`) |
| Security Engineer | **Codex Security** (`codex-security`) |
| Planner and Code Reviewer, final say on every bridge output | **Claude Code** |

Claude Code is the only agent with tool access, repo/session state, and
write permission — it plans, reviews first, and owns verification (a
delegated finding is never the sole basis for an edit until checked; see
"Parallelism, failures, and verification" in `templates/CLAUDE.md`).

## Why

Routing everything through one model is wasteful when another provider
fits a role better. Antigravity ingests specs, writes the code, then
drafts release notes; Codex QA always tests the diff; Codex Security
always reviews it for exploits; Claude Code always plans, reviews before
either Codex role sees a diff, and has final say — including over the
docs Antigravity drafts. Delegating also keeps Claude Code's own context
free of work — reading a large file, diffing a big repo, running QA/
security — where only the *answer* is needed, not the investigation.

For the full design rationale (topology, session continuity, memory
sharing across harnesses, learning-curator internals), see
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Install

No clone needed — Claude Code pulls this repo itself. Run these as two
separate commands, not as one pasted block — pasting both lines at once
can merge them into a single command and break the owner/repo argument:

```
/plugin marketplace add sanoval/agent-bridges
```

```
/plugin install agent-bridges@agent-bridges
```

This registers all three MCP servers (`antigravity`, `codex-qa`,
`codex-security`), the `delegation-pipeline` and `learning-curator`
skills, and the Gate `PreToolUse` hook — and keeps them current
(`/plugin install agent-bridges@agent-bridges --update` to force a check).

Not on a Codex subscription? `codex-qa`/`codex-security` will simply fail
to connect (`claude mcp list` shows them **Failed**) — harmless in
two-bridge mode, see "Which mode do I need?" below.

**Scope this to the projects that actually run the pipeline.** The Gate
hook fires on every `Edit`/`Write`/`NotebookEdit` in any project where the
plugin is enabled — enable it per-project (project `.claude/settings.json`
`enabledPlugins`) rather than at user scope, or you'll get Gate prompts in
unrelated repos. See [Configure team marketplaces](https://code.claude.com/docs/en/discover-plugins#configure-team-marketplaces).

Installing the plugin covers Claude Code. Antigravity/Codex CLIs, model
pins, and copying `CLAUDE.md`/`AGENTS.md` into your project are separate,
still-manual steps — see **[docs/SETUP.md](docs/SETUP.md)** for the full
walkthrough and **"Verifying it works"** in that doc once you're done.

## Usage

Once setup is verified, see **[docs/USAGE.md](docs/USAGE.md)** for what a
day-to-day session looks like: how to start a unit of work, what the Gate
hook will ask you to approve, what happens automatically (checkpointing,
learning), and a narrated end-to-end example.

## Which mode do I need?

- **Have a Codex subscription too?** Use `templates/CLAUDE.md` as-is
  (three-bridge mode). QA and Security get their own independent
  model/process each.
- **Only Claude Code + Antigravity?** Copy `templates/CLAUDE.md` and
  append `templates/CLAUDE-two-bridge-overlay.md` (two-bridge mode). QA
  and Security fold into two separately-framed Antigravity
  `adversarial_review` passes instead of dedicated bridges — weaker
  independence (one vendor's model family for both lenses); the overlay
  explains what that costs and why your own Review step has to work
  harder.

## Acknowledgements

This is an original configuration/template repository — not a fork, no
source code from its MCP dependencies included.

The Antigravity integration uses
[agy-bridge](https://github.com/sshahzaiib/agy-bridge) by Shahzaib Akram
as an external MCP dependency (registered locally as `antigravity`),
distributed under the MIT License.

## License

Copyright (c) 2026 Sanovalaw. Licensed under the [MIT License](LICENSE).
