#!/usr/bin/env bash
# ~/.claude/hooks/followup-spawn-agents.sh
#
# Stop hook — keyword trigger: when the assistant's last message contains
# the bare "follow-up" / "followup" / "follow up" keyword (with OR without a
# trailing question), BLOCK the stop and force the agent to dispatch
# parallel agent teams / workflows to resolve the residual NOW.
#
# Distinct from followup-not-ask.sh, which only fires when the agent is
# explicitly ASKING whether to file a follow-up issue. This hook fires on
# the keyword alone — any time the agent's response drifts toward
# "follow-up", redirect it to in-session parallel dispatch.
#
# Mechanism:
#   - Read transcript from stdin JSON
#   - Extract the last assistant text message
#   - Match bare "follow-up" / "followup" / "follow up" substring (case-insensitive)
#   - If matched, return {"decision":"block","reason":<strong redirect>}
#     so the harness continues the turn and the agent must act
#   - Loop guard: respect stop_hook_active to avoid infinite blocks
#
# Escape hatch: CLAUDE_FOLLOWUP_SPAWN_AGENTS_DISABLED=1
# Fail-open: no jq / no stdin / no transcript / no match → approve.

set -uo pipefail

if [[ "${CLAUDE_FOLLOWUP_SPAWN_AGENTS_DISABLED:-0}" == "1" ]]; then
  printf '{"continue": true, "suppressOutput": true}\n'
  exit 0
fi

approve() { printf '{"continue": true}\n'; exit 0; }

command -v jq >/dev/null 2>&1 || approve

input="$(cat)" || approve
[[ -z "$input" ]] && approve

# Loop guard — if the harness already told us we're continuing from a
# prior stop-hook block, don't block again.
active="$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)"
[[ "$active" == "true" ]] && approve

transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)"
[[ -z "$transcript" || ! -f "$transcript" ]] && approve

# Last assistant turn's concatenated text.
last_text="$(tail -n 600 "$transcript" 2>/dev/null | jq -rs '
  map(select(.type == "assistant"))
  | last
  | (.message.content // [])
  | map(select(.type == "text") | .text)
  | join("\n")
' 2>/dev/null)"
[[ -z "$last_text" || "$last_text" == "null" ]] && approve

low="$(printf '%s' "$last_text" | tr '[:upper:]' '[:lower:]')"

# Bare keyword family — match any of these substrings (lowercase).
matched=""
for kw in \
  "follow-up" "followup" "follow up" \
  "留到下一轮" "留作 follow" "留个 follow" "下一轮再" \
  "下次再" "顺手修掉" "下次修" "下一轮修" \
  "out-of-scope follow" "deferred to a follow" ; do
  if [[ "$low" == *"$kw"* ]]; then
    matched="$kw"
    break
  fi
done
[[ -z "$matched" ]] && approve

# Audit (best-effort).
LOG_DIR="$HOME/.claude/hooks/logs"
mkdir -p "$LOG_DIR" 2>/dev/null || true
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
sid="$(printf '%s' "$input" | jq -r '.session_id // "unknown"' 2>/dev/null)"
jq -cn --arg ts "$ts" --arg sid "$sid" --arg kw "$matched" \
  '{ts:$ts, session_id:$sid, action:"block-followup-spawn-agents", keyword:$kw}' \
  >> "$LOG_DIR/followup-spawn-agents.jsonl" 2>/dev/null || true

# Block the stop and force parallel dispatch.
reason="$(cat <<'R'
[hook:followup-spawn-agents] Your last message contains the "follow-up" keyword — the user explicitly does NOT want follow-up deferrals. Dispatch parallel agent teams NOW and resolve in-session.

Standing rule: residual items are fixed in the SAME session by dispatching parallel work — not listed, not asked about, not deferred to a follow-up issue.

Continue now:
  1. Identify the residual items your message was about to defer.
  2. Dispatch each independent item as its own background subagent in ONE batch — max parallelism. Use the Agent tool with `run_in_background: true` for each. Pick non-overlapping file ownership per subagent to avoid edit conflicts. Each subagent gets: scope, file ownership, "fix and report JSON", and "do not modify files outside ownership".
  3. While subagents work, prep the merge: stage verified outputs, plan commit grouping (one commit per subagent slice), pre-write the commit messages.
  4. As each subagent reports, verify (typecheck / targeted tests), then `git add` that slice. If a subagent broke typecheck, dispatch a follow-up subagent scoped to that fix.
  5. Final verification: full typecheck + full test suite for the touched scope. Commit each slice with a self-contained message.
  6. Report with cheap signal: "已做完 X, evidence: <path>" per resolved item, plus the final commit hashes.

If a residual is genuinely outside your scope (a different module / repo), state the assumption + defensible default and keep going — still without asking. The ONLY things you may still ask about are truly irreversible / taste calls (force push, rm -rf, public deploy, secrets). "File a follow-up issue" is NOT one of them.
R
)"

jq -cn --arg r "$reason" '{decision:"block", reason:$r}'
exit 0