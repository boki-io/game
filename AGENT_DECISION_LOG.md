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

## v0.6 layout (build steps 2 and 3: `MapLayout`, `MapLayoutData`)

Assumptions where the spec left room (all in `scripts/maps/map_layout.gd` unless noted):
- **L1. Legacy path duplicates `main.gd`'s pillar loop and torch list.** `main.gd` cannot be edited from this branch, so
  `MapLayout._legacy` copies `_spawn_props` (seed 1, margin 48, skip within 60 of the centre or 16 px of a wall) and the
  hand-placed torches; `CaveWall.layout` and `CaveDecor.layout` are called, not copied. `tests/maps/map_layout.gd`
  pins all four against today's code (the pillar loop copied into the test). Pillar count is `theme.pillar_count` (8).
- **L2. Pillar positions in `MapLayoutData.pillars` are base positions** (a Prop's origin). Every rule is checked on the
  collider centre = base + (0, -6), radius 6. "40 px from walls/pillars" means edge to edge (shape gap 40); "60 px from
  the centre" and "band + 24" are measured on the collider centre; a pillar's circle may not touch the start square.
- **L3. Wall gaps use the Chebyshev `Rect2.grow` test, as `CaveWall.layout` does**: SCATTER 56, LANES between segments
  of any lane 64 (cross pieces 56), CLUSTERS 56 between islands and 40..56 inside an island. The test checks the true
  rectangle distance against 56 (SCATTER) or 40 (others).
- **L4. LANES:** lane coordinates are evenly spaced inside the wall margin with a per-lane jitter of up to 24 px (one
  jitter per lane, not per wall); walls go to lanes round-robin; share on lanes is `round(wall_count * dominant share)`,
  the rest are SCATTER cross pieces in the other orientation. A lane through the spawn clearing is cut by rejection.
- **L5. CLUSTERS:** anchors by rejection (280 apart), a pair is accepted only whole (the last island of an odd count has
  one wall). The L shape hangs the second wall 40..56 px past the first wall's side at one of its ends. The first half
  of the pillars (rounded up) are tried within 90 px of an anchor (60 tries each), then fall back to SCATTER rules.
- **L6. Torches:** distributed over the four sides by side length (largest remainder), even spacing inside
  `[40, length - 40]` with jitter of up to 20% of the spacing, on the same band positions the hand-placed ones use.
- **L7. Decor:** 35% hug the rock band (as `CaveDecor`), the rest are uniform; kind by `decor_weights` (keys sorted so the
  roll does not depend on dictionary order). Off `start.grow(24)`, 8 px off every wall, 14 px off a pillar centre, 26 px
  from the arena edge. Decor stays drawn-only; no new kinds.
- **L8. The sealed-area test implements the flow-field rule locally** (cell centre inside an obstacle grown by 8 px on a
  16 px grid; cells whose centre is in the rock band are neither free nor reachable). It carries a TODO to switch to
  `FlowField.cell_blocked`. "A free cell across every gap" is checked for every pair of obstacles closer than 80 px:
  a free cell centre within 12 px of the midpoint of their closest points (pillars by their bounding square).
- **L9. Seeds in the test** are `hash("%d:%s" % [i, theme.id])` for i in 0..29, the spec's 6.1 form.
- Results: all eight maps place 100% of walls, pillars and decor on all 30 seeds, and 100% of free cells are reachable;
  no theme's numbers in `map.tres` needed changing.
# Agent decision log: spec v0.6, build step 5 ("v0.6 look")

## L1. How the theme gets in
`Ground`, `CaveWalls` and `Prop` take a plain `theme` property (set before `_ready`/drawing), `CaveWall.setup(rect, theme = null)`
and `Ground.setup(theme, seed)`. `CaveDecor` has `theme` too. `Prop` got `class_name Prop` (it had none; `main.gd` still
preloads the script). Null theme gives today's constants; the constants stay in the scripts as the fallback.

## L2. Floor seed and flecks
`Ground.setup(theme, seed_value)`; no `setup` means `DIRT_SEED`, so the hub floor is identical. `floor_flecks` f maps to
pebbled when a roll is above `1 - f` and cracked above `1 - 5f/12`, which reproduces today's 0.88 / 0.95 at f = 0.12.
With a theme the thresholds come from the theme, without one the old literals are used (exact).

## L3. Decor drawing
- Existing kinds are drawn exactly as before (the mushroom keeps its cyan on every map); only the 8 new kinds use `glow_color`.
- Glowing kinds (CRYSTAL, BIG_FUNGUS, CRACK) use plain alpha circles, not an additive material: one material per decor
  node is not worth it for 90 nodes, and it reads the same on dark floors.
- Flat kinds (MOSS, FROST, PUDDLE, CRACK) draw no shadow. No animation, as the spec says.
- `CaveDecor.layout` is untouched (the layout generator agent owns weights and placement).

## L4. Torches
`torch_color` and `glow_color` colour the flame and halo. `torch_count` is not applied here: `main.gd` owns the torch
positions today, so `MapBuilder` must trim `CaveWalls.torches` to `torch_count`.

## L5. Vignette and ambient: `scripts/maps/map_look.gd` (`MapLook`)
`MapLook.apply_vignette(texture_rect, theme)` copies the scene's gradient texture and sets the outer alpha (the scene
resource is shared, so it is not edited in place); `MapLook.apply_ambient(parent, theme)` adds or updates a
`CanvasModulate` named "Ambient". `MapBuilder` should call it on the world's canvas (a child of `Main`/`World`, not of
the `UI` CanvasLayer). `main.tscn` is not edited.

