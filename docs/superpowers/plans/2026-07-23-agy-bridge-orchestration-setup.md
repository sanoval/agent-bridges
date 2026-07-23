# agy-bridge Orchestration Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Claude Code the single entry point for day-to-day work, able to
delegate heavy tasks to Antigravity via the `agy-bridge` MCP server, with a
reusable delegation-rules file and a context-checkpoint template so long
sessions don't lose decisions or repeat failed approaches.

**Architecture:** Register `agy-bridge` as a user-scoped MCP server in Claude
Code (works identically from CLI and the VS Code extension). Author a
project-installable `CLAUDE.md` that layers our checkpoint/no-reverse-delegation
rules on top of agy-bridge's own bundled delegation rules. Author a
progress-notes template (extending `session-progress-notes`) with an added
"pendekatan yang sudah dicoba & gagal" section. Verify end-to-end with a real
delegation + `follow_up` call.

**Tech Stack:** Claude Code CLI, `agy-bridge` MCP server (Node/npx), Antigravity
CLI (`agy` 1.1.5, already installed at `~/.local/bin/agy`), git.

## Global Constraints

- Delegation is one-directional only: Claude Code → Antigravity. Never
  configure or accept a reverse channel (Antigravity → Claude Code) per the
  approved design doc (`docs/superpowers/specs/2026-07-23-claude-code-antigravity-orchestration-design.md`).
- MCP server registration uses `-s user` scope so it's available in every
  project, not just this workflow repo.
- All template/config files produced by this plan live in this repo
  (`~/claude-antigravity-workflow`) and get copied into target projects
  manually — this plan does not modify any other project.
- No placeholders in produced files — `CLAUDE.md` and the progress-notes
  template must contain complete, usable rules, not "TBD" sections.

---

### Task 1: Register agy-bridge and verify prerequisites

**Files:**
- Create: `docs/setup-log.md`

**Interfaces:**
- Consumes: nothing (first task)
- Produces: a registered `agy-bridge` MCP server visible to `claude mcp list`
  in every project on this machine; `docs/setup-log.md` documents the exact
  commands so the setup is reproducible on another machine.

- [ ] **Step 1: Confirm Antigravity CLI is installed and authenticated**

Run:
```bash
agy --version
```
Expected: prints `1.1.5` (already confirmed installed at `~/.local/bin/agy`).

Then, in an interactive terminal (not scriptable — run this yourself,
not via a non-interactive tool call):
```bash
agy -i
```
Expected: confirms an already-authenticated account, or walks through login
if not yet authenticated. Do not proceed to Step 2 until this shows an
authenticated account.

- [ ] **Step 2: Register the agy-bridge MCP server**

Run:
```bash
claude mcp add-json -s user agy-bridge '{"command":"npx","args":["-y","agy-bridge"],"timeout":600000}'
```
Expected: output confirms `agy-bridge` added at user scope.

- [ ] **Step 3: Verify registration**

Run:
```bash
claude mcp list
```
Expected: output includes a line for `agy-bridge` with a `✔ Connected`
(or equivalent healthy) status. If it shows a connection error, do not
proceed — re-check Step 1 (agy CLI auth) and Node/npx availability
(`node --version` should print `v22.22.0` or newer, already confirmed
present via nvm).

- [ ] **Step 4: Write the setup log**

Create `docs/setup-log.md`:

```markdown
# Setup Log

## 2026-07-23 — agy-bridge MCP registration

Prerequisites confirmed:
- `agy` CLI 1.1.5 installed at `~/.local/bin/agy`, authenticated via `agy -i`
- Node v22.22.0 (nvm), npx available

Command run:
\`\`\`bash
claude mcp add-json -s user agy-bridge '{"command":"npx","args":["-y","agy-bridge"],"timeout":600000}'
\`\`\`

Verified with `claude mcp list` — `agy-bridge` shows Connected.

Scope: `-s user`, so available in every project on this machine, not just
this workflow repo.
```

- [ ] **Step 5: Commit**

```bash
git add docs/setup-log.md
git commit -m "docs: log agy-bridge MCP registration steps"
```

---

### Task 2: Author the delegation-rules CLAUDE.md template

**Files:**
- Create: `templates/CLAUDE.md`

**Interfaces:**
- Consumes: agy-bridge's bundled delegation rules (fetched from
  `https://raw.githubusercontent.com/sshahzaiib/agy-bridge/main/CLAUDE.md`)
  and the design doc's checkpoint/no-reverse-delegation rules.
