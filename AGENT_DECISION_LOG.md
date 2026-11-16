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

All 20 tests pass (the full run had only `scene_flow.gd` and `hub_walk.gd` failing; both were then fixed and re-run on their own). Deviation from the spec: tests use 30 seeds, not 1000+ (D2). Not done: nothing from the
Definition of Done is knowingly missing. Not verified by eye: the death and victory screens and the banner
(covered by tests that read their text, not by a rendered frame); the select screen (columns 1 and 2) and the HUD
were rendered and looked at.

# Agent decision log: spec v0.6 (stage maps), build step 1

Decisions made while building step 1 of `docs/spec-0.6.md` section 14 (directory, data, migration), without asking.

## M1. Field types of `MapTheme`
The spec names the fields but not their GDScript types. Chosen: `floor_plain: Array[Color]`, `wall_lengths: Array[float]`,
`monsters: Array[MonsterVariant]`, `style` and `MonsterVariant.mark` as enums (`MapTheme.Style`, `MonsterVariant.Mark`),
`decor_weights` a plain `Dictionary` of `CaveDecor.Kind` (int) to float. Fields are in inspector groups. `variant_for()`
takes a `StringName`.

## M2. Placeholder decor weights use only today's five decor kinds
The new decor kinds (moss, crystal, ...) are build step 5, so `decor_weights` of the eight maps only name the existing
kinds (0 stalagmite, 1 rock, 2 pebbles, 3 bones, 4 mushroom), skewed per map (bones on Bone Warren, mushrooms on Spore
Cavern). Zero weights are left out of the files. Whoever adds the new kinds should put the signature kinds in the weights.
The `_default` weights are the odds of today's `CaveDecor.layout` (0.21, 0.27, 0.26, 0.13, 0.13), for information: the
legacy layout does not read them.

## M3. Placeholder palettes
`rock`, `floor_plain[0]` and `glow_color` are the thumbnail colours of `tools/maps/gen_thumbnails.py` (spec 10). The rest
is derived: `floor_plain[1..3]` are the first colour at 1.04, 0.97 and 1.02 brightness, `floor_dark` x0.82, `floor_light`
x1.15, `rock_dark` x0.55, `rock_light` x1.35, wall tops x1.45 / x1.75, wall side x0.8, outline x0.5, pillar x1.7, torch colour
is the glow blended 40% toward a warm yellow. Ambient, vignette and torch count differ a little per map (Ember Depths
warm and brightest light, Frostbite and Crystal Vault cool). All are placeholders for the later per-map pass.

## M4. Placeholder monster variants
Body colour is the type's base colour (0.4) blended toward a per-map accent colour, then nudged in lightness until it is at
least 0.14 OKLab from every floor colour of its map; marks are the ones of spec 7.3 (spots, crest, stripe) in the glow colour
lightened by 25%. Outline is the body x0.5 and the eye white, as today. The three types stay at least 0.08 apart.
`map_themes.gd` already checks both readability distances (the spec puts them in `monster_variants.gd`, step 7, which will
repeat or replace them).

## M5. `_template`
A copy of Mossy Hollow's files with the id `_template`, name "Template Map" and the same thumbnail copy. It is not in the
registry and `MapRegistry.by_id()` returns null for it; `map_content.gd` and `map_themes.gd` check it by path.

## M6. Rock/floor "differ" rule loosened
Spec 12 asks that two themes differ in rock and floor colour by an OKLab distance of at least 0.05. Because rock and floor
`[0]` must equal the thumbnail colours (spec 10) and several thumbnails share a dark rock (Mossy Hollow / Flooded Gallery,
Crystal Vault / Spore Cavern ...), the test checks that the rock distance **plus** the floor distance is at least 0.05. Later
palette work can tighten it once the thumbnails are regenerated (step 9).

## M7. Thumbnail-colour test is loose
The average colour of a thumbnail must be within 0.12 OKLab of a 50/50 blend of `rock` and `floor_plain[0]`. Thumbnails will
be redrawn in step 9, and the tolerance is to be tightened then.

## M8. Commit order and the `.import` files
Thumbnails were moved with `git mv` into `content/maps/<id>/thumbnail.png` (a PNG is unchanged: the moved generator
reproduces the same bytes) and the old `.import` files deleted; `godot --headless --path . --import` made the new ones
(committed). `_template/thumbnail.png` is a copy of Mossy Hollow's and has its own `.import`.

## M9. Test enemy-type list
`map_content.gd` takes the enemy types the director can spawn from `data/enemies/*.tres` with `immovable = false` (grunt,
ranged, dasher; the training dummy is excluded) and asserts that list, so a new enemy type makes the test fail until every
map has its variant file (spec 3.8).

## M10. `PathGenerator` constants removed
`NAMES`, `THUMBNAIL_COUNT` and `THUMBNAIL_PATH` are deleted (nothing else read them). The shuffle still draws one
permutation of the registry (so the same seeds produce the same name/thumbnail pairing as v0.5, since the registry order
equals the old name order).


# Agent decision log: spec v0.6, build step 4 (obstacles block enemies)

## v0.6 obstacles

