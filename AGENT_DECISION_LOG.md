# Agent decision log: spec v0.5 (map selector)

Decisions and assumptions made while implementing `docs/spec-0.5.md` without asking the user. Open questions were
put to a fresh agent where noted.

## D1. Base branch: `main`, after pulling it
- User asked for a branch off `main`. At first the local `main` was 9 commits behind `origin/main` and had no hub
  code, which the spec builds on. A fresh agent confirmed the hub code was missing from the stale `main`.
- User then said to pull `main`. `origin/main` already contains all of `main-menu` (PR #1), so `main` was
  fast-forwarded and `map-selector` rebased onto it (only the spec and this log differ from `main`).

## D2. Test seed count is 30, not 1000+
- User asked to limit randomised tests to 20-30 seeds. Spec 11 says 1000+. Used 30 (`SEED_COUNT` constant).
