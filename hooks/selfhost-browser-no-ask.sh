#!/usr/bin/env bash
# ~/.claude/hooks/selfhost-browser-no-ask.sh
# UserPromptSubmit hook. When the user's prompt is about self-hosting a
# branch, popping the app open in a browser, doing browser e2e/verification,
# or connecting to the company intranet, inject a standing decision tree so
# the assistant JUST DOES THE JOB with the correct browser mode instead of
# asking "headless or headed?", "which Chrome?", "should I open it?".
#
# Why this hook exists (2026-06-24): in a self-host session the assistant
# popped a *visible* pair-chrome window during its own verification; the user
# had to interrupt with "必须要 headless chrome", then later "pop open in my
# chrome (not pair chrome)". The right behavior was inferable from intent
# (agent self-verify -> headless; human wants to play -> visible) and never
# needed a question. This hook encodes that so it never has to be re-taught.
# Pairs with: ~/.claude/hooks/playwright-headless.sh (tool-level enforcement),
# memory prefer-headless-chrome-for-agent-verification.
#
# Trigger keywords (substring, case-insensitive, across whole prompt):
#   self-host / 自托管 / 托管 / host this / host it / self host / 跑给我 / 让我玩
#   pop open / 弹开 / 弹出 / pair chrome / headless / my chrome / 我的 chrome
#   daily chrome / let me play / let me try / playtest / smoke test / e2e
#   connect-company / connect company / 内网 / intranet
# Fail-open: no stdin / no match -> exit 0.

set -uo pipefail

input="$(cat)"
[[ -z "$input" ]] && exit 0

prompt="$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]')"

matched=""
for kw in \
  "self-host" "self host" "selfhost" "自托管" "托管" "host this" "host it" \
  "跑给我" "让我玩" "让我试" "let me play" "let me try" "playtest" \
  "pop open" "pop it open" "弹开" "弹出" "弹给我" \
  "pair chrome" "pair-chrome" "headless" "my chrome" "我的 chrome" "我的chrome" \
  "daily chrome" "not pair" "smoke test" "e2e" "端到端" \
  "connect-company" "connect company" "连内网" "内网" "intranet"; do
  if [[ "$prompt" == *"$kw"* ]]; then
    matched="$kw"
    break
  fi
done

[[ -z "$matched" ]] && exit 0

# Stderr from a UserPromptSubmit hook is folded into this turn's context.
printf >&2 '%s\n' \
  "[hook:selfhost-browser-no-ask] prompt matches a self-host / browser / intranet job (keyword: ${matched})." \
  "" \
  "Standing rules for THIS turn — do the job, do NOT ask which mode:" \
  "" \
  "SELF-HOST a branch:" \
  "  - Just do it. Read the win-brain-self-host-bad-patterns skill (this repo)" \
  "    or /worktree-self-host first; pick FREE ports (never reuse the user's" \
  "    running 8001/2026/8201); NEVER 'make dev' (it kills their instances)." \
  "  - Isolate in a worktree off the current branch; install deps; build prod;" \
  "    bring up gateway+frontend; do not ask permission for any of this." \
  "" \
  "BROWSER mode — INFER, never ask 'headless or headed / which chrome':" \
  "  - The AGENT's own verification (smoke test, e2e, 'say hi', screenshot" \
  "    evidence) => HEADLESS. Use 'playwright-cli open <url>' WITHOUT --headed;" \
  "    do NOT pop a visible window; save a screenshot as the evidence artifact." \
  "  - User explicitly says 'my chrome' / '我的 chrome' / 'daily chrome' =>" \
  "    open in their real daily browser: open -a \"Google Chrome\" <url>" \
  "    (NOT pair-chrome, NOT -na)." \
  "  - User says 'pop open' / 'let me play' / '弹开' and did NOT say 'not pair'" \
  "    => pair-chrome pop-open <url> (isolated paired profile)." \
  "  - User says 'not pair chrome' => never pair-chrome; use daily Chrome if" \
  "    they want to see it, else headless." \
  "  - NEVER auto-pop a visible window during pure agent verification." \
  "" \
  "CONNECT-COMPANY intranet:" \
  "  - Just run: bash ~/.claude/skills/connect-company/scripts/connect.sh up" \
  "    (idempotent). probe http:401/200/403 = reachable. localhost bypasses the" \
  "    proxy, so a self-hosted app on localhost loads regardless." \
  "" \
  "Report the mode you chose and the evidence path; do not ask first." \
  "  (set by 2026-06-24 directive: 'direct this type of job instead of asking')." \
  ""

exit 0
