#!/usr/bin/env bash
# fix-uat-env test.sh — rubric §5: 3 positive + 3 negative real test matrix
#
# Tests the hook (hook.sh) trigger detection, NOT the apply script.
# Runs the hook against canned prompts and checks the audit JSONL was hit
# (or not) as expected.
set -uo pipefail

HOOK="$HOME/.claude/hooks/fix-uat-env/hook.sh"
AUDIT="$HOME/.claude/hooks/logs/fix-uat-env-audit.jsonl"
SESSION_LOG_DIR="$HOME/.claude/hooks/logs"

# Wipe audit for clean run
rm -f "$AUDIT"

run_case() {
  local label="$1" prompt="$2" expect_hit="$3"
  local before_count=0 after_count=0
  [[ -f "$AUDIT" ]] && before_count=$(wc -l < "$AUDIT")

  # Run the hook with the canned prompt on stdin
  printf '%s' "$prompt" | bash "$HOOK" >/dev/null 2>&1
  local rc=$?

  [[ -f "$AUDIT" ]] && after_count=$(wc -l < "$AUDIT")
  local hit="no"
  (( after_count > before_count )) && hit="yes"

  if [[ "$hit" == "$expect_hit" ]]; then
    echo "PASS [$label]  hit=$hit  rc=$rc  prompt=\"${prompt:0:60}\""
    return 0
  else
    echo "FAIL [$label]  hit=$hit  expected=$expect_hit  rc=$rc  prompt=\"${prompt:0:60}\""
    return 1
  fi
}

fail=0

# --- positive: should hit ---
run_case "P1-slash-cmd"     "/fix-uat-env please run it"     "yes" || fail=$((fail+1))
run_case "P2-xml-bracket"    "[[fix-uat-env]] bootstrap"      "yes" || fail=$((fail+1))
run_case "P3-compound"       "fix-zhangqing-uat broken env"  "yes" || fail=$((fail+1))
run_case "P4-co-occ"         "the zhangqing env is broken, fix it"  "yes" || fail=$((fail+1))
run_case "P5-natural"        "reapply uat fix"               "yes" || fail=$((fail+1))

# --- negative: should NOT hit ---
run_case "N1-fix-only"       "fix the typo in the README"    "no"  || fail=$((fail+1))
run_case "N2-zhangqing-only" "tell me about zhangqing as a name" "no"  || fail=$((fail+1))
run_case "N3-uat-only"       "UAT stands for user-acceptance test"  "no"  || fail=$((fail+1))
run_case "N4-empty-prompt"   ""                              "no"  || fail=$((fail+1))

# --- escape hatch ---
run_case "E1-disabled-env"   "/fix-uat-env"                   "no"  || fail=$((fail+1))

# --- summary ---
echo
if (( fail == 0 )); then
  echo "ALL TESTS PASSED (9/9)"
  echo "audit log: $AUDIT"
  echo "session log dir: $SESSION_LOG_DIR"
  exit 0
else
  echo "$fail TEST(S) FAILED"
  echo "audit log: $AUDIT"
  exit 1
fi
