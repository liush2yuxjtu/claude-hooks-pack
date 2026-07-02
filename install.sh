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
    printf '[dry-run]'
    for arg in "$@"; do
      printf ' %q' "$arg"
    done
    printf '\n'
  else
    "$@"
  fi
}

# ── 1. Copy hook files ─────────────────────────────────────────────────
log "==> copying hooks to $TARGET_HOOKS"
mkdir -p "$TARGET_HOOKS/fix-uat-env"
for f in "$HOOKS_SRC"/*.sh "$HOOKS_SRC"/*.py; do
  base="$(basename "$f")"
  # Archived / retired scripts are kept under hooks/_archive/ for reference,
  # but install.sh MUST NOT copy them into the user's hooks dir.
  case "$base" in
    *.retired|*.solution|*.archive.*) continue ;;
  esac
  run cp -p "$f" "$TARGET_HOOKS/$base"
  run chmod +x "$TARGET_HOOKS/$base"
done
# NOTE: hooks/fix-uat-env/ was moved to contrib/one-offs/fix-uat-env/.
# It is NOT installed by default — see contrib/one-offs/fix-uat-env/TOP-NOTE.md.

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
    log "==> validating + merging settings fragment"
    run python3 - "$TARGET_SETTINGS" "$SETTINGS_SRC" <<'PYEOF'
import json, sys, pathlib

target, fragment = sys.argv[1], sys.argv[2]
events = ["SubagentStart", "UserPromptSubmit", "PreToolUse", "SessionStart", "Stop"]

# 1. Read existing target (preserve anything user already has). If it isn't valid
#    JSON, don't touch it — log + skip the merge rather than destroying state.
target_path = pathlib.Path(target)
data = {}
if target_path.exists():
    try:
        data = json.loads(target_path.read_text())
    except json.JSONDecodeError as e:
        print(f"[install.sh] WARN: {target} is not valid JSON ({e}) — leaving untouched", file=sys.stderr)
        sys.exit(0)
if not isinstance(data, dict):
    print(f"[install.sh] WARN: {target} is not a JSON object — leaving untouched", file=sys.stderr)
    sys.exit(0)

# 2. Read fragment and count hook entries per event.
frag = json.loads(pathlib.Path(fragment).read_text())
counts = {ev: len(frag.get(ev) or []) for ev in events}
total = sum(counts.values())

# 3. Safety check: if the fragment is empty, REFUSE to merge. An empty
#    fragment would overwrite the user's existing keys with null and wipe
#    their wiring silently. Tell the user how to fix it (build-fragment.sh).
if total == 0:
    print("[install.sh] ERROR: settings/hooks.fragment.json is empty (0 hook entries across 5 events).", file=sys.stderr)
    print("[install.sh] ERROR: NOT merging — would wipe your existing wiring with all-null events.", file=sys.stderr)
    print("[install.sh] FIX:", file=sys.stderr)
    print("[install.sh]   1. On the SOURCE machine (where you originally developed this pack), run:", file=sys.stderr)
    print("[install.sh]        bash bin/build-fragment.sh  > settings/hooks.fragment.json", file=sys.stderr)
    print("[install.sh]   2. Commit the populated fragment and re-run install.sh.", file=sys.stderr)
    print("[install.sh] Your existing wiring is preserved. Hook files were already copied in step 1.", file=sys.stderr)
    sys.exit(0)

# 4. Non-destructive merge: only overwrite events the fragment defines AND
#    only with non-null payloads. This preserves any user customization in
#    events the fragment does not cover.
merged = 0
covered_events = 0
for ev in events:
    if ev in frag and frag[ev] is not None:
        data[ev] = frag[ev]
        merged += counts[ev]
        covered_events += 1

target_path.write_text(json.dumps(data, indent=2, ensure_ascii=False))
print(f"[install.sh] merged {merged} hook entries across {covered_events} lifecycle events")
PYEOF
  fi
fi

# ── 3. Summary ────────────────────────────────────────────────────────
active_count="$(find "$HOOKS_SRC" -maxdepth 1 -type f \( -name '*.sh' -o -name '*.py' \) ! -name '*.retired' ! -name '*.solution' ! -name '*.archive.*' | wc -l | tr -d ' ')"
log "==> done"
log "    installed hooks: $active_count (top-level of hooks/ + captured session-name.py)"
log "    archived (not installed): hooks/_archive/learned-mistakes/  (reference material only)"
log "    contrib  (not installed): contrib/one-offs/fix-uat-env/      (one-off incident remediation)"
log "    next restart of claude-code picks up the new wiring"