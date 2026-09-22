#!/usr/bin/env bash
# PreToolUse hook for Edit|Write|NotebookEdit — mechanically enforces the
# "Gate" section in templates/CLAUDE.md (also in effect when
# templates/CLAUDE-two-bridge-overlay.md is appended to it): direct edits
# to application code should go through the antigravity
# Coder-role delegation call, not Claude Code's own tools.
#
# Files matching the allowlist below are exempt (progress files, project
# memory, delegation config, skills, learning-curator working state under
# .agent-bridges/, project docs) and pass through silently. So does any
# path outside a git work tree (e.g. a scratchpad/temp file, or work done
# outside a project entirely) — the Gate is about application code in a
# repo the pipeline governs, not about every file Claude Code ever
# touches. Everything else surfaces a permission prompt so a human sees
# and confirms the bypass instead of it happening silently.
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

# Outside any git work tree — not a project this pipeline governs (a
# scratchpad file, a loose config edit, etc.) — let it through. Resolve
# symlinks on the directory (via cd -P) before asking git, so a path that
# reaches the repo through a symlinked ancestor (e.g. /tmp -> /private/tmp
# on macOS) still compares equal to git's own (always-resolved) toplevel.
file_dir_raw="$(dirname "$file_path")"
file_dir="$(cd "$file_dir_raw" 2>/dev/null && pwd -P || printf '%s' "$file_dir_raw")"
if ! git -C "$file_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  exit 0
fi
repo_root="$(git -C "$file_dir" rev-parse --show-toplevel 2>/dev/null || true)"
file_path_resolved="$file_dir/$(basename "$file_path")"

# Path relative to the repo root, when we have one, so root-anchored
# patterns (like the project's own top-level skills/) don't accidentally
# match an app-code directory that happens to share a name (e.g.
# src/features/skills/foo.ts is NOT exempt; skills/foo.md at repo root is).
rel_path="$file_path_resolved"
if [ -n "$repo_root" ]; then
  case "$file_path_resolved" in
    "$repo_root"/*) rel_path="${file_path_resolved#"$repo_root"/}" ;;
  esac
fi

allow_regex='(^|/)(CLAUDE|AGENTS|GEMINI)\.md$|(^|/)review-[^/]+(-archive)?\.md$|(^|/)README\.md$|(^|/)docs/.*\.md$|(^|/)\.claude/skills/|(^|/)\.agents/skills/|^skills/|(^|/)\.agent-bridges/'

if printf '%s' "$rel_path" | grep -qE "$allow_regex"; then
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
