#!/usr/bin/env bash
# ~/.claude/hooks/4-fast-rule.sh
# Stop hook — enforce the user's standing 4-FAST rule (2026-06-13)
# whenever any user/agent prompt in the recent transcript asked a
# "problem" that the assistant never answered with the 4-FAST lens.
#
# 4-FAST rules (the assistant MUST bias answers toward these):
#   1. FAST product generation iteration  (within 1 day)
#   2. FAST ship                           (2 hours)
#   3. FAST dev                            (no HITL, 2 mins)
#   4. FAST feedback from toB client / toC users
#
# Behavior matrix:
#   any recent user/agent prompt looks like a "problem"
#     AND no assistant response in the same span applies the rule
#                                            ->  block, emit reminder
#   otherwise                                ->  silent approve
#
# Heuristic for "problem":  the prompt contains a question mark / Chinese
# 吗 / 怎么 / 如何 / 怎么办 / 建议 / 方案 / plan / approach / why / how /
# what / should / could / trade-off, OR ends with `?` / `？`.
#
# Heuristic for "applies rule":  the response contains at least one of
# the rule keywords (fast, 1 day, 一天, 2 hour, 2h, 2 min, 2 分钟,
# no hitl, 无人工, feedback, 反馈, tob, toc, ...). The agent does NOT
# have to literally write "FAST" — shaping the answer toward time /
# iteration / feedback-latency axes is enough; the keyword presence is
# the cheap proxy the hook can grep for.
#
# Failure modes handled (graceful):
#   - jq missing             -> silent approve
#   - transcript unreadable  -> silent approve
#   - empty input            -> silent approve
#   - subagent fork context  -> still fires; the rule is global, not per
#                               scope, per user directive.
#
# Audit: each invocation appends a JSONL line to
#   ~/.claude/hooks/logs/4-fast-rule.jsonl
# with fields {ts, session_id, action, problem_count, rule_count,
#              unmatched_problems}.
#
# Toggle (escape hatch for the user): set CLAUDE_4FAST_DISABLED=1
# in the env to silence this hook for a single run. Useful when
# the user explicitly wants a non-FAST answer. (Variable name must
# start with a letter — bash forbids digit-leading names, so we
# prefix with CLAUDE_ even though the rule is colloquially "4FAST".)

set -uo pipefail

# Honor the escape hatch before doing any work.
if [[ "${CLAUDE_4FAST_DISABLED:-0}" == "1" ]]; then
  printf '{"continue": true, "suppressOutput": true}\n'
  exit 0
fi

LOG_DIR="$HOME/.claude/hooks/logs"
LOG_FILE="$LOG_DIR/4-fast-rule.jsonl"
mkdir -p "$LOG_DIR" 2>/dev/null || true

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# --- Defensive: jq presence ---
if ! command -v jq >/dev/null 2>&1; then
  printf '{"continue": true, "suppressOutput": true}\n'
  exit 0
fi

input="$(cat)"
[[ -z "$input" ]] && { printf '{"continue": true, "suppressOutput": true}\n'; exit 0; }

session_id="$(printf '%s' "$input" | jq -r '.session_id // "unknown"' 2>/dev/null)"
transcript_path="$(printf '%s' "$input" | jq -r '.transcript_path // ""' 2>/dev/null)"

# --- Defensive: no transcript available ---
if [[ -z "$transcript_path" || ! -f "$transcript_path" ]]; then
  printf '{"continue": true, "suppressOutput": true}\n'
  exit 0
fi

# --- Tokenize the transcript into alternating text snippets, one per
# role (user / assistant), newest last. We do this in one jq pass so
# multi-block messages collapse into a single blob per turn. ---
# Extracts the last 64k chars of each role's text, which is plenty for
# "any recent problem" detection while keeping the script fast.
last_user="$(jq -r '
  select(.role == "user") | .content[]? | select(.type == "text") | .text
' "$transcript_path" 2>/dev/null | tail -c 16000)"

last_assistant="$(jq -r '
  select(.role == "assistant") | .content[]? | select(.type == "text") | .text
' "$transcript_path" 2>/dev/null | tail -c 16000)"

# Heuristic 1: is a snippet a "problem"?
is_problem() {
  local p
  p="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  [[ -z "$p" ]] && return 1
  if [[ "$p" == *'?'* || "$p" == *'？'* || "$p" == *"吗"* ]]; then
    return 0
  fi
  local kw
  for kw in "怎么" "如何" "怎么办" "建议" "推荐" "方案" \
            "why" "how" "what" "should" "could" "plan" "approach" \
            "tradeoff" "trade-off" "decide" "choose" "which"; do
    if [[ "$p" == *"$kw"* ]]; then return 0; fi
  done
  return 1
}

