# claude-hooks-pack

[![CI](https://github.com/liush2yuxjtu/claude-hooks-pack/actions/workflows/ci.yml/badge.svg)](https://github.com/liush2yuxjtu/claude-hooks-pack/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Hooks: 26 active](https://img.shields.io/badge/hooks-26%20active-success)](hooks/)
[![Shell: shellcheck](https://img.shields.io/badge/shellcheck-clean-success)](.shellcheckrc)

Redistributable pack of **user-level Claude Code hooks** extracted from
`~/.claude/hooks/` (source-of-truth on the original machine). 26 active hooks
across 5 lifecycle events, plus 3 archived ("learned-mistakes") scripts and 1
contrib one-off (`fix-uat-env/`), with design rubric + value-cascade template.

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
├── README.md                          # this file
├── LICENSE                            # MIT
├── CHANGELOG.md                       # point-in-time snapshot history (unreleased / 0.0.1)
├── CONTRIBUTING.md                    # rubric §8 self-check + local dev recipe
├── install.sh                         # idempotent installer (validates fragment before merging)
├── uninstall.sh                       # backup-restoring uninstaller (defensive archived-cleanup)
├── bin/
│   └── build-fragment.sh              # run on the SOURCE machine to populate settings/hooks.fragment.json
├── hooks/                             # 26 active (top-level .sh + .py)
│   ├── 4-fast-rule.sh
│   ├── capture-session-name.py
│   ├── ... (24 more — see Hook inventory below)
│   ├── value-guard.sh
│   ├── value-guard-next-step.sh
│   ├── value-inject.sh
│   └── winbrain-gitlab-push.sh
├── hooks/_archive/learned-mistakes/   # 3 archived, NOT installed — kept for teaching
│   ├── INDEX.md
│   ├── pop-open-on-ship.sh
│   ├── reap-orphan-chrome.solution.sh
│   └── self-report-fused.sh.retired
├── contrib/one-offs/fix-uat-env/      # incident-remediation sub-bundle, NOT installed by default
│   ├── TOP-NOTE.md                    # when / where / why this exists
│   ├── README.md
│   ├── apply.sh
│   ├── hook.sh
│   └── test.sh
├── docs/
│   ├── HOOK_DESIGN_RUBRIC.md          # 8-section rubric + 8-question self-check
│   └── value-guard-template.md        # VALUE-cascade prompt template (root → L1-L4 → leaves)
├── settings/
│   └── hooks.fragment.json            # the `hooks` block to merge into ~/.claude/settings.json
├── data/
│   └── redlines.tsv                   # redline table consumed by guard.sh
├── test/
│   └── straight-fix-no-ask.test.sh    # §5 rubric compliance harness
└── .github/
    ├── workflows/ci.yml               # shellcheck + JSON validate + bash test + install dry-run
    ├── ISSUE_TEMPLATE/
    │   ├── bug_report.md
    │   └── feature_request.md
    └── PULL_REQUEST_TEMPLATE.md
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

### UserPromptSubmit (9)
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

## Archived (NOT installed; reference material only)

These scripts live under `hooks/_archive/learned-mistakes/` with an
`INDEX.md` explaining each incident. `install.sh` excludes `*.retired`,
`*.solution`, and `*.archive.*` from its install glob, so they are never
copied into `~/.claude/hooks/`. To reactivate, just `git mv` back to
`hooks/` and add an entry in `settings/hooks.fragment.json`.

- **`pop-open-on-ship.sh`** — wrong-Chrome auto-pop pain (2026-06-xx). Replaced by `pair-chrome pop-open` invoked manually by the agent.
- **`reap-orphan-chrome.solution.sh`** — reference run-script. The bare hook `reap-orphan-chrome.sh` only points at this as a manual remediation; never wires it.
- **`self-report-fused.sh.retired`** — always-on VALUE reminder that got absorbed into noise. Superseded by `value-guard*.sh` (scoped to "next-step" / "要不要").

## Contrib one-offs (NOT installed; project- or incident-specific)

- **`contrib/one-offs/fix-uat-env/`** — frozen incident-remediation for a `win_brain` UAT env. Has its own `TOP-NOTE.md` explaining the incident + portability. Not installed by `install.sh` — see [CONTRIBUTING.md](./CONTRIBUTING.md#one-off-contribs) for how to enable.

## First-time source-machine setup

The shipped `settings/hooks.fragment.json` is intentionally all-null
(safety placeholder, not data loss). To populate it on the SOURCE machine:

```bash
# Run once on the machine whose ~/.claude/settings.json has the real wiring.
bash bin/build-fragment.sh > settings/hooks.fragment.json

# Commit + push. install.sh on other machines then has a real payload to
# merge (instead of aborting with "fragment is empty").
git add settings/hooks.fragment.json
git commit -m "frag: extract real hooks block from source machine"
git push
```

If you just `bash install.sh` without populating the fragment first,
install will copy all hook files but **abort the merge step** with clear
instructions pointing here.

## Design references

- `docs/README.md` — documentation index organized by tutorial, how-to,
  reference, and explanation.
- `docs/tutorial-first-install.md` — first install walkthrough with dry run,
  settings safety, restart, rollback, and baseline checks.
- `docs/how-to.md` — task recipes for installing, refreshing source snapshots,
  adding hooks, editing redlines, and uninstalling.
- `docs/reference.md` — repository layout, lifecycle events, installer
  behavior, settings merge rules, and verification commands.
- `docs/explanation.md` — rationale for source-machine snapshots, empty
  fragments, silent nudges, archives, and contrib one-offs.
- `docs/HOOK_DESIGN_RUBRIC.md` — 8-section rubric + 8-question self-check
  that every new hook should pass. Existing hooks self-score in appendix A.
- `docs/value-guard-template.md` — VALUE-cascade prompt template (root →
  L1-L4 → 7 leaves) used by `value-guard.sh` and `value-guard-next-step.sh`.
- `data/redlines.tsv` — TSV of `tool<TAB>regex<TAB>action<TAB>reason` rows
  consumed by `guard.sh`. Edit / extend at install time.

## Provenance

Source machine: `~/.claude/hooks/` on the original developer's macOS box.
Snapshot date: 2026-07-02. The pack is a **point-in-time mirror** — when
the source evolves, re-run `bin/build-fragment.sh` and `cp -p` the changed
hook files over this pack before re-committing.

## Development

See [CONTRIBUTING.md](./CONTRIBUTING.md) for the rubric §8 self-check new
hooks must pass, and [CHANGELOG.md](./CHANGELOG.md) for round-by-round
history.

## License

MIT. See `LICENSE`.
