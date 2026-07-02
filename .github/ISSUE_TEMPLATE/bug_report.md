---
name: Bug report
about: Something an installed hook does not match the rubric §8 or docs
title: '[bug] '
labels: bug
assignees: ''
---

## What hook is broken?

Hook filename (under `hooks/`):

```
hooks/<name>.sh
```

## What you observed

What the hook did that you didn't expect, or didn't do that you expected.

## What you expected

The intended behavior, per `docs/HOOK_DESIGN_RUBRIC.md` §8 or the hook's own header comment.

## Reproduce

Minimal prompt / shell command that triggers the bad behavior.

Expected output: ...
Actual output: ...

## Environment

- macOS / Linux version:
- Claude Code version:
- Hook install path (`readlink -f ~/.claude/hooks/<name>`):

## Audit log excerpt (if applicable)

Path: `~/.claude/hooks/logs/<name>-audit.jsonl`

```jsonl
(paste last 5-10 lines)
```
