#!/usr/bin/env bash
# ~/.claude/hooks/winbrain-gitlab-push.sh
# PreToolUse hook. Project-scoped (win_brain ONLY) lesson, captured 2026-06-26
# from a real push that took 5 failed attempts before it worked.
#
# THE LESSON (why this hook exists):
#   Off-network `git push` to the winchannel internal GitLab
#   (gitlab008.its.winchannel.net, repo datascience/win_ontology/win_brain)
#   FAILS the naive way for TWO compounding reasons:
#     1) The login shell carries a corp proxy `ALL_PROXY=socks5://127.0.0.1:7897`
#        (+ HTTP_PROXY=http://127.0.0.1:7897) that SILENTLY HIJACKS git/curl and
#        yields fake `000` / "Could not resolve host" — looks like the tunnel is
#        broken when it is not.
#     2) `/connect-company`'s SOCKS proxy (127.0.0.1:1080) reaches the intranet
#        for browser/API, but per its own docs it does NOT carry `git push`.
#   The combination wasted 5 attempts (http.proxy / ALL_PROXY / socks5h /
#   sandbox-off all still failed) until the working path was found.
#
#   THE WORKING PATH — push via an ssh -L relay forward through macmini, with the
#   hijacking proxy env stripped:
#     ssh -f -N -o ExitOnForwardFailure=yes -L 8080:gitlab008.its.winchannel.net:80 macmini
#     PUSH_URL=$(git remote get-url gitlab | sed 's#gitlab008.its.winchannel.net#127.0.0.1:8080#')
#     env -u ALL_PROXY -u HTTP_PROXY -u HTTPS_PROXY -u all_proxy -u http_proxy -u https_proxy \
#         no_proxy=127.0.0.1 git push "$PUSH_URL" <branch>
#     lsof -ti tcp:8080 | xargs -r kill   # tear the temp forward down after
#   Prereq: `/connect-company up` (Tailscale up, `ssh macmini` reachable).
#
# This hook BLOCKS the naive `git push gitlab …` so the next session does not
# repeat the 5-attempt fumble — it surfaces the working recipe instead.
#
# Scope: win_brain ONLY — fires only when cwd is under the win_brain project
#   (path matches winbrain / win_brain) AND the push targets the internal gitlab.
#   Allows the push through untouched once it already uses the relay forward
#   (127.0.0.1:8080 / localhost:8080) — that IS the fixed form.
#
# Outcomes:
#   exit 2  = BLOCK; stderr surfaced to the model as the reason (recipe).
#   exit 0  = pass-through (not a naive internal-gitlab push, or already fixed,
#             or not in the win_brain project).
#
# Escape hatch: CLAUDE_WINBRAIN_PUSH_OVERRIDE=1 — allow the raw push this turn
#   (e.g. you are on the office LAN and gitlab008 resolves directly).
#
# audit: ~/.claude/hooks/logs/winbrain-gitlab-push.jsonl

set -uo pipefail

[[ "${CLAUDE_WINBRAIN_PUSH_OVERRIDE:-0}" == "1" ]] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

input=$(cat)
[[ -z "$input" ]] && exit 0

tool=$(jq -r '.tool_name // ""' <<<"$input" 2>/dev/null || echo "")
[[ "$tool" != "Bash" ]] && exit 0

cmd=$(jq -r '.tool_input.command // ""' <<<"$input" 2>/dev/null || echo "")
[[ -z "$cmd" ]] && exit 0
cwd=$(jq -r '.cwd // ""' <<<"$input" 2>/dev/null || echo "")

# Scope: win_brain project only (path-based; the local checkout dir is winbrain9).
case "$cwd" in
  *winbrain*|*win_brain*) : ;;
  *) exit 0 ;;
esac

# Only care about a `git push`.
grep -qE '(^|[^[:alnum:]_])git[[:space:]]+push([^[:alnum:]_]|$)' <<<"$cmd" || exit 0

# Only the internal gitlab (remote name `gitlab` or host gitlab008.its.winchannel.net).
grep -qE 'gitlab008\.its\.winchannel\.net|git[[:space:]]+push[[:space:]]+(-[^[:space:]]+[[:space:]]+)*gitlab([[:space:]]|$)' <<<"$cmd" || exit 0

# Already using the relay forward (the fixed form) → allow.
grep -qE '127\.0\.0\.1:8080|localhost:8080|ssh[[:space:]].*-L[[:space:]]*8080' <<<"$cmd" && exit 0

LOG_DIR="$HOME/.claude/hooks/logs"; mkdir -p "$LOG_DIR" 2>/dev/null || true
jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg cmd "$cmd" \
  '{ts:$ts,verdict:"block",cmd:$cmd}' >> "$LOG_DIR/winbrain-gitlab-push.jsonl" 2>/dev/null || true

cat >&2 <<'EOF'
🛑 winbrain-gitlab-push.sh: BLOCK — naive `git push` to win_brain's internal GitLab will fail.

  Two compounding traps (cost 5 failed attempts last time):
   1) shell carries corp proxy ALL_PROXY=socks5://127.0.0.1:7897 → silently
      hijacks git/curl → fake "Could not resolve host" / 000.
   2) /connect-company SOCKS (1080) reaches intranet for browser/API but does
      NOT carry git push.

  DO THIS — push via an ssh -L relay forward through macmini, proxy env stripped:

    bash ~/.claude/skills/connect-company/scripts/connect.sh up   # ensure Tailscale/relay
    ssh -f -N -o ExitOnForwardFailure=yes -L 8080:gitlab008.its.winchannel.net:80 macmini
    PUSH_URL=$(git remote get-url gitlab | sed 's#gitlab008.its.winchannel.net#127.0.0.1:8080#')
    env -u ALL_PROXY -u HTTP_PROXY -u HTTPS_PROXY -u all_proxy -u http_proxy -u https_proxy \
        no_proxy=127.0.0.1 git push "$PUSH_URL" <branch>
    lsof -ti tcp:8080 | xargs -r kill        # tear the temp forward down after

  (Run the push with dangerouslyDisableSandbox; verify with `git ls-remote` via the
   same forward.) Override only if you are on the office LAN: set
   CLAUDE_WINBRAIN_PUSH_OVERRIDE=1.
EOF
exit 2
