# How to install and manage the hook pack

Use this guide when you need to install, preview, uninstall, populate the
settings fragment, or run local checks for `claude-hooks-pack`.

## Prerequisites

- macOS or Linux shell with `bash`.
- `python3`, used by `install.sh` and `bin/build-fragment.sh`.
- `jq`, used by several hooks and test harnesses.
- `shellcheck`, `shfmt`, and `pre-commit` if you plan to contribute changes.
- A clone of this repository.

## Install hook files without changing settings

Use this when you want the scripts copied but do not want to merge hook wiring
into `~/.claude/settings.json`.

```bash
bash install.sh --no-settings
```

This copies active top-level hook files to `~/.claude/hooks/`, marks them
executable, and copies `data/redlines.tsv`.

### Verification

```bash
test -x ~/.claude/hooks/straight-fix-no-ask.sh
test -f ~/.claude/hooks/redlines.tsv
```

Both commands should exit with status `0`.

## Preview the install

Use dry-run mode before installing on a machine where you care about the exact
filesystem operations.

```bash
bash install.sh --dry-run --no-settings
```

The output should contain command lines prefixed with:

```text
[dry-run]
```

## Install and merge settings

Use this only after `settings/hooks.fragment.json` contains real lifecycle
wiring from the source machine.

```bash
bash install.sh
```

If the fragment is still empty, the installer copies hook files but refuses the
settings merge with an error that points at `bin/build-fragment.sh`. That is a
safety stop, not a failed file copy.

### Verification

```bash
python3 -m json.tool ~/.claude/settings.json >/dev/null
```

Then restart `claude-code` or open a new session so Claude Code picks up the
new hook wiring.

## Populate the settings fragment on the source machine

Run this only on the machine whose `~/.claude/settings.json` already contains
the real hook wiring.

```bash
bash bin/build-fragment.sh > settings/hooks.fragment.json
```

Review the diff before committing:

```bash
git diff -- settings/hooks.fragment.json
```

The fragment should contain entries under at least one of:

```text
SubagentStart
UserPromptSubmit
PreToolUse
SessionStart
Stop
```

## Uninstall

```bash
bash uninstall.sh
```

This restores the newest `~/.claude/settings.json.bak-*` backup and removes
files shipped by this pack from `~/.claude/hooks/`.

### Verification

```bash
test ! -e ~/.claude/hooks/straight-fix-no-ask.sh
```

If no settings backup exists, `uninstall.sh` leaves the current settings file
alone and prints a manual cleanup hint.

## Run local checks before a PR

Install the hooks into a testable location first:

```bash
bash install.sh --no-settings
```

Then run:

```bash
pre-commit run --all-files
bash test/straight-fix-no-ask.test.sh
```

If you changed or added a hook, also run that hook's specific test script.

## Troubleshooting

### `install.sh` says the settings fragment is empty

This means `settings/hooks.fragment.json` has zero hook entries across the five
lifecycle events. Run `bin/build-fragment.sh` on the source machine and commit
the resulting fragment before trying to merge settings on another machine.

### The test cannot find `~/.claude/hooks/straight-fix-no-ask.sh`

Run:

```bash
bash install.sh --no-settings
```

The test harness calls the installed hook path, not the repository copy.

### `pre-commit` is missing

Install the development tools:

```bash
brew install shellcheck shfmt pre-commit
pre-commit install
```

On Linux, use your package manager for `shellcheck` and `shfmt`, then install
`pre-commit` using the method your environment already uses for Python tools.

## Related

- [claude-hooks-pack reference](reference-claude-hooks-pack.md)
- [Getting started with claude-hooks-pack](tutorial-getting-started.md)
- [Why this hook pack is structured this way](explanation-hook-pack-design.md)
