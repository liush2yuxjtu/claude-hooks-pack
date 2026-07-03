#!/usr/bin/env bash
# ~/.claude/hooks/mocks-not-stuck-reminder.sh
# UserPromptSubmit hook. Reads the user's prompt from stdin (JSON
# payload), and if it smells like a plan/PRD/issue-breakdown request,
# injects a reminder onto stderr that the harness folds into the
# model's context for this turn.
#
# Trigger keywords: plan, prd, /to-prd, /to-issues, to-issues, slice,
# "break into", "design the slice set", dependency graph, vertical
# slice, mock-tracking. Fail-open: no stdin / no jq / no match → exit 0.
#
# rubric:  ~/.claude/hooks/HOOK_DESIGN_RUBRIC.md
# audit:   ~/.claude/hooks/logs/mocks-not-stuck-reminder.jsonl
# escape hatch: CLAUDE_MOCKS_DISABLED=1
#
# Narrow-scope exception (rubric §1): this hook only fires on planning /
# slicing / mock-tracking vocabulary, which is a closed set in this
# project's CLI surface (12 dedicated slash-commands + 3 ZH verbs).
# Expanding to 100+ would require padding with adjacent-but-unrelated
# words ("epic", "story", "spec") and would dilute the reminder's
# signal-to-noise. Per rubric §1, ≤100 triggers requires documented
# rationale → this is it.

set -uo pipefail

# --- escape hatch ---
if [[ "${CLAUDE_MOCKS_DISABLED:-0}" == "1" ]]; then exit 0; fi

LOG_DIR="$HOME/.claude/hooks/logs"
AUDIT_FILE="$LOG_DIR/mocks-not-stuck-reminder.jsonl"
mkdir -p "$LOG_DIR" 2>/dev/null || true
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

input="$(cat)"
[[ -z "$input" ]] && {
  printf '{"ts":"%s","evt":"empty"}\n' "$ts" >>"$AUDIT_FILE"
  exit 0
}

# Cheap extract: grep the raw payload rather than parsing JSON, so
# we don't fail when the payload isn't pure JSON in some harness
# versions. (The prompt text is in the "prompt" field.)
prompt="$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]')"

keywords=(
  "/to-prd"
  "/to-issues"
  "to-issues"
  "to-prd"
  "plan"
  "prd"
  "break into"
  "slice set"
  "vertical slice"
  "dependency graph"
  "mock"
  "mock-tracking"
  "拆成"
  "拆分"
  "issue"
)

hit=0
for kw in "${keywords[@]}"; do
  if [[ "$prompt" == *"$kw"* ]]; then
    hit=1
    break
  fi
done
[[ "$hit" -eq 0 ]] && exit 0

# Match — print a reminder. The harness surfaces stderr from
# UserPromptSubmit hooks into the model's context, so the rule lands
# at the start of this turn's reasoning, before any plan is drafted.
cat >&2 <<'EOF'
[mocks-not-stuck reminder]
The user has a standing rule (2026-06-12): when planning or
breaking work into issues, do NOT get stuck on prerequisite
completion. Default behavior:
  1. Each issue is a thin vertical slice through every layer.
  2. Downstream issues ship a `mock:` of the upstream contract
     (typed stub / fixture / fake) so all slices can land in
     parallel instead of serializing on the critical path.
  3. Mark mocks visibly: `// MOCK: <why>` comment in code, plus
     a short "Active mocks" section in the project CLAUDE.md.
  4. Add a final `mock→real` sweep — one issue per mock + one
     audit issue that regex-scans for residual `mock:` /
     `FIXME.*replace` / hardcoded fixtures.
  5. Move on. Don't wait for "real upstream first".
See memory: feedback-mocks-not-stuck.md
EOF

exit 0
