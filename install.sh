#!/usr/bin/env bash
# install.sh — copy hooks into ~/.claude/hooks and merge settings fragment.
# Idempotent: re-running overwrites files; already-installed hooks are refreshed.
#
# Usage:
#   bash install.sh                  # install everything
#   bash install.sh --dry-run        # preview, no changes
#   bash install.sh --no-settings    # only copy hook files, don't touch settings.json
#
# Rollback:
#   bash uninstall.sh                 # restore from backup written next to settings.json

set -euo pipefail

DRY_RUN=0
SKIP_SETTINGS=0
for arg in "$@"; do
  case "$arg" in
    --dry-run)      DRY_RUN=1 ;;
    --no-settings)  SKIP_SETTINGS=1 ;;
    -h|--help)
      sed -n '2,12p' "$0"
      exit 0
      ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

PACK_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS_SRC="$PACK_DIR/hooks"
SETTINGS_SRC="$PACK_DIR/settings/hooks.fragment.json"
TARGET_HOOKS="$HOME/.claude/hooks"
TARGET_SETTINGS="$HOME/.claude/settings.json"

log() { printf '[install.sh] %s\n' "$*"; }
run() {
  if (( DRY_RUN )); then
    printf '[dry-run] %s\n' "$*"
  else
    eval "$@"
  fi
}

# ── 1. Copy hook files ─────────────────────────────────────────────────
log "==> copying hooks to $TARGET_HOOKS"
mkdir -p "$TARGET_HOOKS/fix-uat-env"
for f in "$HOOKS_SRC"/*.sh "$HOOKS_SRC"/*.py; do
  base="$(basename "$f")"
  [[ "$base" == "value-guard-template.md" ]] && continue
  run cp -p "$f" "$TARGET_HOOKS/$base"
  run chmod +x "$TARGET_HOOKS/$base"
done
# Sub-bundle
for f in "$HOOKS_SRC/fix-uat-env/"*.sh "$HOOKS_SRC/fix-uat-env/"README.md; do
  base="$(basename "$f")"
  run cp -p "$f" "$TARGET_HOOKS/fix-uat-env/$base"
  [[ "$base" == *.sh ]] && run chmod +x "$TARGET_HOOKS/fix-uat-env/$base"
done

# Data file used by guard.sh
run mkdir -p "$TARGET_HOOKS/redlines.d"
run cp -p "$PACK_DIR/data/redlines.tsv" "$TARGET_HOOKS/redlines.tsv"
# redlines.d is a per-project drop folder; user populates it themselves.

# ── 2. Merge settings.json ────────────────────────────────────────────
if (( SKIP_SETTINGS )); then
  log "==> --no-settings set, skipping settings.json merge"
else
  if [[ ! -f "$SETTINGS_SRC" ]]; then
    log "WARN: settings fragment missing at $SETTINGS_SRC — skipping merge"
  else
    log "==> backing up $TARGET_SETTINGS"
    if [[ -f "$TARGET_SETTINGS" ]]; then
      ts="$(date -u +%Y%m%dT%H%M%SZ)"
      run cp -p "$TARGET_SETTINGS" "$TARGET_SETTINGS.bak-$ts"
    fi
    log "==> merging hooks block"
    run python3 - "$TARGET_SETTINGS" "$SETTINGS_SRC" <<'PYEOF'
import json, sys, pathlib
target, fragment = sys.argv[1], sys.argv[2]
data = json.loads(pathlib.Path(target).read_text()) if pathlib.Path(target).exists() else {}
frag = json.loads(pathlib.Path(fragment).read_text())
events = ["SubagentStart", "UserPromptSubmit", "PreToolUse", "SessionStart", "Stop"]
for ev in events:
    if ev in frag:
        data[ev] = frag[ev]
pathlib.Path(target).write_text(json.dumps(data, indent=2, ensure_ascii=False))
print(f"[install.sh] merged {sum(len(frag.get(e, [])) for e in events)} hook entries")
PYEOF
  fi
fi

# ── 3. Summary ────────────────────────────────────────────────────────
log "==> done"
log "    active hooks: 27 (5 lifecycle events)"
log "    dormant:      pop-open-on-ship.sh, reap-orphan-chrome.solution.sh, self-report-fused.sh.retired"
log "    next restart of claude-code picks up the new wiring"