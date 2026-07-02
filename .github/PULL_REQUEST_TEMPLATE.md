## What this PR does

One sentence summary.

## Hook inventory impact

- [ ] No hook inventory change (config / docs / infra only)
- [ ] New hook added (see checklist below)
- [ ] Existing hook changed (rubric §8 self-check below)
- [ ] Archived hook reactivated (link `INDEX.md` entry below)
- [ ] Dormant / contrib moved

## Rubric §8 self-check (if hook is new or changed)

Walk through `docs/HOOK_DESIGN_RUBRIC.md` §8 — mark each item ✓/✗ with rationale.

- [ ] **1. Trigger list** size ≥ 100 OR ≤ 100 with header reason
- [ ] **2. Structural trigger** present
- [ ] **3. Test harness** with ≥ 3 positive + ≥ 3 negative
- [ ] **4. Silent-approve + inject** (not silent-block / not block)
- [ ] **5. Escape hatch** `CLAUDE_<NAME>_DISABLED=1`
- [ ] **6. VALUE contract** header references `~/.claude/CLAUDE.md` cascade
- [ ] **7. Audit JSONL + per-session log** paths documented in header
- [ ] **8. Wiring** under correct lifecycle event in `settings/hooks.fragment.json`

## Tests run

- [ ] `pre-commit run --all-files` clean
- [ ] `bash test/straight-fix-no-ask.test.sh` clean
- [ ] (if new hook) `bash test/<name>.test.sh` clean

## CI

CI is `.github/workflows/ci.yml`: shellcheck + JSON validate + bash test +
install dry-run. The PR template doesn't tick the CI box — CI runs itself.

## Files touched

- `<path>` — reason
- ...
