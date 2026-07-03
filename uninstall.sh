#!/usr/bin/env bash
# uninstall.sh — restore settings.json from backup and remove installed hook files.
# Always prefers the most-recent backup under ~/.claude/settings.json.bak-*

set -euo pipefail

PACK_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_HOOKS="$HOME/.claude/hooks"
TARGET_SETTINGS="$HOME/.claude/settings.json"

log() { printf '[uninstall.sh] %s\n' "$*"; }

# ── 1. Restore settings from newest backup ────────────────────────────
if [[ -f "$TARGET_SETTINGS" ]]; then
  # Newest backup first. find + sort by mtime avoids the SC2012 ls-1t warning
  # and handles non-alphanumeric filenames correctly.
  bak="$(find "$TARGET_SETTINGS".bak-* -maxdepth 0 -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | awk '{sub(/^[0-9.]+ /, ""); print}')"
  if [[ -n "$bak" ]]; then
    log "==> restoring settings from $bak"
    mv "$bak" "$TARGET_SETTINGS"
  else
    log "WARN: no backup found; leaving $TARGET_SETTINGS as-is"
    log "      to strip hooks manually: jq 'del(.hooks)' $TARGET_SETTINGS"
  fi
else
  log "==> $TARGET_SETTINGS does not exist, nothing to restore"
fi

# ── 2. Remove installed hooks (only files we shipped) ─────────────────
log "==> removing installed hook files"
PACK_HOOKS="$PACK_DIR/hooks"
[[ -f "$PACK_HOOKS/4-fast-rule.sh" ]] && rm -f "$TARGET_HOOKS/4-fast-rule.sh"
[[ -f "$PACK_HOOKS/capture-session-name.py" ]] && rm -f "$TARGET_HOOKS/capture-session-name.py"
[[ -f "$PACK_HOOKS/clash-mode-guard.sh" ]] && rm -f "$TARGET_HOOKS/clash-mode-guard.sh"
[[ -f "$PACK_HOOKS/done-find-downloads.sh" ]] && rm -f "$TARGET_HOOKS/done-find-downloads.sh"
[[ -f "$PACK_HOOKS/fast-iteration-inject.sh" ]] && rm -f "$TARGET_HOOKS/fast-iteration-inject.sh"
[[ -f "$PACK_HOOKS/finish-not-defer.sh" ]] && rm -f "$TARGET_HOOKS/finish-not-defer.sh"
[[ -d "$PACK_HOOKS/fix-uat-env" ]] && rm -rf "$TARGET_HOOKS/fix-uat-env"
[[ -f "$PACK_HOOKS/followup-not-ask.sh" ]] && rm -f "$TARGET_HOOKS/followup-not-ask.sh"
[[ -f "$PACK_HOOKS/followup-spawn-agents.sh" ]] && rm -f "$TARGET_HOOKS/followup-spawn-agents.sh"
[[ -f "$PACK_HOOKS/force-playwright-cli.sh" ]] && rm -f "$TARGET_HOOKS/force-playwright-cli.sh"
[[ -f "$PACK_HOOKS/guard.sh" ]] && rm -f "$TARGET_HOOKS/guard.sh"
[[ -f "$PACK_HOOKS/honest-report-gate.sh" ]] && rm -f "$TARGET_HOOKS/honest-report-gate.sh"
[[ -f "$PACK_HOOKS/keep-going.sh" ]] && rm -f "$TARGET_HOOKS/keep-going.sh"
[[ -f "$PACK_HOOKS/meta-hook-creator.sh" ]] && rm -f "$TARGET_HOOKS/meta-hook-creator.sh"
[[ -f "$PACK_HOOKS/mocks-not-stuck-reminder.sh" ]] && rm -f "$TARGET_HOOKS/mocks-not-stuck-reminder.sh"
[[ -f "$PACK_HOOKS/no-ask-file-followups.sh" ]] && rm -f "$TARGET_HOOKS/no-ask-file-followups.sh"
[[ -f "$PACK_HOOKS/pair-chrome-soft-gate.sh" ]] && rm -f "$TARGET_HOOKS/pair-chrome-soft-gate.sh"
[[ -f "$PACK_HOOKS/playwright-headless.sh" ]] && rm -f "$TARGET_HOOKS/playwright-headless.sh"
[[ -f "$PACK_HOOKS/pop-open-on-ship.sh" ]] && rm -f "$TARGET_HOOKS/pop-open-on-ship.sh"
[[ -f "$PACK_HOOKS/reap-orphan-chrome.sh" ]] && rm -f "$TARGET_HOOKS/reap-orphan-chrome.sh"
[[ -f "$PACK_HOOKS/research-md-no-ask.sh" ]] && rm -f "$TARGET_HOOKS/research-md-no-ask.sh"
[[ -f "$PACK_HOOKS/selfhost-browser-no-ask.sh" ]] && rm -f "$TARGET_HOOKS/selfhost-browser-no-ask.sh"
[[ -f "$PACK_HOOKS/spawn-not-ask.sh" ]] && rm -f "$TARGET_HOOKS/spawn-not-ask.sh"
[[ -f "$PACK_HOOKS/straight-fix-no-ask.sh" ]] && rm -f "$TARGET_HOOKS/straight-fix-no-ask.sh"
[[ -f "$PACK_HOOKS/value-guard-next-step.sh" ]] && rm -f "$TARGET_HOOKS/value-guard-next-step.sh"
[[ -f "$PACK_HOOKS/value-guard.sh" ]] && rm -f "$TARGET_HOOKS/value-guard.sh"
[[ -f "$PACK_HOOKS/value-inject.sh" ]] && rm -f "$TARGET_HOOKS/value-inject.sh"
[[ -f "$PACK_HOOKS/winbrain-gitlab-push.sh" ]] && rm -f "$TARGET_HOOKS/winbrain-gitlab-push.sh"

# ── 3. Defensive cleanup of files from old install layouts ───────────
# These are no longer installed by current install.sh, but users may still
# have them in $HOME/.claude/hooks from a previous install round. Clean
# them unconditionally so uninstall is a true zero state.
log "==> defensive cleanup of archived + contrib files from old installs"
for f in pop-open-on-ship.sh reap-orphan-chrome.solution.sh self-report-fused.sh.retired; do
  [[ -f "$TARGET_HOOKS/$f" ]] && rm -f "$TARGET_HOOKS/$f"
done
[[ -d "$TARGET_HOOKS/fix-uat-env" ]] && rm -rf "$TARGET_HOOKS/fix-uat-env"

log "==> done. Re-login / restart claude-code to pick up changes."