## L6. Default theme comparison
The default theme stores colours with 8 digits, so it equals today's constants only approximately (`is_equal_approx`);
the default arena may therefore differ from the hard-coded look by under 1/255 per channel, which is invisible.
# v0.6 variants

## V1. Sprite fields and the "today" defaults
`PlaceholderSprite.outline_color` defaults to a fully transparent colour, meaning "the body darkened by half" (today's
look); `eye_color` defaults to white, `mark` to `NONE`. The sprite has its own `Mark` enum (same order as
`MonsterVariant.Mark`; the test checks they agree) so the sprite does not depend on the map classes.

## V2. Danger signals stay untouched
The themed outline is used only in the plain look: during the warn blink, the hit flash and the dim the outline is
derived from the current body colour as before. The mark is hidden by the flash and follows the blink and dim
(lightened / darkened like the body). The warn colour and `!` are unchanged.

## V3. Mark shapes (24-32 px bodies, 12x16 to 20x36)
STRIPE: a band across the lower body (at least 2 px). SPOTS: three squares (at least 2 px) low in the body, clear of
the eye. CREST: two or three small triangles inside the top of the body (3 px tall or more; two teeth when the body
is narrower than 14 px). Rendered at several variants and looked at: all three read, the grunt's spots are the
faintest (2 px), which is down to `mark_color` contrast in the variant files.

## V4. Applying
`SpawnDirector._acquire` applies the variant only when `stage.theme` is not null (an editor run has none). Pooled
enemies are not re-dressed. `Enemy.apply_variant(null)` returns without touching anything. The death puff uses
`sprite.body_color`.

## V5. The "no extra fields" guard
`monster_variants.gd` lists the script's own stored properties of `MonsterVariant` and requires exactly the six
appearance fields; behaviour is compared as the same `EnemyData` object plus its fields, the hitbox radius, the brain
script, health and weight read from enemies the director built under every theme and under no theme.

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

# v0.6 wiring (build step 6, `MapBuilder`)

## W1. `MapBuilder.build(theme, seed, size, targets)` and `MapBuilder.Targets`
The builder gets its nodes through a small `Targets` object (ground, cave, props, decor, ambient_parent, vignette,
obstacles_parent; null skips a part) so `main.gd` and the preview scene can call it. It returns the `MapLayoutData`; the
`ObstacleMap` it creates is put in `targets.obstacles`. Walls and pillars go into `props`, decor into `decor`.
`main.gd` has one `_build_map()` and keeps `rock_walls` / `prop_positions` (for every theme, from the layout).

## W2. Ground and CaveWalls are already built when `main._ready` runs
Children run `_ready` before their parent, so main.tscn's Ground and Cave have built the default look by then. `Ground.setup()`
now rebuilds the floor when the node is ready, and `CaveWalls.set_theme()` is new (recolours and rebuilds the rock). One extra
floor build per run (a few ms); the editor run rebuilds it with the default theme, which is the same up to rounding (L6).

## W3. Legacy duplicate removed
main.gd's pillar loop, torch list and constants are gone; `MapLayout._legacy` is now the only copy and the layout test still
pins it against the v0.5 loop (copied into the test). Default theme: floor seed `DIRT_SEED`, legacy layout, so the editor run
and `arena_cave.gd`, `cave.gd`, `crowd_performance.gd` pass unedited.

## W4. `GameSession.map_seed()`
`hash("%d:%s" % [path_seed, theme.id])` of the current stage's theme, 0 with no stage or theme. Non-default themes seed the
floor with it; the layout takes it too.

## W5. Playable rect
`MapBuilder.ENEMY_PADDING = 6.0` repeats `Enemy.ARENA_PADDING` so the builder compiles in a `--script` test before the
autoloads exist; `map_build.gd` checks they are equal.

