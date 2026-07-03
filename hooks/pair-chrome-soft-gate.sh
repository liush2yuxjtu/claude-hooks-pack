#!/usr/bin/env bash
# ~/.claude/hooks/pair-chrome-soft-gate.sh
# This NEVER blocks. It is a SOFT prompt-injection nudge.
# (Renamed 2026-06-26 from block-pair-chrome.sh once it stopped blocking.)
#
# UserPromptSubmit SOFT-GATE (prompt injection, keyword-triggered).
# User rule (2026-06-26): prefer driving the browser HEADLESS via the
# /playwright-cli skill over /pair-chrome (or any visible/headed browser).
#
# History:
#   v1 — PreToolUse hard block (exit 2) on the pair-chrome tool call.
#   v2 — user: "do not use hard-gate, use prompt injection soft-gate" →
#        PreToolUse soft inject.
#   v3 (this) — user: "trigger by many many key words" → moved to
#        UserPromptSubmit with a LARGE multilingual keyword bank, modeled
#        on the house pattern reap-orphan-chrome.sh. On a keyword hit it
#        injects an agent-only reminder (stdout → additionalContext) and
#        ALWAYS exits 0. "hook 不替 agent 选" (VALUE.md / RUBRIC §3).
#
# WHAT IT DOES
#   When the user's prompt signals "I want to look at / play with / test a
#   browser URL", or names pair-chrome / a visible (headed) browser, it
#   reminds the agent: use the HEADLESS /playwright-cli skill; do NOT pop a
#   visible Chrome / run pair-chrome unless the user explicitly asked.
#
# TRIGGERS (rubric §1: ≥100 tokens, ZH+EN, ≥4 categories, structural co-occurrence)
#   (a) EXPLICIT — fire alone (specific enough to mean visible-browser / human e2e):
#       pair-chrome, pop open, 弹开, --headed, UAT, demo it, let me play,
#       让我玩, 试试, 点点看, 走一遍, playtest, click around, …
#   (b) CO-OCCURRENCE — a BROWSER token AND an INTENT token in the same
#       prompt (browser/浏览器/chrome/页面/localhost/url × 看看/open/test/截图/run/…).
#       Neither alone fires → avoids nagging every benign "看看" / "demo".
#   Negative filter: fenced + inline code stripped; SUPPRESSED entirely when
#   the prompt already says "headless" or "playwright-cli" (user is aligned).
#
# Outcome: ALWAYS exit 0. Hit → stdout JSON additionalContext nudge. Miss → silent.
# Escape hatch: CLAUDE_PAIR_CHROME_OVERRIDE=1 → inject nothing.
#
# rubric: ~/.claude/hooks/HOOK_DESIGN_RUBRIC.md
# audit:  ~/.claude/hooks/logs/pair-chrome-soft-gate.jsonl
# per-session: ~/.claude/hooks/logs/pair-chrome-soft-gate-<session>.md

set -uo pipefail

[[ "${CLAUDE_PAIR_CHROME_OVERRIDE:-0}" == "1" ]] && exit 0

# ── read UserPromptSubmit payload (JSON on stdin) ───────────────────────────────
INPUT=""
[ -t 0 ] || INPUT="$(cat 2>/dev/null || true)"
[ -z "$INPUT" ] && exit 0

extract_field() { # field → value (jq if present, else permissive sed)
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$INPUT" | jq -r ".${1} // \"\"" 2>/dev/null || true
  else
    printf '%s' "$INPUT" | sed -n "s/.*\"${1}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" 2>/dev/null || true
  fi
}

PROMPT="$(extract_field prompt)"
SESSION_ID="$(extract_field session_id)"
[ -z "$PROMPT" ] && exit 0

# Lowercase + strip fenced AND inline code so pasted logs / commands don't false-fire.
norm="$(printf '%s' "$PROMPT" | tr 'A-Z' 'a-z' | sed -e 's/```[^`]*```/ /g' -e 's/`[^`]*`/ /g')"

contains() { case "$norm" in *"$1"*) return 0 ;; *) return 1 ;; esac }
contains_any() {
  local t
  for t in "$@"; do contains "$t" && return 0; done
  return 1
}

# ── Negative filter: already-aligned prompts get no nudge ───────────────────────
if contains_any "headless" "playwright-cli" "playwright_cli" "无头" "无头模式"; then
  exit 0
fi

