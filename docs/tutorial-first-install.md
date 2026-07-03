# First Install Tutorial

This tutorial gets a new machine from clone to a reversible local install.
It assumes macOS or Linux with Bash, Python 3, and Claude Code using the
default `~/.claude/` directory.

## 1. Clone the pack

```bash
git clone https://github.com/liush2yuxjtu/claude-hooks-pack.git
cd claude-hooks-pack
```

Check what will be installed:

```bash
find hooks -maxdepth 1 -type f \( -name '*.sh' -o -name '*.py' \) | sort
```

The top-level hook files are the active payload. Files under
`hooks/_archive/learned-mistakes/` and `contrib/one-offs/` are reference
material and are not installed by default.

## 2. Preview the install

Run a dry run first:

```bash
bash install.sh --dry-run
```

Expected result:

- each active hook is listed as a copy into `~/.claude/hooks/`
- `data/redlines.tsv` is listed as a copy into `~/.claude/hooks/redlines.tsv`
- no files are changed

If `settings/hooks.fragment.json` is still the shipped all-null placeholder,
the dry run will still show hook copies. The real install copies hooks, then
refuses to merge an empty settings fragment so it does not wipe your existing
Claude Code hook wiring.

## 3. Install hook files only

If you only want the scripts on disk, without editing settings:

```bash
bash install.sh --no-settings
```

This is the safest first real install. It refreshes hook files and redline data,
but leaves `~/.claude/settings.json` untouched.

## 4. Install with settings merge

Only do this when `settings/hooks.fragment.json` was generated on the source
machine and contains real hook entries.

```bash
python3 -m json.tool settings/hooks.fragment.json >/dev/null
bash install.sh
```

The installer backs up your current settings file before the merge:

```text
~/.claude/settings.json.bak-<UTC timestamp>
```

It then writes only lifecycle events that the fragment defines with non-null
payloads. Events omitted from the fragment, or set to `null`, keep your local
settings.

## 5. Restart Claude Code

Start a new Claude Code session after install. Hooks are loaded by Claude Code
at session startup, so an already-running session may not see the new wiring.

## 6. Roll back

To remove files shipped by this pack and restore the newest settings backup:

```bash
bash uninstall.sh
```

Restart Claude Code again after uninstall.

## 7. Confirm the baseline

Run the included checks:

```bash
python3 -m json.tool settings/hooks.fragment.json >/dev/null
bash install.sh --dry-run --no-settings
bash test/straight-fix-no-ask.test.sh
```

The test harness should report `10 passed, 0 failed`.
