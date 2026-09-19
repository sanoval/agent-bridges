# Migrating the Antigravity bridge: `agy-bridge` → `agy-mcp`

**Applies to:** agent-bridges `0.2.x` → `0.3.0`.
**Status:** this guide describes `0.3.0`. Do not follow it until `0.3.0` is
released — on `0.2.x` the plugin still registers `agy-bridge` and none of
the tool names below exist.

## Why this migration exists

`agy-bridge` makes **blocking** MCP calls with a per-tool timeout ceiling.
Its `delegate` budget (600s) is the same value as the client-side timeout
the install instructions recommend, so there is no margin: a slow call races
two identical deadlines and you experience it as a ten-minute hang that ends
in nothing. A Coder delegation is exactly the call most likely to be slow —
the pipeline deliberately sends it a whole plan and every touched file at
once (see "Macro-Delegation" in the `delegation-pipeline` skill).

`agy-mcp` does not block. `agy_run` starts a managed job, returns a
`job_id` immediately, and persists the result to disk. A `PostToolUse` hook
wakes Claude Code when the job finishes. A slow job is then just a slow job
— it never occupies a request that can time out.

This is an architectural fix, not a reliability upgrade of the dependency
itself: both projects are MIT-licensed and effectively single-maintainer.
Migrate for the async job model, not because the new dependency is better
maintained.

## What breaks

| | `agy-bridge` (0.2.x) | `agy-mcp` (0.3.0) |
|---|---|---|
| Install | none — `npx -y agy-bridge` fetches on demand | **a real binary you install yourself** (Homebrew or `go install`) |
| Call model | blocking, per-tool timeout ceiling | async job + `job_id`, polled or woken by hook |
| Tools | 6 semantic tools (`analyze_files`, `deep_search`, `web_lookup`, `adversarial_review`, `follow_up`, `delegate`) | generic job tools (`agy_run`, `agy_run_sync`, `agy_status`, `agy_wait`, `agy_cancel`, `list_models`, `list_agents`, `list_sessions`) |
| Role selection | which tool you call | `agy_run` + prompt framing + explicit `model` |
| Session continuity | `follow_up(session_id)` | `agy_run(conversation_id=…)` |
| Model fallback chain | automatic (e.g. Flash → Pro) | **none — you retry explicitly** |
| Read-only enforcement | prompt text only | `mode: "plan"` — enforced by the tool |
| Output size guard | `AGY_MAX_OUTPUT_CHARS` (50k truncation) | **none — use `json_schema` instead** |
| Minimum `agy` CLI | not pinned | **1.1.15 or newer (hard floor)** |

Two of these are genuine upgrades worth the churn: `mode: "plan"` makes the
Analyzer / Release-Writer / review calls mechanically read-only instead of
read-only-by-request, and `json_schema` bounds output by structure instead
of by blind character truncation.

Two are genuine losses you must compensate for: the install is no longer
free, and the automatic model fallback chain is gone.

## Prerequisites

1. **`agy` CLI 1.1.15 or newer.** This is a hard floor for `agy-mcp`, not a
   recommendation. Check with `agy --version` and upgrade if older.
2. **Homebrew or Go 1.27+**, to install the bridge binary.

## Migration steps

### 1. Resolve duplicate `antigravity` registrations first

Before changing anything, check whether you have more than one MCP server
named `antigravity`. Many 0.2.x users do: the plugin ships one in its own
`.mcp.json`, and a manual copy is often also present at user scope in
`~/.claude.json` under `mcpServers.antigravity`, left over from before the
plugin existed.

Two registrations under one name is its own source of trouble — the two
copies drift (different `AGY_DEFAULT_MODEL` values are common) and which one
wins is not something you should have to reason about.

```bash
claude mcp list
```

If a user-scope `antigravity` entry exists in `~/.claude.json`, **remove
that entry** and let the plugin own the registration. Keep a copy of what
you deleted until the migration is verified — it is your rollback.

### 2. Install the bridge binary

```bash
brew install tphakala/tap/agy-mcp
```

or:

```bash
go install github.com/tphakala/agy-mcp/v2@latest
```

Confirm it resolves:

```bash
agy-mcp --version
which agy-mcp
```

If `agy-mcp` is not on your `PATH`, set `AGY_MCP_AGY_PATH`'s sibling
setting for the bridge itself by giving the full binary path as the MCP
server `command` (step 3), or put it on `PATH`. Note that
`AGY_MCP_AGY_PATH` points at the **`agy` CLI**, not at `agy-mcp` — set it
only if `agy` itself is somewhere non-standard.

### 3. Update the plugin

```
/plugin install agent-bridges@agent-bridges --update
```

`0.3.0` registers the `antigravity` server as the `agy-mcp` binary and adds
the completion-wake `PostToolUse` hook. You do not edit `.mcp.json` or
`hooks.json` yourself — both are plugin-owned.

**The server keeps the name `antigravity`**, not the upstream's `agy`. The
role vocabulary in `CLAUDE.md`, the skills, and every progress file is built
on that name. The practical consequence: upstream `agy-mcp` documentation
and issue threads refer to tools as `mcp__agy__agy_run`, while yours are
`mcp__antigravity__agy_run`. Translate accordingly when reading upstream
material.

### 4. Verify your model pins are IDs, not display labels

`agy-mcp` requires the model **ID**. The `agy` CLI prints models as
`<id>\t<display name>`, and a display label passed as an ID is rejected.

Run the bridge's own `list_models` tool and confirm your Antigravity pin
from `CLAUDE.md`'s "Model pins" table appears there verbatim as an ID. Fix
the pin if it does not.

### 5. Two-bridge mode only: replace the `adversarial_review` chain

Skip this section entirely if you run three-bridge mode (Codex QA/Security).

