# Delegation rules: Antigravity and Codex

You have two MCP delegation bridges:

- `agy-bridge` delegates to Antigravity CLI (Gemini).
- `codex` delegates to Codex through `codex mcp-server`.

Delegation keeps large content out of your context — only the result comes
back. Choose one bridge for a unit of work; do not pass results from one bridge
to the other unless Claude Code has first verified that this is necessary.

## Provider selection

Use Antigravity tools when the task is primarily broad or retrieval-oriented:

- **Any file >200 lines** you'd otherwise read → `analyze_files`
- **More than 3 files** in one analysis/comparison → `analyze_files`
- **Git history or repo-wide searches** (git log/diff/blame, broad greps) → `deep_search`
- **Web/documentation lookups** → `web_lookup`

Use Codex when the task needs deep, bounded code reasoning rather than broad
information retrieval:

- **Trace a bug across interacting modules** → `codex` with the symptom,
  suspected entry points, and the exact question to resolve
- **Assess an implementation plan or a non-obvious technical trade-off** →
  `codex` with the proposed approach, constraints, and decision criteria
- **Review a focused diff or a bounded set of changed files** → `codex` with
  the review scope and the failure modes to look for
- **Investigate test failures, edge cases, invariants, or regression risk** →
  `codex` with the failing command/output and relevant files
- **Design a targeted implementation or refactor** that touches several
  related components → `codex` with the required behavior and file scope
- Use `sandbox: read-only` by default for each of the above, with a precise
  prompt that asks for findings, evidence, and recommended next steps
- **Follow-up question on Codex work** → `codex-reply` with the returned
  `threadId` (never resend the context)
- **A Codex edit is explicitly desired** → use `codex` with the requested
  writable sandbox only after Claude Code states the exact file scope

Do not use Codex merely to read a large file, perform a broad repo search, or
look up documentation; use Antigravity for those retrieval-oriented tasks.

For an Antigravity follow-up, use `follow_up` with its returned `session_id`.

Do NOT delegate: small single-file edits, questions you can answer from
context already loaded, or tasks needing tools only you have.

## Orchestration rules (project-specific, layered on top of the above)

- **One direction only.** You (Claude Code) always call Antigravity and Codex.
  Never configure or invoke a path where either bridge calls Claude Code or the
  other bridge. This design rejects bidirectional delegation to avoid
  ping-pong loops.
- **Checkpoint the progress file after every delegation.** Immediately
  after an Antigravity or Codex call returns and you've verified the result,
  update the active `review-<topic>.md` progress file (see
  `templates/review-topic-template.md` for structure) with: what was
  delegated, its provider, the returned session id or thread id, and the
  verified outcome. Do this before starting the next unit of work — do not
  wait until the session ends.
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
