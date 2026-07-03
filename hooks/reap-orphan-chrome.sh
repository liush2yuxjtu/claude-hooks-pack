#!/usr/bin/env bash
# ~/.claude/hooks/reap-orphan-chrome.sh
#
# KEYWORD-TRIGGERED UserPromptSubmit hook. POINTER ONLY — it NEVER kills a process.
# On a hit it injects an agent-visible / user-invisible note saying: "this is a known
# issue, a reference script + solution exists at <path>, go run it". The actual
# diagnose + surgical reap lives in the sibling reference script:
#     ~/.claude/hooks/reap-orphan-chrome.solution.sh
# The agent reads this injected note, runs the solution script, and reports back.
#
# WHY POINTER-ONLY (changed 2026-06-25 per user request)
# Earlier revisions of this hook killed orphan Chrome processes directly inside the
# hook. The user asked to pull that side-effect out: a hook should only inject a
# next-turn prompt (HOOK_DESIGN_RUBRIC §3 "命中: inject prompt … 不直接执行副作用";
# "hook 不替 agent 选"). So the kill moved to the reference script, and the hook is
# now a thin trigger that hands the agent a known-issue + solution pointer.
#
# WHAT IT FIXES (context for the injected note)
# Orphaned headless/automation Chrome (e.g. a Playwright run whose session exited)
# keeps /Applications/Google Chrome.app "running" for LaunchServices, so the daily
# Chrome icon won't open the user's default-profile window — "my Chrome won't open".
#
# TRIGGERS (narrow scope — single anti-pattern, so <100 by design per
# HOOK_DESIGN_RUBRIC §1 "≤100 OK if header states why"). Two ways to fire:
#   (a) STRUCTURAL co-occurrence (the §1 form trigger): a BROWSER token AND a FAILURE
#       token in the same prompt — e.g. "chrome 打不开", "google chrome won't open".
#       Neither alone fires (avoids matching every benign mention of "chrome").
#   (b) An EXPLICIT reap phrase — "reap chrome", "清 chrome 残留", "orphan chrome", etc.
# Categories: 直接报障 / 间接描述(没反应、起不来) / 显式指令(清残留) / EN 同义.
# Fenced AND inline code is stripped before matching so a pasted log containing
# "failed to open" does not false-fire.
#
# Source values: ~/.claude/CLAUDE.md (pair-chrome, "never the wrong Chrome"),
#                ~/.claude/VALUE.md (自决 — surface the solution, let agent act),
#                LEAVES.md (本机健康/不打断).
# rubric: ~/.claude/hooks/HOOK_DESIGN_RUBRIC.md
# audit:  ~/.claude/hooks/logs/reap-orphan-chrome.jsonl
# per-session: ~/.claude/hooks/logs/reap-orphan-chrome-<session>.md (appended on hit)
# solution: ~/.claude/hooks/reap-orphan-chrome.solution.sh  (the script this hook points at)
#
# Escape hatch:
#   CLAUDE_REAP_CHROME_DISABLED=1   skip entirely (inject nothing).

# 2026-06-30 审计发现: 日志从 2026-06-26 起零触发。此非 bug — CLAUDE.md 于 2026-06-26 禁用 pair-chrome，此后无 pair-chrome 会话产生孤儿 Chrome 进程。Hook 检测逻辑正常，无需修改。

set -uo pipefail

[[ "${CLAUDE_REAP_CHROME_DISABLED:-0}" == "1" ]] && exit 0

SOLUTION="$HOME/.claude/hooks/reap-orphan-chrome.solution.sh"

# ── read the UserPromptSubmit payload (JSON on stdin) ───────────────────────────
INPUT=""
if [ ! -t 0 ]; then INPUT="$(cat 2>/dev/null || true)"; fi

extract_field() { # field-name → value (jq if present, else permissive sed)
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$INPUT" | jq -r ".${1} // \"\"" 2>/dev/null || true
  else
    printf '%s' "$INPUT" | sed -n "s/.*\"${1}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" 2>/dev/null || true
  fi
}

PROMPT="$(extract_field prompt)"
SESSION_ID="$(extract_field session_id)"

# ── keyword gate ────────────────────────────────────────────────────────────────
# Lowercase + strip fenced AND inline code so pasted logs / quoted strings don't false-fire.
norm="$(printf '%s' "$PROMPT" | tr 'A-Z' 'a-z' | sed -e 's/```[^`]*```/ /g' -e 's/`[^`]*`/ /g')"

contains() { case "$norm" in *"$1"*) return 0 ;; *) return 1 ;; esac }
contains_any() {
  local t
  for t in "$@"; do contains "$t" && return 0; done
  return 1
}

