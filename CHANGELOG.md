# Changelog

All notable changes to `claude-hooks-pack` are documented here.

The format loosely follows [Keep a Changelog](https://keepachangelog.com/), but
this project does **not** follow SemVer — commits are point-in-time snapshots of
the source machine's `~/.claude/hooks/`, not versioned releases.

## [unreleased] — tidy round 3 (2026-07-02)

### Fixed (tech-debt: shellcheck warnings in active scripts)

- **`hooks/meta-hook-creator.sh`** SC2088: `~/` literals in trigger patterns. Not a bug —
  those literals are intentional user-facing trigger strings (the script matches
  `~/.claude/hooks/` exactly as typed). Silence with `# shellcheck disable=SC2088` +
  rationale comment.
- **`hooks/no-ask-file-followups.sh`** SC2221/SC2222: pattern-list overlaps in two
  `case` blocks. Not a bug — both blocks use any-match (OR) semantics; pattern order
  is irrelevant. Silence with `# shellcheck disable=SC2221,SC2222` + rationale.
- **`contrib/one-offs/fix-uat-env/apply.sh`** SC2164: bare `cd "$REPO"` without
  `|| exit`. Real (small) fix: `cd "$REPO" || { echo "..."; exit 1; }` so the script
  fails loudly instead of continuing from the wrong directory.

### Known tech debt (NOT fixed in this round)

These are pre-existing shellcheck warnings/info on scripts we didn't author;
CI is configured to NOT fail on warnings/info (`shellcheck -S error` for
active hooks). Tracked here so they don't get lost:

- **`hooks/pair-chrome-soft-gate.sh:65`** — SC2019/SC2018/SC2016 (info-level):
  `[A-Z]/[a-z]` character classes + single-quoted regex. Fix would be
  `[[:upper:]]`/`[[:lower:]]` for unicode support, but this hook's triggers
  are ASCII-only by design; switch is debatable.
- **`hooks/reap-orphan-chrome.sh:69`** — same SC2019/SC2018/SC2016 trio.
  Reason for keeping: same as pair-chrome-soft-gate.
- **`hooks/_archive/learned-mistakes/{pop-open-on-ship,reap-orphan-chrome.solution,self-report-fused}.sh`**
  — SC2034 (unused vars) and likely more. These scripts are intentionally
  archived; not enforcing shellcheck on them.

CI currently passes 5/5 jobs. To move any of these warnings to a green-only
state, run `shellcheck <path>` locally and address each.

## [unreleased] — tidy round 1 (2026-07-02)

### Fixed (P0 — install/uninstall safety)
- **install.sh** no longer wipes `~/.claude/settings.json` with all-null hooks
  when `settings/hooks.fragment.json` is empty. The merge now:
  1. validates the fragment is non-empty (refuses otherwise);
  2. aborts with clear remediation pointing at `bin/build-fragment.sh`;
  3. preserves the user's existing wiring instead of overwriting it with nulls.
- **install.sh** removed the dead-code `value-guard-template.md` skip-glob —
  the file lives under `docs/`, never matched against `hooks/*.sh`.
- **uninstall.sh** gained a defensive cleanup block for archived + contrib
  files, closing the 2-file orphan leak (`reap-orphan-chrome.solution.sh`,
  `self-report-fused.sh.retired`) for users on an old install layout.

### Changed (P1+P2 — file layout)
- 3 dormant files (`pop-open-on-ship.sh`, `reap-orphan-chrome.solution.sh`,
  `self-report-fused.sh.retired`) moved to `hooks/_archive/learned-mistakes/`.
  Each retains its file extension + shebang so it can be reactivated by
  simply moving it back to `hooks/`. `INSTALL.SH` now excludes
  `*.retired|*.solution|*.archive.*` so they're never installed.
- The `fix-uat-env/` sub-bundle moved out of `hooks/` to
  `contrib/one-offs/fix-uat-env/` with a `TOP-NOTE.md` documenting why this
  is incident-remediation, not reusable hook logic.

### Added (P3 — repo infrastructure)
- `bin/build-fragment.sh` — helper to extract the real `hooks{}` block from
  the source machine into a populatable fragment. Required to be run once on
  the source machine; until then install.sh intentionally refuses to merge.
- `.github/workflows/ci.yml` — shellcheck + JSON validate + bash test +
  install dry-run on push / PR.
- `.editorconfig` — single source of truth for indentation + line endings.
- `.shellcheckrc` — disables SC1090/SC1091 (hooks source lib files CI lacks),
  enables `quote-add-variables` review hints.
- `.pre-commit-config.yaml` — shellcheck, shfmt, trailing-whitespace,
  end-of-file-fixer, YAML/JSON lint, large-file guard, yamllint.
- `CONTRIBUTING.md` — rubric §8 self-check + local dev recipe.
- `CHANGELOG.md` — this file.
- `.github/ISSUE_TEMPLATE/bug_report.md`, `feature_request.md`.
- `.github/PULL_REQUEST_TEMPLATE.md` — new-hook checklist.

## [0.0.1] — 2026-07-02 (initial public snapshot)

- Initial commit: 27 active + 3 dormant user-level hooks across 5 Claude
  Code lifecycle events, plus the `fix-uat-env/` sub-bundle.
- install.sh / uninstall.sh pair (idempotent installer that backs up
  `~/.claude/settings.json` before merge).
- README + zh-CN README, MIT LICENSE, `.gitignore`, `docs/` rubric +
  value-guard template, `data/redlines.tsv`, `test/`.
