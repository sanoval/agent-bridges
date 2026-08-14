#!/usr/bin/env bash
# PreToolUse hook for Edit|Write|NotebookEdit and the GitHub MCP write tools
# — mechanically enforces the "Gate" section in templates/CLAUDE.md /
# templates/CLAUDE-two-bridge.md: direct edits to application code should go
# through the antigravity Coder-role delegation call, not Claude Code's own
# tools.
#
# Three outcomes:
#   deny  — the hook's own machinery (.claude/hooks/, .claude/settings*.json).
#           An enforcement mechanism the agent can silently rewrite is not
#           one. Edit these yourself, outside the session, if you mean to.
#   allow — project memory, progress files, delegation config, skills.
#           Passes through silently; these are not the Coder role's job.
#   ask   — everything else (application code): surfaces a permission prompt
#           so a bypass is something the user sees and approves.
#
# Paths are resolved relative to CLAUDE_PROJECT_DIR and the allowlist is
# root-anchored, so a `skills/` or `review-*.md` path *inside* the source
# tree (e.g. src/skills/billing.py) is gated like any other code.
#
# Requires jq. If jq is missing the hook fails CLOSED (asks) rather than
# letting the edit through unexamined.
#
# This hook does not cover Bash commands that mutate tracked files —
# reliably detecting those in general isn't robust via the `if` matcher
# (permission-rule prefix syntax, not full regex over command text). That
# half of the Gate stays honor-system.
set -uo pipefail

# Reason strings must not contain double quotes or backslashes — they are
# interpolated into JSON by printf, not by jq, so the fail-closed path works
# even when jq is unavailable.
emit() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"}}\n' "$1" "$2"
  exit 0
}

input="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
  emit ask 'agent-bridges Gate: jq is not installed, so this hook cannot inspect the tool input and is failing closed. Confirm manually that this edit is the Trivial tier or outside the Coder role scope (see the Gate section in CLAUDE.md), then install jq so the hook can resolve this on its own.'
fi

# Collect every path this tool call would write: Edit/Write (file_path),
# NotebookEdit (notebook_path), GitHub MCP single-file writes (path), and
# GitHub MCP push_files (files[].path).
if ! paths="$(printf '%s' "$input" | jq -r '
  [ .tool_input.file_path, .tool_input.notebook_path, .tool_input.path ]
  + [ (.tool_input.files // [])[] | .path ]
  | map(select(type == "string" and length > 0))
  | .[]
' 2>/dev/null)"; then
  emit ask 'agent-bridges Gate: the tool input could not be parsed, so this hook cannot tell whether the write targets application code. Failing closed - confirm which Gate exception applies before approving.'
fi

# No path we can inspect — let it through rather than guessing.
if [ -z "$paths" ]; then
  exit 0
fi

root="${CLAUDE_PROJECT_DIR:-$PWD}"

# The hook's own machinery. Rewriting these disables the Gate, so they are
# never a silent pass and never merely an ask.
deny_regex='^\.claude/hooks/|^\.agents/hooks/|^\.claude/settings(\.local)?\.json$'

# Not the Coder role's job. Memory files match at any depth (nested CLAUDE.md
# is legitimate in a monorepo); everything else is anchored to the project
# root so same-named directories inside src/ stay gated.
allow_regex='(^|/)(CLAUDE|AGENTS|GEMINI)\.md$|^review-[^/]+(-archive)?\.md$|^\.claude/|^\.agents/|^skills/'

while IFS= read -r p; do
  [ -n "$p" ] || continue

  rel="${p#"$root"/}"
  rel="${rel#./}"

  if printf '%s' "$rel" | grep -qE "$deny_regex"; then
    emit deny 'agent-bridges Gate: this path is the Gate hook or the settings that install it. An enforcement mechanism the agent can rewrite mid-session is not enforcement, so this is blocked rather than prompted. If the change is intended, edit the file directly outside the session.'
  fi

  # One non-exempt path in a multi-file write is enough to gate the call.
  if ! printf '%s' "$rel" | grep -qE "$allow_regex"; then
    emit ask 'Gate (see the Gate section in CLAUDE.md): this looks like an application-code edit. Per the delegation pipeline it belongs to the antigravity Coder-role call unless it is the Trivial tier you assigned at step 1 and wrote into the checkpoint, or work outside the Coder role scope entirely (progress files, delegation config, local git). Deciding it is trivial now, with the edit already drafted, is the exact judgement this gate exists to distrust. State which exception applies before approving.'
  fi
done <<EOF
$paths
EOF

exit 0