- Produces: `templates/CLAUDE.md` — copied verbatim into any project that
  wants this orchestration setup (`cp templates/CLAUDE.md <project>/CLAUDE.md`,
  or appended to an existing project `CLAUDE.md`).

- [ ] **Step 1: Write the template file**

Create `templates/CLAUDE.md`:

```markdown
# Delegation rules: agy-bridge

You have agy-bridge MCP tools that delegate heavy work to the Antigravity CLI
(Gemini). Delegation keeps large content OUT of your context — only answers
come back. Prefer delegating over doing it yourself when:

- **Any file >200 lines** you'd otherwise read → `analyze_files`
- **More than 3 files** in one analysis/comparison → `analyze_files`
- **Git history or repo-wide searches** (git log/diff/blame, broad greps) → `deep_search`
- **Web/documentation lookups** → `web_lookup`
- **Plan critique or code review** → `adversarial_review` (always — a second
  model family catches what you miss)
- **Follow-up question on a prior delegation** → `follow_up` with the returned
  session id (never resend the context)

Do NOT delegate: small single-file edits, questions you can answer from
context already loaded, or tasks needing tools only you have.

## Orchestration rules (project-specific, layered on top of the above)

- **One direction only.** You (Claude Code) are always the one calling
  agy-bridge tools. Never configure or invoke a path where Antigravity
  calls back into Claude Code — this project's design explicitly rejects
  bidirectional delegation to avoid ping-pong loops.
- **Checkpoint the progress file after every delegation.** Immediately
  after a `delegate`, `analyze_files`, `deep_search`, `web_lookup`, or
  `adversarial_review` call returns and you've verified the result, update
  the active `review-<topic>.md` progress file (see
  `templates/review-topic-template.md` for structure) with: what was
  delegated, the session id (for `follow_up`), and the verified outcome.
  Do this before starting the next unit of work — do not wait until the
  session ends.
- **Checkpoint after every major decision.** If you choose one approach
  over another, or rule an approach out, write it to the progress file's
  "Pendekatan yang sudah dicoba & gagal" section immediately, with the
  reason. A future session (or a future delegation) must not have to
  rediscover a dead end.
- **On session start (fresh context or post-compaction):** read the
  relevant `review-<topic>.md` first. Do not try to reconstruct state from
  raw conversation history. Re-verify any claim that names a specific file
  or function before acting on it — code may have changed since the note
  was written.
```

- [ ] **Step 2: Verify the file has both required sections**

Run:
```bash
grep -c "^## Orchestration rules" templates/CLAUDE.md
grep -c "^# Delegation rules: agy-bridge" templates/CLAUDE.md
```
Expected: both commands print `1`.

- [ ] **Step 3: Commit**

```bash
git add templates/CLAUDE.md
git commit -m "feat: add delegation-rules CLAUDE.md template with checkpoint rules"
```

---

### Task 3: Author the extended progress-notes template

**Files:**
- Create: `templates/review-topic-template.md`

**Interfaces:**
- Consumes: the `session-progress-notes` skill structure
  (`~/.claude/skills/session-progress-notes/SKILL.md`).
- Produces: `templates/review-topic-template.md` — copied into a project as
  `review-<topic-slug>.md` at the start of any task expected to span a long
  session or multiple sessions.

- [ ] **Step 1: Write the template file**

Create `templates/review-topic-template.md`:

```markdown
# Conversation State — <Topic>

Tanggal mulai: <date>
Repo: <repo name/path>
Scope: <what this covers, what's explicitly excluded/deferred and why>

## Konteks
<why this task exists, what the overall scope is>

---

## Status: <Unit N — Name> — SELESAI/IN PROGRESS

### Requirement summary
<cite exact doc/spec sections — future reader must be able to re-verify>

### Implementasi aktual
<what exists in code, with file:line or module references>

### Delegasi ke Antigravity (jika ada)
<tool dipakai (analyze_files/deep_search/web_lookup/adversarial_review/delegate),
session_id (untuk follow_up), hasil singkat yang sudah diverifikasi>

### Gap list
| # | Gap | Severity | Catatan |
|---|-----|----------|---------|

### Kesimpulan
<verdict + concrete next step, not just a status word>

---

## Pendekatan yang sudah dicoba & gagal
| # | Pendekatan | Kenapa gagal/ditolak | Tanggal |
|---|-----------|----------------------|---------|

---

## Belum dikerjakan (lanjutan sesi berikutnya)
- [ ] <unit not yet started>
- [ ] <unit explicitly skipped, with reason>
```