## W6. Signature decor in `decor_weights`
Added to each map (kind numbers of `CaveDecor.Kind`): Mossy Hollow moss 9 (+ mushroom 5), Crystal Vault crystal 10, Ember
Depths crack 10 (rocks stay at 4 for "scorched rocks"), Frostbite icicle 7 and frost 6, Spore Cavern big fungus 9 and crystal 2
(mushroom lowered 7 to 3), Bone Warren bones 9 to 12, Flooded Gallery puddle 10, Sulfur Pits vent 9. The signature kinds are
40 to 70% of each map's total weight and the largest single weights. Layout, themes, content and look tests pass unchanged.
`_template` keeps Mossy Hollow's old weights (it is a copy for `new_map.py`, not touched here).

## W7. `map_build.gd` and the two test changes
`map_build.gd` runs main.tscn for each theme with `path_seed = 1000 + i` (so the map seed comes from `GameSession.map_seed()`)
and once with no stage. The wall check walks the Player into wall 0 and drops a grunt on the far side (it must move and not
end inside the wall); the floor check counts the theme's `floor_dark` pixels in the dark tile (8-bit tolerance). The layout test's
sealed-area check now builds an `ObstacleMap` with `MapBuilder.playable_rect` and calls `FlowField.cell_blocked`; the result is
unchanged (100% reach on all maps and seeds). `crowd_bone_warren.gd` uses `MapLayout.generate(bone_warren, 12345)`; its gate is a
timing mean on a loaded machine: with other agents running it failed once in four runs (the run without obstacles was just as
slow, 13 and 21 ms), so a single FAIL there under load should be rerun before it is believed.

## W8. Rendered review (real frames, stage flow: `GameSession.new_run`, the stage picked from the path, `main.tscn`)
Looked at Ember Depths, Mossy Hollow, Crystal Vault, Bone Warren and Spore Cavern, close up (normal camera) and with the
camera zoomed to 0.4 to see the whole arena. Each map has its own floor, rock and glow, torches along the band (trimmed to
`torch_count`), its signature decor (ember cracks, moss, cyan crystals, bones, violet fungi), walls and pillars in the theme's
stone, and enemies in the map's colours (orange, yellow, pink). The ambient tint does not hide anything. Nothing was changed
after the look. Seen but not changed: at the full-arena zoom the walls of Ember Depths and Crystal Vault are thin dark lines
close to the floor's value (at the normal zoom they read); worth a pass in the per-map tuning (spec build step 10). The scratch
scene was deleted.
## v0.6 tools

