#!/usr/bin/env bash
# ~/.claude/hooks/value-guard-next-step.sh
#
# Stop hook — 条件触发版 value-guard。
# 与 value-guard.sh 的区别:
#   - 默认 silent approve(无 anti-pattern 时不打扰)
#   - 当最后一条 assistant 消息命中"让用户在可推断选项里选一个"反模式时,
#     append 一段 prompt 到 per-session reminder,
#     让 value-inject.sh 在下次 UserPromptSubmit 把它作为
#     additionalContext 注入,让 agent 自己决定怎么走。
#
# ONLY 注入 prompt — hook 不替你选,agent 自己读 value 推演链自决。
# 不 block,exit 0 + {continue:true},与 value-guard.sh 同风格。
#
# 检测目标: 100 个中英 trigger words(任一命中即触发,可叠加)
#           + ≥ 3 行 "- ☐ " checkbox 形态
#
# Cascade 注入内容: VALUE.md → BRANCH_01..04 → LEAVES.md
#                  + LEAF_2(全做 + 自决)+ LEAF_5(压成 1 个 HITL)指引
#
# Audit:   ~/.claude/hooks/logs/value-guard-next-step.jsonl
# Per-session log: APPENDS to value-reminder-<session_id>.md
#                  (value-guard.sh 在同一 Stop 事件里写过这个文件,
#                   我们追加在末尾,保证注入顺序 = default → anti-pattern)
#
# 退出开关: CLAUDE_VALUE_GUARD_DISABLED=1

set -uo pipefail

# ── escape hatch ───────────────────────────────────────────────────────
if [[ "${CLAUDE_VALUE_GUARD_DISABLED:-0}" == "1" ]]; then
  printf '{"continue": true, "suppressOutput": true}\n'
  exit 0
fi

LOG_DIR="$HOME/.claude/hooks/logs"
AUDIT_FILE="$LOG_DIR/value-guard-next-step.jsonl"
mkdir -p "$LOG_DIR" 2>/dev/null || true

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

input="$(cat)"
session_id="$(printf '%s' "$input" | jq -r '.session_id // "unknown"' 2>/dev/null)"
transcript_path="$(printf '%s' "$input" | jq -r '.transcript_path // ""' 2>/dev/null)"

# ── 取最后一条 assistant 消息的纯文本 ─────────────────────────────────
# 优先从 transcript JSONL 读;fallback 到 stdin 的 last_assistant_message 字段。
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

# transcript 拿不到就静默退出 —— 没法判断就放行,不当 false positive
if [[ -z "$last_msg" ]]; then
  printf '{"continue": true, "suppressOutput": true}\n'
  exit 0
fi

# ── 检测 anti-pattern (100 trigger words + checkbox shape) ───────────
# 命中即 inject prompt 到 next-turn additionalContext,让 agent 自决。
# hook 不替你选,ONLY 注入 — 把判断权还给 agent + value cascade。
markers_found=0
matched=()

