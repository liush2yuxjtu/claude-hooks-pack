# fix-uat-env

> User-level Claude keyword-trigger hook + idempotent env-patch script.

## Trigger keywords (UserPromptSubmit)

The hook fires on any of:

| Pattern | Type |
|---|---|
| `/fix-uat-env` | slash command |
| `[[fix-uat-env]]` | XML marker |
| `<<fix-uat-env>>` | XML marker |
| `fix-zhangqing-uat` | hyphenated compound |
| `zhangqing` + `fix` co-occurs on same line | co-occurrence |
| `reapply uat fix` (case-insensitive) | natural language |

## When NOT to fire

- prompt mentions `fix` or `uat` alone (no zhangqing or marker)
- prompt mentions `zhangqing` alone (no `fix`)
- empty prompt
- `CLAUDE_FIX_UAT_ENV_DISABLED=1` is set

## What the hook does

1. Silent — does not block, does not pollute stdout (rubric §3)
2. Appends a per-session reminder to `~/.claude/hooks/logs/fix-uat-env-<session_id>.md` so the assistant knows to run `apply.sh`
3. Logs to `~/.claude/hooks/logs/fix-uat-env-audit.jsonl` (rubric §6)

## What apply.sh does (idempotent)

1. **scripts/serve.sh** — ensures `DEER_FLOW_AUTH_DISABLED_USER_EMAIL` is forwarded to the uvicorn + frontend child processes (so dev-bypass greeting shows the real name, not `e2e`)
2. **config.local.yaml** — ensures `agents_api.enabled: true` (so custom agents like `fmcg-diagnosis-test` reach the UI dropdown)
3. **backend/.deer-flow/groups/zhangqing-group/extensions_config.json** — ensures the FMCG skills (rd-overall-diagnosis, store-diagnosis, etc.) are `enabled: true`
4. **backend/.deer-flow/agents/fmcg-diagnosis-test/SOUL.md** — creates the agent SOUL if missing (boilerplate that matches what `make dev` produces)

Re-running is safe. All four steps are no-op on a clean checkout.

## Run

```bash
# Trigger the hook by typing one of the keywords, OR call directly:
bash ~/.claude/hooks/fix-uat-env/apply.sh

# Test matrix (5 positive + 4 negative + 1 escape):
bash ~/.claude/hooks/fix-uat-env/test.sh
```

## Self-check vs HOOK_DESIGN_RUBRIC.md §8

| Item | Status |
|---|---|
| 1. Trigger list ≥ 100 OR ≤ 100 with header reason | ✓ 6 patterns; header documents "intentionally small: each pattern is precise, false positive risk low" |
| 2. ≥ 1 structural trigger (non-plaintext) | ✓ 3 structural markers (`/...`, `[[...]]`, `<<...>>`); 1 compound (`fix-zhangqing-uat`) |
| 3. Independent harness + ≥ 3 positive + ≥ 3 negative | ✓ `test.sh` runs 5 positive + 4 negative + 1 escape-hatch case |
| 4. Default silent approve, hit inject (not block) | ✓ exit 0 always; no stdout; per-session reminder is the only side effect on hit |
| 5. Escape hatch `CLAUDE_<NAME>_DISABLED=1` | ✓ `CLAUDE_FIX_UAT_ENV_DISABLED=1` |
| 6. Header references VALUE.md / LEAVES.md | ✓ header cites `VALUE.md §L1/L3` and `LEAVES.md A_AGENT_VALUE_EXPECT` |
| 7. Audit JSONL + per-session log paths in header | ✓ `~/.claude/hooks/logs/fix-uat-env-audit.jsonl` and `...-fix-uat-env-<session>.md` |
| 8. Settings.json wiring order | ✓ appended to end of `UserPromptSubmit` hooks (no deps on earlier hooks) |

## value-source

- `VALUE.md` §L1 授权 = "你看着办" — agent self-resolves, hook does not block
- `VALUE.md` §L3 默认动作 = ship + 出证据 — apply.sh always logs timestamped evidence
- `LEAVES.md` A_AGENT_VALUE_EXPECT — agent sees the per-session reminder, decides to run apply.sh
- `user-level CLAUDE.md` "MUST use a new API" + "MUST fix" — env-level fixes should be automated and reproducible

## Files

```
~/.claude/hooks/fix-uat-env/
  ├── hook.sh       # UserPromptSubmit entry, ~80 lines
  ├── apply.sh      # Idempotent 4-step patch, ~100 lines
  ├── test.sh       # 5+4+1 test matrix
  └── README.md     # this file
```
