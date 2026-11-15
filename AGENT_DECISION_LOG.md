# Agent decision log: spec v0.5 (map selector)

Decisions and assumptions made while implementing `docs/spec-0.5.md` without asking the user. Open questions were
put to a fresh agent where noted.

## D1. Base branch is `main-menu`, not `main`
- User asked for a branch off `main`. `main` is 8 commits behind `main-menu` and contains no hub code (hub scene,
  `SceneFader`, `hub_confirm`, `last_character`), which the spec builds on. `docs/spec-0.5.md` (rev 3) only existed
  as an uncommitted change on `main-menu`.
- A fresh agent independently verified this with `git grep` and recommended branching from `main-menu`.
- Decision: `map-selector` branches from `main-menu` and the spec is the first commit.

## D2. Test seed count is 30, not 1000+
- User asked to limit randomised tests to 20-30 seeds. Spec 11 says 1000+. Used 30 (`SEED_COUNT` constant).
