#!/usr/bin/env bash
# ~/.claude/hooks/reap-orphan-chrome.solution.sh
#
# REFERENCE SOLUTION (run by the agent, NOT a hook) for the recurring symptom:
#   "my normal / daily Chrome won't open".
#
# ROOT CAUSE (diagnosed 2026-06-25)
# Orphaned headless/automation Chrome instances spawned from the user's MAIN
# /Applications/Google Chrome.app bundle (typically a Playwright / playwright-cli run
# whose controlling session exited) keep that bundle "running" as far as macOS
# LaunchServices is concerned. Double-clicking the daily Chrome icon (or
# `open -a "Google Chrome"`) then just re-activates the leftover instead of opening
# the user's default-profile window — i.e. "Chrome won't open".
#
# This script is what `reap-orphan-chrome.sh` (the UserPromptSubmit hook) POINTS the
# agent at. The hook never kills anything itself; it injects an agent-visible note
# saying "known issue, reference script + solution here — go run it". The agent then
# runs THIS, reads the report, and tells the user what happened.
#
# WHAT IT DOES
#   1. Diagnose: classify every main-bundle Chrome process
#        daily-gui / pair-chrome / for-testing / headless-orphan(reapable) / headless-live(skip)
#   2. Reap: surgically kill ONLY headless-orphan ones (see SAFETY).
#   3. (--relaunch) If no default-profile Chrome is running, relaunch it with
#        `open -n -a "Google Chrome" --args --profile-directory=Default`
#        (-n bypasses the LaunchServices "already running" short-circuit).
#
# USAGE
#   bash ~/.claude/hooks/reap-orphan-chrome.solution.sh            # diagnose + reap
#   bash ~/.claude/hooks/reap-orphan-chrome.solution.sh --dry-run  # diagnose only, never kill
#   bash ~/.claude/hooks/reap-orphan-chrome.solution.sh --relaunch # reap, then open -n default profile
#   flags: --diagnose-only (alias --dry-run) | --aggressive (drop age gate) | --age <secs>
#
# SAFETY — surgical. Reaps ONLY a process that is ALL of:
#   1. the MAIN daily Chrome binary  (/Applications/Google Chrome.app/Contents/MacOS/Google Chrome)
#   2. running with --headless        (so NEVER a visible window / the daily browser)
#   3. abandoned, by one of:
#        (A) orphaned directly to launchd (PPID == 1) — CDP driver gone → always safe; or
#        (B) parent is an orphaned (PPID == 1) playwright/node controller AND Chrome alive
#            ≥ AGE seconds (default 1800) — a session-detached leftover.
# NEVER touches: daily GUI Chrome (no --headless); pair-chrome (.claude/chrome-profiles);
# "Google Chrome for Testing" (other bundle); automation still under a live session.
#
# Source values: ~/.claude/CLAUDE.md (pair-chrome, "never the wrong Chrome"),
#                ~/.claude/VALUE.md (自决), LEAVES.md (本机健康/不打断).
# audit: ~/.claude/hooks/logs/reap-orphan-chrome.jsonl  (hook field: reap-orphan-chrome-solution)
#
# Escape hatch: CLAUDE_REAP_CHROME_DISABLED=1 → refuse to reap (diagnose only).

set -uo pipefail

DRYRUN=0
RELAUNCH=0
AGGRESSIVE="${CLAUDE_REAP_CHROME_AGGRESSIVE:-0}"
AGE="${CLAUDE_REAP_CHROME_AGE:-1800}"
[[ "${CLAUDE_REAP_CHROME_DISABLED:-0}" == "1" ]] && DRYRUN=1
while [ $# -gt 0 ]; do
  case "$1" in
  --dry-run | --diagnose-only) DRYRUN=1 ;;
  --relaunch) RELAUNCH=1 ;;
  --aggressive) AGGRESSIVE=1 ;;
  --age)
    shift
    AGE="${1:-1800}"
    ;;
  *) echo "unknown flag: $1" >&2 ;;
  esac
  shift
done

CHROME_MAIN="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
LOG_DIR="$HOME/.claude/hooks/logs"
mkdir -p "$LOG_DIR" 2>/dev/null || true
LOG_FILE="$LOG_DIR/reap-orphan-chrome.jsonl"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

