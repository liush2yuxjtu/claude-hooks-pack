#!/usr/bin/env bash
# Test harness for straight-fix-no-ask.sh (rubric §5).
# Feeds fake Stop-hook JSON (via last_assistant_message fallback) and asserts
# block vs approve. Run: bash ~/.claude/hooks/straight-fix-no-ask.test.sh
set -uo pipefail
HOOK="$HOME/.claude/hooks/straight-fix-no-ask.sh"
pass=0; fail=0

run() { # $1=expected(block|approve) $2=label $3=message
  local expected="$1" label="$2" msg="$3" out decision
  out="$(jq -cn --arg m "$msg" '{stop_hook_active:false, session_id:"test-harness", last_assistant_message:$m}' | bash "$HOOK")"
  if printf '%s' "$out" | jq -e '.decision == "block"' >/dev/null 2>&1; then
    decision="block"
  else
    decision="approve"
  fi
  if [[ "$decision" == "$expected" ]]; then
    pass=$((pass+1)); printf 'PASS [%s] %s\n' "$expected" "$label"
  else
    fail=$((fail+1)); printf 'FAIL [want=%s got=%s] %s\n    out=%s\n' "$expected" "$decision" "$label" "$out"
  fi
}

# reset per-session counter so the cap doesn't swallow later positives
rm -f "$HOME/.claude/hooks/state/straight-fix-no-ask.test-harness.count" 2>/dev/null

echo "── POSITIVE (must block) ──"
run block "incident: 要的话我可以下一轮顺手修掉" \
  $'result: 修复完成。\n一个独立 bug:routers/tools.py:775 import 缺失。要的话我可以下一轮顺手修掉。'
run block "en: i can do that next round if you want" \
  $'Fixed the tests, all green.\nI can do that next round if you want — just say the word.'
run block "zh direct ask: 要不要我把剩下的也改了" \
  $'都改好了。要不要我把剩下的也改了?'
run block "zh conditional offer: 如果需要,我可以帮你补文档" \
  $'搞定。如果需要,我可以帮你补文档。'
run block "en gate: please confirm / should i" \
  $'The migration is ready. Should I go ahead and apply it? Please confirm.'

echo "── NEGATIVE (must approve) ──"
run approve "clean result line" \
  $'result: 已修复并推送,evidence: /tmp/x.log。75 passed, ruff clean.'
run approve "cheap signal only" \
  $'已做完 X, evidence: backend/tests/test_x.py。全部通过。'
run approve "offer keyword only inside code block" \
  $'Done.\n```bash\n# next round of tests, if you want to run more\necho hi\n```\nAll green.'
run approve "benign happy to report" \
  $'Happy to report the deploy succeeded; metrics are nominal.'
run approve "benign you could see diff" \
  $'I refactored the parser. You could see the change at parser.py:42 (informational).'

echo
echo "RESULT: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]]