BROWSER_TOKENS=("chrome" "谷歌浏览器" "谷歌瀏覽器" "google chrome" "浏览器" "瀏覽器")
FAILURE_TOKENS=(
  "打不开" "打不開" "打不开了" "开不了" "開不了" "开不起来" "啟動不了" "启动不了"
  "起不来" "起不來" "没反应" "沒反應" "没反映" "无法打开" "無法打開" "无法启动"
  "弹不出" "彈不出" "点了没反应" "點了沒反應" "闪退" "閃退" "崩了" "卡住打不开"
  "won't open" "wont open" "won't launch" "wont launch" "can't open" "cant open"
  "cannot open" "can not open" "failed to open" "fails to open" "fail to open"
  "not opening" "doesn't open" "does not open" "won't start" "not launching"
  "not responding" "no response" "keeps crashing" "crash on launch" "won't come up"
)
EXPLICIT_TOKENS=(
  "reap chrome" "reap orphan chrome" "kill orphan chrome" "orphan chrome"
  "orphaned chrome" "headless chrome 残留" "headless chrome leftover"
  "chrome 残留" "chrome 殘留" "清理 chrome" "清 chrome" "清掉 chrome"
  "孤儿 chrome" "孤兒 chrome" "/reap-chrome" "reap-orphan-chrome"
)

TRIGGER=""
MATCHED=""
if contains_any "${EXPLICIT_TOKENS[@]}"; then
  TRIGGER="explicit"
  for t in "${EXPLICIT_TOKENS[@]}"; do contains "$t" && MATCHED="$MATCHED${MATCHED:+,}$t"; done
elif contains_any "${BROWSER_TOKENS[@]}" && contains_any "${FAILURE_TOKENS[@]}"; then
  TRIGGER="cooccurrence(browser+failure)"
  for t in "${BROWSER_TOKENS[@]}"; do contains "$t" && MATCHED="$MATCHED${MATCHED:+,}$t"; done
  for t in "${FAILURE_TOKENS[@]}"; do contains "$t" && MATCHED="$MATCHED${MATCHED:+,}$t"; done
fi

# No keyword hit → silent no-op (default behavior on every normal prompt).
[ -z "$TRIGGER" ] && exit 0

# ── audit + per-session note ────────────────────────────────────────────────────
LOG_DIR="$HOME/.claude/hooks/logs"
mkdir -p "$LOG_DIR" 2>/dev/null || true
LOG_FILE="$LOG_DIR/reap-orphan-chrome.jsonl"
SESSION_LOG="$LOG_DIR/reap-orphan-chrome-${SESSION_ID:-nosession}.md"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if command -v jq >/dev/null 2>&1; then
  jq -nc --arg ts "$TS" --arg sid "${SESSION_ID:-}" --arg markers "$MATCHED" --arg detail "$TRIGGER" \
    '{ts:$ts,session_id:$sid,hook:"reap-orphan-chrome",action:"pointer-injected",markers_found:$markers,detail:$detail}' \
    >>"$LOG_FILE" 2>/dev/null || true
else
  printf '{"ts":"%s","hook":"reap-orphan-chrome","action":"pointer-injected","markers_found":"%s","detail":"%s"}\n' \
    "$TS" "$MATCHED" "$TRIGGER" >>"$LOG_FILE" 2>/dev/null || true
fi
printf -- '- %s  trigger=%s  markers=[%s]\n' "$TS" "$TRIGGER" "$MATCHED" >>"$SESSION_LOG" 2>/dev/null || true

# ── inject agent-facing note (UserPromptSubmit stdout → additionalContext) ───────
# User-invisible. Tells the agent there is a known issue + a reference script/solution.
cat <<EOF
[reap-orphan-chrome · agent-only] 用户的消息命中"Chrome 打不开"信号(markers: ${MATCHED:-explicit})。

这是一个已知问题,有现成的 reference script + solution:
  根因:孤儿 headless/Playwright Chrome 霸占 /Applications/Google Chrome.app bundle
        → macOS LaunchServices 认为 Chrome "已在运行",不再为默认 profile 新开窗口
        → 用户的日常 Chrome 打不开。
  参考脚本(诊断 + 外科手术清理,绝不碰日常 GUI / pair-chrome / Chrome for Testing):
        bash $SOLUTION              # 诊断 + 清理孤儿 headless Chrome
        bash $SOLUTION --dry-run    # 只诊断不清理(先看一眼)
        bash $SOLUTION --relaunch   # 清理后用 open -n 拉起默认 profile
  兜底:open -n -a "Google Chrome"  (-n 绕过 LaunchServices 的"已在运行"判定)

建议:先跑 \`bash $SOLUTION\`(或先 --dry-run 看诊断),再据输出向用户汇报清掉了什么。
EOF

exit 0
