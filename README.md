# claude-hooks-pack

Redistributable pack of **user-level Claude Code hooks** extracted from
`~/.claude/hooks/` (source-of-truth on the original machine). 27 active hooks
across 5 lifecycle events, plus 3 dormant scripts and 1 sub-bundle
(`fix-uat-env/`), with design rubric and value-cascade template.

**🌏 中文版:** [README.zh-CN.md](./README.zh-CN.md) — 含一键复制发给 LLM 的"逐个解释 + 选择性安装"提示词。

## Install

```bash
# from the repo root
bash install.sh                  # copies hooks + merges settings.json
bash install.sh --dry-run        # preview, no writes
bash install.sh --no-settings    # only copy hook files
```

`install.sh` will:

1. Copy all `.sh` / `.py` files from `./hooks/` into `~/.claude/hooks/`.
2. Back up your existing `~/.claude/settings.json` to
   `~/.claude/settings.json.bak-<UTC>` and merge the `hooks` block from
   `./settings/hooks.fragment.json`.
3. Copy the `redlines.tsv` data file (used by `guard.sh`) into
   `~/.claude/hooks/`.

Restart `claude-code` (or start a new session) to pick up the wiring.

## Uninstall

```bash
bash uninstall.sh
```

Restores `~/.claude/settings.json` from the most-recent backup and removes
every hook file this pack shipped.

## Layout

```
claude-hooks-pack/
├── README.md                    # this file
├── LICENSE                      # MIT
├── install.sh                   # idempotent installer
├── uninstall.sh                 # backup-restoring uninstaller
├── hooks/                       # 27 active + 3 dormant + 1 sub-bundle
│   ├── 4-fast-rule.sh
│   ├── capture-session-name.py
│   ├── clash-mode-guard.sh
│   ├── done-find-downloads.sh
│   ├── fast-iteration-inject.sh
│   ├── finish-not-defer.sh
│   ├── fix-uat-env/             # sub-bundle (hook.sh + apply.sh + test.sh + README.md)
│   ├── followup-not-ask.sh
│   ├── followup-spawn-agents.sh
│   ├── force-playwright-cli.sh
│   ├── guard.sh
│   ├── honest-report-gate.sh
│   ├── keep-going.sh
│   ├── meta-hook-creator.sh
│   ├── mocks-not-stuck-reminder.sh
│   ├── no-ask-file-followups.sh
│   ├── pair-chrome-soft-gate.sh
│   ├── playwright-headless.sh
│   ├── pop-open-on-ship.sh            [dormant]
│   ├── reap-orphan-chrome.sh
│   ├── reap-orphan-chrome.solution.sh [dormant, reference]
│   ├── research-md-no-ask.sh
│   ├── self-report-fused.sh.retired   [dormant]
│   ├── selfhost-browser-no-ask.sh
│   ├── spawn-not-ask.sh
│   ├── straight-fix-no-ask.sh
│   ├── value-guard-next-step.sh
│   ├── value-guard.sh
│   ├── value-inject.sh
│   └── winbrain-gitlab-push.sh
├── docs/
│   ├── HOOK_DESIGN_RUBRIC.md     # rubric for designing new hooks (8 § / 8-question self-check)
│   └── value-guard-template.md   # VALUE-cascade prompt template (root → L1-L4 → leaves)
├── settings/
│   └── hooks.fragment.json       # the `hooks` block to merge into ~/.claude/settings.json
├── data/
│   └── redlines.tsv              # redline table consumed by guard.sh
└── test/
    └── straight-fix-no-ask.test.sh   # test harness for §5 rubric compliance
```

## Hook inventory by lifecycle event

### SessionStart (1)
| Hook | What it does |
|---|---|
| `capture-session-name.py` | Capture session identifier into `state/` for downstream correlation. |

### SubagentStart (1)
| Hook | What it does |
|---|---|
| inline `echo` | Injects `CLAUDE_REDLINE_ENFORCE=1` into the spawned subagent's env. |