TRIGGERS=(
  # ── 直接要用户拍板 (1-25) ──
  "要哪个" "要不要" "要哪个就告诉我" "等你说" "等你确认"
  "等你点头" "等你回复" "等你 OK" "看你" "你来决定"
  "你说呢" "怎么办" "怎么选" "选哪个" "行不行"
  "可以吗" "OK 吗" "好吗" "是不是" "该不该"
  "想不想" "需要吗" "需要你" "走哪条" "选 A 还是 B"
  "你定" "你选"

  # ── 多选菜单 / X 还是 Y (26-35) ──
  "A 还是 B" "几选一" "三选一" "四选一" "1/2/3"
  "选 1" "选 2" "选 A" "选 B" "哪个好"

  # ── 修正建议 / 下一步可选 (36-46) ──
  "修正建议" "后续建议" "下一步可选" "可选下一步" "可选动作"
  "推荐做法" "建议做" "提议" "不如" "不默认做"
  "不替你做"

  # ── follow-up / next step (47-55) ──
  "follow-up" "follow up" "followup" "next step" "next steps"
  "optional next" "follow-ups" "next-step" "suggested next"

  # ── 等你拍板的间接说法 (56-65) ──
  "请确认" "请你确认" "等你拍板" "看你的" "你的意见"
  "你的想法" "你觉得呢" "我看不到" "等我" "你来 X"

  # ── 甩责 / delegation (66-75) ──
  # 注: "要我 X 吗" / "你来 X" / "让我 X 吗" 这类含字面占位符 X 的旧词条
  #     永远匹配不到真实文本,已删除,改由下方 REGEXES 的非连续模式覆盖。
  "你来手" "你来贴" "你来点" "我做还是你做"
  "我做不做" "是否要做" "要我做吗" "是否继续" "是否同意"

  # ── 审批 / approval gate (76-85) ──
  "同意吗" "接受吗" "可以这样吗" "这样行吗" "这样 OK 吗"
  "这样好吗" "你认可吗" "你支持吗" "我等你" "等你拍"

  # ── 间接 deferring (86-95) ──
  "不知道你" "看情况" "不确定你" "取决于你" "你的选择"
  "你的偏好" "你的决定" "我可以吗" "我能吗"

  # ── English only (96-100) ──
  "your call" "up to you" "want me to" "shall I" "let me know"

  # ── 条件式"接着做"offer / "我先停在这, 你要更多再说"(101-130) ──
  # 这类不是问句(无 ?/吗), 是"把已授权的下一步零售化成 offer"——
  #   典型: "需要我接着做的话:可以…或…。否则这就是…完成态。"
  # L3 默认动作 = 直接做 + 出证据, 不是把"要不要继续"抛回给用户。
  "需要我接着" "需要我继续" "需要我再" "需要的话" "需要的话我"
  "要我接着" "要我继续" "要继续的话" "想继续的话" "要的话"
  "可以接着" "我可以接着" "我可以继续" "我也可以" "还可以帮你"
  "如需" "如有需要" "若需要" "如果需要" "如果你需要"
  "否则就是" "否则这就是" "完成态" "就算完成" "也可以接着"
  "接着做的话" "接下来可以" "下一步我可以" "需要继续" "随时可以接着"

  # ── English offer-to-continue (131-140) ──
  "if you want" "if you'd like" "if you need" "i can also" "i could also"
  "happy to" "feel free to" "let me know if" "otherwise this is" "otherwise that's"
)

# ── 非连续 / 占位形态: ERE regex(grep -qE),覆盖 grep -qF 漏掉的拆字话术 ──
# 关键缺口: "要我继续……体检吗?" 这种 "要我…吗" 中间隔了 N 个字,
#           字面词条全 miss。用 [^。!?\n]* 在同一句内跨字匹配,
#           遇句末标点/换行即止,避免跨句误报。
REGEXES=(
  "要我[^。!?？!\n]*吗"                       # 要我继续…体检吗 / 要我帮你…吗
  "让我[^。!?？!\n]*吗"                       # 让我先…吗
  "需要[^。!?？!\n]*吗"                       # 需要我…吗
  "可以[^。!?？!\n]*吗"                       # 可以这样…吗 / 可以吗
  "要不要[^。!?？!\n]*"                       # 要不要我…(做)
  "是否[^。!?？!\n]*(继续|要|做|同意|可以|需要)"   # 是否要继续…
  "你来[^。!?？!\n]*(做|弄|贴|点|跑|手|改|看)"      # 你来…点一下
  "(告诉我|让我知道)[^。!?？!\n]*(即可|就行|哪个|选)"  # 选好告诉我即可 / 哪个就告诉我
  # ── 条件式 offer(无问号也算): "需要我…的话/可以" "否则…完成态" ──
  "需要我[^。!?？!\n]*(的话|可以|继续|接着|再)"         # 需要我接着做的话 / 需要我继续可以
  "要我[^。!?？!\n]*(的话|接着|继续)"                  # 要我接着扫的话
  "(如果|若|如)[^。!?？!\n]*需要[^。!?？!\n]*(我|可以)"  # 如果需要我可以
  "否则[^。!?？!\n]*(完成|就是|可以演示|完成态)"         # 否则这就是…完成态
  "可以[^。!?？!\n]*(一次扫|接着做|继续做|帮你)"          # 可以一次扫掉 / 可以接着做
  "(想|要)[^。!?？!\n]*继续[^。!?？!\n]*的话"            # 想继续的话 / 要继续的话
)

