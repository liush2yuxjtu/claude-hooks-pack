#!/usr/bin/env bash
# fix-uat-env hook — UserPromptSubmit
#
# rubric: HOOK_DESIGN_RUBRIC.md
# value-source: VALUE.md §L1 授权 / §L3 默认动作=ship+出证据 / LEAVES.md A_AGENT_VALUE_EXPECT
# when-NOT-trigger: when prompt has no /fix-uat-env or co-occurring "zhangqing"+"fix"+"uat"
#                   keywords; for casual mention of "fix" alone, hook is silent.
#
# Trigger list (intentionally ≤ 100; precision > recall for an env-patch
# trigger that should not fire on every "fix" / "uat" mention):
#   1) /fix-uat-env           — slash command (structural)
#   2) [[fix-uat-env]]        — XML-style marker (structural)
#   3) <<fix-uat-env>>        — alternate XML-style marker (structural)
#   4) zhangqing-fix          — co-occurrence: "zhangqing" + "fix" same line
#   5) fix-zhangqing-uat      — hyphenated compound (structural)
#   6) reapply uat fix        — natural-language (substring, case-insensitive)
#
# Behavior (rubric §3):
#   - default: silent approve (exit 0, no output, no block)
#   - hit: append a per-session reminder so the next assistant turn knows
#          to run apply.sh, AND log to audit JSONL
#   - no auto-apply: agent self-resolves (A_AGENT_VALUE_EXPECT leaf)
#
# Escape hatch (rubric §4): CLAUDE_FIX_UAT_ENV_DISABLED=1 → silent
# Audit:     ~/.claude/hooks/logs/fix-uat-env-audit.jsonl
# Session:   ~/.claude/hooks/logs/fix-uat-env-<session_id>.md
set -uo pipefail

# --- Escape hatch ---
if [[ "${CLAUDE_FIX_UAT_ENV_DISABLED:-0}" == "1" ]]; then
  exit 0
fi

# --- Read prompt from stdin (UserPromptSubmit) ---
input="$(cat)"
[[ -z "$input" ]] && exit 0

# --- Trigger detection ---
matched=()
# structural markers (priority)
[[ "$input" =~ /fix-uat-env[[:space:]] ]] && matched+=("/fix-uat-env")
[[ "$input" =~ \[\[fix-uat-env\]\] ]] && matched+=("[[fix-uat-env]]")
[[ "$input" =~ \<\<fix-uat-env\>\> ]] && matched+=("<<fix-uat-env>>")
# compound keyword
[[ "$input" =~ fix-zhangqing-uat ]] && matched+=("fix-zhangqing-uat")
# co-occurrence: "zhangqing" + "fix" on same line
if echo "$input" | grep -qiE 'zhangqing' &&
  echo "$input" | grep -qiE 'fix'; then
  matched+=("zhangqing+fix-co-occ")
fi
# natural language
echo "$input" | grep -qiE 'reapply[[:space:]]+uat[[:space:]]+fix' &&
  matched+=("reapply-uat-fix-nl")

if [[ ${#matched[@]} -eq 0 ]]; then
  exit 0
fi

# --- Hit path: append per-session reminder, log audit, silent exit ---
LOG_DIR="$HOME/.claude/hooks/logs"
mkdir -p "$LOG_DIR"
AUDIT="$LOG_DIR/fix-uat-env-audit.jsonl"
SESSION_ID="${CLAUDE_SESSION_ID:-$(date +%s)}"
SESSION_LOG="$LOG_DIR/fix-uat-env-${SESSION_ID}.md"

# Append reminder to per-session log (rubric §6)
{
  echo "## $(date -u +%FT%TZ) fix-uat-env trigger fired"
  echo "- matched: ${matched[*]}"
  echo "- action: run \`bash ~/.claude/hooks/fix-uat-env/apply.sh\` to patch:"
  echo "  1. scripts/serve.sh → forward DEER_FLOW_AUTH_DISABLED_USER_EMAIL"
  echo "  2. config.local.yaml → agents_api.enabled: true (so fmcg-diagnosis-test shows in UI)"
  echo "  3. backend/.deer-flow/groups/zhangqing-group/extensions_config.json → ensure FMCG skills enabled"
  echo "  4. backend/.deer-flow/agents/fmcg-diagnosis-test/SOUL.md → ensure exists"
  echo "  All 4 steps are idempotent. Re-running apply.sh is safe."
  echo "- escape: CLAUDE_FIX_UAT_ENV_DISABLED=1 to silence this reminder."
  echo
} >>"$SESSION_LOG"

# Audit JSONL (rubric §6)
ts="$(date -u +%FT%TZ)"
joined="$(
  IFS=,
  echo "${matched[*]}"
)"
printf '{"ts":"%s","session_id":"%s","action":"hit","matched":"%s","prompt_len":%d}\n' \
  "$ts" "$SESSION_ID" "$joined" "${#input}" >>"$AUDIT"

# Silent: do not print to stdout, do not block (rubric §3)
exit 0
