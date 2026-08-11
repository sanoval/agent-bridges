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

## Provider selection: Macro-Delegation vs Micro-Delegation

Both bridges possess high-capacity context limits (Antigravity/Gemini has a 1M–2M token context window; Codex has 128k+ tokens with deep reasoning). **Do not micro-delegate single files or small isolated questions.** Prefer **Macro-Delegation**: package entire directories, whole feature modules, documentation specs, and full log dumps into a single high-payload request.

Use Antigravity tools for broad context ingestion, whole-module analysis, and retrieval:

- **Whole-module & multi-file directory ingestion** (`src/feature/**/*`, `tests/feature/*`, `docs/*`) → `analyze_files`. Ingest all relevant context in one call rather than making multiple single-file passes.
- **Git history, repo-wide architecture sweeps, or codebase-wide pattern matching** → `deep_search`.
- **Web/documentation lookups & broad API exploration** → `web_lookup`.
- **Heavy self-contained computation or mass log/trace analysis** (e.g. 50k+ lines of stack traces, generating massive fixtures) → `delegate`.

Every Antigravity prompt must specify:
1. The full scope of files/directories to ingest (`cwd` set to project root).
2. The exact question or audit goals.
3. The expected **high-density structured output** (exhaustive gap matrix, edge-case table, or structured verdict with `file:line` citations).

Use Codex for deep, bounded code reasoning, logic synthesis, and heavy implementation:

- **Full-feature refactoring & architectural logic synthesis** → `codex` with the full requirement spec, module boundaries, and implementation targets.
- **Cross-module bug tracing & invariant analysis** → `codex` with the symptom, stack trace, entry points, and suspected code paths.
- **Assessment of complex trade-offs or implementation plans** → `codex` with proposed design, constraints, and decision criteria.
- **Heavy code generation or multi-file edits** → `codex` with `sandbox: workspace` (or writable sandbox), delegating the end-to-end implementation and test verification to Codex before returning the summary diff to Claude Code.
- Use `sandbox: read-only` by default when doing pure analysis/review; switch to writable sandbox when full code implementation is delegated.
- **Follow-up on Codex work** → `codex-reply` with the returned `threadId` (never resend the context).

Do not use Codex merely to read a file or perform a broad search; route retrieval and massive ingestion to Antigravity. For Antigravity follow-ups, use `follow_up` with `session_id`.

## Cross-model second opinions (`adversarial_review`)

Antigravity also exposes `adversarial_review` (routes to a different model
family than Codex). Routine reviews go to Codex only. For **high-stakes
decisions** — architecture choices, risky refactors, security-sensitive
diffs — run Codex **and** `adversarial_review` on the same question, then
reconcile: where they agree, proceed; where they disagree, investigate the
disagreement yourself before deciding, and record the resolution in the
progress file. Do not use `adversarial_review` as the sole reviewer for code
Codex wrote, or vice versa, without noting which model produced what.

## Balancing the swap zone

Core ingestion (Antigravity) and core implementation (Codex) are never
balanced — they stay strictly task-fit routed, even if that skews usage
toward one bridge. The **only** swap zone is routine reviews / second
opinions: work that fits either bridge equally well. For that zone alone,
use the progress file's Delegation tally (see
`templates/review-topic-template.md`) to break ties instead of defaulting
to Codex every time:

- If the tally shows one bridge ahead of the other by more than 2x (with a
  floor of at least 3 calls on the leading side, so an early 1-vs-0 doesn't
  trigger churn), route the next routine review to the less-used bridge.
- If counts are roughly even, keep today's default (Codex for routine
  reviews).
- High-stakes reviews (architecture, risky refactor, security-sensitive
  diff) always use **both** bridges via `adversarial_review` regardless of
  tally — balancing changes which single bridge handles a *routine* review,
  it never reduces coverage on high-stakes work.
- This never adds a bridge call that wasn't already going to happen — it
  only changes which bridge gets picked.
- Increment the tally at the same point the existing "checkpoint after
  every delegation" rule already fires — no separate step.

Do NOT delegate: trivial single-line edits, questions answered by already-loaded
context, or tasks needing local tools only you have. Do not substitute a Claude
subagent for a bridge delegation that fits — see "Claude subagents are not bridge
delegation" above.

## Example delegation prompts

Antigravity `analyze_files` (Macro-Delegation Ingestion):
> Ingest all files under `src/billing/`, `tests/billing/`, and `docs/billing-spec.md`.
> Question: Is there any potential race condition where `post_invoice` writes a ledger entry
> without a committed invoice row? Audit all payment retry paths and idempotency keys.
> Output: High-density findings report with a summary verdict, edge-case analysis matrix,
> and evidence listed as `file:line` citations. cwd: /path/to/repo

Codex `codex` (Deep Multi-file Reasoning / Implementation):
> Objective: Refactor the refund idempotency logic across `src/billing/refund.py` and
> `src/common/retry.py`. Symptom: `test_refund_idempotency` fails intermittently under high concurrency.
> Task: Analyze the race condition, implement the minimal lock-free retry fix across both files,
> and verify by running tests. Return a summary of root cause, exact changes made, and test status.
> sandbox: workspace

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