- [ ] **Step 2: Verify required sections are present**

Run:
```bash
grep -c "^## Pendekatan yang sudah dicoba & gagal" templates/review-topic-template.md
grep -c "^### Delegasi ke Antigravity" templates/review-topic-template.md
```
Expected: both commands print `1`.

- [ ] **Step 3: Commit**

```bash
git add templates/review-topic-template.md
git commit -m "feat: add progress-notes template with failed-approaches section"
```

---

### Task 4: End-to-end smoke test of delegation and session continuity

**Files:**
- Create: `docs/smoke-test-log.md`

**Interfaces:**
- Consumes: the registered `agy-bridge` MCP server from Task 1.
- Produces: `docs/smoke-test-log.md` recording proof that delegation and
  `follow_up` continuity actually work on this machine, before relying on
  this setup in a real project.

- [ ] **Step 1: Trigger a real delegation call**

In a Claude Code session (this one or a new one, in this repo), ask Claude
to delegate a trivial task, e.g.:

> "Use the agy-bridge `web_lookup` tool to look up what MCP (Model Context
> Protocol) stands for."

Expected: Claude Code calls the `web_lookup` tool, and the tool result
includes a `session_id` in its response metadata (per agy-bridge's
`follow_up` design) plus an answer under the `AGY_MAX_OUTPUT_CHARS` default
(50,000 characters).

- [ ] **Step 2: Trigger a follow-up call using the returned session_id**

Ask Claude to continue that same delegated session, e.g.:

> "Use `follow_up` on that same session to ask one more clarifying
> question, without resending the original context."

Expected: Claude Code calls `follow_up` with the `session_id` from Step 1
(not `web_lookup` again from scratch), and gets a coherent answer that
shows awareness of the prior exchange — confirming session continuity works
and context wasn't resent.

- [ ] **Step 3: Record the result**

Create `docs/smoke-test-log.md`:

```markdown
# Smoke Test Log

## 2026-07-23 — agy-bridge delegation + follow_up

- Delegated task: web_lookup on "what MCP stands for"
- session_id returned: <paste actual session_id observed>
- follow_up call: <describe the follow-up question asked>
- Result: <PASS/FAIL> — <one line on whether continuity was preserved
  without resending context>
```

- [ ] **Step 4: Commit**

```bash
git add docs/smoke-test-log.md
git commit -m "test: verify agy-bridge delegation and session continuity"
```

---

### Task 5: Write the repo README tying it all together

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: outputs of Tasks 1–4 (setup log, templates, smoke test log).
- Produces: `README.md` — the entry point for using this setup in any new
  project.

- [ ] **Step 1: Write the README**

Create `README.md`:

```markdown
# claude-antigravity-workflow

Config and templates for making Claude Code the single entry point for work
that also needs Antigravity, using the `agy-bridge` MCP server for one-way
delegation (Claude Code → Antigravity only).

## Design

See `docs/superpowers/specs/2026-07-23-claude-code-antigravity-orchestration-design.md`
for the full rationale (why Hermes/9Router/Kilo Code/bidirectional bridges
were not chosen).

## Setup (one-time, per machine)

See `docs/setup-log.md` for the exact commands used to register `agy-bridge`
as a user-scoped MCP server.

## Using this in a new project

1. Copy the delegation rules into the project:
   ```bash
   cp templates/CLAUDE.md /path/to/project/CLAUDE.md
   ```
   (If the project already has a `CLAUDE.md`, append this file's contents
   instead of overwriting.)
2. When starting a task expected to span a long or multi-session effort,
   copy the progress-notes template:
   ```bash
   cp templates/review-topic-template.md /path/to/project/review-<topic-slug>.md
   ```
3. Work from Claude Code (CLI or VS Code) as the single entry point. Claude
   Code will delegate to Antigravity via agy-bridge per the rules in
   `CLAUDE.md`, and checkpoint progress into `review-<topic-slug>.md` as it
   goes.

## Verification

See `docs/smoke-test-log.md` for proof that delegation and session
continuity (`follow_up`) work end-to-end on this machine.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README tying together setup, templates, and verification"
```

- [ ] **Step 3: Push everything to GitHub**

```bash
git push
```
Expected: all commits from Tasks 1–5 appear on
`https://github.com/sanoval/claude-antigravity-workflow`.
