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

## D3. Spec gaps, decided without asking
Where a question came up and the spec did not answer it, the choice made and why:
- **Name and thumbnail pairing.** Spec 4.4 asks for 7 distinct thumbnails from a pool of at least 7 and 7 distinct
  names, with no link between them. There are 8 of each and name i is paired with thumbnail i (themed to match, e.g.
  "Frostbite Grotto" has an icy thumbnail), so a card never shows a mossy picture under a crystal name. One shuffle
  picks both. The spec's pool minimum of 7 holds.
- **Modifier tints.** Spec 5.1 tints Population and Difficulty red when positive and Experience and Gold green when
  positive. Negatives are not specified: they get the opposite tint (a lower Population is green, a lower Gold is
  red), and 0% stays white.
- **Zero formatting.** 0 shows as `0%`, not `+0%`.
- **Card layout.** Modifiers are rows beside the thumbnail on a 160x80 card, so three cards plus gaps fit the 360 px
  high screen below the rock band.
- **Editor workflow.** Spec 7 says `main.tscn` must still run on its own. With no path a won stage cannot load a
  select screen, so `GameSession.is_last_stage()` returns true when there is no path and the win shows the victory
  screen (with an empty summary). `select.tscn` opened directly makes its own random run.
- **`finish_run()` also clears `current_stage`.** The spec lists only the path and `run_progress`. The HUD caches its
  "Stage 2/3 - Name" line at bind time so clearing it is safe.
- **Beaten stages in older columns.** The select screen shows the stage taken in each earlier column as Beaten and
  the other cards of that column as Locked.
- **Highlighted lines.** Only the lines from the last beaten stage to its available stages are highlighted (spec 5.2).
  Lines of earlier columns stay muted.
- **Gem with 0 XP.** A mob with `xp_drop` 0 still goes through `spawn_gem` as before with value 0 and drops no coin;
  only the hub dummies have it and they never die.
- **Coin position.** A coin spawns at the same position as the gem.
- **Level-up poll.** `main.gd` polls `LevelUpMenu.active` each frame (the spec allows polling or a new signal).
- **Abandon prompt focus.** The prompt focuses No by default so a stray Enter does not abandon the run, and Esc
  closes it like No.
- **`GameSession.scene_hook`.** A small test seam: when set, scene changes call it instead of fading. Used by the
  new tests so a flow can be checked without leaving the scene under test.
- **New `class_name`s need `godot --import`.** The global class cache only learns them on an import or editor run.
- **`tests/run_all.sh` got a 120 s limit per test.** A script error in a test (the old `scene_flow.gd` after
  `restart_run()` was removed) left the SceneTree running forever, which hung the whole run.
- **Old tests fixed at the end.** Spec 9.4 said to leave `scene_flow.gd` and the stale README table broken for now;
  per the user's instruction they were fixed at the end because it was cheap. `hub_walk.gd` also expected the door to
  load the arena and was updated the same way.

## D4. Fresh-agent consultations
- Base branch (D1): one agent, verified with `git grep`. It recommended branching from `main-menu`. The user then
  settled it by saying `main` should contain the code, which it did once pulled.
- No other open question needed outside input; the rest were small and are in D3.

## Summary of the implementation
Branch `map-selector` (off `main`, one commit per build step, nothing pushed):
1. `StageData` + population/experience in `SpawnDirector` (`stage_modifiers.gd`).
2. Gold: `Coin`, coin pool in `Pickups`, drop chance, `GameSession.gold`, HUD number, `coin` and `stage_clear` sounds
   (script, generated files and `audio.gd` list) (`gold.gd`).
3. `PathGenerator`/`StagePath`, eight generated thumbnails (`tools/gen_stage_thumbs.py`) (`path_generator.gd`, 30 seeds).
4. `GameSession` path state and methods, `RunProgress` (carry level, XP, upgrades; restore without opening the
   level-up menu), `restart_run()` removed (`run_progress.gd`).
5. End screen DEATH/VICTORY modes without Restart, `AbandonPrompt` on the pause menu, the "Stage cleared" banner,
   the stage line on the HUD.
6. Select screen (`select.tscn`, `StageCard`): three columns, lines, card states, keyboard and mouse input, abandon
   prompt (`select_screen.gd`).
7. Stage end sequencing in `main.gd` (level-up first, 2 s banner with a pause-ignoring timer, victory, death),
   door -> select (`stage_flow.gd`).
8. Polish: themed thumbnails, highlighted lines, card states, sounds, transitions through `SceneFader`.
9. Old tests fixed (`scene_flow.gd`, `hub_walk.gd`, README table).

All 22 tests pass. Deviation from the spec: tests use 30 seeds, not 1000+ (D2). Not done: nothing from the
Definition of Done is knowingly missing. Not verified by eye: the death and victory screens and the banner
(covered by tests that read their text, not by a rendered frame); the select screen (columns 1 and 2) and the HUD
were rendered and looked at.