### UserPromptSubmit (10)
| Hook | Trigger shape | Purpose |
|---|---|---|
| `mocks-not-stuck-reminder.sh` | `/to-prd` / plan / issue-breakdown | Reminder: ship mocks to unblock downstream parallel agents. |
| `research-md-no-ask.sh` | `_RESEARCH.md` filename | Stop asking whether to commit/delete harness research files. |
| `spawn-not-ask.sh` | "what to do next / should I" pattern | Spawn non-blocking subagents, don't ask the user. |
| `fast-iteration-inject.sh` | "1-day / 2-hour / no-HITL / feedback" | Bias answer toward speed + shipping + feedback latency. |
| `selfhost-browser-no-ask.sh` | self-host / browser e2e / intranet | Just do the job in the right browser mode. |
| `value-inject.sh` | always-on | Reads the per-session reminder written by Stop hooks, injects as `additionalContext`. |
| `reap-orphan-chrome.sh` | keyword | Pointer note: "run `reap-orphan-chrome.solution.sh`". |
| `pair-chrome-soft-gate.sh` | browser / UAT / visible-Chrome | Soft nudge toward headless `playwright-cli`. |
| `done-find-downloads.sh` | "Done / Finished / 搞定" | Surface `~/Downloads` changes as turn context. |
| `fix-uat-env/hook.sh` | UAT / env-fix context | Sub-bundle for fixing broken UAT env. |

### PreToolUse (5)
| Matcher | Hook | Purpose |
|---|---|---|
| `Bash` | `clash-mode-guard.sh` | HARD block on changes to global proxy / TUN / SOCKS. |
| `Bash\|Edit\|Write\|MultiEdit` | `guard.sh` | Redline engine — block on `redlines.tsv` matches. |
| `mcp__plugin_playwright_playwright__.*` | `force-playwright-cli.sh` | Force route through `playwright-cli` skill. |
| `Bash\|Skill` | `playwright-headless.sh` | Soft-gate to prefer headless browser mode. |
| `Bash` | `winbrain-gitlab-push.sh` | Project-scoped lesson (win_brain) for GitLab push retries. |

### Stop (10)
| Hook | Trigger shape | Purpose |
|---|---|---|
| `4-fast-rule.sh` | always-on | Reinforce the standing 4-FAST rule on every stop. |
| `value-guard.sh` | always-on | Always-on reminder: VALUE cascade → self-resolve before HITL. |
| `value-guard-next-step.sh` | 140 trigger words + ☐×3+ | Scold "next-step menu / 要不要 / 等你说" anti-patterns. |
| `meta-hook-creator.sh` | "create / design new hook" | Inject HOOK_DESIGN_RUBRIC §8 self-check before writing hooks. |
| `followup-not-ask.sh` | "follow-up issue?" | Stop asking whether to file residual problems as follow-up. |
| `followup-spawn-agents.sh` | bare "followup / follow up" | BLOCK stop, dispatch parallel agents to resolve. |
| `straight-fix-no-ask.sh` | "proposal / next round / 要不要" anti-pattern | Stop hook scolds ask-and-defer ending, force same-turn fix. |
| `keep-going.sh` | checkpoint-style stop | Force continuation until DOD / hard block / irreversible. |
| `honest-report-gate.sh` | "finished" claim with hedges | Block stop if report doesn't honestly reflect state. |
| `finish-not-defer.sh` | "scope-shedding / 留作增量" | Block stop if agent punts work into "future increment". |

## Dormant (not wired in the source `settings.json`)

These exist on disk but are not registered in the original settings.json —
kept here so you can wire them up if needed:

- `pop-open-on-ship.sh` — was unwired on 2026-06-xx (wrong-Chrome auto-pop pain).
- `reap-orphan-chrome.solution.sh` — reference run-script, not a hook itself.
- `self-report-fused.sh.retired` — superseded by `value-guard*.sh` family.

## Design references

- `docs/HOOK_DESIGN_RUBRIC.md` — 8-section rubric + 8-question self-check
  that every new hook should pass. Existing hooks self-score in appendix A.
- `docs/value-guard-template.md` — VALUE-cascade prompt template (root →
  L1-L4 → 7 leaves) used by `value-guard.sh` and `value-guard-next-step.sh`.
- `data/redlines.tsv` — TSV of `tool<TAB>regex<TAB>action<TAB>reason` rows
  consumed by `guard.sh`. Edit / extend at install time.

## Provenance

Source machine: `~/.claude/hooks/` on the original developer's macOS box.
Snapshot date: 2026-07-02. The pack is a **point-in-time mirror** — when
the source evolves, re-run the inventory step (or just `cp -p` the new
files over this pack) before re-committing.

## License

MIT. See `LICENSE`.