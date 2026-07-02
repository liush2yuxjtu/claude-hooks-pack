#!/usr/bin/env bash
# ~/.claude/hooks/finish-not-defer.sh
#
# Stop hook — enforce: "真做完,别用『诚实范围说明 / 留作增量』当借口收尾。"
# rubric: HOOK_DESIGN_RUBRIC.md
#
# 触发源 (rubric §0):
#   - ~/.claude/VALUE.md 根值「信任是放大器,问题是衰减器」
#   - ~/.claude/values/BRANCH_03_ship_evidence.md (L3 默认动作 = ship + 出证据,不是 ask/defer)
#   - ~/.claude/values/BRANCH_04_irreversible.md  (L4 只有不可逆+高代价才停;defer 不是不可逆)
#   - ~/.claude/values/LEAVES.md → LEAF_2「4 选 1 → 全做」, LEAF_7「DOD 真达成才算完」
#   - ~/.claude/CLAUDE.md (MUST NOT defer user-facing work to a follow-up MR 系列)
#   - 用户 2026-06-26 显式反馈:"we like honest report INSTEAD of pretending finished —
#     now we want it to REALLY do the job without asking. add a stop hook."
#
# 为什么需要它(它补的洞 / 与已有 hook 的差异):
#   keep-going.sh         → 仅在 marker 文件存在时强制续作(窄;非默认开)。
#   straight-fix-no-ask   → 抓「提议 / 反问 / 要不要我」(OFFER/ASK 形态)。
#   followup-not-ask      → 抓 (deferral keyword) AND (问号"?"/"吗") 同现。
#   本 hook 抓的是第三种、最隐蔽的形态:**陈述句式的"诚实范围说明"** ——
#   不提问、不甩责,而是在一份"已完成"报告里,把用户明确要的核心需求
#   切出来标成「留作增量 / 范围诚实说明 / 仍走 standalone / 缝隙已标注 / 后续对接」。
#   它读起来很诚实、很专业,但本质是 *把没做完包装成做完了*。这正是用户点名要拦的。
#
#   关键纪律(避免误伤真诚实):只有当 (deferral/scope-caveat marker) AND
#   (完成声明 OR 诚实范围标题) 同时出现才拦 —— 即"边宣称完成边 defer"。
#   纯粹"我还没做、正在做 X"的诚实陈述(无完成声明)不命中。
#
#   decision:block = "force CONTINUE"(让 agent 接着把切掉的部分真做完),
#   与 rubric §7 禁止的 continue:false(KILL 工作流)相反。沿用已验证机制。
#
# 什么情况下**不**触发(rubric §1 抗噪 + §2 负向过滤):
#   - stop_hook_active=true → 放行,防无限循环
#   - per-session 命中达上限(默认 4)→ 自动放行,防 runaway
#   - 触发词只在 ```fenced code block``` 内 → 不计数(剥离后再匹配)
#   - 没有 deferral marker,或有 deferral 但没有"完成声明/范围标题" → 放行
#     (= 正在做、没假装完成,不拦)
#   - 取不到 transcript / 无 jq → fail-open 放行
#   - 真·不可逆需授权(force push / rm -rf / 推 token):reason 给干净出口 ——
#     把它写成一句明确陈述(默认建议+代价)即可,不算 defer。
#
# Audit (rubric §6): ~/.claude/hooks/logs/finish-not-defer.jsonl
#                    字段 ts/session_id/action/markers_found/matched/has_done_claim
# Per-session 日志:  ~/.claude/hooks/logs/finish-not-defer-<session>.md
#
# Escape hatch (rubric §4): CLAUDE_FINISH_NOT_DEFER_DISABLED=1
# Self-test (rubric §5):    finish-not-defer.test.sh
# Fail-open: 任何内部不确定 → approve(放行停止),绝不卡死工作流。

set -uo pipefail

approve() { printf '{"continue": true, "suppressOutput": true}\n'; exit 0; }

# ── escape hatch ───────────────────────────────────────────────────────
[[ "${CLAUDE_FINISH_NOT_DEFER_DISABLED:-0}" == "1" ]] && approve

command -v jq >/dev/null 2>&1 || approve

input="$(cat)" || approve
[[ -z "$input" ]] && approve

# ── loop guard ─────────────────────────────────────────────────────────
active="$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)"
[[ "$active" == "true" ]] && approve

session_id="$(printf '%s' "$input" | jq -r '.session_id // "unknown"' 2>/dev/null)"

# ── per-session runaway cap ────────────────────────────────────────────
STATE="$HOME/.claude/hooks/state"
mkdir -p "$STATE" 2>/dev/null || true
CAP="${CLAUDE_FINISH_NOT_DEFER_MAX:-4}"
CNT_FILE="$STATE/finish-not-defer.${session_id}.count"
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

