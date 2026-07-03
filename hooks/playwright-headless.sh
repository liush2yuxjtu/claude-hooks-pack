#!/usr/bin/env bash
# ~/.claude/hooks/playwright-headless.sh
# PreToolUse SOFT-GATE (prompt injection). User rule: prefer driving a
# browser HEADLESS (Playwright CLI / Playwright MCP / chrome-devtools MCP /
# playwright-cli skill).
#
# This hook NEVER blocks. Converted 2026-06-26 from hard exit-2 blocks per
# the user's directive "do not use hard-gate, use prompt injection
# soft-gate". On a headed / headless:false / default-headed invocation it
# ALLOWS the call and injects a reminder into the model's context via
# hookSpecificOutput.additionalContext. "hook 不替 agent 选" (VALUE.md /
# HOOK_DESIGN_RUBRIC §3). The agent is trusted to switch to headless.
#
# Triggers (the hook runs for whatever tools its settings.json matcher
# selects — currently Bash|Skill; the MCP branches are kept so the same
# file still works if the matcher is widened):
#   Bash         — playwright / chrome CLI with --headed, --no-headless,
#                  --headless=false, or a default-headed subcommand
#                  (codegen / debug / open / ui / install) sans --headless.
#   Skill        — playwright, playwright-cli.
#   mcp__plugin_playwright_playwright__*               — Playwright MCP.
#   mcp__plugin_chrome-devtools-mcp_chrome-devtools__* — chrome-devtools MCP.
#
# Outcome: ALWAYS exit 0. On a hit, stdout carries one JSON line
#   {hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:…}}.
#   No hit → silent pass-through.
#
# Escape hatch:
#   CLAUDE_HEADLESS_OVERRIDE=1   inject nothing this turn (used by
#     /tidy-chrome / worktree-qa when a visible browser is the explicit
#     intent of the user).
#
# rubric: ~/.claude/hooks/HOOK_DESIGN_RUBRIC.md
# audit:  ~/.claude/hooks/logs/playwright-headless.jsonl

set -uo pipefail

if [[ "${CLAUDE_HEADLESS_OVERRIDE:-0}" == "1" ]]; then
  exit 0
fi

command -v jq >/dev/null 2>&1 || exit 0

input=$(cat)
[[ -z "$input" ]] && exit 0

tool=$(jq -r '.tool_name // ""' <<<"$input" 2>/dev/null || echo "")
[[ -z "$tool" ]] && exit 0

LOG_DIR="$HOME/.claude/hooks/logs"
mkdir -p "$LOG_DIR" 2>/dev/null || true
LOG_FILE="$LOG_DIR/playwright-headless.jsonl"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

audit() { # reason payload
  jq -nc \
    --arg ts "$ts" --arg tool "$tool" \
    --arg verdict "soft-nudge" --arg reason "$1" --arg payload "${2:-}" \
    '{ts:$ts,tool:$tool,verdict:$verdict,reason:$reason,payload_snippet:$payload}' \
    >>"$LOG_FILE" 2>/dev/null || true
}

# inject <reason> <payload> <nudge-text> — emit additionalContext, allow, exit.
inject() {
  audit "$1" "$2"
  jq -nc --arg ctx "$3" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$ctx}}'
  exit 0
}

case "$tool" in
Bash)
  cmd=$(jq -r '.tool_input.command // ""' <<<"$input" 2>/dev/null || echo "")
  [[ -z "$cmd" ]] && exit 0

  # Cheap gate: only react when a browser CLI is plausibly involved.
  if ! grep -qE '(^|[[:space:]]|/)(pnpm[[:space:]]+exec[[:space:]]+playwright|npx[[:space:]]+playwright|playwright|chromium|google-chrome|chrome)([[:space:]]|$)' <<<"$cmd"; then
    exit 0
  fi

  if grep -qE '(^|[[:space:]])--headed([[:space:]]|$)' <<<"$cmd"; then
    inject "explicit --headed flag" "$cmd" \
      "[playwright-headless soft-gate · NOT a block] This command passes --headed → a VISIBLE browser window. User rule: prefer HEADLESS. Drop --headed or pass --headless=new (or --headless=old). The call will proceed; switch to headless unless the user explicitly asked for a visible window this turn. (CLAUDE_HEADLESS_OVERRIDE=1 silences this.)"
  fi

  if grep -qE -- '--headless[= ]false|--no-headless' <<<"$cmd"; then
    inject "explicit headless=false" "$cmd" \
      "[playwright-headless soft-gate · NOT a block] This command opts OUT of headless (--no-headless / --headless=false). User rule: prefer HEADLESS. Change it to --headless=new. Proceeding anyway — please correct unless a visible browser was explicitly requested."
  fi

  if grep -qE '(playwright|chromium|google-chrome|chrome)[[:space:]]+(codegen|debug|open|ui|install)([[:space:]]|$)' <<<"$cmd" &&
    ! grep -qE -- '--headless' <<<"$cmd"; then
    inject "default-headed subcommand without --headless" "$cmd" \
      "[playwright-headless soft-gate · NOT a block] This Playwright/Chromium subcommand defaults to a VISIBLE window and no --headless was given. User rule: prefer HEADLESS — append --headless=new (e.g. pnpm exec playwright codegen --browser=chromium --headless=new). Proceeding; add the flag unless a visible browser was explicitly asked for."
  fi

  exit 0
  ;;

Skill)
  skill=$(jq -r '.tool_input.skill // .tool_input.name // ""' <<<"$input" 2>/dev/null || echo "")
  case "$skill" in
  playwright-cli | playwright)
    inject "playwright-cli skill invoked" "$skill" \
      "[playwright-headless soft-gate · NOT a block] Invoking '$skill'. The Playwright MCP it wraps defaults to HEADLESS — keep it that way: do NOT pass --headed / headless:false. pair-chrome (visible Chrome) is disabled. Only surface a visible browser if the user explicitly asked this turn."
    ;;
  esac
  exit 0
  ;;

mcp__plugin_playwright_playwright__* | mcp__plugin_chrome-devtools-mcp_chrome-devtools__*)
  payload=$(jq -c '.tool_input // {}' <<<"$input" 2>/dev/null || echo "")
  if grep -qE '"headless"[[:space:]]*:[[:space:]]*false|"headed"[[:space:]]*:[[:space:]]*true' <<<"$payload"; then
    inject "MCP payload headless:false" "$payload" \
      "[playwright-headless soft-gate · NOT a block] This MCP browser payload sets headless:false / headed:true → a VISIBLE browser. User rule: prefer HEADLESS. Drop that key (prefer the headless /playwright-cli skill). Proceeding; correct it unless a visible browser was explicitly requested."
  fi
  inject "MCP browser tool invoked" "$payload" \
    "[playwright-headless soft-gate · NOT a block] MCP browser tool invoked — confirm it runs HEADLESS (chrome-devtools MCP can pop a visible window). User rule: prefer HEADLESS / the /playwright-cli skill. (CLAUDE_HEADLESS_OVERRIDE=1 silences this.)"
  ;;

*)
  exit 0
  ;;
esac
