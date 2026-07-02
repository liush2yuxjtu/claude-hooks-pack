#!/usr/bin/env bash
# ~/.claude/hooks/meta-hook-creator.sh
#
# Stop hook — meta-hook。检测最后一条 assistant 消息里是否在"创建 / 设计
# 新 hook"。命中后 inject 一段 HOOK_DESIGN_RUBRIC.md §8 self-check reminder
# 到 next-turn additionalContext,让 agent 在写新 hook 之前过一遍 8 题。
#
# Trigger count < 100 是允许的 — meta-hook 主题极窄(只在创建 hook 时触发),
# 按 rubric §1 "≤ 100 时在 header 里写明理由" 的例外条款处理。
#
# 不阻塞,不替 agent 决策,ONLY 注入 rubric self-check。
#
# rubric:  ~/.claude/hooks/HOOK_DESIGN_RUBRIC.md
# audit:   ~/.claude/hooks/logs/meta-hook-creator.jsonl
# per-session log: APPENDS to value-reminder-<session_id>.md
# escape hatch: CLAUDE_META_HOOK_DISABLED=1

set -uo pipefail

if [[ "${CLAUDE_META_HOOK_DISABLED:-0}" == "1" ]]; then
  printf '{"continue": true, "suppressOutput": true}\n'
  exit 0
fi

LOG_DIR="$HOME/.claude/hooks/logs"
AUDIT_FILE="$LOG_DIR/meta-hook-creator.jsonl"
mkdir -p "$LOG_DIR" 2>/dev/null || true

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

input="$(cat)"
session_id="$(printf '%s' "$input" | jq -r '.session_id // "unknown"' 2>/dev/null)"
transcript_path="$(printf '%s' "$input" | jq -r '.transcript_path // ""' 2>/dev/null)"

# ── 取最后一条 assistant 消息纯文本 ──
last_msg=""
if [[ -n "$transcript_path" && -r "$transcript_path" ]]; then
  last_msg="$(
    jq -rs '
      [.[]
       | select(.type=="assistant")
       | (.message.content // [])
         | .[]
         | select(.type=="text")
         | .text
      ] | last // ""
    ' "$transcript_path" 2>/dev/null
  )"
fi
if [[ -z "$last_msg" ]]; then
  last_msg="$(printf '%s' "$input" | jq -r '.last_assistant_message // ""' 2>/dev/null)"
fi

if [[ -z "$last_msg" ]]; then
  printf '{"continue": true, "suppressOutput": true}\n'
  exit 0
fi

# ── trigger detection ──
markers_found=0
matched=()

check() {
  local m="$1"
  if printf '%s' "$last_msg" | grep -qF -- "$m"; then
    markers_found=$((markers_found + 1))
    matched+=("$m")
  fi
}

# ── 直接意图(imperative + hook)──
# English
check "create a hook"
check "write a hook"
check "add a hook"
check "build a hook"
check "new hook"
check "make a hook"
check "design a hook"
check "implement a hook"

# Chinese
check "写一个 hook"
check "写一个 hook 脚本"
check "新建 hook"
check "新 hook"
check "加一个 hook"
check "做个 hook"
check "做一个 hook"
check "写新 hook"
check "加新 hook"
check "写这个 hook"
check "写那个 hook"
check "写 hook"
check "建 hook"
check "加 hook"
check "实现 hook"
check "实现一个 hook"
check "完成 hook"
check "设计 hook"
check "设计一个 hook"

# ── File path / wiring 上下文 ──
check "~/.claude/hooks/"
check "~/.claude/settings.json"
check "HOOK_DESIGN_RUBRIC"

# ── Hook 设计的特定语言 ──
check "trigger words"
check "trigger list"
check "matcher"

# ── 命中:append rubric self-check block ──
if (( markers_found >= 1 )); then
  reminder_file="$LOG_DIR/value-reminder-${session_id}.md"
  matched_str="${matched[*]}"

  cat >> "$reminder_file" <<META_EOF

---

## ⚠️ meta-hook-creator · 检测到你在创建新 hook

命中标志: \`${matched_str}\`

**新建 hook 前,逐题过 HOOK_DESIGN_RUBRIC.md §8 self-check:**

1. ☐ Trigger 列表 ≥ 100,或 ≤ 100 时在 header 里写明理由?
2. ☐ 至少 1 个结构触发(非纯文本,如 ☐×3+ / code block / URL 模式)?
3. ☐ 独立 harness + ≥ 3 positive + ≥ 3 negative 测试矩阵?
4. ☐ Default silent approve,hit inject prompt 不阻塞?
5. ☐ Escape hatch \`CLAUDE_<NAME>_DISABLED=1\`?
6. ☐ Header 引用 VALUE.md / LEAVES.md?
7. ☐ Audit JSONL 路径 + per-session 日志路径写明?
8. ☐ Settings.json wiring 顺序正确(无前置依赖可任意,有则 append-after)?

**8/8 → ship。6-7 → 修订后再 ship。<6 → 不要 ship。**
META_EOF

  jq -cn \
    --arg ts "$ts" \
    --arg sid "$session_id" \
    --argjson n "$markers_found" \
    --arg m "$matched_str" \
    '{ts:$ts, session_id:$sid, action:"meta-hook-trigger", markers_found:$n, markers:$m}' \
    >> "$AUDIT_FILE" 2>/dev/null || true

  printf '{"continue": true, "stopReason": "meta-hook-creator: hook-creation intent detected; HOOK_DESIGN_RUBRIC.md self-check queued for next turn"}\n'
  exit 0
fi

# ── 未命中: 静默 approve ──
printf '{"continue": true, "suppressOutput": true}\n'
exit 0
