#!/usr/bin/env bash
# ~/.claude/hooks/no-ask-file-followups.sh
#
# Stop hook — kills the "要我把残留的红开成 follow-up issue 吗?" ask.
#
# Problem it fixes: at the end of a long run the agent keeps ENDING its turn
# on a question like "要我把 E1/E5/E6 残留开成 follow-up issue 吗?" /
# "shall I file these as follow-up issues?". Filing a follow-up issue is a
# cheap, reversible, file-only action (the project tracks issues as markdown
# under .agent/issues/ via /to-issues + /office-issues). Asking wastes a whole
# turn + a cache window on a decision the user has repeatedly said is the
# agent's to make. (Same family as spawn-not-ask.sh / research-md-no-ask.sh
# and the VALUE.md L3 "default = ship + evidence, not ask" rule.)
#
# Behavior: when the agent's LAST assistant message both (a) asks a question
# and (b) is about filing follow-up issues / tracking residual reds/gaps, this
# hook BLOCKS the stop and feeds back an instruction: file the issues NOW, then
# report the paths — do not ask. On the bounced turn the agent files them and
# stops cleanly (the ask is gone, so this hook no longer matches).
#
# Loop-safety: if `stop_hook_active` is true (we already bounced once) OR a
# per-session breaker file exists, allow the stop. The breaker is cleared on
# any stop that does NOT match, so the next genuine occurrence is caught.
#
# Fail-open: no stdin / no jq / no transcript / unreadable transcript → exit 0
# (never wedge a session). Toggle off for one run with
# CLAUDE_NO_ASK_FOLLOWUPS_DISABLED=1.

set -uo pipefail

[[ "${CLAUDE_NO_ASK_FOLLOWUPS_DISABLED:-0}" == "1" ]] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)"
[[ -z "$input" ]] && exit 0

stop_active="$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)"
session_id="$(printf '%s' "$input" | jq -r '.session_id // "unknown"' 2>/dev/null)"
transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)"

LOG_DIR="$HOME/.claude/hooks/logs"
mkdir -p "$LOG_DIR" 2>/dev/null || true
breaker="$LOG_DIR/no-ask-followups-${session_id}.brk"

# Already bounced this stop → let it through and reset the breaker.
if [[ "$stop_active" == "true" ]]; then
  rm -f "$breaker" 2>/dev/null || true
  exit 0
fi

[[ -n "$transcript" && -r "$transcript" ]] || exit 0

# Pull the text of the LAST assistant message from the JSONL transcript.
last_assistant="$(jq -rs '
  [ .[]
    | select(.type? == "assistant" or .role? == "assistant" or .message.role? == "assistant")
  ] | last
  | (.message.content // .content // "")
  | if type == "array" then
      [ .[] | (.text // "") ] | join("\n")
    else tostring end
' "$transcript" 2>/dev/null)"

[[ -z "$last_assistant" ]] && exit 0

low="$(printf '%s' "$last_assistant" | tr '[:upper:]' '[:lower:]')"

# (a) Is it a question? (CJK or ASCII question marker, or an explicit ask verb.)
has_question=0
case "$low" in
  *"?"*|*"？"*|*"吗"*|*"要不要"*|*"要我"*|*"需要我"*|*"shall i"*|*"should i"*|*"want me to"*|*"do you want"*|*"would you like"*)
    has_question=1 ;;
esac
[[ "$has_question" -eq 0 ]] && { rm -f "$breaker" 2>/dev/null || true; exit 0; }

# (b) Is it about filing / tracking follow-up issues for residual work?
about_followup=0
for kw in "follow-up issue" "follow up issue" "followup issue" "follow-up" \
          "开成 follow" "开成follow" "开成 issue" "开 issue" "开个 issue" "建个 issue" \
          "开成工单" "开工单" "建工单" "残留" "遗留" "未尽" "track it as" "file ... issue" \
          "file them as" "file as issue" "file follow" "raise an issue" "open an issue" \
          "open issues" "开 follow" "做成 issue" "记成 issue" "single issue" "follow-up ticket"; do
  if [[ "$low" == *"$kw"* ]]; then about_followup=1; break; fi
done

# Tighten: also accept the very common "把...红/gap/E1...开成...issue" shape.
if [[ "$about_followup" -eq 0 ]]; then
  case "$low" in
    *"issue"*|*"工单"*|*"ticket"*)
      case "$low" in
        *"残留"*|*"遗留"*|*" red"*|*"reds"*|*"the red"*|*" gap"*|*"gaps"*|*" e1"*|*" e5"*|*" e6"*|*"follow"*)
          about_followup=1 ;;
      esac ;;
  esac
fi

if [[ "$about_followup" -eq 0 ]]; then
  rm -f "$breaker" 2>/dev/null || true
  exit 0
fi

# Matched: an ask about filing follow-up issues. Block once and redirect.
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '%s\n' "{\"ts\":\"$ts\",\"session\":\"$session_id\",\"action\":\"block-and-file\"}" \
  >> "$LOG_DIR/no-ask-file-followups.jsonl" 2>/dev/null || true
: > "$breaker" 2>/dev/null || true

reason='[hook:no-ask-file-followups] Your turn ended on a question about whether to file follow-up issues for residual reds/gaps. Do NOT ask — filing a follow-up issue is cheap, reversible, and file-only. File them NOW, then stop.

Do this on the bounced turn:
  1. Locate the issue tracker. This project tracks issues as markdown under .agent/issues/ (the /to-issues + /office-issues convention). Find the active issues dir (search for INDEX.md under **/.agent/issues/). If none exists, create .agent/issues/.
  2. For EACH residual item you were about to ask about (e.g. the E1/E5/E6 reds, U1/U2 API-client gaps, harness-blocked login/setup form states — pull the exact list from your own last message and the audit/QUALITY_GATES artifacts), write one issue file: NN-<slug>.md with YAML frontmatter (id, title, type, blocked_by: [], triage: ready-for-agent) + a body containing: what is broken, the owning area, reproduction/evidence path, and explicit removal/exit criteria. Reuse the owner + exit-criteria already written in QUALITY_GATES.md §5 / COVERAGE_AUDIT.md — do not re-derive.
  3. Append each new issue to the dir INDEX.md.
  4. Report the created file paths in one line. Do NOT ask the user anything about scope or whether to proceed — just file and report.

Exceptions that are still genuinely the user'"'"'s call (do NOT auto-do these, and you MAY mention them as a one-liner, not a question): git push, opening an MR, force-push, rm -rf, rotating secrets. Filing local issue markdown is NOT one of these.'

jq -nc --arg r "$reason" '{decision:"block", reason:$r}'
exit 0
