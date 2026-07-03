#!/usr/bin/env bash
# ~/.claude/hooks/pop-open-on-ship.sh
# Stop hook. When the assistant's last message contains a "ready to ship"
# phrase, pop open any URLs / local deliverable files mentioned in it.
#
# ⛔ UNWIRED since 2026-06-xx (slice 0003)
# Reason: wrong-Chrome auto-pop pain — the URL would land in the user's daily
# Chrome instead of the paired one, defeating the purpose. Keep on disk as
# reference; re-wire only after the CDP-based pair-chrome routing is stable.
#
# Trigger phrases:
#   EN: "ready to ship", "ship it", "ready to deploy", "deploy now",
#       "ship to public", "ship to prod"
#   ZH: "上线", "可以发", "可以上线", "可以部署", "推上线",
#       "准备发", "可以发布", "上线吧", "发布吧"
#
# Routing:
#   - Deploy preview URLs (e.g. *.vercel.app): open in NAMED CHROME PROFILE
#     ($HOME/.claude/chrome-profiles/min-win@<worktree>)
#   - Other http(s) URLs: plain `open`
#   - Local files (file:// or relative/absolute paths ending in
#     .html / .md / .json / .pdf, or in dist/|out/|build/): plain `open`
#
# Fail-open: any error -> exit 0 (informational, never block).
#
# rubric:  ~/.claude/hooks/HOOK_DESIGN_RUBRIC.md
# audit:   ~/.claude/hooks/logs/pop-open-on-ship.jsonl
# escape hatch: CLAUDE_POP_OPEN_DISABLED=1  (also POP_OPEN_DRY_RUN=1)
#
# Narrow-scope exception (rubric §1): this hook fires on ship-time
# vocabulary only — a closed set of intent phrases, not a general
# lexical scan. Expanding to 100+ would require padding with
# adjacent-but-unrelated words ("merge", "deploy", "rollback") and
# would re-introduce the wrong-Chrome auto-pop pain that caused
# slice 0003 to unwire this hook. Per rubric §1, ≤100 triggers
# requires documented rationale → this is it.

# NOTE: as of slice 0003-stop-hook-removal (2026-06-13), this script is
# NO LONGER WIRED into `~/.claude/settings.json` (the `Stop` entry was
# removed because it caused the wrong-Chrome auto-pop pain). Kept on disk
# for reversibility — see slice 0005 chat-title-hook for the SessionStart
# replacement pattern.

set -uo pipefail

# --- escape hatch ---
if [[ "${CLAUDE_POP_OPEN_DISABLED:-0}" == "1" ]]; then exit 0; fi

LOG_DIR="$HOME/.claude/hooks/logs"
AUDIT_FILE="$LOG_DIR/pop-open-on-ship.jsonl"
mkdir -p "$LOG_DIR" 2>/dev/null || true
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# --- env knobs ---
# POP_OPEN_DRY_RUN=1 -> don't actually run `open`, just print what we would open
DRY="${POP_OPEN_DRY_RUN:-0}"

# --- Read stdin (Stop JSON) ---
input="$(cat)"
[[ -z "$input" ]] && exit 0

