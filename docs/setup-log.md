# Setup Log

## 2026-07-23 — agy-bridge MCP registration

Prerequisites confirmed:
- `agy` CLI 1.1.5 installed at `~/.local/bin/agy`, authenticated (verified by controller via `agy --version` and `agy models` without auth prompts; oauth_creds.json exists at ~/.gemini/)
- Node v22.22.0 (nvm), npx available

Command run:
```bash
claude mcp add-json -s user agy-bridge '{"command":"npx","args":["-y","agy-bridge"],"timeout":600000}'
```

Verified with `claude mcp list` — `agy-bridge` shows Connected.

Scope: `-s user`, so available in every project on this machine, not just
this workflow repo.