for t in "${TRIGGERS[@]}"; do
  if printf '%s' "$last_msg" | grep -qF -- "$t"; then
    markers_found=$((markers_found + 1))
    matched+=("$t")
  fi
done

for r in "${REGEXES[@]}"; do
  if printf '%s' "$last_msg" | grep -qE -- "$r"; then
    markers_found=$((markers_found + 1))
    matched+=("re:${r}")
  fi
done

# checkbox 形态: ≥ 3 行 "- ☐ "
checkbox_count="$(printf '%s' "$last_msg" | grep -cE '^- ☐ ' || true)"
if (( checkbox_count >= 3 )); then
  markers_found=$((markers_found + 1))
  matched+=("☐×${checkbox_count}")
fi

# ── 命中: 追加 scolding block 到 per-session reminder ─────────────────
if (( markers_found >= 1 )); then
  reminder_file="$LOG_DIR/value-reminder-${session_id}.md"

  matched_str="${matched[*]}"

  cat >> "$reminder_file" <<SCOLD_EOF

---

## ⚠️ value-guard-next-step · 上轮 anti-pattern 命中

命中标志: \`${matched_str}\`

**你刚才做了什么:**
在结尾抛出 "修正建议 / 不默认做 / 等你说" 列表,把已批发的决策权零售化成多选菜单。

**这违反:**
- L1 授权是批发,不是零售(\`~/.claude/values/BRANCH_01_authorization.md\`)
- L3 默认动作 = ship + 出证据,不是 ask(\`~/.claude/values/BRANCH_03_ship_evidence.md\`)

**对应叶:**
- LEAF_2 「4 选 1 → 全做 + 自决」
- LEAF_5 「4 选 1 → 压成 1 个 HITL」

**下次直接做的形状(不再列菜单):**
- 把 cheap 项合并执行,evidence 写进 commit / artifact / HTML
- 真不可逆的(改全局 settings.json / 推 token / rm -rf / MR push / 公开承诺)保留为单条 HITL
- 不可逆 HITL 必须用格式: "X 已做完 Y/Z/W, 只剩 Q 这步不可逆, OK 吗?"
- 永远不要 "要我 X 吗?" / "你要不要做 X?" / "要走哪条?" / "要哪个就告诉我?"

**cheap signal 自检三选一,必出一句:**
- a) "已做完 X, evidence: <URL/path>"
- b) "选 X, 因为 Y 的代价是 Z; 不选 Y"
- c) "X 不可逆, 但 90% 已做完 (diff stat + tests + revert path), OK 吗?"
SCOLD_EOF

  # ── audit JSONL ──
  jq -cn \
    --arg ts "$ts" \
    --arg sid "$session_id" \
    --argjson n "$markers_found" \
    --arg m "$matched_str" \
    '{ts:$ts, session_id:$sid, action:"anti-pattern-trigger", markers_found:$n, markers:$m}' \
    >> "$AUDIT_FILE" 2>/dev/null || true

  printf '{"continue": true, "stopReason": "VALUE anti-pattern (next-step suggestion list) detected; scolding block queued for next turn — see value-guard-next-step.jsonl"}\n'
  exit 0
fi

# ── 未命中: 静默 approve ──
printf '{"continue": true, "suppressOutput": true}\n'
exit 0
