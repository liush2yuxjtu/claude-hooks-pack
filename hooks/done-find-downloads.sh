#!/usr/bin/env bash
# ~/.claude/hooks/done-find-downloads.sh
# UserPromptSubmit hook. When the user's prompt is a short completion
# acknowledgement ("Done", "Finished", "完成", "搞定", "导出了" …), surface
# the files that changed most recently in ~/Downloads as turn context — so
# the assistant can auto-pick up whatever the user just produced/exported
# (e.g. an exported decisions JSON) WITHOUT asking for the path.
#
# Why: the user often finishes an out-of-band step (export a file, save a
# screenshot, download a report) and replies only "done". The path is in
# ~/Downloads; the model shouldn't have to ask "paste the path". This hook
# hands it the freshest Downloads files the moment a "done" lands.
#
# Trigger: prompt (trimmed) is short (<= DONE_HOOK_MAXLEN chars, default 48)
#          AND matches the completion regex (en + zh) AND is not a negation.
# Scope:   mainly ~/Downloads. Override dirs via DONE_HOOK_DIRS (colon-sep).
# Window:  files modified within DONE_HOOK_WINDOW_MIN minutes (default 240);
#          if none, falls back to the newest few regardless of age.
# Emission: plain stdout -> folded into the model's context (exit 0).
# Fail-open: no stdin / no python+jq / no match / no dir -> silent exit 0.
#
# Escape hatch: DONE_FIND_DOWNLOADS_DISABLED=1
# Audit:        ~/.claude/hooks/logs/done-find-downloads.jsonl
# Rubric:       ~/.claude/hooks/HOOK_DESIGN_RUBRIC.md

set -uo pipefail

[[ "${DONE_FIND_DOWNLOADS_DISABLED:-0}" == "1" ]] && exit 0

LOG_DIR="$HOME/.claude/hooks/logs"
AUDIT="$LOG_DIR/done-find-downloads.jsonl"
mkdir -p "$LOG_DIR" 2>/dev/null || true
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
audit() { printf '{"ts":"%s","evt":"%s"%s}\n' "$ts" "$1" "${2:-}" >> "$AUDIT" 2>/dev/null || true; }

input="$(cat)"
[[ -z "$input" ]] && { audit empty; exit 0; }

# --- extract the prompt field (python preferred, jq fallback, raw last) ---
prompt=""
if command -v python3 >/dev/null 2>&1; then
  prompt="$(printf '%s' "$input" | python3 -c 'import sys,json
try: print(json.load(sys.stdin).get("prompt",""))
except Exception: pass' 2>/dev/null)"
fi
if [[ -z "$prompt" ]] && command -v jq >/dev/null 2>&1; then
  prompt="$(printf '%s' "$input" | jq -r '.prompt // ""' 2>/dev/null)"
fi
[[ -z "$prompt" ]] && { audit no_prompt; exit 0; }

# trim + lowercase
trimmed="$(printf '%s' "$prompt" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
lower="$(printf '%s' "$trimmed" | tr '[:upper:]' '[:lower:]')"

# Gate 1: short acknowledgement only — avoids matching "done" inside long prompts.
maxlen="${DONE_HOOK_MAXLEN:-48}"
if [[ "${#trimmed}" -gt "$maxlen" ]]; then audit too_long; exit 0; fi

# Gate 2: negation guard — "not done yet", "还没完成", "未完成", "差不多".
if printf '%s' "$lower" | grep -Eiq "not (done|finished|ready)|isn'?t done|haven'?t|n'?t done yet"; then audit negation; exit 0; fi
if printf '%s' "$trimmed" | grep -Eq "没(做完|完成|搞定|弄好)|还没|未完成|差点|没好"; then audit negation_zh; exit 0; fi

# Gate 3: completion match (en word-boundary + zh).
matched=""
if printf '%s' "$lower" | grep -Eq "(^|[^a-z])(done|finished|finish|complete|completed|all ?done|i'?m done|im done|ready|exported|export(ed)?( done)?|fin|that'?s (it|all))([^a-z]|\$)"; then
  matched="en"
