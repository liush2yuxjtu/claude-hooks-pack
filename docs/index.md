# Documentation

This directory documents `claude-hooks-pack` with the Diataxis structure:
tutorials for learning, how-to guides for tasks, reference pages for exact
interfaces, and explanations for design rationale.

## Start here

| Need | Document | Quadrant |
|---|---|---|
| Install the pack for the first time and verify it works | [Getting started with claude-hooks-pack](tutorial-getting-started.md) | Tutorial |
| Install, dry-run, uninstall, or populate the settings fragment | [How to install and manage the hook pack](how-to-install-and-manage-hooks.md) | How-to |
| Check every shipped command, file, option, and lifecycle surface | [claude-hooks-pack reference](reference-claude-hooks-pack.md) | Reference |
| Understand why the pack uses an empty settings fragment and excludes archives | [Why this hook pack is structured this way](explanation-hook-pack-design.md) | Explanation |

## Project surface

`claude-hooks-pack` is a redistributable snapshot of user-level Claude Code
hooks. It ships 26 active top-level hooks, an intentionally empty settings
fragment, installer and uninstaller scripts, CI checks, a design rubric, and
archived or one-off material that is kept for learning but not installed by
default.

For the shortest path, use the tutorial first. For exact command behavior,
read the reference.
