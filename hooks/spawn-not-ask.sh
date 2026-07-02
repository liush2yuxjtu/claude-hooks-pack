#!/usr/bin/env bash
# ~/.claude/hooks/spawn-not-ask.sh
# UserPromptSubmit hook. When the user's prompt contains the
# "what-to-do-next / should I / 要不要 / or" meta-questioning pattern,
# inject a standing rule into this turn's context: SPAWN non-blocking
# subagents (run_in_background: true) instead of asking the user for
# permission. The user has max/unlimited tokens — permission seeking
# is wasteful when the path is already obvious.
#
# Trigger keywords (lowercase, substring across the whole payload):
#   - "要不要", "哪个", "要我", "该", "你想", "怎么", "想让我"
#   - "or other", "or just", "which one", "want me to", "should i"
#   - "do you want", "could i", "may i", "shall i", "would you like"
# Fail-open: no stdin / no jq / no match → exit 0.

set -uo pipefail

input="$(cat)"
[[ -z "$input" ]] && exit 0

prompt="$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]')"

matched=""
for kw in "要不要" "哪个" "要我" "该怎么" "你想" "怎么" "想让我" \
           "or other" "or just" "which one" "want me to" "should i" \
           "do you want" "could i" "may i" "shall i" "would you like" \
           "any preference" "pick one" "go ahead" "ok to" "ready to"; do
  if [[ "$prompt" == *"$kw"* ]]; then
    matched="$kw"
    break
  fi
done

[[ -z "$matched" ]] && exit 0

# Inject to stderr. The harness folds stderr from UserPromptSubmit
# hooks into the model's context for the current turn.
printf >&2 '%s\n' \
  "[hook:spawn-not-ask] user prompt matches 'what to do next / should I / 要不要' pattern (keyword: ${matched})." \
  "" \
  "Standing rule for this turn:" \
  "  - You have max / unlimited tokens. Do NOT ask the user 'should I do" \
  "    X or Y or Z?' for low-risk, reversible actions. DISPATCH instead." \
  "  - For parallel work: use Agent(general-purpose, run_in_background: true)" \
  "    with one subagent per independent sub-task. They run in parallel;" \
  "    you get a single notification when each lands." \
  "  - For sequential work: dispatch one subagent, wait for the result," \
  "    decide the next step." \
  "  - For trivial / inline work: just do it. No subagent, no permission ask." \
  "  - ASK only when the choice is irreversible (delete a real file, force" \
  "    push, ship a public deploy, change auth/secrets, etc.) or genuinely" \
  "    taste-driven (naming, copy, 'which color?')." \
  "  - When the user gave you a numbered options list (1, 2, 3), treat" \
  "    option 1 as the recommended default UNLESS the user already" \
  "    pre-selected. Mention which you picked in the report, not as a" \
  "    question." \
  "  - This rule is session-wide. Set by user's 2026-06-13 directive" \
  "    ('we have max and unlimited token, spawn non-blocking subagents" \
  "    instead of asking for permission')." \
  ""

exit 0
