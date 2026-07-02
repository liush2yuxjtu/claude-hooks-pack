#!/usr/bin/env bash
# ~/.claude/hooks/straight-fix-no-ask.sh
#
# Stop hook — enforce: "go straight and fix without asking for help."
# rubric: HOOK_DESIGN_RUBRIC.md
#
# 触发源 (rubric §0):
#   - ~/.claude/VALUE.md 根值「信任是放大器,问题是衰减器」
#   - ~/.claude/values/BRANCH_03_ship_evidence.md (L3 默认动作 = ship + 出证据,不是 ask)
#   - ~/.claude/values/BRANCH_01_authorization.md (L1 授权是批发,不是零售)
#   - ~/.claude/values/LEAVES.md  → LEAF_2「4 选 1 → 全做 + 自决」, LEAF_5「压成 1 个 HITL」
#   - ~/.claude/CLAUDE.md (MUST NOT ask … 系列)
#
# 为什么需要它(与已有 hook 的差异 / 它补的洞):
#   followup-not-ask.sh 只在 (deferral keyword) AND (question marker "?"/"吗") 同时出现时
#   才拦截。但最常见的反模式是 *陈述句形态的提议*,根本没有问号:
#       "要的话我可以下一轮顺手修掉 X"
#       "如果需要,我可以帮你改"
#       "下次再顺手处理"
#       "I can do that next round if you want"
#   这些是 OFFER / DEFER-TO-LATER 形态,不带 "?"/"吗",于是从 followup-not-ask 的
#   question-marker 闸门下溜走。本 hook 专抓"提议代替动手 / 留待下一轮"的陈述句,
#   不要求问号 —— 命中即 decision:block,把"现在就做"从建议升级为强制。
#
#   注:decision:block = "force CONTINUE"(让 agent 接着干),与 rubric §7 禁止的
#   `continue:false`(直接 KILL 工作流)是相反的两件事。followup-not-ask.sh /
#   keep-going.sh 同用 decision:block,本 hook 沿用同一已验证机制。
#
# 什么情况下**不**触发(rubric §1 抗噪 + §2 负向过滤):
#   - stop_hook_active=true(已经在 block 续作链里)→ 放行,防无限循环
#   - 命中数达到 per-session 上限(默认 5)→ 自动放行,防 runaway
#   - 触发词只出现在 ```fenced code block``` 内 → 不计数(剥离后再匹配)
#   - 没有 transcript / 没有 jq / 取不到最后一条 assistant 文本 → fail-open 放行
#   - 真正不可逆 / 需授权 / 越界的事:reason 给了干净出口 —— agent 只要把
#     "这是越界/需授权,所以不做"明确写成一句话(不带提议词)再停,即可放行
#
# 行为:命中 → {"decision":"block","reason":...} 让 agent 接着把刚才"提议"的事
#       直接做掉;reason 不替 agent 选具体怎么做,只指出"你在提议而不是动手"。
#
# Audit (rubric §6): ~/.claude/hooks/logs/straight-fix-no-ask.jsonl
#                    字段 ts/session_id/action/markers_found/matched
# Per-session 日志:  ~/.claude/hooks/logs/straight-fix-no-ask-<session>.md
#
# Escape hatch (rubric §4): CLAUDE_STRAIGHT_FIX_NO_ASK_DISABLED=1
# Fail-open: 任何内部不确定 → approve(放行停止),绝不卡死工作流。

set -uo pipefail

approve() { printf '{"continue": true, "suppressOutput": true}\n'; exit 0; }

# ── escape hatch ───────────────────────────────────────────────────────
[[ "${CLAUDE_STRAIGHT_FIX_NO_ASK_DISABLED:-0}" == "1" ]] && approve

command -v jq >/dev/null 2>&1 || approve

input="$(cat)" || approve
[[ -z "$input" ]] && approve

# ── loop guard:已经在续作链里就放行 ───────────────────────────────────
active="$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)"
[[ "$active" == "true" ]] && approve

session_id="$(printf '%s' "$input" | jq -r '.session_id // "unknown"' 2>/dev/null)"

