# Getting started with claude-hooks-pack

In this tutorial you will install the hook files locally, run the included test
harness, and see why the settings merge is intentionally separate from copying
the scripts.

## What you need

- `bash`
- `python3`
- `jq`
- A clone of `https://github.com/liush2yuxjtu/claude-hooks-pack`

## Step 1: Clone and enter the repository

```bash
git clone https://github.com/liush2yuxjtu/claude-hooks-pack.git
cd claude-hooks-pack
```

You now have the hook pack on disk. The active hook scripts are in `hooks/`.

## Step 2: Install only the hook files

```bash
bash install.sh --no-settings
```

This copies the active hook files to `~/.claude/hooks/` and leaves
`~/.claude/settings.json` unchanged.

## Step 3: Verify one hook is installed

```bash
test -x ~/.claude/hooks/straight-fix-no-ask.sh && echo "hook installed"
```

Expected output:

```text
hook installed
```

You have a visible result by this point: at least one shipped hook is installed
and executable.

## Step 4: Run the included test harness

```bash
bash test/straight-fix-no-ask.test.sh
```

Expected result:

```text
RESULT: 10 passed, 0 failed
```

The test feeds sample Stop-hook payloads into the installed
`straight-fix-no-ask.sh` hook and checks whether it blocks or approves the
right cases.

## Step 5: Preview the full installer

```bash
bash install.sh --dry-run
```

If `settings/hooks.fragment.json` is still empty, the preview shows file copy
operations and then the merge-safety path. The empty fragment is expected in a
fresh public snapshot.

## Step 6: Learn where real lifecycle wiring comes from

On the source machine, the machine with real hook wiring in
`~/.claude/settings.json`, run:

```bash
bash bin/build-fragment.sh > settings/hooks.fragment.json
```

That command extracts only the Claude Code lifecycle hook block. After review
and commit, other machines can run:

```bash
bash install.sh
```

to copy scripts and merge the populated settings fragment.

## Step 7: Uninstall when you are done testing

```bash
bash uninstall.sh
```

If `install.sh` created a settings backup, the newest backup is restored. The
hook files shipped by this pack are removed from `~/.claude/hooks/`.

## What you built

You installed the hook files, verified that a shipped hook exists, ran the
included test harness, and learned why settings wiring is generated from the
source machine instead of guessed from the repository.

For exact command behavior, read the
[reference](reference-claude-hooks-pack.md). For day-to-day tasks, use
[How to install and manage the hook pack](how-to-install-and-manage-hooks.md).
