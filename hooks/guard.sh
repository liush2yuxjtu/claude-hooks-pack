#!/usr/bin/env bash
# ~/.claude/hooks/guard.sh
# PreToolUse redline engine. Reads tool-call JSON on stdin, scans
# ~/.claude/hooks/redlines.tsv (tool<TAB>regex<TAB>action<TAB>reason),
# and emits exit 2 (block) / exit 1 (warn) on hit. Fails open if jq is missing.

set -uo pipefail

REDLINES="${HOME}/.claude/hooks/redlines.tsv"
LOG="${HOME}/.claude/hooks/guard.log"

# Fail open if no rules file or jq missing — never break the session.
if ! command -v jq >/dev/null 2>&1; then
  echo "guard.sh: jq missing, fail-open" >&2
  exit 0
fi
[[ -r "$REDLINES" ]] || exit 0

# Scoping switch: when CLAUDE_REDLINE_ENFORCE=0, the main agent runs
# unguarded (chat / planning). SubagentStart hook in settings.json
# sets this to 1 for forked agents so they get the full guard.
# Default is enforce-on for safety; the main agent's zshrc flips it off.
if [[ "${CLAUDE_REDLINE_ENFORCE:-1}" == "0" ]]; then
  printf 'guard.sh: CLAUDE_REDLINE_ENFORCE=0, skipping (main agent / planning mode)\n' >&2
  exit 0
fi

input=$(cat)
[[ -z "$input" ]] && exit 0

tool=$(jq -r '.tool_name // ""' <<<"$input" 2>/dev/null || echo "")
[[ -z "$tool" ]] && exit 0

# Concat every writable payload field into one haystack.
payload=$(jq -r '
  (.tool_input // {}) | (
    (.command   // "") + "\n" +
    (.new_string // "") + "\n" +
    (.old_string // "") + "\n" +
    (.content   // "") + "\n" +
    (.file_path // "") + "\n" +
    ((.edits // []) | map((.new_string // "") + "\n" + (.old_string // "")) | join("\n"))
  )
' <<<"$input" 2>/dev/null || echo "")

worst=0
hits=()

while IFS=$'\t' read -r tool_pat regex action reason; do
  [[ -z "${tool_pat:-}" ]] && continue
  [[ "${tool_pat:0:1}" == "#" ]] && continue
  [[ "$tool" =~ ^(${tool_pat})$ ]] || continue

  # heredoc escape hatch: prefer-prod-mode-for-demos
  # skips the rule when the Bash command contains a heredoc
  # delimiter (<<) — the "dev" patterns likely appear in
  # documentation text inside cat <<EOF, not as real commands.
  if [[ "$tool" == "Bash" ]] && [[ "$reason" == prefer-prod-mode-for-demos* ]]; then
    cmd=$(jq -r '.tool_input.command // ""' <<<"$input" 2>/dev/null || echo "")
    if grep -qE '<<' <<<"$cmd"; then
      continue
    fi
  fi

  if grep -qE "$regex" <<<"$payload"; then
    case "${action:-warn}" in
    block)
      hits+=("🛑 BLOCKED: ${reason:-(no reason)}")
      worst=2
      ;;
    warn)
      hits+=("⚠️  WARN: ${reason:-(no reason)}")
      [[ $worst -lt 1 ]] && worst=1
      ;;
    *)
      hits+=("⚠️  WARN (unknown action '${action}'): ${reason:-(no reason)}")
      [[ $worst -lt 1 ]] && worst=1
      ;;
    esac
  fi
done <"$REDLINES"

if ((${#hits[@]} > 0)); then
  for h in "${hits[@]}"; do echo "$h" >&2; done
  mkdir -p "$(dirname "$LOG")"
  {
    echo "--- $(date -u +%FT%TZ) tool=$tool worst=$worst"
    for h in "${hits[@]}"; do echo "  $h"; done
  } >>"$LOG" 2>/dev/null || true
fi

# Escape hatch: if every hit is warn-level (worst==1) AND the payload
# carries an explicit `// @redline-ok` marker, downgrade to pass.
# Hard blocks (worst==2) are NOT silenceable via comment — those
# always require the user to fix the rule or restate the intent.
if ((worst == 1)) && grep -qE '@redline-ok' <<<"$payload"; then
  printf '✓ safelisted: @redline-ok marker present, warn-level rules downgraded (hard blocks still enforced)\n' >&2
  worst=0
  hits=()
fi

exit $worst
