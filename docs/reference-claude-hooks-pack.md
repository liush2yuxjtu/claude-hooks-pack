# claude-hooks-pack reference

`claude-hooks-pack` is a distributable repository for user-level Claude Code
hooks. It copies hook scripts into `~/.claude/hooks/`, optionally merges a
`hooks` settings fragment into `~/.claude/settings.json`, and keeps archived
or incident-specific scripts outside the default install path.

## Repository layout

| Path | Purpose |
|---|---|
| `install.sh` | Copies active hook files and optionally merges `settings/hooks.fragment.json`. |
| `uninstall.sh` | Restores the newest settings backup and removes files shipped by the pack. |
| `bin/build-fragment.sh` | Extracts the real `hooks` block from the source machine's `~/.claude/settings.json`. |
| `hooks/` | Active top-level `.sh` and `.py` hooks installed by `install.sh`. |
| `hooks/_archive/learned-mistakes/` | Archived scripts and notes. Not installed by current `install.sh`. |
| `contrib/one-offs/fix-uat-env/` | Frozen incident remediation bundle. Not installed by current `install.sh`. |
| `settings/hooks.fragment.json` | Merge payload for Claude Code lifecycle hook wiring. Ships empty by design. |
| `data/redlines.tsv` | Redline table copied to `~/.claude/hooks/redlines.tsv` for `guard.sh`. |
| `test/straight-fix-no-ask.test.sh` | Shell test harness for `straight-fix-no-ask.sh`. |
| `.github/workflows/ci.yml` | CI for shellcheck, JSON validation, bash tests, and install dry-run. |

## Installer

### Command

```bash
bash install.sh [--dry-run] [--no-settings]
```

### Options

| Option | Effect |
|---|---|
| `--dry-run` | Prints file operations without writing hook files or settings changes. |
| `--no-settings` | Copies hook files and `data/redlines.tsv`, but skips the settings merge. |
| `-h`, `--help` | Prints the usage block from the script header and exits. |

Any other argument exits with status `2`.

### Installed files

`install.sh` copies every top-level `hooks/*.sh` and `hooks/*.py` file except
filenames ending in `.retired`, `.solution`, or `.archive.*`. It marks copied
hook files executable.

It also copies:

```text
data/redlines.tsv -> ~/.claude/hooks/redlines.tsv
```

The installer creates `~/.claude/hooks/redlines.d/`, but the user populates
that directory themselves.

### Settings merge

Unless `--no-settings` is passed, the installer reads
`settings/hooks.fragment.json`, validates it as JSON, and counts entries under
these lifecycle events:

```text
SubagentStart
UserPromptSubmit
PreToolUse
SessionStart
Stop
```

If the total entry count is `0`, the script refuses to merge. This preserves
the user's existing `~/.claude/settings.json` instead of replacing hook wiring
with empty lifecycle keys.

If the fragment contains entries, `install.sh` backs up the target settings
file to:

```text
~/.claude/settings.json.bak-<UTC>
```

It then overwrites only lifecycle keys that exist in the fragment and are not
`null`.

## Uninstaller

### Command

```bash
bash uninstall.sh
```

### Behavior

`uninstall.sh` restores the newest file matching:

```text
~/.claude/settings.json.bak-*
```

If no backup exists, it leaves `~/.claude/settings.json` unchanged and prints a
manual `jq 'del(.hooks)'` hint.

It removes hook files shipped by this pack from `~/.claude/hooks/`, then also
removes archived and contrib files that old install layouts may have copied
before those files moved out of the active install path.

## Source-machine fragment builder

### Command

```bash
bash bin/build-fragment.sh > settings/hooks.fragment.json
```

Run this on the source machine, meaning the machine whose
`~/.claude/settings.json` has the real hook wiring.

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Fragment was written to stdout. |
| `1` | `~/.claude/settings.json` is missing, has no `hooks` key, or has an empty `hooks` key. |
| `2` | `~/.claude/settings.json` is invalid JSON or has an unexpected top-level shape. |

### Output shape

The builder keeps only the five Claude Code lifecycle events and drops
machine-local settings, permissions, environment values, and other keys.

## Active hook inventory

The current active install set has 26 top-level hooks:

```text
4-fast-rule.sh
capture-session-name.py
clash-mode-guard.sh
done-find-downloads.sh
fast-iteration-inject.sh
finish-not-defer.sh
followup-not-ask.sh
followup-spawn-agents.sh
force-playwright-cli.sh
guard.sh
honest-report-gate.sh
keep-going.sh
meta-hook-creator.sh
mocks-not-stuck-reminder.sh
no-ask-file-followups.sh
pair-chrome-soft-gate.sh
playwright-headless.sh
reap-orphan-chrome.sh
research-md-no-ask.sh
selfhost-browser-no-ask.sh
spawn-not-ask.sh
straight-fix-no-ask.sh
value-guard-next-step.sh
value-guard.sh
value-inject.sh
winbrain-gitlab-push.sh
```

Lifecycle wiring is not inferred from the files themselves. It comes from
`settings/hooks.fragment.json` after the source machine populates that file.

## Current settings fragment

The repository currently ships this fragment state:

```text
SubagentStart: null
UserPromptSubmit: null
PreToolUse: null
SessionStart: null
Stop: null
```

That means `install.sh` can copy hook files, but the default settings merge is
refused until the source machine runs `bin/build-fragment.sh` and commits a
populated fragment.

## Tests and checks

### Local checks

```bash
pre-commit run --all-files
bash test/straight-fix-no-ask.test.sh
```

The test script expects the hook to exist at:

```text
~/.claude/hooks/straight-fix-no-ask.sh
```

Run `bash install.sh --no-settings` first when testing from a clean machine.

### CI checks

`.github/workflows/ci.yml` runs:

| Job | What it checks |
|---|---|
| `shellcheck` | Strict shellcheck for installer scripts and error-level shellcheck for active hooks and contrib scripts. |
| `json-validate` | `settings/hooks.fragment.json` parses as JSON. |
| `bash-test` | Installs hooks into a temporary `HOME` and runs `straight-fix-no-ask` tests. |
| `install-dryrun` | Syntax-checks shell scripts and verifies dry-run install output. |

## Related

- [Getting started with claude-hooks-pack](tutorial-getting-started.md)
- [How to install and manage the hook pack](how-to-install-and-manage-hooks.md)
- [Why this hook pack is structured this way](explanation-hook-pack-design.md)
