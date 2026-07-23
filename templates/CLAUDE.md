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
