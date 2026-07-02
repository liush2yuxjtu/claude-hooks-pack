#!/usr/bin/env bash
# ~/.claude/hooks/value-guard.sh
#
# Stop hook — ALWAYS fires on every stop. No keyword filter, no block
# decision. Its only job is to deliver the VALUE.md cascade as a prompt
# to the agent (via transcript stdout + per-session log file) and let
# the stop happen (return approve).
#
# The actual context-injection delivery is done by the companion
# UserPromptSubmit hook `value-inject.sh`, which reads the per-session
# log file written here and injects it as additionalContext on the next
# user turn. The two together give: "every stop event → reminder visible
# to the agent on the next turn", with zero blocking.
#
# Cascade:
#   ~/.claude/VALUE.md                          (root)
#   ~/.claude/values/BRANCH_01_authorization.md (L1)
#   ~/.claude/values/BRANCH_02_silence.md       (L2)
#   ~/.claude/values/BRANCH_03_ship_evidence.md (L3)
#   ~/.claude/values/BRANCH_04_irreversible.md  (L4)
#   ~/.claude/values/LEAVES.md                  (7 (Q,A_H,A_V) tuples)
#
# Audit: each invocation appends a JSONL line to
#   ~/.claude/hooks/logs/value-guard.jsonl
# with fields {ts, session_id, action: "remind"}.
#
# Per-session log: a short reminder is also written to
#   ~/.claude/hooks/logs/value-reminder-<session_id>.md
# which value-inject.sh picks up on the next user turn. The
# companion hook MUST run AFTER this one in the same session so the
# log file exists by the time it reads.
#
# Toggle: set CLAUDE_VALUE_GUARD_DISABLED=1 in the env to silence
# this hook for a single run (e.g. when debugging).

set -uo pipefail

# Honor the escape hatch before doing any work.
if [[ "${CLAUDE_VALUE_GUARD_DISABLED:-0}" == "1" ]]; then
  printf '{"continue": true, "suppressOutput": true}\n'
  exit 0
fi

LOG_DIR="$HOME/.claude/hooks/logs"
AUDIT_FILE="$LOG_DIR/value-guard.jsonl"
mkdir -p "$LOG_DIR" 2>/dev/null || true

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

input="$(cat)"
session_id="$(printf '%s' "$input" | jq -r '.session_id // "unknown"' 2>/dev/null)"

# --- Always-on reminder text. This is the "prompt to agent" payload.
# The agent will see this on the next turn via value-inject.sh.
reminder_file="$LOG_DIR/value-reminder-${session_id}.md"

cat > "$reminder_file" <<'REMINDER_EOF'
[VALUE.md 自决 cascade — 在你准备问任何 HITL 问题前,先沿这条链推演]

根  信任是放大器,问题是衰减器
  ↓
L1  授权 = "你看着办",不是"每步问我"
  ↓
L2  沉默 = "你看着办",不是"我没看见"  (用户 93% 沉默率,数据: 26/28)
  ↓
L3  默认动作 = ship + 出证据,不是 ask
  ↓
L4  不可逆 + 高 cost 才真问,问前做完 90%
  ↓
叶  ~/.claude/values/LEAVES.md 7 个 (Q_REAL, A_HUMANOLD, A_AGENT_VALUE_EXPECT) 实证

自检 5 题 — 助手当下要不要"问"?
  1. "我能不能干 X"        → 干  (L1)
  2. "X 还是 Y 等价路径"   → 选便宜的干  (L2)
  3. "要截图/launch/弹窗吗" → 做, 路径在报告里  (L3)
  4. "我看不到, 你来"      → 出 work-around  (L2+L3)
  5. "MR push / rm -rf / 推 token" → 真问, 但 90% 先做完  (L4)

允许插 middle logic node: 如果 4 层不够, 在对应 BRANCH_*.md 末尾的
"MIDDLE-LOGIC-NODE 注入区" 加一行, 描述本类问题的解法 (触发 / 行为 / 证据)。

self-resolve 后必须含 cheap signal 三选一:
  a) "已做完 X, evidence: <URL/path>"
  b) "选 X, 因为 Y 的代价是 Z; 不选 Y"
  c) "X 不可逆, 但 90% 已做完 (diff stat + tests + revert path), OK 吗?"
REMINDER_EOF

# --- Audit log (one line per invocation, JSONL) ---
jq -cn --arg ts "$ts" --arg sid "$session_id" \
  '{ts:$ts, session_id:$sid, action:"remind"}' \
  >> "$AUDIT_FILE" 2>/dev/null || true

# --- Stop hook return: approve, with a stopReason that surfaces the
# reminder to the user too. We do NOT block. ---
printf '{"continue": true, "stopReason": "VALUE.md reminder queued for next turn (see ~/.claude/hooks/logs/value-reminder-<session>.md)"}\n'
exit 0