# ── 负向过滤:剥掉 fenced code block 再匹配 ────────────────────────────
stripped="$(printf '%s' "$last_text" | awk '
  /^[[:space:]]*```/ { infence = !infence; next }
  !infence { print }
')"
low="$(printf '%s' "$stripped" | tr '[:upper:]' '[:lower:]')"

# ── (1) DEFERRAL / SCOPE-CAVEAT triggers(把核心需求切出去标"以后再说")─────
# 高信号多词短语;避免裸"后续"/"增量"/"later" 这类高误报单词。
markers_found=0
matched=()
DEFER_TRIGGERS=(
  # ── A. 留作增量 / 留待后续(核心反模式)──
  "留作增量" "留作后续" "留作下一步" "留作 follow" "留作followup" "作为增量" "作为后续增量"
  "后续增量" "增量对接" "增量交付" "留作迭代" "下一步增量" "二期再" "二期对接" "二期接入"
  "留待后续" "留待下一步" "留到后续" "留给后续" "留给下一步" "暂留作" "先留作"
  "后续再接" "后续再对接" "后续对接" "后续补" "后续补上" "后续完善" "后续打通" "后续接入"
  "下一轮再接" "下一轮补" "下个 pr 再" "另开 pr 接" "另起一轮接" "留个 todo" "留 todo"
  # ── B. 诚实范围说明 / 范围诚实 / 已标注缝隙(包装语)──
  "范围诚实说明" "范围诚实" "诚实说明" "诚实范围" "诚实地说" "老实说这部分"
  "范围说明" "scope 说明" "已标注" "缝隙已标注" "缝隙已" "已留标注" "已注释缝隙"
  "已标注缝隙" "标注了缝隙" "留作标注" "标注待办" "标注 todo" "标注后续"
  # ── C. 仍走 / 沿用 standalone / 未真接(声称打通但其实没接)──
  "仍走" "仍沿用" "沿用自带" "沿用其自带" "仍用其自带" "仍是自带" "仍走 standalone"
  "仍走自带" "仍走旧" "仍走 mock" "还是走 mock" "仍是 mock" "暂用 mock" "暂走 mock"
  "未真接" "未真正接" "未真正打通" "未接后端" "未接入后端" "未对接后端" "没真接"
  "没有真正接" "尚未接入" "尚未对接" "尚未打通" "尚未接" "暂未接入" "暂未对接"
  "暂未打通" "暂未实现" "暂未真" "暂不接" "暂不打通" "未端到端" "非端到端"
  # ── D. 部分完成 / 假装完成 ──
  "部分完成" "部分打通" "只打通了" "仅打通" "只接了" "仅接了" "只做了一半" "做了一半"
  "核心链路已" "主链路已打通其余" "其余留" "其余部分留" "剩余留" "剩下的留"
  "demo 级" "demo 程度" "占位实现" "先占位" "占位即可" "先给占位" "桩实现" "先用桩"
)
for kw in "${DEFER_TRIGGERS[@]}"; do
  if [[ "$low" == *"$kw"* ]]; then
    markers_found=$((markers_found + 1)); matched+=("$kw")
    [[ "$markers_found" -ge 6 ]] && break
  fi
done

# ── EN deferral triggers ───────────────────────────────────────────────
if [[ "$markers_found" -lt 6 ]]; then
  EN_DEFER=(
    "left as an increment" "left as increment" "as a follow-up" "as a followup"
    "leave it as a follow" "leave as follow" "follow-up increment" "in a follow-up mr"
    "in a future pr" "in a future mr" "deferred to" "punt to" "punted to" "out of scope for now"
    "scope caveat" "scope note" "honest scope" "honest caveat" "known limitation"
    "known limitations" "marked the seam" "seam is marked" "seam noted" "wired later"
    "not yet wired" "not actually wired" "not truly wired" "still standalone" "still uses its own"
    "still uses the standalone" "still goes through the standalone" "still mock" "still a mock"
    "stubbed for now" "placeholder for now" "stub implementation" "demo-level" "demo grade"
    "partially wired" "only wired the" "only the core path" "rest is left" "remaining left"
    "left for later" "to be wired" "to be done later" "follow-up work" "incremental follow"
  )
  for kw in "${EN_DEFER[@]}"; do
    if [[ "$low" == *"$kw"* ]]; then
      markers_found=$((markers_found + 1)); matched+=("$kw")
      [[ "$markers_found" -ge 6 ]] && break
    fi
  done
fi

# ── 结构触发(rubric §1 形态):markdown 标题式"范围/遗留/局限"小节 ──────────
if [[ "$markers_found" -eq 0 ]]; then
  if printf '%s' "$stripped" | grep -Eiq '^[[:space:]]*#{1,6}[[:space:]]*(范围(诚实)?说明|遗留(项|说明)?|未完成|局限|scope (note|caveat)|known limitation|honest|out[- ]of[- ]scope|follow[- ]?up)'; then
    markers_found=1; matched+=("structural:scope-caveat-heading")
  fi
fi

# 没有任何 deferral marker → 放行(不是 defer)
[[ "$markers_found" -eq 0 ]] && approve

# ── (2) 完成声明 / scope-caveat 上下文门控 ──────────────────────────────
# 只有"边宣称完成边 defer"才拦。无完成声明 = 正在做的诚实陈述,放行。
has_done=0
DONE_MARKERS=(
  "result:" "已完成" "已合入" "已合并" "已交付" "已 ship" "已 push" "已推送" "全部完成"
  "搞定" "收尾" "交付完成" "完工" "做完了" "已经完成" "本次完成" "完成了" "已落地"
  "ship 完成" "ship 了" "已上墙" "大功告成" "齐活" "✅ 完成" "全绿" "已验证通过"
  "shipped" "all done" "done." "completed" "finished" "delivered" "wrapped up"
  "ready to merge" "pushed to" "merged" "task complete" "everything is" "fully working"
  "范围诚实说明" "范围说明" "scope note" "scope caveat" "honest scope" "诚实说明"
)
for kw in "${DONE_MARKERS[@]}"; do
  low2="$(printf '%s' "$kw" | tr '[:upper:]' '[:lower:]')"
  if [[ "$low" == *"$low2"* ]]; then has_done=1; break; fi
done

# 有 deferral 但没有完成声明/范围标题 → 这是"正在做"的诚实陈述,放行
[[ "$has_done" -eq 0 ]] && approve

# ── 命中:记账 + per-session 日志 + block ─────────────────────────────
echo $((cnt + 1)) > "$CNT_FILE" 2>/dev/null || true

LOG_DIR="$HOME/.claude/hooks/logs"
mkdir -p "$LOG_DIR" 2>/dev/null || true
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
matched_json="$(printf '%s\n' "${matched[@]}" | jq -R . | jq -cs . 2>/dev/null)"
jq -cn --arg ts "$ts" --arg sid "$session_id" --argjson mf "$markers_found" \
  --argjson m "${matched_json:-[]}" --argjson hd "$has_done" \
  '{ts:$ts, session_id:$sid, action:"block-defer-while-claiming-done", markers_found:$mf, matched:$m, has_done_claim:$hd}' \
  >> "$LOG_DIR/finish-not-defer.jsonl" 2>/dev/null || true
{
  printf '\n## %s — finish-not-defer 命中\n' "$ts"
  printf -- '- matched: %s\n' "$(printf '%s ' "${matched[@]}")"
} >> "$LOG_DIR/finish-not-defer-${session_id}.md" 2>/dev/null || true

reason="$(cat <<'R'
[hook:finish-not-defer] 你在一份"已完成"的收尾里,把用户明确要的核心需求切出去标成「留作增量 / 范围诚实说明 / 仍走 standalone / 缝隙已标注 / 后续对接」。用户 2026-06-26 显式规则:**要的是真做完,不是诚实地 defer**。诚实很好,但诚实 ≠ 可以不做。按 VALUE 级联(根→L3:默认动作 = ship + 出证据;L4:只有不可逆+高代价才停):

1. 把你刚才标成"留作增量 / 后续 / 仍走自带 / 未真接 / 占位"的那一(几)块,**这一轮真正做完** —— 探查、改代码、起服务、跑端到端、出证据。彼此独立就开后台并行 subagent 一起做。
2. 做完后用一句可复核的话收尾:"已做完 X,evidence: <path/URL>"。
3. 唯一可以"不做"的情况:(a) 真正不可逆且高代价(force push / rm -rf / 推 token / 公开发布 / 改全局凭据)需授权 —— 此时先把 90%(diff+test+revert)做完,再用一句明确陈述说明默认建议与代价;(b) 真硬阻塞(缺凭据/外部不可达且已穷尽 work-around)—— 写清 blocker 一句话。这两种都不是"留作增量"。
4. "缝隙已标注 / 留作后续 / demo 级 / 占位即可" 这类自我开脱一律不接受:能做就现在做完它。

重写收尾:要么把切掉的部分真做完并出证据,要么用一句明确的"不可逆需授权 / 硬阻塞"陈述收口 —— 不要再用"诚实范围说明"把没做完包装成做完。
R
)"

jq -cn --arg r "$reason" '{decision:"block", reason:$r}'
exit 0
