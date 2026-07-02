# TOP-NOTE — fix-uat-env (one-off incident remediation)

> **This sub-bundle is NOT a reusable hook.** It was extracted from a
> specific incident on the source machine, frozen as-is for reproducibility,
> and moved out of the main `hooks/` tree. Install.sh does not install it.
> If you need the same env-fix on a different project, see "Portability" below.

## Incident summary

| | |
|---|---|
| Date | 2026-06-xx (snapshot only) |
| Project | `win_brain` (DeerFlow fork) — `zhangqing` UAT env |
| Symptom | Dev-bypass greeting showed literal `e2e` instead of the real user; custom `fmcg-diagnosis-test` agent hidden from UI dropdown because `agents_api.enabled` was `false`; FMCG skills disabled in `groups/zhangqing-group/extensions_config.json` |
| Fix | 4-step idempotent env patch (`apply.sh`) triggered by a UserPromptSubmit hook on `/fix-uat-env`, `[[fix-uat-env]]`, `<<fix-uat-env>>`, `fix-zhangqing-uat`, or `zhangqing + fix` co-occurrence |
| Cost of the hook existing in the public pack | High — references internal team names + project-specific paths. Low reusability — only meaningful to one project. Hence: moved here. |

## What's in this directory

```
contrib/one-offs/fix-uat-env/
├── TOP-NOTE.md                           # this file
├── README.md                             # the original sub-bundle README
├── hook.sh                               # UserPromptSubmit entry (~80 lines)
├── apply.sh                              # idempotent 4-step patch (~100 lines)
└── test.sh                               # 5+4+1 test matrix
```

## Portability

If you're hitting the same symptom on a different project:

1. Copy `apply.sh` out and rewrite the 4 steps for your project:
   - **DEER_FLOW_AUTH_DISABLED_USER_EMAIL forwarding** → drop unless you're on DeerFlow too
   - **config.local.yaml `agents_api.enabled: true`** → only if you have a custom agents feature flag
   - **`extensions_config.json` FMCG skills** → DeerFlow-specific; replace with your own skills
   - **`fmcg-diagnosis-test/SOUL.md` skeleton** → replace with your agent SOUL template
2. Decide whether the hook-on-keyword UX is worth the noise for your project. If not, delete `hook.sh` and just call `apply.sh` manually.
3. If kept, register the hook via `install.sh` of your project's pack, NOT this one.

## Status

**Frozen.** No fixes planned for the original source-machine workflow
because the source-machine itself has moved past the incident. Future
contributions should live in a fresh sub-bundle under their own directory.
