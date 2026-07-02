#!/usr/bin/env bash
# ~/.claude/hooks/value-inject.sh
#
# UserPromptSubmit hook — ALWAYS injects the VALUE.md cascade as
# additionalContext on every user turn. This is the actual delivery
# side of the "send a prompt to agent" flow.
#
# The Stop hook (value-guard.sh) writes a per-session reminder file
# each time the agent stops. This hook picks that file up at the
# start of the next user turn and injects it into context, so the
# agent always sees the cascade before drafting any response.
#
# Even if the Stop hook has never fired (e.g. fresh session), this
# hook still injects the cascade — VALUE.md is a standing rule, not
# a one-shot nudge.
#
# Cascade (root → branches → leaves):
#   ~/.claude/VALUE.md                          (root)
#   ~/.claude/values/BRANCH_01_authorization.md (L1)
#   ~/.claude/values/BRANCH_02_silence.md       (L2)
#   ~/.claude/values/BRANCH_03_ship_evidence.md (L3)
#   ~/.claude/values/BRANCH_04_irreversible.md  (L4)
#   ~/.claude/values/LEAVES.md                  (7 (Q,A_H,A_V) tuples)
#
# Output format: JSON with `hookSpecificOutput.additionalContext`
# which Claude Code folds into the model's context for this turn.
#
# Failure modes handled (graceful):
#   - jq missing                  -> silent exit 0 (no context added)
#   - cascade files missing       -> silent exit 0
#   - empty stdin                 -> silent exit 0
#
# Toggle: set CLAUDE_VALUE_INJECT_DISABLED=1 to silence this hook.

set -uo pipefail

if [[ "${CLAUDE_VALUE_INJECT_DISABLED:-0}" == "1" ]]; then
  exit 0
fi

# --- Defensive: jq presence ---
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

input="$(cat)"
[[ -z "$input" ]] && exit 0

session_id="$(printf '%s' "$input" | jq -r '.session_id // "unknown"' 2>/dev/null)"

LOG_DIR="$HOME/.claude/hooks/logs"
per_session_reminder="$LOG_DIR/value-reminder-${session_id}.md"

# --- Build the additionalContext payload. The payload has 3 parts:
#
#   1. The standing cascade (always present) — root + branch summaries
#      so the agent has the value tree in mind every turn.
#
#   2. The most recent per-session reminder (if any) — surfaces what
#      the Stop hook queued at the end of the previous turn.
#
#   3. The cascade-inference instruction — tells the agent HOW to
#      use the cascade (root → branches → leaves → middle logic node
#      → self-resolve).
#
# We build this as a single string then wrap in JSON via jq. ---

# Compact standing pointer. We do NOT paste the value tree verbatim each
# turn (that cost ~2.6k tokens). Instead inject a self-inferring stub: the
# root value + the 5-question self-check + a pointer to read the full tree
# ONLY when a real HITL question actually arises. The agent infers the rest.
instruction='[VALUE 自决 — 信任是放大器,问题是衰减器]
要问 HITL 前先自检(5 题):
  1. "我能不能干 X"        → 干
  2. "X 还是 Y 等价路径"   → 选便宜的干
  3. "要截图/launch/弹窗吗" → 做,路径写进报告
  4. "我看不到,你来"      → 出 work-around
  5. "MR push / rm -rf / 推 token" → 真问,但先做完 90%(diff+test+revert)
自决后给 cheap signal:"已做完 X, evidence: <path>" 或 "选 X 因为 Y, 不选 Z"。
细节按需 self-infer: ~/.claude/VALUE.md(根→L1-L4→7 叶)。L1-L4 不可删。'

# Per-session reminder (if the Stop hook queued one)
reminder=""
if [[ -f "$per_session_reminder" ]]; then
  reminder="
[last stop reminder] :
$(cat "$per_session_reminder" 2>/dev/null)"
fi

# Compose the full payload
payload="${instruction}${reminder}"

# Escape for JSON: use jq --arg so all special chars (quotes, newlines,
# backticks, unicode) are handled correctly. Output is single-line JSON.
jq -nc --arg ctx "$payload" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $ctx
  }
}'

exit 0
