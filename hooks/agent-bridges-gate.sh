#!/usr/bin/env bash
# PreToolUse hook for Edit|Write|NotebookEdit — mechanically enforces the
# "Gate" section in templates/CLAUDE.md (also in effect when
# templates/CLAUDE-two-bridge-overlay.md is appended to it): direct edits
# to application code should go through the antigravity
# Coder-role delegation call, not Claude Code's own tools.
#
# Files matching the allowlist below are exempt (progress files, project
# memory, delegation config, skills, learning-curator working state under
# .agent-bridges/) and pass through silently. Everything else surfaces a
# permission prompt so a human sees and confirms the bypass instead of it
# happening silently.
#
# This hook does not cover Bash commands that mutate tracked files —
# reliably detecting those in general isn't robust via the `if` matcher
# (permission-rule prefix syntax, not full regex over command text). That
# half of the Gate stays honor-system.
set -euo pipefail

input="$(cat)"

file_path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"
if [ -z "$file_path" ]; then
  file_path="$(printf '%s' "$input" | jq -r '.tool_input.notebook_path // empty')"
fi

# No file path we can inspect — let it through rather than guessing.
if [ -z "$file_path" ]; then
  exit 0
fi

allow_regex='(^|/)(CLAUDE|AGENTS|GEMINI)\.md$|(^|/)review-[^/]+(-archive)?\.md$|(^|/)\.claude/|(^|/)\.agents/|(^|/)skills/|(^|/)\.agent-bridges/'

if printf '%s' "$file_path" | grep -qE "$allow_regex"; then
  exit 0
fi

reason='Gate (templates/CLAUDE.md, "Gate: before you touch Edit, Write, or a file-modifying Bash command"): this looks like an application-code edit. Per the delegation pipeline, this should go to the antigravity Coder-role call unless it is one of the documented exceptions — a fix so small round-tripping is not worth it, a small correction to Antigravity'"'"'s own diff, or work outside the Coder role'"'"'s scope entirely (progress files, delegation config, local git). Confirm which exception applies before approving.'

jq -n --arg reason "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "ask",
    permissionDecisionReason: $reason
  }
}'
