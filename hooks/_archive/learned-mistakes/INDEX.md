# Archived hooks — reference material, NOT installed

This directory holds hook scripts kept for **teaching value** ("here's what
went wrong on the original machine") but explicitly excluded from
`install.sh`. They live in the pack so future hooks authors can see the
mistakes they replaced.

If you want any of these back as a wired hook, copy it out of here into
`hooks/` at the top level — `install.sh` will pick it up again. Just be
aware of the incident it represents (see comments at the top of each file).

## Why these are archived

| File | Original purpose | Why archived | Archived on |
|---|---|---|---|
| `pop-open-on-ship.sh` | PreToolUse: auto-pop `pair-chrome`'d URL on a Stop event triggering "ship". | Wrong-Chrome auto-pop pain: hit the user's daily Chrome instead of the paired one. Wrong signal grep: fired on too many non-ship scenarios (e.g. `git push` of README, UAT done-sound). | 2026-06-xx (replaced by `pair-chrome pop-open` invoked **manually** by the agent, not auto-piped) |
| `reap-orphan-chrome.solution.sh` | SessionStart: kill orphaned Chrome processes when a session dies. | The detected "orphan" turned out to be the user's *real* Chrome — reaping crashed everyone's tabs. Replaced by `reap-orphan-chrome.sh` (the bare hook), which only points at this script as a manual remediation. | 2026-06-xx (replaced by `reap-orphan-chrome.sh`) |
| `self-report-fused.sh.retired` | Stop: prepend a "VALUE self-check" reminder to every assistant message. | The reminder was being silently absorbed by all hook outputs → noise. Superseded by the `value-guard.sh` + `value-guard-next-step.sh` pair, which only fires on the trigger word "next-step" / "要不要". | 2026-06-xx (replaced by `value-guard*.sh`) |

## Files in this directory

```
hooks/_archive/learned-mistakes/
├── INDEX.md                              # this file
├── pop-open-on-ship.sh                   # original = wrong-Chrome auto-pop
├── reap-orphan-chrome.solution.sh        # original = the script the bare hook points at
└── self-report-fused.sh.retired          # original = always-on VALUE reminder (now scoped)
```

## See also

- `docs/HOOK_DESIGN_RUBRIC.md` — §8 self-check; specifically item 1
  "≥ 100 triggers OR ≤ 100 with header reason" + item 4 "default silent
  approve, hit inject (not block)" are the rubric items these archived
  hooks violated or designed around.
