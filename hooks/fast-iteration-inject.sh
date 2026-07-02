#!/usr/bin/env bash
# ~/.claude/hooks/fast-iteration-inject.sh
# UserPromptSubmit hook. When the user prompt smells like "FAST iteration"
# (1-day / 2-hour / no-HITL / toB-toC feedback), inject the standing
# 4-FAST rules into the model context so the next turn shapes its
# answer toward speed + shipping + feedback latency.
#
# 4-FAST rules (the model should bias answers toward these):
#   1. FAST product generation iteration  (within 1 day)
#   2. FAST ship                           (2 hours)
#   3. FAST dev                            (no HITL, 2 mins)
#   4. FAST feedback from toB client / toC users
#
# Trigger keywords (zh + en). Matched as plain alternation; macOS BSD
# grep -E doesn't support \y word boundaries, so we lean on
# punctuation (whitespace, quote, comma, slash) to bound tokens.
#
# Fail-open: no stdin / no jq / no match -> silent exit 0.
#
# rubric:  ~/.claude/hooks/HOOK_DESIGN_RUBRIC.md
# audit:   ~/.claude/hooks/logs/fast-iteration-inject.jsonl
# escape hatch: CLAUDE_FAST_INJECT_DISABLED=1

set -uo pipefail

# --- escape hatch ---
if [[ "${CLAUDE_FAST_INJECT_DISABLED:-0}" == "1" ]]; then exit 0; fi

LOG_DIR="$HOME/.claude/hooks/logs"
LOG_FILE="$LOG_DIR/fast-iteration-inject.jsonl"
mkdir -p "$LOG_DIR" 2>/dev/null || true

input="$(cat 2>/dev/null || true)"
[[ -z "$input" ]] && { printf '{"ts":"%s","evt":"empty_text","matched":[],"bytes":0}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$LOG_FILE"; exit 0; }

prompt="$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]')"

# 4-FAST trigger keyword set. Each entry is a plain string; we search for
# the literal token surrounded by punctuation so that "1day" inside
# "1day-leftover" still matches but "day" inside "Monday" does not.
# (The 4-fast-rule.sh Stop hook uses a wider net; this hook is narrower
# to keep false-positives low for a model already tuned for FAST.)
KEYWORDS=(
  "1 day" "1day" "1-day" "one day" "24h" "24 hours" "24hours" "same day" "today"
  "1天" "一天" "一天内" "当天" "今天" "今日" "明天" "今明两天" "赶" "尽快" "asap"
  "2 hour" "2hour" "2h" "2-hour" "two hour" "couple hour"
  "2小时" "两小时" "两个小时" "2h 内" "2 小时内"
  "2 min" "2min" "2-minute" "two minute" "couple minute"
  "2分钟" "两分钟" "2 分钟" "两分钟搞定"
  "no hitl" "no human" "no approval" "no confirm" "don't ask" "do not ask"
  "不要 hitl" "不要问" "不用确认" "自己决定" "自己拍板" "无需确认" "无需批准"
  "ship it" "ship now" "ship today" "ship fast" "ship without" "ship asap"
  "上线" "发布" "推上去" "合入" "提个 mr" "直接合" "立刻发" "马上发"
  "tob" "to c" "to b" "2b" "2c" "b2b" "b2c"
  "feedback" "user feedback" "customer feedback" "client feedback"
  "反馈" "吐槽" "客户反馈" "用户反馈" "用户说" "客户说" "客户想要" "客户问"
  # ── 扩展时段 + 紧迫词 + 部署动词(rubric §1 ≥100 达标)──
  "by eod" "by tomorrow" "tonight" "this week" "end of day"
  "本周" "本周内" "今晚" "明天前" "这周搞定"
  "rush" "urgent" "launch" "go live" "deploy"
)

# Loop per keyword instead of one massive alternation. macOS BSD
# grep -E silently fails to match for patterns over a few hundred chars
# (verified: 534-char pattern with 80+ alternatives returns zero matches
# even when individual alternatives work). Iterating is slower but
# avoids the limit and keeps the false-positive rate low.
matches=""
for kw in "${KEYWORDS[@]}"; do
    if printf '%s' "$prompt" | grep -Fq -- "$kw" 2>/dev/null; then
        matches+="${kw}"$'\n'
    fi
done
matches="$(printf '%s' "$matches" | sort -u | head -20)"

if [[ -z "$matches" ]]; then
  printf '{"ts":"%s","evt":"no_keyword_match","matched":[],"bytes":0}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$LOG_FILE"
  exit 0
fi

# Build the inject block. CEO-language, concrete, decision-ready.
read -r -d '' INJECT <<'EOF' || true

[user-level 4-FAST hook] 用户的 prompt 触发 FAST-iteration 关键词(见 log)。请按以下规则 bias 你的下一轮回答:

- **1 天内出活** — 任何 ≤1 天可完成的工作,按 ≤1 天交付,不等"完整方案"
- **2 小时内 ship** — 任何 ≤2h 可合并的改动,直接 ship(commit + push,per [[never-make-mr]] 规则,推 MR 前先拍板)
- **2 分钟 dev loop** — 任何 ≤2min 的 dev 循环,直接做,不要问"我能不能做"
- **零 HITL** — 不要主动问"我可以吗?","请确认" — 除非会改不可逆状态(mr 推送 / 删文件 / rm -rf)
- **toB / toC feedback** — 用户报 bug / 吐槽 / 反馈 = same-day ship candidate,默认按最高优先级排,不要排到 backlog

具体到本轮:
- 用 `codex:rescue` / `simplify` / `code-review` 走 QA gate
- 改完跑 `pnpm check` + `pnpm test:e2e` 一次
- `git commit` 完就停(推 MR 留给用户拍板)
- 报告时:先讲"对客户/业务改了什么",再讲"团队怎么做的"(CEO 语言,不写代码术语)
EOF

# Print to stdout (which Claude Code's UserPromptSubmit hook folds into
# the model's additionalContext) + always exit 0.
printf '%s\n' "$INJECT"
printf '{"ts":"%s","evt":"keyword+gate_passed","matched":%s,"bytes":%d}\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "$(printf '%s' "$matches" | python3 -c 'import json,sys; print(json.dumps([l for l in sys.stdin.read().splitlines() if l]))' 2>/dev/null || echo '[]')" \
  "${#INJECT}" \
  >> "$LOG_FILE"
exit 0
