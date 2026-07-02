#!/usr/bin/env bash
# ~/.claude/hooks/clash-mode-guard.sh
# PreToolUse HARD guard — unconditionally blocks any Bash command that would
# change the Clash/mihomo GLOBAL proxy mode, disable TUN, kill the proxy, or
# turn off the system SOCKS/HTTP proxy.
#
# WHY: Claude Code itself reaches the Anthropic API *through* this proxy. If an
# agent flips mihomo to mode=direct / global, disables TUN, or kills verge-mihomo
# "to test a clean connection", the API call path dies mid-task and the agent
# breaks with `403 Request not allowed` / connection errors. The user has been
# bitten by this. This guard makes that class of action impossible.
#
# Scope: this guard does NOT honor CLAUDE_REDLINE_ENFORCE — it ALWAYS enforces,
# for the main agent AND forks, because the failure mode (self-severing the API
# link) is identical regardless of who runs the command.
#
# Allowed: READING clash state (GET /configs, /rules, /proxies). Switching the
# *selected node* inside a proxy group (PUT /proxies/<group>) is also fine — that
# does not change global mode and keeps traffic flowing.
#
# Escape hatch (user explicitly wants it, this turn): prefix the command with
#   CLASH_GUARD_OVERRIDE=1
# e.g.  CLASH_GUARD_OVERRIDE=1 curl -X PATCH .../configs -d '{"mode":"direct"}'
#
# Protocol: exit 2 = block (stderr shown to model), exit 0 = allow. Fails open.

set -uo pipefail

LOG="${HOME}/.claude/hooks/clash-mode-guard.log"

# Fail open if jq missing — never break the session over a guard.
command -v jq >/dev/null 2>&1 || exit 0

input=$(cat)
[[ -z "$input" ]] && exit 0

tool=$(jq -r '.tool_name // ""' <<<"$input" 2>/dev/null || echo "")
[[ "$tool" == "Bash" ]] || exit 0

cmd=$(jq -r '.tool_input.command // ""' <<<"$input" 2>/dev/null || echo "")
[[ -z "$cmd" ]] && exit 0

# User opt-out for this single command.
if grep -qE 'CLASH_GUARD_OVERRIDE=1' <<<"$cmd"; then
  exit 0
fi

reason=""

# --- 1) Clash controller config WRITE that changes mode or TUN -------------
# Block only WRITE verbs to /configs that touch mode/tun/enable. GET stays free.
if grep -qiE '/configs([?"'"'"' ]|$)' <<<"$cmd" \
   && grep -qiE '(-X|--request)[[:space:]]*(PATCH|PUT|POST)' <<<"$cmd" \
   && grep -qiE '"?(mode|tun|enable)"?[[:space:]]*[:=]' <<<"$cmd"; then
  reason="changes Clash global mode / TUN via the external-controller /configs endpoint"
fi

# Even without an explicit -X, a data body that sets a global mode is fatal.
if [[ -z "$reason" ]] && grep -qiE '"mode"[[:space:]]*:[[:space:]]*"(direct|global|script)"' <<<"$cmd"; then
  reason="sets Clash global mode to direct/global/script (severs Claude's API proxy path)"
fi

# Disabling TUN in any data body.
if [[ -z "$reason" ]] && grep -qiE '"tun"[[:space:]]*:[[:space:]]*\{[^}]*"enable"[[:space:]]*:[[:space:]]*false' <<<"$cmd"; then
  reason="disables Clash TUN (severs Claude's API proxy path)"
fi

# --- 2) Killing / stopping the proxy process ------------------------------
if [[ -z "$reason" ]] && grep -qiE '(pkill|killall|kill[[:space:]]+-?[0-9A-Za-z]*[[:space:]])([^|;&]*)(mihomo|verge-mihomo|clash-verge|[Cc]lash)' <<<"$cmd"; then
  reason="kills the Clash/mihomo process (severs Claude's API proxy path)"
fi
if [[ -z "$reason" ]] && grep -qiE 'launchctl[[:space:]]+(unload|bootout|stop|disable)[^|;&]*([Cc]lash|mihomo)' <<<"$cmd"; then
  reason="stops the Clash service via launchctl (severs Claude's API proxy path)"
fi
if [[ -z "$reason" ]] && grep -qiE 'osascript[^|;&]*quit[^|;&]*[Cc]lash' <<<"$cmd"; then
  reason="quits Clash Verge via AppleScript (severs Claude's API proxy path)"
fi

# --- 3) Turning OFF the system proxy --------------------------------------
if [[ -z "$reason" ]] && grep -qiE 'networksetup[[:space:]]+-set(socks|web|secureweb)proxystate[[:space:]]+[^[:space:]]+[[:space:]]+(off|Off|OFF)' <<<"$cmd"; then
  reason="turns off the macOS system proxy (severs Claude's API proxy path)"
fi

[[ -z "$reason" ]] && exit 0

# Log the block.
mkdir -p "$(dirname "$LOG")"
{
  echo "--- $(date -u +%FT%TZ) BLOCKED"
  echo "  reason: $reason"
  echo "  cmd: ${cmd:0:400}"
} >> "$LOG" 2>/dev/null || true

# Emit a clear, actionable block to the model.
cat >&2 <<EOF
🛑 BLOCKED by clash-mode-guard: this command $reason.

Claude Code reaches the Anthropic API THROUGH this proxy. Changing global mode,
disabling TUN, or killing mihomo will break THIS agent mid-task (403 / API error).

Do NOT change the global proxy to test connectivity. Use one of these instead:
  • Read-only state checks are fine: GET /configs, /rules, /proxies.
  • To route ONE host around the proxy, add a targeted DIRECT *rule* (rule-provider
    / RULE in the Clash config) — never flip the global mode.
  • Switch the selected node inside a group (PUT /proxies/<group>) — keeps traffic up.
  • Reach an intranet/DB host via the company relay (SOCKS5), not by disabling Clash.

If you TRULY mean to change it this turn, re-run prefixed with CLASH_GUARD_OVERRIDE=1.
EOF
exit 2