# Extract the assistant's last message. The Stop payload shape varies by
# harness version; try common fields then fall back to grepping the raw blob.
last_message=""
if command -v jq >/dev/null 2>&1; then
  last_message="$(printf '%s' "$input" | jq -r '
    [
      (.last_assistant_message // empty),
      (.assistant_message // empty),
      (.message // empty),
      (.transcript[-1].message // empty),
      (.transcript[-1].content // empty)
    ] | map(select(. != null and . != "")) | first // ""
  ' 2>/dev/null)"
fi
if [[ -z "$last_message" ]]; then
  # Fallback: grep the entire payload for the trigger phrase itself; if found,
  # use the whole blob as the message (we still need URLs from it).
  last_message="$input"
fi
[[ -z "$last_message" ]] && exit 0

# --- Trigger detection (case-insensitive substring match) ---
lc="$(printf '%s' "$last_message" | tr '[:upper:]' '[:lower:]')"

triggers=(
  "ready to ship"
  "ship it"
  "ready to deploy"
  "deploy now"
  "ship to public"
  "ship to prod"
  "上线"
  "可以发"
  "可以上线"
  "可以部署"
  "推上线"
  "准备发"
  "可以发布"
  "上线吧"
  "发布吧"
)

matched=0
for kw in "${triggers[@]}"; do
  if [[ "$lc" == *"$kw"* ]]; then
    matched=1
    break
  fi
done
[[ "$matched" -eq 0 ]] && exit 0

# --- Extract URLs and file paths ---
# Use awk to walk each line, dedupe, and emit one item per line.

extract() {
  # BSD-grep-compatible: use [[:graph:]] (printable non-space) instead of
  # a hand-rolled negated class containing quote chars.
  printf '%s\n' "$last_message" |
    grep -oE 'https?://[[:graph:]]+' |
    sed -E 's/[.,;:!?]+$//' |
    awk '!seen[$0]++'
}

extract_local_files() {
  # file:// URLs
  printf '%s\n' "$last_message" |
    grep -oE 'file://[[:graph:]]+' |
    sed -E 's/[.,;:!?]+$//'

  # Absolute or home-relative paths ending in known deliverable extensions.
  # Require the leading slash NOT to be preceded by ':' so we don't grab
  # the path out of https://example.com/foo.html.
  printf '%s\n' "$last_message" |
    grep -oE '(^|[^[:alnum:]_:./])(/|~)[A-Za-z0-9_./-]+\.(html|md|json|pdf)' |
    sed -E 's/^[^A-Za-z0-9_/.~]+//' |
    sed -E 's/[.,;:!?]+$//'

  # Relative paths starting with ./ or ../ + extension (the ./ or ../ must
  # be at a word boundary, not inside a URL).
  printf '%s\n' "$last_message" |
    grep -oE '(^|[^[:alnum:]_:./])\.{1,2}/[A-Za-z0-9_./-]+\.(html|md|json|pdf)' |
    sed -E 's/^[^A-Za-z0-9_/.~]+//' |
    sed -E 's/[.,;:!?]+$//'

  # Paths inside dist/, out/, build/ (absolute, home, or ./ relative).
  # Same non-URL boundary rule.
  printf '%s\n' "$last_message" |
    grep -oE '(^|[^[:alnum:]_:./])(/|~|\.{1,2}/)[A-Za-z0-9_./-]*/(dist|out|build)/[A-Za-z0-9_./-]+' |
    sed -E 's/^[^A-Za-z0-9_/.~]+//' |
    sed -E 's/[.,;:!?]+$//'
}

urls="$(extract | head -n 20)"
files="$(extract_local_files | awk '!seen[$0]++' | head -n 20)"

if [[ -z "$urls" && -z "$files" ]]; then
  printf '[pop-open-on-ship] ship phrase detected, but no URLs/files found in last message\n' >&2
  exit 0
fi

# --- Resolve Chrome profile name (project@worktree) ---
project_name="min-win"
worktree_name="main"
top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -n "$top" ]]; then
  project_name="$(basename "$top")"
  # Detect .claude/worktrees/<name>/... or sibling worktrees
  cwd_abs="$(cd "$(dirname "$top")" && pwd)"
  wt_basename="$(basename "$top")"
  if [[ "$cwd_abs" == *"/.claude/worktrees/"* || "$top" == *"/.claude/worktrees/"* ]]; then
    worktree_name="$wt_basename"
  else
    worktree_name="main"
  fi
fi
PROFILE_DIR="$HOME/.claude/chrome-profiles/${project_name}@${worktree_name}"

# --- Helper: open one item ---
opened=()
failed=()

open_one() {
  local kind="$1" target="$2"

  if [[ "$DRY" == "1" ]]; then
    opened+=("$kind: $target")
    return 0
  fi

  if [[ "$kind" == "url-preview" ]]; then
    mkdir -p "$PROFILE_DIR"
    # Fresh profile per e2e session (ephemeral per CLAUDE.md).
    rm -rf "${PROFILE_DIR:?}/"*
    open -na "Google Chrome" --args \
      --user-data-dir="$PROFILE_DIR" \
      --no-first-run \
      --disable-background-networking \
      --new-window \
      "$target" >/dev/null 2>&1 &&
      opened+=("$kind: $target") ||
      failed+=("$kind: $target")
  elif [[ "$kind" == "url" ]]; then
    open "$target" >/dev/null 2>&1 &&
      opened+=("$kind: $target") ||
      failed+=("$kind: $target")
  else # file
    # Pass through verbatim — `open` accepts both bare paths and file:// URLs.
    open "$target" >/dev/null 2>&1 &&
      opened+=("$kind: $target") ||
      failed+=("$kind: $target")
  fi
}

# --- Classify and open URLs ---
if [[ -n "$urls" ]]; then
  while IFS= read -r u; do
    [[ -z "$u" ]] && continue
    if [[ "$u" == *".vercel.app"* || "$u" == *".vercel.com"* ]]; then
      open_one "url-preview" "$u"
    else
      open_one "url" "$u"
    fi
  done <<<"$urls"
fi

# --- Open local files ---
if [[ -n "$files" ]]; then
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    open_one "file" "$f"
  done <<<"$files"
fi

# --- Summary on stdout ---
{
  printf '[pop-open-on-ship] ship phrase detected, opened %d item(s)' \
    "${#opened[@]}"
  if [[ "$DRY" == "1" ]]; then
    printf ' [DRY RUN]'
  fi
  printf '\n'
  for o in "${opened[@]:-}"; do
    [[ -n "$o" ]] && printf '  OPEN  %s\n' "$o"
  done
  for x in "${failed[@]:-}"; do
    [[ -n "$x" ]] && printf '  FAIL  %s\n' "$x"
  done
} >&2

# Always exit 0 — informational, never block.
exit 0
