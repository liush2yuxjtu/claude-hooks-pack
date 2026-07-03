# Why this hook pack is structured this way

`claude-hooks-pack` is a point-in-time mirror of a working user-level Claude
Code hooks setup. The repository has to preserve behavior from the source
machine without accidentally damaging another user's local Claude Code
configuration.

## The problem

Hook files and hook wiring are different things.

The files live in:

```text
~/.claude/hooks/
```

The wiring lives in:

```text
~/.claude/settings.json
```

A repository can safely ship hook scripts, but it cannot infer every user's
existing lifecycle wiring. Replacing `~/.claude/settings.json` with a guessed
or empty hook block would silently remove the user's local hooks.

There is a second problem: not every script in the repository should be
installed. Archived scripts are kept to explain old mistakes. One-off contrib
bundles are tied to a specific incident. Installing those by default would turn
reference material into active behavior.

## The approach

The project separates files, wiring, and reference material:

```text
repo
|-- hooks/                         active installable top-level hooks
|-- settings/hooks.fragment.json   lifecycle wiring, populated by source machine
|-- hooks/_archive/                reference only
|-- contrib/one-offs/              incident-specific, manual only
`-- docs/                          design and usage documentation
```

`install.sh` copies active top-level hooks first. That operation is reversible
and idempotent. It then treats settings merge as a separate step with a safety
gate.

If the fragment has zero lifecycle entries, the installer refuses to merge it.
This protects the target machine from an all-null hook block.

`bin/build-fragment.sh` exists so the source machine can produce the real
settings payload:

```text
source ~/.claude/settings.json
        |
        v
bin/build-fragment.sh
        |
        v
settings/hooks.fragment.json
        |
        v
install.sh on target machine
```

The builder keeps only Claude Code lifecycle events. It drops unrelated local
settings so machine-specific state does not travel with the pack.

## Why archived scripts stay in the repository

The archive is a learning surface, not an install surface. Files under
`hooks/_archive/learned-mistakes/` explain old behavior and recovery scripts.
They are useful when designing future hooks, but current `install.sh` excludes
`.retired`, `.solution`, and `.archive.*` filenames from the active copy loop.

This gives maintainers two properties:

- The old script remains reviewable and recoverable.
- A fresh install does not reactivate an old failure mode.

## Why one-offs moved to `contrib/one-offs`

`contrib/one-offs/fix-uat-env/` references a specific incident, project, and
environment shape. Keeping it in the active `hooks/` tree made the public pack
look more reusable than it was.

Moving it to `contrib/one-offs/` makes the boundary explicit:

- It can be studied or copied by someone with the same problem.
- It is not installed by default.
- It carries a `TOP-NOTE.md` that names the incident and portability limits.

## Trade-offs

The safety gate makes first-time setup a two-step process when the user wants
settings wiring. They must run `bin/build-fragment.sh` on the source machine,
commit the populated fragment, and then install elsewhere.

That is slower than shipping a prefilled `settings/hooks.fragment.json`, but it
prevents a worse outcome: wiping or replacing a target user's existing hook
wiring with null lifecycle entries.

The archive and contrib separation also adds directories to learn, but it keeps
the active install set small and predictable.

## Alternatives considered

### Always merge the fragment, even when empty

This was rejected because an all-null fragment can overwrite meaningful local
hook wiring. `install.sh` now refuses a zero-entry merge and prints the
source-machine fix instead.

### Install every script under `hooks/`

This was rejected because archived and retired scripts are not active product
behavior. Current install logic copies only top-level `.sh` and `.py` files and
excludes retired, solution, and archive suffixes.

### Hand-edit `settings/hooks.fragment.json`

This is possible but discouraged. The fragment should reflect the source
machine's real Claude Code settings. `bin/build-fragment.sh` is the repeatable
path and drops unrelated machine-local keys.

## Related

- [claude-hooks-pack reference](reference-claude-hooks-pack.md)
- [How to install and manage the hook pack](how-to-install-and-manage-hooks.md)
- [Getting started with claude-hooks-pack](tutorial-getting-started.md)
