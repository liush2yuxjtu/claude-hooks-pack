#!/usr/bin/env bash
# ~/.claude/hooks/followup-not-ask.sh
#
# Stop hook — enforce: NEVER ask the user whether to file / defer a
# residual problem to a "follow-up issue". Resolve it in the same
# session instead.
#
# Mechanism: on every Stop, read the LAST assistant text message from the
# transcript. If it both (a) contains a deferral keyword ("follow-up
# issue", "开成 issue", "留作 follow-up", "要不要...修", etc.) AND (b) is
# phrased as a question ("?" / "?" / "吗"), BLOCK the stop and feed back a
# corrective reason that tells the agent to resolve the residual now.
#
# Returning {"decision":"block","reason":...} makes the agent continue the
# turn with `reason` as feedback instead of ending. Any other path returns
# {"continue":true} (approve the stop).
#
# Set by user directive (2026-06-18 fork): "for such problem of follow-up
# issue, please never ask, instead resolve them right now."
#
# Escape hatch: CLAUDE_FOLLOWUP_NOT_ASK_DISABLED=1 silences this hook.
# Fail-open: no stdin / no jq / no transcript / no match → approve.

set -uo pipefail

if [[ "${CLAUDE_FOLLOWUP_NOT_ASK_DISABLED:-0}" == "1" ]]; then
  printf '{"continue": true, "suppressOutput": true}\n'
  exit 0
fi

approve() {
  printf '{"continue": true}\n'
  exit 0
}

command -v jq >/dev/null 2>&1 || approve

input="$(cat)" || approve
[[ -z "$input" ]] && approve

# Loop guard: if this hook already blocked once this stop-cycle, don't
# block again (avoid an infinite Stop->block->Stop loop). The harness sets
# stop_hook_active=true when the agent is already continuing from a prior
# stop-hook block.
active="$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)"
[[ "$active" == "true" ]] && approve

transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)"
[[ -z "$transcript" || ! -f "$transcript" ]] && approve

# Last assistant turn's concatenated text (cap input for speed).
last_text="$(tail -n 600 "$transcript" 2>/dev/null | jq -rs '
  map(select(.type == "assistant"))
  | last
  | (.message.content // [])
  | map(select(.type == "text") | .text)
  | join("\n")
' 2>/dev/null)"
[[ -z "$last_text" || "$last_text" == "null" ]] && approve

low="$(printf '%s' "$last_text" | tr '[:upper:]' '[:lower:]')"

# (b) Is it a question at all? No question marker → not an ask → approve.
case "$low" in
*'?'* | *'？'* | *'吗'*) : ;;
*) approve ;;
esac

# (a) Deferral / follow-up keyword family (lowercase substring).
matched=""
for kw in \
  "follow-up issue" "followup issue" "follow up issue" \
  "follow-up ticket" "follow-up task" "follow-up pr" "follow-up mr" \
  "file a follow-up" "file follow-up" "open a follow-up" "create a follow-up" \
  "defer to a follow-up" "defer to follow-up" "track as follow-up" \
  "as a follow-up" "into follow-up" "leave as follow-up" "punt to" \
  "开成 follow" "开成follow" "开成 issue" "开成issue" "开个 issue" "开个issue" \
  "提个 issue" "提个issue" "开成 follow-up" "留作 follow" "留个 follow" \
  "留到 follow" "挂个 issue" "挂成 issue" "排到 backlog" "开成单" "开成 ticket" \
  "残留" "follow-up 吗" "follow up 吗" "要不要修" "要不要我修" "需不需要修" \
  "是否需要修" "要我修" "要不要开" "要不要把" "要不要继续修"; do
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
  '{ts:$ts, session_id:$sid, action:"block-followup-ask", keyword:$kw}' \
  >>"$LOG_DIR/followup-not-ask.jsonl" 2>/dev/null || true

# Block the stop and tell the agent to resolve, not ask.
reason="$(
  cat <<'R'
[hook:followup-not-ask] Your message asks the user whether to file / defer a residual problem to a follow-up issue (or whether to fix the remaining reds). Do NOT ask this.

Standing rule: residual problems are resolved in the SAME session, not deferred to a follow-up issue and not gated behind a permission question.

Continue now:
  1. Pick the residual items you were about to defer (e.g. the remaining test reds / gaps / known-exceptions).
  2. Fix them directly — investigate, edit, verify (run the relevant test/typecheck). Use parallel background subagents if they are independent.
  3. If an item is genuinely an app-side defect outside this change's scope, fix it anyway if it's small; only if it is large AND risky do you state the assumption + a defensible default and keep going — still without asking.
  4. Report with a cheap signal: "已做完 X, evidence: <path>" per resolved item.

The ONLY things you may still ask about are truly irreversible / taste calls (force push, rm -rf, ship a public deploy, secrets, naming/copy). Filing or skipping a follow-up issue is NOT one of them — just do the work.
R
)"

jq -cn --arg r "$reason" '{decision:"block", reason:$r}'
exit 0