### T1. `new_map.py`
- Copies `_template` without its `.import` and `.uid` files (a copied `.import` would share the template's uid); Godot makes
  the new one on the next `--import`, which the README says to run. Also replaces the `res://content/maps/_template/` paths
  in every copied `.tres`. Refuses: ids that are not lowercase snake_case (so no `_` prefix), an existing folder, an id
  already in `IDS`, and a display name another map already uses (map_content.gd needs unique names).
- Tried with a scratch map: `map_content.gd` and `map_themes.gd` fail for any ninth map, for two reasons the spec's "no
  test changes" did not foresee: both hard-code "eight maps" (`IDS.size() == 8`, `all().size() == 8`), and the template has
  mossy_hollow's palette, so a fresh copy is not 0.05 away from it. The second is right (the map must be given its own look);
  the first is noted in the README (the count checks need updating). Not changed here: `map_content.gd` belongs to another
  track. The scratch map was removed.

### T2. Signature thumbnails (step 9)
- `gen_thumbnails.py` keeps the rock, floor and glow table and the base scene (ceiling, rocks, halo) and replaces the generic
  crystals by one drawing function per map: moss patches and vines, faceted crystal clusters, lava cracks and embers,
  icicles and frost sparkle, glowing mushrooms and spores, a ribcage with a skull, a water pool with drips and ripples, sulfur
  vents with steam. All colours derive from the table's glow/rock/floor. Same 64x40, same seeds (`100 + index`).
- It also writes `_template/thumbnail.png` as a copy of mossy_hollow's, since the template's map.tres has that palette.
- Thumbnail average against the rock/floor blend, measured: 0.017 (frost) to 0.064 (bone warren); the old thumbnails were
  0.047 to 0.091. `THUMB_TOLERANCE` is tightened from 0.12 to 0.07. The 0.05 theme-difference rule is unchanged.


# v0.6 final

## F1. Preview scene and shot tool (step 8, rest)
- `scenes/dev/map_preview.tscn` + `map_preview.gd`: Ground, Decor, Props, Players, Enemies, Cave, Overlay, Camera, vignette and a
  label, built into by `MapBuilder.build` with an `Arena` node (so a walking Player collides). The three monsters are real
  `enemy.tscn` instances dressed with `apply_variant` and then set to `PROCESS_MODE_DISABLED` (a still sample, never in
  `EnemyGrid`). `L` reloads with `CACHE_MODE_REPLACE_DEEP`, so the monster files change too. `Z` and arrow keys are additions.
  The overlay is a child Node2D whose `draw` signal the script handles; its flow field is a private `FlowField` searched at once
  from the Player (or the arena centre). Nothing reads or writes `GameSession` (the test checks `current_stage`/`path_seed`).
- The enemy is created untyped and the shot tool loads the scene at run time: `Enemy` uses autoloads, which do not exist while a
  `--script` file is compiled (a preloaded scene lost its script and failed on `data`).
- `shot_maps.gd` DOES render in `--script` mode when the process is not headless (a window opens). It uses a SubViewport (640x360
  for the normal view, 1600x896 for the whole arena). `await RenderingServer.frame_post_draw` stalled twice (the run hung after a
  few maps), so it uses `process_frame` plus `force_draw(false)` and a 90 s watchdog; three clean runs after that. Not tried:
  an exported build, or a machine with no display.

## F2. Count checks
`map_content.gd` and `map_layout.gd` ask for at least eight maps; `map_content.gd` for one theme per registry id. Tried with a
scratch ninth map (removed): `map_content.gd` and `map_preview.gd` pass; `map_themes.gd` fails only for the unchanged copy
of the palette (rock/floor and layout identical to Mossy Hollow), which is the rule working. `_template` is now a copy of Mossy
Hollow's current files (the old one lacked the moss weight and the new wall and mark colours).

## F3. Rendered review (step 10), real frames of all eight maps, looked at one by one
Before: wall tops and pillars were 0.01 to 0.06 OKLab from the floor on seven maps (only the outline and the south face showed);
grunt spots were 2 px; moss, frost and puddles were faint blobs. Changed (data in the `.tres`, drawing in two scripts):
- Wall top, top light and pillar of seven maps moved 0.15 (tops) and 0.19 (pillars) in OKLab lightness away from the floor (lighter
  on dark floors, darker on Frostbite's pale floor), keeping the hue (chroma x1.3). Bone Warren already read.
- Mark colours of all 24 variants: near white or near black, whichever is further from the body (0.5 to 0.8 OKLab). `PlaceholderSprite`
  marks: spots at least 3 px (0.22 of the width), stripe at least 3 px (0.16 of the height). Appearance only, no new field.
- `CaveDecor` moss, frost and puddle get a rim and stronger fills (code constants, not theme data).
- New checks in `map_themes.gd`: wall top and pillar at least 0.10 from the plain floor, mark at least 0.30 from the body.
- Seen after: the eight read as different places by hue; LANES (Crystal Vault, Flooded Gallery long verticals; Bone Warren
  long horizontals), CLUSTERS (Ember Depths short islands) and SCATTER (Mossy Hollow, Spore Cavern) are recognisable on the whole-arena
  render; at the contact-sheet size the walls are thin lines but visible on all eight. Not changed: the floor's dark patches use
  the same noise shape on every map when the seed is equal (the shot tool uses a seed per map; in runs the seed differs per map).
  Marks are all near black or white now, so the map's identity is in body colour and decor, not in the mark.

## F4. `crowd_bone_warren.gd` run solo
The machine was not idle (the user's own `godot --path .` game and a browser were running, load average 4 to 4.6; nothing of
mine). Eight solo runs: moving mean with obstacles 12.83 (FAIL), 9.77, 16.76 (FAIL), 10.51, 9.87, 9.92, 10.26, 10.73; stationary
8.93, 10.18, 10.72, 8.95, 9.03, 11.27, 9.37, 12.83 (FAIL). The run without obstacles was as slow in the same runs (8.2 to 20.2 ms,
about the same spread), so the noise is the machine's, not the flow field or line of sight (1 search stationary, 13 moving, never more than
1000 expansions in a frame). The 12 ms gate sits close to the baseline's mean (about 9 to 10 ms), so a busy machine trips it.
The gate was NOT loosened; changing the statistic (for example best of three runs) needs the user's approval.
Three more runs (one inside the full `run_all.sh`, two solo) with the user's game still running: FAIL moving 14.52; FAIL stationary
25.08 (without obstacles 11.59); FAIL moving 12.73. So 6 of 11 runs failed under load; the full suite otherwise passed (28 of 29).
The gate needs an idle machine to be meaningful; rerun it once the other `godot` process is gone before believing a FAIL.
