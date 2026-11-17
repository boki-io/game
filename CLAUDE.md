# CLAUDE.md

Hero Horde: a 2D survivors-like in Godot 4.7 (GDScript). `README.md` has the game, controls and project layout;
`docs/spec-*.md` are the design specs, one per version, built in order. This file is how to work on it.

## The workflow for a new step (a version or feature)

Every step goes **spec, review, approval, build, PR**, in that order. Do not start building before the spec is approved.

### 1. Start from the right base
- `git fetch`, then check that the base branch really has the code the work builds on (`git log`, `git ls-tree`,
  `git grep` for the classes the spec names). A stale local `main` once had no hub code at all.
- Branch off an up-to-date `main` (`git checkout main && git pull --ff-only`). If the work depends on an unmerged
  branch, say so and ask which base to use. Name branches after the work: `spec-0.6-maps`, `map-selector`.
- Never work on `main`. Never force-push. Do not push or open a PR until asked, except where step 4 below says so.

### 2. Write the spec: `docs/spec-X.Y.md`
- Follow the earlier specs: a header (what it builds on, status and revision), Scope (in and out), Flow, the design in
  numbered sections, Sounds if any, a **Build order**, **Open questions / assumptions** and a **Definition of Done**.
- **Verify every claim against the code before writing it** (file, class, constant, number). Past mistakes came from
  assuming: enemies are plain `Node2D`s with no physics body, a pillar's collider sits 6 px above its base, the real
  spawn clearing is 134 px not 110, an enemy hitbox is 6 to 8 px.
- Make requirements testable: a number, a tolerance, a named metric. Say what is out of scope and what a later version
  will do.
- Put the file layout in the spec (where new files go and what moves), and say which existing tests or APIs it touches.
- Ask the user the questions the spec cannot answer (depth, scope, file name) **before** writing, in one batch with
  recommended defaults. Do not ask about things the code can answer.
- Update the revision number and a one-line status when the spec changes.

### 3. Review, then wait for approval
- Run an independent review: start a fresh agent that reads the spec against the code and the earlier specs, and ranks
  findings Critical / Important / Minor with concrete fixes. Apply them, note them in the status line, and tell the user
  what changed and what you did not apply.
- The user approves the spec. Until then it is not pushed.

### 4. After approval: push the spec
- Commit `docs/spec-X.Y.md` on the spec branch and push it (`git push -u origin <branch>`). That is the only push that
  is pre-authorised; the build is pushed only when the user asks.

### 5. Build from the spec
- Follow the spec's **build order**: one step at a time, **one commit per step**, tests written with the step. Commit
  messages say what and why, and end with the attribution lines the session gives.
- When working without questions (the user said so): decide, and record each assumption in `AGENT_DECISION_LOG.md`
  (what the spec left open, what was chosen, why); put a real question to a fresh agent first. End the log with a
  summary of what was built and what was not verified.
- A deviation from the spec (for example fewer test seeds) is requested by the user, then written in the log.
- Tests the spec says to leave broken stay broken and are listed; fix them at the end only if it is cheap.

### 6. Raise the PR
- Push the branch, then `gh pr create --base main --head <branch>`. Title: the version and name. Body: Summary
  (bullets), Notes (deviations, test changes, where decisions are logged) and a **Test plan** with checked boxes for what
  was run and an **unchecked box for anything not tried by hand** (a full play-through). End the body with
  `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
- Say plainly what was and was not verified. Do not claim a manual check that was not done.

## Working in the Godot project

- **Godot:** `/Applications/Godot.app/Contents/MacOS/Godot` (put it on `PATH`; the shell is case-insensitive, so
  `godot` works). Run the game with `godot --path .`.
- **Always run `godot --headless --path . --import`** after adding a `class_name` script, adding or moving an asset,
  or moving a script that a `.tres` names. The global class cache is not committed (`.godot/` is ignored), and a
  missing class shows up as "Could not find type" parse errors. Commit the generated `.import` and `.uid` files.
- **Move files with `git mv`**, delete stale `.import` files and re-import; never leave `.import` files pointing at an
  old source path.
- **Code reads like its neighbours:** match comment density, naming and idiom; `##` doc comments on classes and
  non-obvious functions; types on declarations. Autoloads are `GameSession`, `SceneFader`, `Audio`, `PlayerRegistry`,
  `EnemyGrid` and friends; do not read `GameSession` from low-level classes.
- **Tuning and content are data** (`content/**/*.tres`), not constants in scripts, unless they are
  structural.
- **Sounds:** a new sound goes in three places: `audio.gd` `SOUNDS`, `tools/gen_sfx.py` and the generated file in
  `assets/audio/` (missing files are skipped silently, so check all three). After running a generator, check
  `git status`: only the new files should appear, restore any existing file it changed.

## Tests

- Run one: `godot --headless --path . --script tests/<name>.gd` (prints `PASS` or `FAIL: ...`). Run all:
  `tests/run_all.sh`. `tests/README.md` lists what each test covers and how to write one; add a row for every new test.
- **A script error inside a test leaves the SceneTree running forever**, so a broken test hangs instead of failing.
  Run a new test with a time limit (a background run, `sleep`, then `pkill -f "script tests/<name>.gd"`), and read
  the output before assuming it passed.
- **In a test, never name a class that uses an autoload** (`Player`, `Enemy`, `AbilityCaster`) in a typed variable:
  it fails to compile. Use untyped variables, `await process_frame` first, and `tests/fixture.gd` loaded with `load()`.
  Tests that name new `class_name` types use `preload`, so they also work before the class cache exists.
- Randomised tests use **30 seeds** (`SEED_COUNT`), not 1000+, by the user's choice. Seeded logic must reproduce from
  its seed; do not use the global RNG (`Array.shuffle()`, `randf()`) where a seed has to reproduce a result.
- `GameSession.scene_hook` (a Callable) replaces a scene change in tests, so a flow can be checked without leaving the
  scene under test. After freeing a scene in a test, set `paused = false` (the real scene change does that).
- Headless has a dummy renderer, so **pixels are not tested**. To look at a screen, render real frames:
  `godot --path . <scene> --write-movie <scratchpad>/x.png --fixed-fps 30 --quit-after 45`, then read a PNG. Set `HERO_HORDE_SAVE=<scratchpad>/save.json` for any non-headless run, or reaching a run end
  writes the real save (`user://camp.json`). Drive state
  with a small scratch scene, and delete it afterwards.
- Run the whole suite before a PR and say which tests failed and why. Existing tests may need updating when a flow
  changes (the door now opens the select screen, not the arena).

## Shell and tooling habits

- Scratch files go in the session scratchpad directory, not `/tmp` and not the repo. Remove scratch files you add to
  the repo before committing (`git status` before every commit).
- macOS has BSD `sed`: edit files with the Edit tool or a short `python3` script, not `sed -i`.
- Do not `rm` a path built from a shell variable (the safety check refuses it); use a literal path or skip the cleanup.
- Use the dedicated tools (Read, Edit, Write) for files; keep shell for git, Godot and scripts.
- Long-running commands go to the background with a time limit, and you read their output when they finish.

## Specs and docs

- `docs/spec-X.Y.md` is the source of truth for a version. If the build differs from it, update the spec or log the
  deviation, do not let them drift.
- Keep `README.md` (layout, controls) and `tests/README.md` current when files or tests are added.
