# Delegation rules: Antigravity and Codex

You have two MCP delegation bridges:

- `antigravity` delegates to Antigravity CLI (Gemini), served by the
  `agy-bridge` MCP server package.
- `codex` delegates to Codex through `codex mcp-server`.

Delegation keeps large content out of your context — only the result comes
back. Choose one bridge for a unit of work. Never pipe one bridge's raw
output into the other — that is how context bloat and ping-pong loops start.
The distilled pipeline is different and encouraged: Antigravity gathers
broadly, you (Claude Code) condense the findings, and the condensed version
goes into a Codex prompt. You are always the filter between bridges.

## Claude subagents are not bridge delegation

Your own subagents (the `Agent`/`Task` tool — `Explore`, `general-purpose`,
etc.) still run as Claude and still count against Claude's own usage limit.
Only `antigravity` and `codex` calls run on a separate vendor's quota and
actually relieve it. Before spawning a Claude subagent, check whether the
task matches an Antigravity or Codex criterion below — broad search, reading
large files, or repo-wide greps are Antigravity candidates
(`analyze_files`/`deep_search`), not Explore candidates. Reserve Claude
subagents for work that genuinely needs a tool, permission, or piece of
session state only Claude Code has.

**Default Claude subagents to the orchestrator's model (e.g. Sonnet).**
Because broad/mechanical work is already routed to the bridges above, what's
left for Claude subagents is disproportionately judgment work — investigation,
synthesis, decisions — where a weaker model risks wrong output that then
needs re-verification or redoing, erasing any savings. Only assign a cheaper
model (e.g. Haiku) to a subagent when there's an established, recurring
pattern of simple, parallelizable, cheaply-verified work (e.g. the same
mechanical check repeated across N files) — never as a default, and never
for a one-off task you haven't seen repeat.

## Provider selection

Use Antigravity tools when the task is primarily broad or retrieval-oriented:

- **Any file >200 lines** you'd otherwise read → `analyze_files`
- **More than 3 files** in one analysis/comparison → `analyze_files`
- **Git history or repo-wide searches** (git log/diff/blame, broad greps) → `deep_search`
- **Web/documentation lookups** → `web_lookup`
- **Other heavy, self-contained computation** that fits neither bridge's
  specialized tools (mass summarization, generating large fixtures) →
  `delegate`

Every Antigravity prompt must state: the exact question to answer, the output
format you want back (findings list, table, verdict + evidence), and `cwd` set
to the project root. For `deep_search`, also state what counts as a hit.
Always ask for `file:line` citations.

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

## Cross-model second opinions (`adversarial_review`)

Antigravity also exposes `adversarial_review` (routes to a different model
family than Codex). Routine reviews go to Codex only. For **high-stakes
decisions** — architecture choices, risky refactors, security-sensitive
diffs — run Codex **and** `adversarial_review` on the same question, then
reconcile: where they agree, proceed; where they disagree, investigate the
disagreement yourself before deciding, and record the resolution in the
progress file. Do not use `adversarial_review` as the sole reviewer for code
Codex wrote, or vice versa, without noting which model produced what.

Do NOT delegate: small single-file edits, questions you can answer from
context already loaded, or tasks needing tools only you have. And do not
substitute a Claude subagent for a bridge delegation that fits — see
"Claude subagents are not bridge delegation" above.

## Example delegation prompts

Antigravity `analyze_files`:
> Analyze `src/billing/invoice.py` and `src/billing/ledger.py`. Question: can
> `post_invoice` ever write a ledger entry without an invoice row committing?
> Output: verdict, then evidence as a list of `file:line` citations. cwd:
> /path/to/repo

Codex `codex` (read-only):
> Symptom: `test_refund_idempotency` fails intermittently with a duplicate-key
> error. Suspected entry points: `RefundService.process` and the retry
> decorator in `src/common/retry.py`. Question: identify the race and propose
> the minimal fix. Return findings with `file:line` evidence and recommended
> next steps. sandbox: read-only

## Parallelism, failures, and verification

- **Delegate independent units in parallel.** The bridges are separate
  servers; fire concurrent calls when units don't depend on each other.
  Serialize only when one unit's output feeds the next. (Antigravity's first
  call in a session takes ~40–50s to cold-start — that is not a hang.)
- **On bridge failure** (timeout, disconnect, unusable output): retry once.
  On a second failure, fall back — to the other bridge if the task fits it,
  otherwise do the work natively — and record the failure in the progress
  file so the next session doesn't retry a dead bridge. Never loop retries.
- **Verification is defined as:** every delegation prompt demands `file:line`
  citations; you spot-check one or two of them before recording the result.
  Claims without citations get recorded as *unverified* and must not be the
  sole basis for an edit or a decision. Remember Antigravity truncates output
  (~50k chars) — always request structured findings, never content dumps.

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
- **Compact after checkpointing, before the next unit.** Delegation keeps
  raw content out of context, but the orchestrator session still accumulates
  delegation summaries, checkpoint writes, and conversation history. Once a
  unit is checkpointed to the progress file, run `/compact` before starting
  the next unit; run `/clear` when switching to an unrelated task. The
  progress file — not conversation history — is the source of truth across
  that boundary.
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
- **Keep the progress file lean.** When a unit is SELESAI and no open gap
  references it, move its full section to `review-<topic>-archive.md` and
  leave a one-line summary behind. The progress file is re-read every
  session start; if it grows unbounded, the tool meant to save context
  becomes a context cost.
