#!/usr/bin/env bash
# ~/.claude/hooks/research-md-no-ask.sh
# UserPromptSubmit hook. When the prompt mentions _RESEARCH.md, inject
# a standing rule into this turn's context: NEVER ask the user whether
# to commit or delete _RESEARCH.md. The file is owned by harness/tmp
# copies, so it's fine to leave untracked or to delete silently. The
# model must not surface "commit or delete?" as a follow-up question.
#
# Trigger keywords: _research.md, research.md. Fail-open: no stdin /
# no jq / no match → exit 0.
#
# rubric:  ~/.claude/hooks/HOOK_DESIGN_RUBRIC.md
# audit:   ~/.claude/hooks/logs/research-md-no-ask.jsonl
# escape hatch: CLAUDE_RESEARCH_MD_DISABLED=1
#
# Narrow-scope exception (rubric §1): this hook guards ONE specific file
# family (_RESEARCH.md + research.md). Trigger count = 2 is INTENTIONAL —
# expanding it would broaden beyond intended scope and start false-positive
# matching on unrelated "research.md" files (e.g. literature reviews).
# Per rubric §1, ≤100 triggers requires documented rationale → this is it.

set -uo pipefail

# --- escape hatch ---
if [[ "${CLAUDE_RESEARCH_MD_DISABLED:-0}" == "1" ]]; then exit 0; fi

LOG_DIR="$HOME/.claude/hooks/logs"
AUDIT_FILE="$LOG_DIR/research-md-no-ask.jsonl"
mkdir -p "$LOG_DIR" 2>/dev/null || true
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

input="$(cat)"
[[ -z "$input" ]] && { printf '{"ts":"%s","evt":"empty"}\n' "$ts" >> "$AUDIT_FILE"; exit 0; }

# Cheap extract: grep the raw payload rather than parsing JSON. The
# prompt text is somewhere in the "prompt" field, but a substring
# match across the whole payload is good enough and avoids jq
# dependency at the hook layer.
prompt="$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]')"

keywords=(
  "_research.md"
  "research.md"
)

hit=0
for kw in "${keywords[@]}"; do
  if [[ "$prompt" == *"$kw"* ]]; then
    hit=1
    break
  fi
done
[[ "$hit" -eq 0 ]] && exit 0

# Match — print a standing rule. The harness surfaces stderr from
# UserPromptSubmit hooks into the model's context, so the rule lands
# at the start of this turn's reasoning, before any "commit or
# delete?" question can be drafted.
cat >&2 <<'EOF'
[_RESEARCH.md no-ask rule]
The user has a standing rule (2026-06-12): NEVER ask the user whether
to commit or delete _RESEARCH.md. The file is produced by exploratory
sub-agents and lives in the harness / tmp backup; both options
(commit / delete) are valid and the user does not want the question
posed. Default behavior:
  1. If the file is referenced in passing in a recap, do NOT add a
     "commit 还是删?" line.
  2. If a future directive would naturally raise the question, skip
     it and move on.
  3. If _RESEARCH.md must be acted on for some other reason, do the
     cheapest thing silently (git add + commit, or rm) — and note it
     in one line in the report. Do not ask for permission.
EOF

exit 0
