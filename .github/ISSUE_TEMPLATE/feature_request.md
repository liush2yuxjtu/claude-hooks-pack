---
name: Hook proposal
about: Propose a new user-level Claude Code hook
title: '[new hook] '
labels: enhancement
assignees: ''
---

## What you want

One sentence: what should this hook do, on which lifecycle event.

**Event:** `SessionStart` / `SubagentStart` / `UserPromptSubmit` / `PreToolUse` / `Stop`

## Trigger patterns

List the patterns you plan to match. Per rubric §8 item 1, you need ≥ 100 or
a header comment explaining why this is a small, precise set.

- pattern A
- pattern B
- ...

## Hook behavior on hit

Default-silent-approve + inject, OR non-silent block? Per rubric §8 item 4:
"Default silent approve, hit inject (not block)."

## Rubric §8 self-check

Walk through the 8 items from `docs/HOOK_DESIGN_RUBRIC.md` §8 for your
proposal. Mark each ✓ or ✗ with a one-line rationale.

- [ ] **1. Trigger list size** — rationale:
- [ ] **2. Structural trigger** — which one:
- [ ] **3. Test harness plan** — what positive / negative cases:
- [ ] **4. Silent-approve + inject** — what to inject:
- [ ] **5. Escape hatch** — env var name (`CLAUDE_<NAME>_DISABLED=1`):
- [ ] **6. VALUE contract** — root → L1-L4 path:
- [ ] **7. Audit + session log** — JSONL path + per-session path:
- [ ] **8. Wiring target** — where in `settings/hooks.fragment.json`:

## Test plan

Describe `test/<name>.test.sh`. ≥ 3 positive + ≥ 3 negative cases.

## Replaces / supersedes

If your hook supersedes an archived hook, link the
`hooks/_archive/learned-mistakes/INDEX.md` entry.