# Heuristic 2: does a snippet reference the 4-FAST rule?
applies_4fast() {
  local a
  a="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  [[ -z "$a" ]] && return 1
  local kw
  for kw in \
    "fast" "1 day" "1-day" "1day" "一天" "1天" "24h" "24小时" \
    "2 hour" "2-hour" "2hour" "2h" "两小时" "2小时" "120 min" "120min" \
    "2 min" "2-min" "2min" "2分钟" "2分" "120s" \
    "no hitl" "no-hitl" "无人工" "无人" "无人值守" "无人介入" \
    "feedback" "反馈" "tob" "to c" "toc" "b 端" "c 端" "b端" "c端" \
    "iter" "迭代" "ship" "上线" "发布" "shipping" \
    "4-fast" "4 fast" "4fast"; do
    if [[ "$a" == *"$kw"* ]]; then return 0; fi
  done
  return 1
}

# Heuristic 3: scan user / assistant turns in the LAST 32 KB of the
# transcript for an unmatched problem prompt. We do this by walking
# the role-tagged lines, alternating user -> assistant -> user, and
# checking whether the assistant response for a given user problem
# was tagged with 4-FAST. The first unmatched problem blocks.
#
# Implemented with two parallel streams + a pairing pass below. The
# pairing is best-effort: if a user problem is followed by a 4-FAST-
# tagged assistant response anywhere in the recent span, it counts
# as answered. This trades a tiny false-positive rate (very long
# sessions with old problems) for a 4-line jq instead of a 40-line
# awk.
user_turns="$(jq -r '
  select(.role == "user") | .content[]? | select(.type == "text") | .text
' "$transcript_path" 2>/dev/null | tail -c 32000)"

assistant_turns="$(jq -r '
  select(.role == "assistant") | .content[]? | select(.type == "text") | .text
' "$transcript_path" 2>/dev/null | tail -c 32000)"

problem_count=0
rule_count=0
unmatched_problems=0

# Count problems in the recent user stream.
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  if is_problem "$line"; then
    problem_count=$((problem_count + 1))
  fi
done <<< "$user_turns"

# Count rule-hits in the recent assistant stream.
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  if applies_4fast "$line"; then
    rule_count=$((rule_count + 1))
  fi
done <<< "$assistant_turns"

# "Unmatched" heuristic: a problem exists in the recent user stream
# AND no 4-FAST tag exists in the recent assistant stream. This is
# deliberately coarser than per-turn pairing — it catches the common
# "agent drifted away from 4-FAST in the most recent response" case
# without needing turn alignment. If the user is in a long session
# where an old problem WAS answered with 4-FAST, rule_count > 0
# still trips the unlock (no block).
if [[ "$problem_count" -ge 1 && "$rule_count" -eq 0 ]]; then
  unmatched_problems=$problem_count
fi

# Also do the per-tail check (the previous-generation behavior, kept
# as a stricter overlay): if the very last user prompt is a problem
# AND the very last assistant response does NOT apply 4-FAST, block
# even if some earlier turn did.
tail_problem=0
tail_rule=0
is_problem "$last_user" && tail_problem=1
applies_4fast "$last_assistant" && tail_rule=1

audit() {
  jq -cn --arg ts "$ts" --arg sid "$session_id" --arg action "$1" \
        --argjson pc "$2" --argjson rc "$3" --argjson up "$4" \
    '{ts:$ts, session_id:$sid, action:$action, problem_count:$pc, rule_count:$rc, unmatched_problems:$up}' \
    >> "$LOG_FILE" 2>/dev/null || true
}

block=0
reason_summary=""

if [[ "$unmatched_problems" -ge 1 ]]; then
  block=1
  reason_summary="$unmatched_problems problem(s) in recent turns with no 4-FAST answer"
fi
if [[ "$tail_problem" -eq 1 && "$tail_rule" -eq 0 ]]; then
  block=1
  reason_summary="${reason_summary:+$reason_summary; }last turn: problem asked, last response did not reference 4-FAST"
fi

if [[ "$block" -eq 1 ]]; then
  audit "block" "$problem_count" "$rule_count" "$unmatched_problems"
  jq -n --arg reason "[4-FAST RULE — user-level standing rule 2026-06-13]
$reason_summary

Re-emit your answer biasing it toward:

  1. FAST product generation iteration  (within 1 day)
  2. FAST ship                           (2 hours)
  3. FAST dev                            (no HITL, 2 mins)
  4. FAST feedback from toB client / toC users

Interpretation guide:
  - '1 day'      = full idea → code → deploy loop fits in one calendar day.
  - '2 hours'    = decision → shipped ≤ 2h.
  - '2 mins, no HITL' = dev/build/test feedback is non-interactive and ≤ 2 min.
  - 'FAST feedback' = toB / toC voice reaches the dev loop within the same iteration, not next sprint.

You do NOT need to literally write 'FAST'. Just shape the answer so it explicitly trades off on the 4 axes and call out which axis you are optimizing for. Re-emit.

If this hook fires spuriously, set CLAUDE_4FAST_DISABLED=1 in the env for this run." \
    '{decision:"block", reason:$reason}'
  exit 0
fi

audit "approve" "$problem_count" "$rule_count" "$unmatched_problems"
printf '{"continue": true, "suppressOutput": true}\n'
exit 0