Two-bridge mode leaned on `adversarial_review`'s built-in chain (Gemini 3.1
Pro high → Claude Opus 4.6 → Flash) for its QA and Security lenses, and the
overlay explicitly told you *not* to force the Antigravity pin onto those
two calls. That chain does not exist in `agy-mcp`. Without action, both
lenses would silently fall back to the Coder's own model — Antigravity
reviewing its own work with no model independence at all, which removes the
last thing that made two-bridge mode worth running.

Replace it with two explicit pins — and take the opportunity to fix
something the old tool could not do.

`adversarial_review` had exactly one preference chain, so both lenses
always resolved to the *same* model. That is the weakness the overlay
admits to: you got a reviewer that wasn't the Coder, but you did not get
two reviewers with independent blind spots. Explicit pins let you assign a
different model per lens, so the migration can restore that second
property instead of merely preserving the first.

In your project's `CLAUDE.md` "Model pins" table, add:

| Pin | Value | Applies to |
|---|---|---|
| QA lens pin | `gemini-3.1-pro-high` | Every two-bridge QA lens call |
| Security lens pin | `claude-opus-4-6-thinking` | Every two-bridge Security lens call |

Verify both IDs appear in your own `list_models` output before relying on
them — model availability is per-account, and these are the IDs from one
account, not a guarantee about yours.

The split is deliberate. QA claims are checkable against ground truth — a
test either passes or it doesn't — so model identity matters less there,
and `gemini-3.1-pro-high` keeps continuity with what the QA lens has been
running on all along. Security claims are the opposite: you cannot run a
test that proves "not exploitable," so the finding rests on the model's
judgment alone. Put the most independent, strongest-reasoning model you
have on the lens whose output you can least verify — and on an account
where the Coder runs a Google model, an Anthropic one is the genuinely
different family.

Whatever you choose, the rule is: both pins differ from the Antigravity
pin, and from each other.

### 6. Verify end to end

- `claude mcp list` shows exactly one `antigravity`, connected.
- An `agy_run` call returns a `job_id` immediately instead of blocking.
- When that job finishes, Claude Code is woken with a one-line completion
  message naming the `job_id` — this is the hook working. If the job
  completes but nothing wakes you, see Troubleshooting.
- `agy_status` on that `job_id` returns its state and result.
- A call with `mode: "plan"` leaves the working tree untouched
  (`git status` clean afterwards).
- The Gate hook still fires on a direct `Edit`/`Write` — the migration must
  not have disturbed it.

## What you must re-learn as a user

**Delegation no longer blocks.** Step 2 (Implement) returns a `job_id`, not
a diff. You will be woken when it lands. This is the intended behavior, not
a failure — resist the reflex to re-fire the call because "nothing
happened."

**"No longer hangs" is not the same claim as "faster."** The underlying
model call takes however long it takes — what changed is that you're no
longer sitting on one blocking request racing a 600-second ceiling.
Resist reporting this migration as a speed improvement unless you actually
measured wall-clock time on the same kind of task before and after;
absent that measurement, the honest claim is "stopped timing out," not
"got faster." The one place a real speed difference is plausible is
process startup: `agy-bridge` is resolved fresh over `npx` on every
launch, `agy-mcp` is a pre-compiled binary already on disk — but that's
milliseconds of cold-start, not the minutes a hung `delegate` call used to
cost you.

**Failures are now explicit, and that is the point.** Quota exhaustion
comes back as `failure_reason: "quota_exhausted"` with the reset window,
immediately, instead of being silently absorbed by a fallback chain that
eats your wall clock. The pipeline's existing rule is unchanged: retry
once, then do the work yourself and record the skip in the progress file.

**Ask for structured output, and mean it.** The 50k-character truncation
that used to protect your context is gone. Use `json_schema` on review-type
calls so the shape of the output is enforced rather than hoped for.

## Rollback

The migration is reversible and the rollback is local — you do not need a
plugin release to get back.

Re-add the `antigravity` server at user scope in `~/.claude.json` with the
0.2.x definition you saved in step 1:

```json
{
  "command": "npx",
  "args": ["-y", "agy-bridge"],
  "env": { "AGY_DEFAULT_MODEL": "<your Antigravity pin>" },
  "timeout": 600000
}
```

Then disable the `agent-bridges` plugin for the project (`/plugin`) so its
`0.3.0` registration and `PostToolUse` hook stop applying, and restart
Claude Code. You are back on the blocking bridge, including its timeout
behavior.

Report what pushed you back — a rollback that nobody hears about is a bug
that stays fixed only for you.

## Troubleshooting

**`agy not found on PATH`** — `agy-mcp` starts fine without the `agy` CLI
(tool discovery and `list_sessions` still work), and fails per-call
instead. Install `agy`, or set `AGY_MCP_AGY_PATH` to its full path.

**Jobs finish but never wake Claude Code** — the `PostToolUse` hook is the
only thing that surfaces completion, because Claude Code does not surface
MCP server notifications on its own. Check that `agy-mcp` is on `PATH` for
the hook's shell too (the hook runs `agy-mcp hook-wait`), and that the
plugin is enabled for this project. The hook is built to fail silently — on
any internal error it exits 0 rather than disrupting your tool call — so a
broken hook looks like nothing happening, not like an error. Poll
`agy_status` manually in the meantime; no work is lost.

**A model ID is rejected** — you are passing a display label. See step 4.

**Two jobs you did not start** — `agy_run` accepts an `idempotency_key`.
Reusing one key for the same normalized request returns the existing job
instead of starting a second; bindings last 24 hours. Use it if a flaky
transport is causing duplicate dispatches.

**Ephemeral workspaces flooding `list_sessions`** — a known upstream issue
(#167). Filter by `dir`.
