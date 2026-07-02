#!/usr/bin/env bash
# ~/.claude/hooks/honest-report-gate.sh
#
# Stop hook — KEYWORD-TRIGGERED honest-report gate.
#
# Why: the agent sometimes ends a turn *claiming* a job is finished, or hedges
# ("应该可以 / should work / 理论上 / 留作增量 / 范围诚实说明") instead of either
# (a) actually doing+verifying it, or (b) plainly saying what was NOT done. The
# user wants the agent to REALLY do the job and report honestly, without being
# asked. This hook watches the final assistant message; if it trips any of a
# large keyword set (completion-claims OR hedge/deferral words) it blocks the
# stop ONCE and injects a reminder to separate VERIFIED-DONE (with evidence)
# from DEFERRED/UNVERIFIED, then go verify or honestly say it's not done.
#
# Soft + self-limiting (never loops, never runaway):
#   - Respects `stop_hook_active`: if the stop was already blocked once this
#     turn (by this or any Stop hook) -> allow the stop. So it fires at most
#     once per turn-ending; the agent's honest re-report is then let through.
#   - Pure nudge: the decision text explicitly says "if genuinely verified,
#     restate the evidence and stop — this fires once." Hook 不替 agent 选。
#
# Escape hatch: set CLAUDE_HONEST_REPORT_OFF=1 to silence for a run.
#
# Audit: appends one JSONL line per fire to logs/honest-report-gate.jsonl.

set -uo pipefail

# Escape hatch first — emit nothing, allow stop.
if [[ "${CLAUDE_HONEST_REPORT_OFF:-0}" == "1" ]]; then
  exit 0
fi

input="$(cat)"

LOG_DIR="$HOME/.claude/hooks/logs"
mkdir -p "$LOG_DIR" 2>/dev/null || true

# Pass the hook JSON as argv[2] (NOT stdin — stdin carries the python program).
python3 - "$LOG_DIR" "$input" <<'PY'
import sys, os, json, datetime

log_dir = sys.argv[1]
raw = sys.argv[2] if len(sys.argv) > 2 else ""

def allow():            # let the stop happen
    sys.exit(0)

try:
    data = json.loads(raw)
except Exception:
    allow()

# Loop guard: if we (or any Stop hook) already forced a continuation this turn,
# let the agent's honest re-report through instead of piling on.
if data.get("stop_hook_active"):
    allow()

tpath = data.get("transcript_path") or ""
session_id = data.get("session_id") or "unknown"

# --- pull the LAST assistant text message from the transcript -----------------
last_text = ""
try:
    with open(tpath, encoding="utf-8") as f:
        lines = f.readlines()
    for ln in reversed(lines):
        ln = ln.strip()
        if not ln:
            continue
        try:
            obj = json.loads(ln)
        except Exception:
            continue
        msg = obj.get("message") or {}
        is_assistant = (obj.get("type") == "assistant") or (msg.get("role") == "assistant")
        if not is_assistant:
            continue
        content = msg.get("content", obj.get("content"))
        text = ""
        if isinstance(content, str):
            text = content
        elif isinstance(content, list):
            parts = []
            for c in content:
                if isinstance(c, dict) and c.get("type") == "text":
                    parts.append(c.get("text", ""))
                elif isinstance(c, str):
                    parts.append(c)
            text = " ".join(parts)
        if text and text.strip():
            last_text = text
            break
except Exception:
    allow()

if not last_text.strip():
    allow()

low = last_text.lower()

# --- many keyword triggers ----------------------------------------------------
# Bucket A: "it's finished" claims.   Bucket B: hedge / deferral / pretend.
# Trigger on ANY hit from either bucket (the user asked for many triggers); the
# single-fire guard keeps it from being noisy.
CLAIM_EN = [
    "done", "finished", "complete", "completed", "shipped", "ship it",
    "all set", "good to go", "ready to merge", "works now", "it works",
    "fixed", "resolved", "lgtm", "looks good", "all green", "result:",
]
CLAIM_ZH = [
    "完成", "已完成", "搞定", "做完", "跑通", "可以了", "好了", "修好",
    "已修复", "已解决", "已交付", "全绿", "已上线", "大功告成",
]
HEDGE_EN = [
    "should work", "should be fine", "should be", "probably", "likely",
    "in theory", "theoretically", "presumably", "i assume", "assuming",
    "untested", "not tested", "can't verify", "cannot verify",
    "couldn't verify", "without testing", "todo", "follow-up", "follow up",
    "deferred", "left as", "out of scope", "stub", "placeholder", "mock",
    "for now", "leave it as",
]
HEDGE_ZH = [
    "应该可以", "应该能", "应该没问题", "理论上", "大概", "估计", "或许",
    "未验证", "没验证", "未测试", "没测", "没跑", "留作增量", "后续再",
    "待办", "占位", "桩", "留给", "暂时", "先这样", "范围诚实说明",
    "应该是", "按理说", "没来得及", "留作后续", "未覆盖",
]

def hits(text, words):
    return [w for w in words if w in text]

claim = hits(low, CLAIM_EN) + hits(last_text, CLAIM_ZH)
hedge = hits(low, HEDGE_EN) + hits(last_text, HEDGE_ZH)
matched = claim + hedge

if not matched:
    allow()

# audit
try:
    with open(os.path.join(log_dir, "honest-report-gate.jsonl"), "a", encoding="utf-8") as a:
        a.write(json.dumps({
            "ts": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
            "session_id": session_id,
            "matched": matched[:12],
            "action": "block-once",
        }, ensure_ascii=False) + "\n")
except Exception:
    pass

trig = "、".join(matched[:6])
reason = (
    "⛔ honest-report gate(本轮只触发这一次)—— 你的收尾里出现了"
    f"「{trig}」这类「完成/对付」信号。停之前先把『做了什么』和『声称什么』分开:\n"
    "1) 每一条「完成 / done / 修好 / 全绿」都要贴证据:命令输出 / 测试 PASS / 文件路径 / 截图。"
    "没真跑过就不要说「完成」。\n"
    "2) 凡是 deferred / stub / mock / 留作增量 / 未验证 / 应该可以 / 理论上 的部分,"
    "直接明说「这块没做」或「没验证」,不要用模糊措辞糊过去,也不要写一段「范围诚实说明」就当交付。\n"
    "3) 能现在做/现在验证的,就现在动手做(写代码 / 跑测试 / 起服务 / curl / 截图),"
    "而不是停下来汇报或问「要不要继续」。\n"
    "4) 真的已验证完成:复述证据(evidence: <path / 输出 / 测试名>)然后正常停下——"
    "本钩子已记一次,你再次停下会被放行。\n"
    "(关掉本轮:CLAUDE_HONEST_REPORT_OFF=1)"
)

print(json.dumps({"continue": False, "reason": reason}, ensure_ascii=False))
sys.exit(0)
PY
exit 0
