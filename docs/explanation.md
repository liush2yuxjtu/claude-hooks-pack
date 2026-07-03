# Explanation

## Why this pack exists

Claude Code hooks often start as local behavior patches in
`~/.claude/hooks/`. That is useful for one developer, but hard to review,
reinstall, or share. This repository turns that local hook directory into a
versioned, reviewable, redistributable pack.

The repository is a point-in-time mirror of the source machine. When the source
machine changes, the pack should be refreshed by copying changed hook files and
regenerating the settings fragment.

## Why hook files and settings are separate

Hook scripts and hook wiring answer different questions.

Hook scripts answer:

- what code runs
- what it detects
- what it logs
- what escape hatch disables it

Settings wiring answers:

- which lifecycle event runs the hook
- in what order hooks run
- which matcher is used for tool-related hooks

Keeping them separate makes installation safer. A user can copy scripts without
changing settings, inspect them, then merge wiring only when the fragment is
known to contain real source-machine entries.

## Why the shipped fragment can be empty

The default `settings/hooks.fragment.json` can contain `null` for every event.
That is a safety placeholder. It prevents the repository from pretending to know
the target user's local Claude Code wiring before the source machine exports it.

`install.sh` treats a zero-entry fragment as a hard stop for the settings merge.
Hook files are still copied, but local settings are preserved.

## Why hooks default to silent nudges

Most hooks should not interrupt the user. The design rubric prefers:

```json
{"continue": true, "suppressOutput": true}
```

That shape lets hooks add context or log an audit trail without making every
Claude Code turn noisy. Hard blocks are reserved for cases where the assistant
is about to cause real damage, hide unfinished work, or violate an explicit
project rule.

## Why archived scripts stay in the repo

Some scripts are useful as incident history, but harmful as default behavior.
The archive keeps those lessons visible without reinstalling the old behavior.

Examples:

- scripts that opened the wrong Chrome profile
- scripts that were replaced by quieter VALUE guard behavior
- solution scripts that should be run manually, not wired automatically

The installer excludes archived and retired file names, so keeping them in the
repository does not make them active.

## Why one-offs live under contrib

Some hooks fix a specific project incident and do not generalize. Putting them
under `contrib/one-offs/` keeps the fix reproducible while making its scope
honest. A one-off needs a `TOP-NOTE.md` because future readers need to know why
the script exists and why it is not installed by default.

## What "good" means for a hook

A good hook is narrow enough to avoid false positives, documented enough to
debug, and reversible enough to disable. The rubric requires trigger discipline,
tests, an escape hatch, audit logs, and clear wiring.

The goal is not to make the agent ask fewer questions by magic. The goal is to
encode lessons about repeated failure modes so the agent gets useful context at
the moment it is most likely to make that mistake.
