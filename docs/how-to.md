# How-to Guide

Use these recipes for common maintenance tasks.

## Install without touching settings

```bash
bash install.sh --no-settings
```

Use this when you want the latest scripts in `~/.claude/hooks/`, but do not
want to change `~/.claude/settings.json`.

## Preview an install

```bash
bash install.sh --dry-run
bash install.sh --dry-run --no-settings
```

Dry runs print the exact copy, chmod, mkdir, and merge commands that would run.
They do not change files.

## Generate a real settings fragment on the source machine

Run this only on the machine whose `~/.claude/settings.json` already contains
the desired hook wiring:

```bash
bash bin/build-fragment.sh > settings/hooks.fragment.json
python3 -m json.tool settings/hooks.fragment.json >/dev/null
git diff -- settings/hooks.fragment.json
```

Then commit the populated fragment:

```bash
git add settings/hooks.fragment.json
git commit -m "frag: extract real hooks block from source machine"
git push
```

Do not hand-edit `settings/hooks.fragment.json` for routine hook changes. It is
a generated transfer artifact.

## Add a new hook

1. Read [HOOK_DESIGN_RUBRIC.md](HOOK_DESIGN_RUBRIC.md), especially section 8.
2. Copy a passing hook shape, such as `hooks/value-guard.sh` or
   `hooks/pair-chrome-soft-gate.sh`.
3. Add an escape hatch named `CLAUDE_<NAME>_DISABLED=1`.
4. Add a test harness under `test/<name>.test.sh` with at least three positive
   and three negative cases.
5. Update `settings/hooks.fragment.json` by running `bin/build-fragment.sh` on
   the source machine, not by editing it manually.
6. Run local verification.

```bash
pre-commit run --all-files
bash test/<name>.test.sh
bash install.sh --dry-run --no-settings
```

## Validate the straight-fix hook

```bash
bash test/straight-fix-no-ask.test.sh
```

The harness sends synthetic Stop-hook payloads through
`hooks/straight-fix-no-ask.sh` and checks block versus approve decisions.

## Edit redlines

The redline engine reads a TSV table:

```text
tool<TAB>regex<TAB>action<TAB>reason
```

Project-local additions belong in `~/.claude/hooks/redlines.d/` after install.
Repository defaults live in `data/redlines.tsv`.

After editing the repository default:

```bash
bash install.sh --dry-run --no-settings
bash install.sh --no-settings
```

## Keep one-off incident scripts out of the default install

Put narrow project or incident remediation under:

```text
contrib/one-offs/<name>/
```

Include a `TOP-NOTE.md` that states when the incident happened, which project or
machine it targeted, what symptom it fixes, and what it is not meant to be.

`install.sh` does not install `contrib/one-offs/` by default.

## Reactivate an archived hook

1. Read `hooks/_archive/learned-mistakes/INDEX.md`.
2. Move the script back to top-level `hooks/`.
3. Bring it up to the current rubric.
4. Add or update tests.
5. Regenerate the source-machine settings fragment.

Archived files are reference material until they are moved back to top-level
`hooks/`.

## Uninstall the pack

```bash
bash uninstall.sh
```

The uninstaller restores the newest `~/.claude/settings.json.bak-*` backup when
one exists, removes files shipped by this pack, and also removes archived or
contrib files left by older install layouts.
