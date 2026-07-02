#!/bin/bash
# Stop hook —— 强制"不停下来问/不做阶段性汇报式停顿,直接干完下一步",
# 直到 DOD 真正达成 / 硬阻塞 / 不可逆高代价操作需授权。
#
# 为什么需要它:用户的 followup-not-ask / value-guard 等是"提示型"钩子(只注入文字,
# 不阻止停止),模型仍可能在自认为是"自然 checkpoint"处停下汇报。本钩子用 Stop 的
# decision:block 真正阻止停止,把"继续"从建议升级为强制。
#
# 安全设计(防 runaway):
#   1) marker 门控:仅当 ~/.claude/hooks/state/keep-going.on 存在时才生效。
#      普通短任务(无 marker)完全不受影响。
#   2) 计数封顶:同一激活周期最多强制续作 $MAX 次(默认 25),到顶自动摘 marker 放行。
#   3) 自我退出:reason 明确要求 agent 在 (a)DOD 达成 / (b)硬阻塞 / (c)不可逆需授权 时,
#      先 `rm` marker 再停 —— 给 agent 一个干净的关闭开关。
#   4) 仅作用于主会话:fork/subagent 走 SubagentStop,不会被本 Stop 钩子拦住。

STATE="$HOME/.claude/hooks/state"
mkdir -p "$STATE" 2>/dev/null
MARK="$STATE/keep-going.on"

# 未激活 → 放行停止
[ -f "$MARK" ] || exit 0

CNT_FILE="$STATE/keep-going.count"
CNT=$(cat "$CNT_FILE" 2>/dev/null); CNT=${CNT:-0}
MAX=$(cat "$STATE/keep-going.max" 2>/dev/null); MAX=${MAX:-25}

# 到顶:自动停用并放行,防止无限循环
if [ "$CNT" -ge "$MAX" ] 2>/dev/null; then
  rm -f "$MARK" "$CNT_FILE" 2>/dev/null
  exit 0
fi
echo $((CNT + 1)) > "$CNT_FILE"

cat <<'JSON'
{"decision":"block","reason":"【keep-going 钩子】不要停下来汇报或等确认 —— 立刻继续既定计划的下一个具体步骤并动手做(写代码 / 跑测试 / 起服务 / 出证据)。只有以下三种情况才允许停:(a) 整个目标 DOD 已真正达成且已验证(真实用户能用 + CEO 中文证明包);(b) 真正的硬阻塞(缺凭据 / 外部不可达,且已穷尽 work-around 仍过不去);(c) 不可逆且高代价操作(push MR / rm -rf / 推 token)需用户授权 —— 此时先把 90%(diff + test + revert 方案)做完再问。若命中 (a)/(b)/(c) 任一,先执行 `rm ~/.claude/hooks/state/keep-going.on` 再停;否则现在就继续干,不要复述进度、不要问'要不要继续'。"}
JSON
exit 0