### O1. `ObstacleMap` is a Node that also works outside the tree; no autoload is named
Spec says "pure logic plus a thin node". `ObstacleMap extends Node` (group `obstacles`, `ObstacleMap.get_for(node)`), and
`setup()` plus every query work on an instance that was never added to the tree. It reaches `PlayerRegistry` by path
(`/root/PlayerRegistry`) instead of by name, so the script (and `FlowField`) compile in a `--script` test that preloads them
before the autoloads exist (a layout test can `preload` them). `setup(walls, pillars, arena_size, playable := Rect2())`.

### O2. How enemies find the map
The director gets `obstacles` and hands it to each enemy it creates; an enemy with none falls back to
`ObstacleMap.get_for(self)` in `_ready`. The fallback is needed because `tests/fixture.gd` spawns enemies without a director.
The hub has no ObstacleMap, so its dummies get null (also skipped for `immovable`).

### O3. `FlowField.cell_blocked(map, cell)` signature
`static func cell_blocked(map: ObstacleMap, cell: Vector2i) -> bool`: cell centre outside `map.bounds` (the playable
area: the rock band plus `Enemy.ARENA_PADDING`) or inside an obstacle grown by 8 px (`map.blocked(centre, 8)`, so the
growth is round at corners, not square). The sealed-area layout test should build an `ObstacleMap` and call this; pass the
same `playable` rect as `main.gd` (or none: then only obstacles block).

### O4. Spatial grid and radius limit
64 px cells; every shape is listed in all cells within 32 px of it. A point query looks only at the cell of the point, so
`blocked`/`push_out` are valid for radius <= 16; `segment_clear`/`ray_distance` sample the segment every 16 px. Rectangles
use the wall footprint (equal to the CaveWall collider), pillars the circle r=6 at base + (0,-6).

### O5. Order inside `Enemy._physics_process`
Moves in steps of at most 5 px (up to 8), each followed by `push_out`, so a 600 px/s knockback or a dash cannot jump a 16 px
wall (a single push-out tunnelled in a test). Then the arena clamp, then one more `push_out` (the last position change),
then the contact hit and the teleport-back, whose ring position is already obstacle-free.

### O6. Straight-or-flow details
LOS for `chase()` is a swept circle of `hitbox_radius + 6`. An enemy hugging a wall (within that margin of it) therefore
counts as blocked and uses the flow field: harmless, the flow field leads the same way. Flow mode lasts 0.5 s (counted in
physics frames). The first search starts at once (not after 0.25 s) so a run has a field from its first frames.
The field search never restarts while one is running; a search that is slower than 0.25 s (about 6 frames) cannot happen at
the 1,000 budget, so a moving Player is followed with about one search per 0.25 s.

### O7. Ranged and Dasher
- Ranged line of sight is tested on the shot line (both ends lifted by the 8 px shot height) with a 2 px radius, because
  that is the path the projectile flies. APPROACH goes to HOLD only with `dist <= hold_distance` and a clear shot; HOLD goes
  to APPROACH after 0.3 s without one or beyond `resume_distance`. A shot is also re-checked when the wind-up ends: a blocked
  shot is not fired (cooldown 0.2 s).
- Dasher AIM needs LOS with its own hitbox radius (not the 6 px extra). The lane is `ray_distance(dir, dash_distance,
  hitbox_radius)` each AIM frame and once more when the dash starts; if the Player steps behind a wall mid-AIM the dash is just
  short.
- New `EnemyBrain.asks_to_move()` (default true; Ranged only in APPROACH, Dasher only in APPROACH) so the stuck failsafe
  skips holding shooters and a Dasher in AIM/LOCK/DASH/RECOVER.

### O8. Stuck failsafe is a 3 s window
"Moved under 2 px over 3 s" is measured as a window: every 3 s of continuous asking-to-move the position is compared with
the one at the window start. (A rolling anchor that resets at 2 px never fired because a grunt pressed on a wall drifts
about 1 px/s along it.) So a stuck enemy is recycled between 3 and 6 s after it gets stuck. Needs a director (it uses
`ring_position`), so director-less test enemies are never recycled.

### O9. Teleport-back is independent of obstacles
Enemies further than `teleport_distance` (about 415 px) from the Player are still recycled to the ring. Tests that park a
Player far from an enemy therefore see it teleport: keep them close.

### O10. `main.gd` hook
`_build_obstacles()` builds the ObstacleMap from `rock_walls` and the new `prop_positions` (recorded in `_spawn_props`) and
gives it to the director. Marked HOOK: MapBuilder (step 6) replaces it by calling `ObstacleMap.setup()` with the layout.

### O11. Tests
- `tests/maps/obstacle_blocking.gd` removes the arena's legacy walls and pillars and places its own (real `CaveWall` colliders
  plus an ObstacleMap), so it does not depend on any layout. About 60 s of real time (limit 120 s). Do not use
  `Engine.time_scale` in tests: it scales the physics delta, it does not add steps.
- `tests/maps/crowd_bone_warren.gd` uses a HAND-MADE dense layout (10 walls in 5 rows, 2 pillars), marked in the file,
  because `MapLayout` is built elsewhere. Replace `_dense_layout()` with the generator's Bone Warren output later.
- Spec's "20 grunts behind a lane wall" is implemented with a 400 px wall and the Player 120 px behind it.