# ── (a) EXPLICIT tokens — fire alone ────────────────────────────────────────────
EXPLICIT_TOKENS=(
  # pair-chrome / visible-browser, ZH
  "pair-chrome" "pair chrome" "弹开" "弹开看看" "弹窗" "弹出浏览器" "弹个浏览器"
  "弹到我面前" "弹到前面" "弹一个看看" "打开 chrome" "打开chrome" "开个 chrome"
  "开 chrome" "在 chrome 里打开" "在chrome打开" "chrome 打开" "可见浏览器"
  "有头浏览器" "有头模式" "关掉无头" "真浏览器" "真实浏览器" "用真浏览器"
  # human e2e / "let me play|look|test", ZH
  "让我玩" "让我玩玩" "我玩玩" "玩一下" "玩玩看" "试玩" "试用一下" "让我试"
  "让我试试" "我试试" "我点点" "点点看" "点一下看看" "我点一下" "走一遍"
  "走查" "人肉测试" "人肉测" "手动测" "手测" "手动点" "亲自测" "自己点一下"
  "演示一下" "演示给我" "跑给我看" "给我看看效果" "看看效果" "uat 一下"
  "uat一下" "做个 demo" "做个demo" "demo 给我" "demo一下" "弹开浏览器"
  # pair-chrome / visible-browser, EN
  "paired chrome" "pop open" "pop-open" "popopen" "open in chrome"
  "open chrome window" "launch chrome" "launch a chrome" "visible browser"
  "headed browser" "headed mode" "--headed" "real browser" "actual browser"
  "show me the browser" "open a real browser" "open the browser window"
  # human e2e / "let me play|look|test", EN
  "let me play" "let me play with" "can i play" "can i try" "let me try it"
  "let me try" "i want to test" "i wanna test" "let me click"
  "let me click around" "click around" "playtest" "play with it"
  "play with the app" "uat" "demo it" "demo this" "show me the page"
  "let me see it" "let me look at it" "see it in the browser"
  "in a real browser" "open it in the browser" "human test" "manual test"
  "manually test" "eyeball it" "click through" "click-through"
  "test it myself" "try it myself" "let me poke at it" "poke around"
)

# ── (b) CO-OCCURRENCE — broad tokens, need BROWSER ∧ INTENT ──────────────────────
BROWSER_TOKENS=(
  "chrome" "浏览器" "browser" "页面" "page" "前端" "frontend" "网页"
  "localhost" "127.0.0.1" " url " "网址" "链接" "the app" "应用" "webapp"
  "web app" "站点" "site" "界面"
)
INTENT_TOKENS=(
  "看看" "看一下" "看下" "看一看" "瞧瞧" "see " "look" " view" "open " "打开"
  "跑一下" "跑起来" "run " "test" "测试" "测一下" "截图" "screenshot"
  "snapshot" "navigate" "click" "点一下" "操作" "interact" "driving"
  "drive " "automate" "自动化" "渲染" "render"
)

TRIGGER=""
MATCHED=""
if contains_any "${EXPLICIT_TOKENS[@]}"; then
  TRIGGER="explicit"
  for t in "${EXPLICIT_TOKENS[@]}"; do contains "$t" && MATCHED="$MATCHED${MATCHED:+,}$t"; done
elif contains_any "${BROWSER_TOKENS[@]}" && contains_any "${INTENT_TOKENS[@]}"; then
  TRIGGER="cooccurrence(browser+intent)"
  for t in "${BROWSER_TOKENS[@]}"; do contains "$t" && MATCHED="$MATCHED${MATCHED:+,}$t"; done
  for t in "${INTENT_TOKENS[@]}"; do contains "$t" && MATCHED="$MATCHED${MATCHED:+,}$t"; done
fi

# No keyword hit → silent no-op.
[ -z "$TRIGGER" ] && exit 0

# ── audit + per-session note ────────────────────────────────────────────────────
LOG_DIR="$HOME/.claude/hooks/logs"
mkdir -p "$LOG_DIR" 2>/dev/null || true
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if command -v jq >/dev/null 2>&1; then
  jq -nc --arg ts "$TS" --arg sid "${SESSION_ID:-}" --arg markers "$MATCHED" --arg detail "$TRIGGER" \
    '{ts:$ts,session_id:$sid,hook:"pair-chrome-soft-gate",action:"soft-nudge-injected",markers_found:$markers,detail:$detail}' \
    >>"$LOG_DIR/pair-chrome-soft-gate.jsonl" 2>/dev/null || true
fi
printf -- '- %s  trigger=%s  markers=[%s]\n' "$TS" "$TRIGGER" "$MATCHED" \
  >>"$LOG_DIR/pair-chrome-soft-gate-${SESSION_ID:-nosession}.md" 2>/dev/null || true

# ── inject agent-only nudge (UserPromptSubmit stdout → additionalContext) ────────
cat <<EOF
[pair-chrome soft-gate · agent-only · NOT a block] The user's message signals browser / visible-Chrome / UAT / e2e intent (trigger: ${TRIGGER}; markers: ${MATCHED}).

REMEMBER (user rule 2026-06-26): drive the browser HEADLESS via the /playwright-cli skill — no visible window, no Space routing, no terminal-notifier banner:
    playwright-cli open <url> | goto <url> | snapshot | click <ref> | fill <ref> "<val>" | screenshot | close

Do NOT run /pair-chrome or pop a visible/headed Chrome unless the user explicitly asked for the paired/visible browser THIS turn. This is a soft reminder, not a block — you decide. (Silence it with CLAUDE_PAIR_CHROME_OVERRIDE=1.)
EOF

exit 0