audit() { # action pid detail
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg ts "$TS" --arg action "$1" --arg pid "${2:-}" --arg detail "${3:-}" \
      '{ts:$ts,hook:"reap-orphan-chrome-solution",action:$action,pid:$pid,detail:$detail}' >>"$LOG_FILE" 2>/dev/null || true
  else
    printf '{"ts":"%s","hook":"reap-orphan-chrome-solution","action":"%s","pid":"%s","detail":"%s"}\n' \
      "$TS" "$1" "${2:-}" "${3:-}" >>"$LOG_FILE" 2>/dev/null || true
  fi
}
ppid_of() { ps -p "$1" -o ppid= 2>/dev/null | tr -d ' '; }
cmd_of() { ps -p "$1" -o command= 2>/dev/null; }
etime_secs() {
  local e
  e="$(ps -p "$1" -o etime= 2>/dev/null | tr -d ' ')"
  [ -z "$e" ] && {
    echo 0
    return
  }
  local days=0 hms="$e"
  case "$e" in *-*)
    days="${e%%-*}"
    hms="${e#*-}"
    ;;
  esac
  local IFS=:
  set -- $hms
  local h=0 m=0 s=0
  case $# in 3)
    h=$1
    m=$2
    s=$3
    ;;
  2)
    m=$1
    s=$2
    ;;
  1) s=$1 ;; esac
  echo $((10#${days:-0} * 86400 + 10#${h:-0} * 3600 + 10#${m:-0} * 60 + 10#${s:-0}))
}

echo "════════════════════════════════════════════════════════════════"
echo " Chrome-won't-open  诊断 + 修复  (reap-orphan-chrome.solution.sh)"
echo " mode: $([ "$DRYRUN" = 1 ] && echo DIAGNOSE-ONLY || echo REAP)$([ "$RELAUNCH" = 1 ] && echo " +RELAUNCH")  age-gate=${AGE}s aggressive=${AGGRESSIVE}"
echo "════════════════════════════════════════════════════════════════"
echo ""
printf "%-8s %-8s %-26s %s\n" "PID" "PPID" "类别" "命令(截断)"
printf "%-8s %-8s %-26s %s\n" "----" "----" "----" "----"

reapable=()
while IFS= read -r pid; do
  [ -z "$pid" ] && continue
  cmd="$(cmd_of "$pid")"
  [ -z "$cmd" ] && continue
  case "$cmd" in *"$CHROME_MAIN"*) ;; *) continue ;; esac
  pp="$(ppid_of "$pid")"
  short="$(printf '%s' "$cmd" | sed "s#$CHROME_MAIN#Chrome#" | cut -c1-58)"
  klass=""
  reason=""
  if printf '%s' "$cmd" | grep -q "Google Chrome for Testing"; then
    klass="for-testing(跳过)"
  elif printf '%s' "$cmd" | grep -q ".claude/chrome-profiles"; then
    klass="pair-chrome(保护)"
  elif ! printf '%s' "$cmd" | grep -q -- "--headless"; then
    klass="daily-gui(保护)"
  else
    # headless — orphan?
    if [ "$pp" = "1" ]; then
      klass="headless-orphan✗"
      reason="orphaned-to-launchd"
    else
      gpp="$(ppid_of "$pp")"
      pcmd="$(cmd_of "$pp" || true)"
      if [ "$gpp" = "1" ] && printf '%s' "$pcmd" | grep -qiE 'playwright|node'; then
        age="$(etime_secs "$pid")"
        if [ "$AGGRESSIVE" = 1 ] || [ "$age" -ge "$AGE" ]; then
          klass="headless-orphan✗"
          reason="orphaned-playwright-ctrl(${age}s)"
        else klass="headless-live(跳过 ${age}s<${AGE})"; fi
      else klass="headless-live(跳过)"; fi
    fi
  fi
  printf "%-8s %-8s %-26s %s\n" "$pid" "$pp" "$klass" "$short"
  [ -n "$reason" ] && reapable+=("$pid|$reason")
done < <(pgrep -f "$CHROME_MAIN" 2>/dev/null || true)

echo ""
reaped=0
if [ "${#reapable[@]}" -eq 0 ]; then
  echo "→ 没有发现可清理的孤儿 headless Chrome。"
  audit "diagnose" "" "no reapable orphan found"
else
  echo "→ 发现 ${#reapable[@]} 个孤儿 headless Chrome:"
  for entry in "${reapable[@]}"; do
    pid="${entry%%|*}"
    reason="${entry#*|}"
    if [ "$DRYRUN" = 1 ]; then
      echo "   [dry-run] 将清理 PID $pid ($reason)"
      audit "would-reap" "$pid" "$reason"
    else
      if kill "$pid" 2>/dev/null; then
        echo "   ✓ 已清理 PID $pid ($reason)"
        reaped=$((reaped + 1))
        audit "reaped-chrome" "$pid" "$reason"
      else
        echo "   ✗ kill 失败 PID $pid"
        audit "kill-failed" "$pid" "$reason"
      fi
    fi
  done
  [ "$reaped" -gt 0 ] && audit "summary" "" "reaped $reaped"
fi

# Relaunch default-profile Chrome if asked and none is currently running.
if [ "$RELAUNCH" = 1 ] && [ "$DRYRUN" = 0 ]; then
  echo ""
  has_default=0
  while IFS= read -r pid; do
    cmd="$(cmd_of "$pid")"
    case "$cmd" in *"$CHROME_MAIN"*) ;; *) continue ;; esac
    printf '%s' "$cmd" | grep -q -- "--headless" && continue
    printf '%s' "$cmd" | grep -q ".claude/chrome-profiles" && continue
    printf '%s' "$cmd" | grep -q "Google Chrome for Testing" && continue
    has_default=1
  done < <(pgrep -f "$CHROME_MAIN" 2>/dev/null || true)
  if [ "$has_default" = 1 ]; then
    echo "→ 日常 GUI Chrome 已在运行,无需重启。"
  else
    echo "→ 没有日常 Chrome 在跑,用 open -n 拉起默认 profile..."
    open -n -a "Google Chrome" --args --profile-directory=Default 2>&1 && echo "   ✓ open -n 已发出" && audit "relaunch" "" "open -n default profile"
  fi
fi

echo ""
echo "提示:若仍打不开,手动执行  open -n -a \"Google Chrome\"  (-n 绕过 LaunchServices 的\"已在运行\"判定)。"
exit 0