elif printf '%s' "$trimmed" | grep -Eq "完成|搞定|做完|弄好|好了|导出(了|好)?|搞好|完事|齐活|勾完|选好|拍完|存好"; then
  matched="zh"
else
  audit no_match; exit 0
fi

# --- collect recently-changed files in the target dir(s) ---
dirs_raw="${DONE_HOOK_DIRS:-$HOME/Downloads}"
window="${DONE_HOOK_WINDOW_MIN:-240}"
maxfiles="${DONE_HOOK_MAXFILES:-12}"

IFS=':' read -r -a DIRS <<< "$dirs_raw"

# gather "mtime\tpath" lines (newest window first), skip dotfiles + .download partials
gather() { # $1 = -mmin window arg ("" = no time filter)
  local d
  for d in "${DIRS[@]}"; do
    [[ -d "$d" ]] || continue
    if [[ -n "$1" ]]; then
      find "$d" -maxdepth 1 -type f -mmin "$1" ! -name '.*' ! -name '*.download' ! -name '*.crdownload' -print 2>/dev/null
    else
      find "$d" -maxdepth 1 -type f ! -name '.*' ! -name '*.download' ! -name '*.crdownload' -print 2>/dev/null
    fi
  done | while IFS= read -r f; do
    m="$(stat -f '%m' "$f" 2>/dev/null || stat -c '%Y' "$f" 2>/dev/null)"
    [[ -n "$m" ]] && printf '%s\t%s\n' "$m" "$f"
  done | sort -rn
}

fallback=0
listing="$(gather "-$window")"
if [[ -z "$listing" ]]; then
  fallback=1
  listing="$(gather "")"     # no recent files: show newest few overall
fi
listing="$(printf '%s\n' "$listing" | head -n "$maxfiles")"

if [[ -z "$listing" ]]; then
  audit no_files ",\"matched\":\"$matched\""
  exit 0
fi

now="$(date +%s)"
human_age() { # $1 = epoch mtime
  local diff=$(( now - $1 )); (( diff < 0 )) && diff=0
  if   (( diff < 60 ));   then printf '%ds ago' "$diff"
  elif (( diff < 3600 )); then printf '%dm ago' "$(( diff / 60 ))"
  elif (( diff < 86400 ));then printf '%dh ago' "$(( diff / 3600 ))"
  else printf '%dd ago' "$(( diff / 86400 ))"; fi
}
human_size() { # $1 = path
  local b; b="$(stat -f '%z' "$1" 2>/dev/null || stat -c '%s' "$1" 2>/dev/null)"; [[ -z "$b" ]] && { printf '?'; return; }
  if   (( b < 1024 ));        then printf '%dB' "$b"
  elif (( b < 1048576 ));     then awk "BEGIN{printf \"%.1fKB\", $b/1024}"
  else awk "BEGIN{printf \"%.1fMB\", $b/1048576}"; fi
}

# --- build context block on stdout ---
dir_label="$(printf '%s' "$dirs_raw")"
if (( fallback )); then
  printf '[done-downloads hook] 检测到完成确认("%s")。%s 近 %s 分钟内无新文件;以下为最近变动的文件(供自动接续):\n' "$trimmed" "$dir_label" "$window"
else
  printf '[done-downloads hook] 检测到完成确认("%s")。以下是 %s 近 %s 分钟内变动的文件,很可能是用户刚导出/产出的(决策 JSON、报告、截图、下载件等):\n' "$trimmed" "$dir_label" "$window"
fi

count=0
while IFS=$'\t' read -r mt path; do
  [[ -z "$path" ]] && continue
  printf '  • %s   (%s, %s)\n' "$path" "$(human_age "$mt")" "$(human_size "$path")"
  count=$(( count + 1 ))
done <<< "$listing"

printf '若用户的「完成」指向其中某个文件(尤其最新的相关文件),直接读取它据此继续,不要再向用户索要路径;若都不相关则忽略本提示。\n'

audit emitted ",\"matched\":\"$matched\",\"fallback\":$fallback,\"files\":$count"
exit 0