# ── per-session runaway cap ────────────────────────────────────────────
STATE="$HOME/.claude/hooks/state"
mkdir -p "$STATE" 2>/dev/null || true
CAP="${CLAUDE_STRAIGHT_FIX_NO_ASK_MAX:-5}"
CNT_FILE="$STATE/straight-fix-no-ask.${session_id}.count"
cnt="$(cat "$CNT_FILE" 2>/dev/null)"; cnt="${cnt:-0}"
if [[ "$cnt" =~ ^[0-9]+$ ]] && [[ "$cnt" -ge "$CAP" ]]; then approve; fi

# ── 取最后一条 assistant 消息纯文本 ───────────────────────────────────
transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)"
last_text=""
if [[ -n "$transcript" && -f "$transcript" ]]; then
  last_text="$(tail -n 800 "$transcript" 2>/dev/null | jq -rs '
    map(select(.type == "assistant"))
    | last
    | (.message.content // [])
    | map(select(.type == "text") | .text)
    | join("\n")
  ' 2>/dev/null)"
fi
if [[ -z "$last_text" || "$last_text" == "null" ]]; then
  last_text="$(printf '%s' "$input" | jq -r '.last_assistant_message // ""' 2>/dev/null)"
fi
[[ -z "$last_text" || "$last_text" == "null" ]] && approve

# ── 负向过滤:剥掉 fenced code block(``` … ```)再匹配 ─────────────────
stripped="$(printf '%s' "$last_text" | awk '
  /^[[:space:]]*```/ { infence = !infence; next }
  !infence { print }
')"
low="$(printf '%s' "$stripped" | tr '[:upper:]' '[:lower:]')"

# ── TRIGGERS:offer / defer-to-later / punt / approval-gate(≥100,无需问号)──
# 每组上方 `# ── 类别 ──`;高信号多词短语,避免裸 "可以"/"can" 这类高误报词。
markers_found=0
matched=()
TRIGGERS=(
  # ── A. 留待下一轮 / 以后再做(陈述句提议,核心反模式)──
  "下一轮顺手" "下一轮我可以" "下一轮可以" "下一轮再" "下一轮我来" "下一轮帮你"
  "下次顺手" "下次我可以" "下次可以" "下次再" "下次我来" "下次帮你"
  "后续我可以" "后续可以" "后续再" "后续我来" "之后我可以" "之后可以" "之后再"
  "稍后我可以" "稍后再" "回头我可以" "回头再" "回头帮你"
  "顺手修掉" "顺手修" "顺手帮你" "顺手处理" "顺手解决" "顺带修" "顺带帮你"
  "留到下次" "留到下一轮" "留作下次" "留作下一轮" "留作 follow" "留个 follow"
  "另开一轮" "另起一轮" "另开 pr" "另开 mr" "下个 pr" "下个 mr" "下个 pr 再" "下一个 pr"
  # ── B. 条件式提议「要的话我可以…」(无问号)──
  "要的话我" "要的话可以" "需要的话我" "需要的话可以" "如果需要我" "如果需要,我"
  "如果需要的话" "如果你需要" "如果想要" "如果你想" "如果你愿意" "想要的话"
  "有需要我" "有需要的话" "若需要" "若有需要" "要是需要" "要是想" "想的话我可以"
  "需要我帮" "我可以帮你" "我可以再" "我也可以" "我还可以帮"
  # ── C. 直接反问 / 拍板(常带问号,这里也收陈述变体)──
  "要不要我" "要不要" "需要我吗" "需要我" "要我吗" "要我" "用不用我"
  "是否需要" "是否要我" "是否要" "你要不要" "你看要不要" "你看需不需要"
  "需不需要我" "需不需要" "你拍板" "听你的" "你决定要不要" "你说了算"
  "你说要不要" "看你要不要" "由你定"
  # ── D. delegation 甩责(具体多词短语,降误报)──
  "你可以自己" "你自己来" "你自己处理" "交给你来" "交给你处理" "由你来"
  "建议你自己" "需要你来" "得你来" "请你自己" "麻烦你自己"
  # ── E. 审批 gate ──
  "请确认" "确认后我" "确认后再" "等你确认" "经你同意" "经你确认" "得到你同意"
  "征得你同意" "你点头" "你批准后" "你拍板后" "拿到你确认"
  # ── ZH 小计 ~ 95;以下 EN ~ 35,合计 ≥ 100(rubric §1 70/30)──
  # ── A-en. defer-to-later ──
  "next round" "next pass" "next time i" "do it next" "in a follow-up" "in a followup"
  "in a future pr" "in a future mr" "later i can" "i'll do it next" "circle back"
  "leave it for" "leave that for" "punt to" "defer to"
  # ── B-en. conditional offer ──
  "if you want i" "if you'd like i" "if you want, i" "if you'd like, i"
  "if you need i" "if you prefer i" "if desired" "should you want"
  "i'd be happy to" "happy to help" "happy to do that" "happy to add" "happy to fix"
  "let me know if you want" "let me know if you'd like"
  "let me know and i" "just say the word" "i can also do" "i can do that if"
  # ── C-en. direct ask ──
  "do you want me to" "want me to" "should i " "shall i " "would you like me to"
  "do you need me to" "should i go ahead" "let me know if i should"
  # ── E-en. approval gate ──
  "please confirm" "once you confirm" "awaiting your" "pending your" "with your approval"
)
for kw in "${TRIGGERS[@]}"; do
  if [[ "$low" == *"$kw"* ]]; then
    markers_found=$((markers_found + 1))
    matched+=("$kw")
    [[ "$markers_found" -ge 6 ]] && break   # 够证明即可,省时间
  fi
done

# ── 结构触发(rubric §1 形态):"X 还是 Y" 菜单 / 末行问句提议 ─────────────
if [[ "$markers_found" -eq 0 ]]; then
  if printf '%s' "$stripped" | grep -Eq '(还是).{1,40}[?？]\s*$|要不要.{0,30}$'; then
    markers_found=1
    matched+=("structural:menu-or-trailing-offer")
  fi
fi

[[ "$markers_found" -eq 0 ]] && approve

# ── 命中:记账 + per-session 日志 + block ─────────────────────────────
echo $((cnt + 1)) > "$CNT_FILE" 2>/dev/null || true

LOG_DIR="$HOME/.claude/hooks/logs"
mkdir -p "$LOG_DIR" 2>/dev/null || true
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
matched_json="$(printf '%s\n' "${matched[@]}" | jq -R . | jq -cs . 2>/dev/null)"
jq -cn --arg ts "$ts" --arg sid "$session_id" --argjson mf "$markers_found" \
  --argjson m "${matched_json:-[]}" \
  '{ts:$ts, session_id:$sid, action:"block-offer-not-do", markers_found:$mf, matched:$m}' \
  >> "$LOG_DIR/straight-fix-no-ask.jsonl" 2>/dev/null || true
{
  printf '\n## %s — straight-fix-no-ask 命中\n' "$ts"
  printf -- '- matched: %s\n' "$(printf '%s ' "${matched[@]}")"
} >> "$LOG_DIR/straight-fix-no-ask-${session_id}.md" 2>/dev/null || true

reason="$(cat <<'R'
[hook:straight-fix-no-ask] 你的收尾消息在「提议 / 留待下一轮 / 问要不要」,而不是直接动手。按 VALUE 级联(根→L1→L3:默认动作 = ship + 出证据,不是 ask),现在就去做,别问、别留:

1. 把你刚才提议或要留到"下一轮 / 下次 / 后续 / 顺手"的那件事,**这一轮直接做掉** —— 探查、改代码、跑测试、出证据。彼此独立就开后台并行 subagent。
2. 做完给 cheap signal:"已做完 X, evidence: <path>"。
3. 唯一可以"不做"的情况:这件事 (a) 真正越界(明显属于另一个任务/仓库,且非小改) 或 (b) 不可逆且高代价(force push / rm -rf / 推 token / 公开发布 / 改全局凭据)。即便如此也别用"要不要 / 要的话我可以"提问形态 —— 而是把"这是越界/需授权,所以本轮不做"明确写成一句话陈述(给出默认建议 + 代价),不带提议词,再停。
4. "顺手修掉 / 下一轮再修 / 留作 follow-up" 这类口头 IOU 一律不接受:能做就现在做。

重写收尾:去掉提议/反问,要么把事做完并出证据,要么用一句明确的"越界/需授权"陈述收口。
R
)"

jq -cn --arg r "$reason" '{decision:"block", reason:$r}'
exit 0
