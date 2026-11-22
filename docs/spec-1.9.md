# Spec v1.9: Foundations (performance, scalability and code health)

Builds on everything up to spec 1.8 (the overworld hordes) plus the overworld HUD commit `9b0ee70` on `fixes-0.2` (not yet merged
to `main`, which is at `9e13310`). Branch `fix-0.3`, based on `fixes-0.2` at `9b0ee70`; merge `fixes-0.2` into `main` first, or
rebase this branch onto `main` once it is merged. Status: draft, rev 2, not approved (rev 1: an end-to-end review of the whole
codebase with measured baselines; rev 2 applies an independent review: `crowd_performance` passes and only `crowd_bone_warren` fails,
the grid design's mid-frame removal and result order, the full director API tests use, migrations as a function plus a backup and
a never-cleared read-only flag, warnings as errors for `scripts/` only, the LOS cache gated on a measured hit rate, no stale player
cache, the overworld's off-screen radius, per-zone nature rules that keep the zone filter, timing tests run serially, CI on Ubuntu,
corrected counts).

This spec is not a feature. It is a ranked backlog of the changes the code needs so that more content (zones, enemies, characters,
bosses) can be added without the frame time, the save files or the code structure getting in the way. Nothing the player sees
changes, except that big crowds stay smooth. It is split into phases (A to F) that can each be built and merged alone; phases D to F
may be split off into their own specs when they are reached.

Terms: a **hot path** is code that runs per enemy per physics frame. The **bench** is the headless benchmark of section 3. **Frame
cost** is the wall time of one frame under `--fixed-fps 60` in headless mode (scripts and physics; no rendering). **Severity**:
**Critical** blocks scaling or loses player data, **Important** costs real time or will cause bugs as the game grows, **Minor** is
hygiene.

## Flow

The work goes measure, then fix, then structure. Phase A commits the bench, so every later step can show its numbers before and
after. Phase B makes the enemy crowd cheaper (the one place where the frame time is spent). Phases C and D remove the two structural
traps that every new feature walks into (the enemy director contract and the save files). Phases E and F are content plumbing and
tooling. Each phase ends with the full test suite green except the failures listed in section 13.

## 1. Scope

In scope:
- A committed benchmark and frame-time budgets (Phase A, section 5).
- The enemy crowd hot path: separation, line of sight, the flow field lookup, the spatial grid, contact hits (Phase B, section 6).
- The enemy director contract and the scene service lookups (Phase C, section 7).
- One save module with atomic writes and versioned migrations for the four save files (Phase D, section 8).
- Registries, typed payloads, shared scene plumbing, overworld streaming spikes (Phase E, section 9).
- Tooling: CI, GDScript warnings, a parallel test runner, Git LFS for music (Phase F, section 10).
- The minor findings (section 11).

Out of scope (later specs):
- Any gameplay, balance or content change. Enemy behaviour must stay the same: the existing behaviour tests are the guard.
- A GDExtension (C++) crowd module. It is the next step if the targets of section 6 are not enough for the numbers a later spec
  wants (2,000+ enemies); this spec only keeps the crowd code in a shape that could be ported (one loop over flat data).
- Rendering performance. Headless mode has no renderer; a rendered measurement is a manual step (section 5.3) and its fixes, if
  any, are a later spec.
- Splitting `GameSession` (section 9.5 records the plan; it touches 367 lines of tests and is its own spec).
- Nature props for zones 2 to 8 (section 9.4 only makes the overworld able to load them).
- Exported-build testing on Windows.

## 2. Decisions taken (from the user's answers)

- **Base:** the whole codebase including `fixes-0.2`; branch `fix-0.3` off `fixes-0.2`.
- **File:** `docs/spec-1.9.md`.
- **Shape:** every finding, ranked Critical / Important / Minor, grouped into phases with a build order, tests and a definition of
  done per phase.
- **Measured:** the baselines below come from scratch benchmarks run during the review (kept out of the repo); Phase A commits a
  cleaned-up version of them.

## 3. Baseline measurements

Machine: Apple M1 Pro, Godot 4.7.2.stable, headless, `--fixed-fps 60` (each frame advances one physics tick and nothing sleeps, so
the wall time between two `physics_frame` signals is the cost of one frame). A save path in the scratchpad (`HERO_HORDE_SAVE`).

### 3.1 Arena crowd (`main.tscn`, Knight, invulnerable, enemies at 150 to 330 px, 1,000,000x HP so none die)

Enemies of the three types in turn, made with `SpawnDirector._acquire` and `Enemy.activate` (the pooled path). 60 frames to settle,
then 240 measured.

| Enemies | Spawn all | Frame avg | p95 | Max | Nodes |
|---|---|---|---|---|---|
| 100 | 3.8 ms | 1.84 ms | 2.37 ms | 2.61 ms | 1,327 |
| 300 | 11.0 ms | 5.24 ms | 6.28 ms | 8.85 ms | 2,646 |
| 600 | 22.8 ms | 11.17 ms | 12.80 ms | 28.02 ms | 4,590 |
| 1000 | 37.1 ms | 19.79 ms | 22.79 ms | 25.82 ms | 7,123 |

The cost is linear: about **19 µs per enemy per frame**. At 1,000 the frame budget (16.6 ms) is gone before anything is drawn.
`SpawnDirector.alive_cap` is 300 today (`spawn_director.gd:11`). The two crowd tests pile 300 enemies on the player at 20 to
160 px (denser than the bench above), with a 12 ms mean physics budget:
- `tests/crowd_performance.gd` (the default cave, no walls) **passes**: mean 7.87 ms, 9.91 ms with all relics at level 3.
- `tests/maps/crowd_bone_warren.gd` (the Bone Warren layout) **fails**: 14.42 ms with the player standing, 15.48 ms moving, and
  17.35 ms in its own obstacle-free comparison run. With no walls there is no steering, so in a pile the cost is separation and
  the grid, not line of sight (spec 1.8, O9).

### 3.2 Where the time goes (600 enemies)

One part switched off at a time:

| Switched off | Frame avg |
|---|---|
| nothing | 10.74 ms |
| every `Enemy._physics_process` | 0.63 ms |
| `EnemyGrid._physics_process` (the grid rebuild) | 9.88 ms (the rebuild is about 0.9 ms) |
| the player's abilities (`AbilityCaster`) | 10.68 ms |

So about 95% of the frame is the enemy script. Calling each piece once for every one of the 600 enemies (µs per frame, all 600):

| Call | µs / frame | per enemy |
|---|---|---|
| the whole `Enemy._physics_process` | 6,471 | 10.8 |
| `brain.think` (`chase`: steering and separation) | 2,967 | 4.9 |
| `obstacles.segment_clear` to the player (done every 4th frame) | 2,947 | 4.9 |
| `obstacles.flow_direction` | 2,703 | 4.5 |
| `EnemyGrid.separation` (done every 2nd frame) | 2,433 | 4.1 |
| `obstacles.push_out` (up to 9 a frame) | 387 | 0.6 |
| `PlayerRegistry.nearest` | 309 | 0.5 |
| `global_position` write | 208 | 0.3 |
| `Effects.get_for` (a group lookup) | 152 | 0.25 |
| `hitbox.get_overlapping_areas` | 149 | 0.25 |
| an empty call (loop overhead) | 44 | 0.07 |

Separation, line of sight and the flow field read are the three hot spots. Each is a small GDScript loop that allocates (`Vector2i`
keys, `Array` defaults in `Dictionary.get`, per-call `Array` results).

This profile is of the spread crowd (150 to 330 px) on the default cave. The pile (20 to 160 px, the crowd tests' case) is not
profiled yet; the bone warren numbers of 3.1 say it is dominated by separation and the grid. Phase A profiles the pile on Bone
Warren before Phase B starts, and Phase B's order of steps follows that profile.

### 3.3 Overworld (`overworld.tscn`, Knight, fresh journey, hordes on)

| What | Time |
|---|---|
| `WorldData.shared()` (five 2000 x 2000 masks) | 37 ms |
| `HordePlan.build` (592 hordes, 5,630 planned enemies) | 38 ms |
| the scene's instantiate and `_ready` | 258 ms |
| one `WorldTerrain.build_chunk_now` | 3.2 ms |
| a minute of running the main route at 240 px/s | avg 1.06 ms, p50 0.58, p95 3.89, p99 5.72, **max 48.05 ms** |

The live cap (`HordeRules.max_alive` 120) keeps the overworld far below the arena's cost (at most 39 alive in that minute). One frame
in 3,600 took 48 ms; which work caused it is not known yet (section 9.6).

### 3.4 Test suite

`tests/run_all.sh` on `fix-0.3` at `9b0ee70` (serial, the same machine, while nothing else ran heavy): **93 passed, 1 failed**,
13 min 50 s wall time. The failure is `tests/maps/crowd_bone_warren.gd` (stationary mean physics 13.83 ms, moving 14.99 ms, over
12 ms), the known failure of spec 1.8 (O9). The run's exit warnings include "123 resources still in use at exit" from that test
(F25).

## 4. Findings, ranked

Evidence is `file:line` on `9b0ee70`. The phase is where the fix is designed.

| ID | Sev. | Area | Finding | Evidence | Phase |
|---|---|---|---|---|---|
| F1 | Critical | Perf | The crowd costs 19 µs per enemy per frame; 300 enemies piled on Bone Warren already miss the 12 ms budget (`crowd_bone_warren` fails) and 1,000 spread enemies miss the whole frame | 3.1, 3.2 | B |
| F2 | Critical | Data | Every save file is rejected and renamed `.bad` unless `version == 1`; the first schema change resets the player's gold, attributes, inventory and journeys. There is no migration path | `save_game.gd:83`, `inventory_save.gd:77`, `journey_save.gd:75` | D |
| F3 | Important | Perf | `EnemyGrid.separation` walks Dictionary buckets with a `[]` default per cell and a modulo per neighbour, 4.1 µs a call | `enemy_grid.gd:58-84` | B |
| F4 | Important | Perf | `FlowField.direction_at` and `WorldObstacles.flow_direction` scan 8 neighbours (with `Vector2i` temporaries and `is_blocked` calls) on every call, although the answer only changes when a search completes | `flow_field.gd:112-135`, `world_obstacles.gd:188-217` | B |
| F5 | Important | Perf | Line of sight to the player is computed per enemy, although enemies in the same 16 px cell get the same answer in the same frame | `enemy.gd:394-408`, `obstacle_map.gd:118-134` | B |
| F6 | Important | Perf | The grid is rebuilt from scratch every frame into a Dictionary of new Arrays (0.9 ms at 600) | `enemy_grid.gd:25-32` | B |
| F7 | Important | Arch | `HordeDirector` extends `SpawnDirector` only so `Enemy` finds the fields it reads; `Enemy` checks `has_method("on_stuck")`; `ring_position` returns `null` and `teleport_distance` is `INF` to switch arena behaviour off; pools and the kill-reward code are written twice | `horde_director.gd:1-4, 46, 124, 229-285, 384-398`, `spawn_director.gd:118-152`, `enemy.gd:556, 576` | C |
| F8 | Minor | Arch | Scene services are found with `get_first_node_in_group` on every call (38 call sites, including every `take_damage`); measured at 0.25 µs a call, so kept (7.2) | `effects.gd:30`, `obstacle_map.gd:37`, `damage_zones.gd:10`, `projectiles.gd:13` | C |
| F9 | Important | Data | Four save files each hand-roll the same temp-file write and rename, the same `_is_number`, the same `.bad` handling; `audio.gd` writes its settings without a warning on failure and reads without a version check | `save_game.gd:30-49`, `inventory_save.gd:18-42`, `journey_save.gd:17-44`, `audio.gd:256-281` | D |
| F10 | Important | Data | `tests/run_all.sh` deletes a hard-coded list of save suffixes and misses `.settings`, so every run leaves files in the temp folder; a new save file needs another edit there | `tests/run_all.sh:14` | D |
| F11 | Important | Code | Ability and zone options are untyped Dictionaries (`opts`, `extras`, `belt`); a misspelt key is silently ignored | `player_projectile.gd:36-48`, `damage_zones.gd:32-49, 68-71`, `player.gd:200, 234` | E |
| F12 | Important | Content | Registries are hand-kept path lists, and `find()` loads every entry on every call (`ItemRegistry.find` in save parsing and on every pickup) | `item_registry.gd:30-44`, `relic_registry.gd`, `character_registry.gd`, `map_registry.gd` | E |
| F13 | Important | Content | The overworld loads one nature rule set (`mossy_hollow`) for all eight zones, and two `load()` calls of `hordes.tres` live in scene code | `overworld.gd:65, 90, 99` | E |
| F14 | Important | Tooling | No CI: the suite (94 tests and 4 helpers) only runs when someone remembers | repository | F |
| F15 | Important | Tooling | No GDScript warning settings in `project.godot`: `scripts/` and `content/` are almost fully typed (about 8 untyped `var`s, 8 untyped parameters and 1 function without a return type, mostly deliberate duck types such as `WorldProps.sprites`), but nothing keeps it so. Tests are untyped on purpose (CLAUDE.md) | `project.godot`, `world_props.gd:16, 23`, `nature_layout.gd:245` | F |
| F16 | Important | Perf | One 48 ms frame in a minute of overworld running; the cause is unmeasured (a chunk build and its props land in the same frame through `chunk_built`) | 3.3, `world_terrain.gd:10, 92-106`, `world_props.gd:27, 43` | E |
| F17 | Minor | Code | The item banner (show, wait, fade) is written twice | `main.gd:57-80`, `overworld.gd:243-267` | E |
| F18 | Minor | Perf | `Effects` keeps particles, numbers and effects as Dictionaries and rebuilds three arrays with `filter()` every frame | `effects.gd:199-212` | E |
| F19 | Minor | Code | `AbilityCaster.value` formats a new `StringName` per stat read; `Stats.value` walks every conditional source per read | `ability_caster.gd:84-85`, `stats.gd:12-16` | E |
| F20 | Minor | Code | `Pickups.roll_item_drop` makes and seeds a new `RandomNumberGenerator` per kill and builds `lying_item_ids()` twice | `pickups.gd:95-107` | E |
| F21 | Minor | Code | `GameSession._stage_kills` reads `run_manager` from the current scene by name | `game_session.gd:370-374` | E |
| F22 | Minor | Code | `Arena.world_size` is a static set in `_enter_tree` and only correct if the Arena is the scene's first child | `arena.gd:10-25` | C |
| F23 | Minor | Repo | 45 MB of music is in plain git (`assets/music/`); the repository is 58 MB | `du` | F |
| F24 | Minor | Code | `EnemyGrid.separation` uses the global `randf()` for two enemies on the same spot | `enemy_grid.gd:78` | B |
| F25 | Minor | Runtime | 29 to 31 resources are reported in use at exit (static caches: `WorldData._shared`, `PropCatalog`, `HordeSites`) | bench output | E |
| F26 | Minor | Tests | The suite runs one Godot per test in sequence | `tests/run_all.sh` | F |

What the review found in good shape, and this spec keeps: strict static typing; pooling for enemies, pickups, projectiles and effect
sprites; the brain strategy objects (`EnemyBrain`); content as `.tres` data with a template per kind; explicit path lists that work
in exported builds; atomic save writes; seeded generation; the `scene_hook` test seam; staggered work (LOS every 4th frame,
separation every 2nd, budgeted flow field searches, chunk builds one per frame); the placeholder sprite that only redraws on change.

## 5. Phase A: measure (bench and budgets)

### 5.1 `tools/bench/`

- `tools/bench/crowd.gd` (a `SceneTree` script): the arena crowd of 3.1. Arguments after `--`: `counts=100,300,600,1000`,
  `spread=150-330` (px; `20-160` is the crowd tests' pile), `map=` (empty for the default cave, or a map id such as
  `bone_warren`, laid out with a fixed seed as `crowd_bone_warren.gd` does), `frames=240`, `runs=3`, `mode=` one of `all`,
  `no_enemy_script`, `no_grid`, `no_player_attacks`, `no_hitbox`, `profile` (the per-call table of 3.2). Prints one `BENCH` line per
  count: enemies, spawn time, frame avg, p95, p99.9 and max over all runs, node count. In `profile` mode it also prints the LOS
  cache hit rate that 6.3 would get (pairs of 16 px cells asked twice in a frame over all asks).
- Tests and tools that create `Enemy` or `Player` follow CLAUDE.md: untyped variables, `tests/fixture.gd` loaded with `load()`,
  `await process_frame` first.
- `tools/bench/overworld.gd`: the overworld run of 3.3. Prints the load times, the frame percentiles and **every frame over 16.6 ms
  with what happened in it** (chunks built and freed that frame, hordes materialised, props placed), so F16 can be found.
- `tools/bench/README.md`: how to run them (`godot --headless --fixed-fps 60 --path . --script tools/bench/crowd.gd -- counts=600`,
  with `HERO_HORDE_SAVE` set), and a table of the baselines of section 3 and of each phase's results, with the machine.

They are tools, not tests: wall time depends on the machine, so they never fail. `tools/*` is already excluded from exports.

### 5.2 Budgets (the targets of this spec, on the M1 Pro baseline machine)

| Metric | Baseline | Target after Phase B |
|---|---|---|
| Crowd 300, frame avg | 5.24 ms | ≤ 3.0 ms |
| Crowd 600, frame avg | 11.17 ms | ≤ 6.0 ms |
| Crowd 1000, frame avg | 19.79 ms | ≤ 10.0 ms |
| Pile 300 on Bone Warren (`spread=20-160 map=bone_warren`), frame avg | measured in step 1 | half of the step 1 number |
| `crowd_performance.gd` mean physics | 7.87 ms (passes) | still passes, and lower |
| `crowd_bone_warren.gd` (all three of its runs) | 14.42 / 15.48 / 17.35 ms (fails) | each under 12 ms (passes) |
| Overworld, p99.9 frame over three one-minute runs | max 48 ms in one run | ≤ 16.6 ms, or the cause logged in the spec's build notes |

The two crowd tests keep their 12 ms budget (they measure the engine's physics time, which is comparable across runs on one
machine). If a target is missed after every step of Phase B, the build notes say by how much and the GDExtension option of section 1
is raised with the user; the targets are not lowered silently.

### 5.3 Rendered check (manual)

The bench is headless. Once per phase that touches the crowd, the builder runs the arena with 600 enemies in a window (a scratch
scene, F3 overlay on) and writes the FPS in the bench README. This is recorded as checked or not checked in the PR, never assumed.

## 6. Phase B: the enemy crowd (F1, F3 to F6, F24)

The behaviour must not change: the same steering rules, the same separation formula and neighbour cap, the same LOS rule, the same
stuck and teleport rules. Every existing enemy, steering, horde and ability test is the guard. Each step is measured with the bench
(600 and 1000) and the numbers go in the commit message and the bench README.

### 6.1 Flat spatial grid (`EnemyGrid`, F6, F3)

Replace the `Dictionary` of `Array` buckets with flat packed data rebuilt each frame with few allocations:
- `register`/`unregister` keep today's `_enemies` Dictionary (unregister runs mid-frame on every kill, through `release`, so the
  per-frame data must not depend on it).
- At the rebuild, a snapshot: `_frame: Array[Enemy]` (the registered enemies copied once), `_pos: PackedVector2Array` (their
  positions at that moment), `_order: PackedInt32Array` (indexes into `_frame` sorted by cell), and for each occupied cell a run
  id: a `Dictionary` from the `int` cell key to the run id, with `_run_start` and `_run_end: PackedInt32Array`. Queries index
  `_frame` and keep today's `e.active` check, so an enemy released earlier in the frame is still skipped.
- Cell key: `cy * 65536 + cx` with 32 px cells (right for cells within ±32,767, which covers the 32,000 px world and the negative
  positions just outside it). The sort builds a `PackedInt64Array` of `key << 20 | index` and calls its native `sort()`; the
  index is decoded with `& 0xFFFFF` and the key with `>> 20` (an arithmetic shift, so negative keys decode right). Up to 1,048,575
  enemies fit in the 20 bits.
- `query`, `nearest` and `separation` keep their signatures. Two differences are accepted and documented in the class comment:
  the order within a cell is now the sort's (index order of the snapshot), not registration order, so under the
  `max_neighbors` cap a different subset of neighbours can be read; and positions are the rebuild's snapshot, not the live
  `global_position` (enemies have moved at most one frame's step since). `query`'s result order changes too; its callers that stop
  after N hits sort first or pick by distance (`player_projectile.gd:84` sorts; `frost_comet.gd:48` and any other caller is checked
  in this step and made order-independent where it caps).
- F24: two enemies on the same spot are pushed apart along a direction from the pair's instance ids, opposite for the two
  (`Vector2.from_angle(float((min_id * 31 + max_id) % 628) / 100.0)`, negated for the higher id), not `randf()`.
- Test: `tests/enemy_grid.gd` (new): for 30 seeds, random positions (some coincident, some negative, some beyond 32,000 px):
  `query` and `nearest` equal a brute-force scan **as sets** (and `nearest` by distance); `separation` equals a reference function
  in the test that is given the same snapshot and order; an enemy unregistered or deactivated after the rebuild is never returned
  and does not shift any other result; two coincident enemies are pushed in opposite directions.

### 6.2 Flow direction memo (F4)

`FlowField` and `WorldObstacles` keep, next to the live distance field, a `PackedByteArray` of the direction code per cell (0 = not
computed, 1 = no better neighbour, 2 to 9 = the eight steps) and clear it when a search completes and replaces the live field
(`step()` swaps the buffers; the memo is `fill(0)`ed at the same moment). `direction_at`/`flow_direction` return the memo when it is
set, else compute it as today (in a `_compute_direction(cell)` that tests can call directly) and store it. Crowds stand in few
cells, so the 8-neighbour scan runs about once per occupied cell per search instead of once per enemy per call. The `fill(0)` is
22,400 bytes for the arena field and 9,216 for the overworld window.
- Test: `tests/maps/flow_memo.gd` (new; `FlowField` is covered today inside `tests/maps/obstacle_blocking.gd` and
  `tests/overworld/world_obstacles.gd`, which must pass unchanged): for 30 seeds of map layouts, the memoised direction equals the
  computed one for every free cell, before and after a second search completes; the same for a `WorldObstacles` window.

### 6.3 Shared line of sight (F5)

**Gated:** only a quarter of the enemies refresh LOS in a frame and a 16 px cell holds one or two enemies at 12 px separation, so
the cache may rarely hit. This step is built only if the bench's `profile` mode (5.1) shows a hit rate of at least 30% in the
600-enemy spread crowd or the Bone Warren pile; otherwise it records the rate and changes nothing.

`ObstacleMap.segment_clear` is called per enemy to the player in `Enemy._steer` (through `has_line_of_sight`) and
`_home_velocity`. Add `ObstacleMap.clear_to(from: Vector2, target: Vector2, radius: float) -> bool`, which caches the answer per
(16 px cell of `from`, 16 px cell of `target`, radius rounded to 1 px) for the current physics frame (a `Dictionary` with an `int`
key, cleared when `Engine.get_physics_frames()` changes). `Enemy._steer` and `_home_velocity` call `clear_to` directly;
`Enemy.has_line_of_sight` is unchanged (it is also used by `dasher_brain.gd:37` and by `ranged_brain.gd:65` with a `SHOT_HEIGHT`
lift, which must stay exact), and so are `HordeDirector._sees`, the projectiles and the abilities.
- This changes the answer for an enemy whose exact line differs from its cell's first asker. That is accepted: the line is only
  used to choose between walking straight and following the flow field, and the field is correct everywhere. The steering tests
  (`tests/maps/obstacle_blocking.gd` and the stuck tests) must still pass unchanged; if one fails, the cache key gains the 8 px
  sub-cell (and the build notes say so).
- Test: `clear_to` equals `segment_clear` for the first caller of a cell pair in a frame, the cache empties on the next frame, and
  `WorldObstacles` inherits it.

### 6.4 One target per frame, and contact hits (F1)

- `PlayerRegistry.nearest` gets a fast path with no cache (tests set `p.dead` directly, so a cached player would go stale):
  `if players.size() == 1: return null if players[0].dead else players[0]`. The result is the same.
- Contact hits: measure with `crowd.gd mode=no_hitbox` (enemies' `Hitbox` monitoring off) at 600 and 1000. **Only if** the
  physics server's share is over 1 ms at 600 does this step replace the enemy `Hitbox` `Area2D` with a distance test against each
  living player's `Hurtbox` circle (the hurtbox shape's radius plus `data.hitbox_radius`, measured between the two shapes' centres:
  the enemy hitbox sits at (0, -6) in `enemy.tscn`, and the hurtbox at its own offset in `player.tscn`), keeping `contact_interval`, the
  `brain.can_contact()` gate and `Hurtbox.receive_hit`. Otherwise the step records the number and changes nothing. (The review's
  quick test was inconclusive.)

### 6.5 Off-screen ticking (only if 6.1 to 6.4 miss the targets)

Enemies farther than `EnemyDirector.offscreen_radius` from every player run their full tick every second physics frame
(alternating by instance id) with twice the delta; contact hits are impossible there. `offscreen_radius` is computed in
`EnemyDirector._ready` from the viewport size in `project.godot` (half its diagonal plus 24 px, today's `ring_radius`), for both
directors: `HordeDirector._ready` does not call `super` today, so its inherited `ring_radius` is 0 and must not be used. (This
step comes after Phase C if it is needed; before Phase C the field goes on `SpawnDirector` and `HordeDirector` calls `super`.) Their LOS refresh and separation already stagger. This is the
only step that can change behaviour slightly (a far enemy's path is integrated at 30 Hz), so it is built last, only if needed, and
the stuck and teleport tests must still pass.

### 6.6 What Phase B does not do

No change to the brains, the statuses, the separation weights or radii, the number of push-out steps, or the alive caps. Raising
`alive_cap` is a balance decision for a later spec, made with the new numbers.

## 7. Phase C: structure the enemy director and the scene services (F7, F8, F22)

### 7.1 `EnemyDirector` (`scripts/enemy/enemy_director.gd`, new)

A base class `EnemyDirector extends Node` that owns what both directors share today and what `Enemy` calls:
- Pools stay per subclass, because tests reach into them: the arena keeps `_pools: Dictionary` keyed by `EnemyData`
  (`tests/gold.gd:65`, `tests/inventory/item_drop.gd:332`, `tests/vacuum_magnet.gd:213` assign `_pools[data] = []`), the overworld
  keeps `_zone_pools`. The base has `release(enemy)`, `alive`, `alive_by_type`, `enemies_root`, `obstacles`, and a virtual
  `_return_to_pool(enemy)` each subclass implements.
- `reward(enemy, xp: int)`: the gem, coin, magnet and item drop rolls of today's two `_on_enemy_died`, with `coin_bonus`, `stage`
  (for `coin_chance`) and the rewards node as fields. The rewards node stays untyped (`_rewards: Node`): `horde_fixture.gd:19, 70`
  passes a plain `Node` stand-in. The arena passes `stage.scaled_xp(xp_drop)`, the overworld `roundi(xp_drop * xp_mult)`. The rolls
  use a `RandomNumberGenerator` field (`rng`, randomized in `_ready`, settable by tests) instead of the global `randf()`
  (`spawn_director.gd:146`, `horde_director.gd:390`); `Pickups.roll_magnet` gains an optional `rng` parameter like
  `roll_item_drop` has (F20).
- The calls `Enemy` makes: `teleport_distance` (float, `INF` = never), `ring_position(around) -> Variant` (null = none) and
  `on_stuck(enemy, target)`, virtual; the base `on_stuck` does nothing and `teleport_distance` is `INF`. `Enemy.director` is typed
  `EnemyDirector` (today `SpawnDirector`, `enemy.gd:49`).
- `SpawnDirector extends EnemyDirector` keeps the timed ring spawning, `ring_position`, `teleport_distance` and gains `on_stuck`
  with today's arena behaviour from `enemy.gd:579-582`: teleport to `ring_position(target.global_position)` and reset the enemy's
  stuck anchor (a public `enemy.reset_stuck()`). `HordeDirector extends EnemyDirector` directly (no arena exports to switch off);
  its `on_stuck(e, _target)` keeps today's body.
- `Enemy._check_stuck` and `_check_home_stuck` call `director.on_stuck(self, target)` (the home check passes null) with no
  `has_method`. Their timing rules stay.
- Every member tests and scenes use today stays, with the same name and meaning: on `SpawnDirector` `release`, `alive`,
  `alive_by_type`, `_acquire(type)`, `_pools`, `_on_enemy_died`, `apply_stage`, `coin_bonus`, `enemy_types`, `obstacles`,
  `run_manager`, `pickups`, `enemies_root`, `stage`, `ring_radius`, `teleport_distance`, the exports in `main.tscn`; on
  `HordeDirector` `setup`, `live_count`, `prewarm`, `prewarm_pending`, `reset`, `horde_of`, `live_horde_ids`, `_live`, `_wake`,
  `rules`, `journey`, `world`, `on_stuck`, `kills`, `safe_points`, `den_cleared`. The builder greps `tests/` for both class names
  and their instances before the step and lists anything else found in the commit message.
- Test: `tests/enemy_director.gd` (new): for 30 seeds, the arena and overworld reward paths given the same `rng` seed, the same
  enemy data and the same chances produce the same drops as each other (today's code cannot be replayed: it uses the global RNG);
  a stuck arena enemy is teleported to the ring and its anchor reset, and a stuck overworld enemy is sent home, both through
  `on_stuck`.

### 7.2 Scene services (F8): no step

The group lookups were measured at 0.25 µs a call (3.2), so they are not a cost, and a scene change never has two play scenes in the
tree at once (`SceneFader` changes the scene, it does not overlay one). They stay. The one rule this spec adds: a new scene service
follows the same `get_for(node)` pattern (a group, a static `get_for`), so the callers stay uniform.

### 7.3 `Arena.world_size` (F22)

Keep the static (it is read on hot paths), but set it from `Arena._enter_tree` **and** assert in debug builds (`assert`) that the
Arena is its scene root's first child; the overworld and main scenes already satisfy it. The doc comment says why.

## 8. Phase D: one save module with migrations (F2, F9, F10)

### 8.1 `SaveFile` (`scripts/systems/save_file.gd`, new, static, no autoload)

- `SaveFile.write_json(path: String, data: Dictionary) -> bool`: the temp-file write and rename used by all four files today, with
  the warning on failure.
- `SaveFile.read_json(path: String) -> Variant`: today's read rules (a missing file falls back to `.tmp`, an empty file is null, a
  file that does not parse is renamed `.bad` and gives null).
- `SaveFile.is_number(v) -> bool` (the four copies of `_is_number` go).
- `SaveFile.suffixes() -> PackedStringArray`: every suffix the game writes next to the base path (`""`, `.inventory`,
  `.settings`, `.journey.<id>` for every `CharacterRegistry` id, each with `.tmp`, `.bad` and the migration backups `.v<N>` of
  8.2). `tests/run_all.sh` runs `godot --headless --path . --script tools/save_suffixes.gd` **once** before its loop, keeps the
  list, and deletes those files after each test, so F10 is fixed and a new file needs no runner edit. Save tests that write
  their own PID-named files outside `$save` clean up after themselves as today (unchanged).

### 8.2 Versions and migrations

- Each file keeps its own `VERSION` (camp 1, inventory 1, journey 1, settings 1). Migrations are a function, not a constant table
  (a `Dictionary` of Callables is not a constant expression in GDScript): `SaveFile.migrate(root: Dictionary, current: int,
  step: Callable) -> Dictionary`, where `step.call(root, from_version)` returns the root at `from_version + 1` (each file's step is a
  `static func _migrate_step(root, from)` with a `match`). Tests pass their own `step`.
- Loading a root with a version below the current one: the original file is first copied to `<path>.v<N>` (N its version, kept,
  never overwritten), then the root is migrated step by step and parsed by today's checks. A file that fails the checks after
  migration is renamed `.bad` as today (the `.v<N>` copy stays).
- Loading a version **above** the current one (a save from a newer build): the file is left untouched, the game runs with a fresh
  state in memory, and that file is **read-only for the rest of the session**: every write to it is refused with a warning. The flag
  is never cleared automatically (not by a new game, not by a later save). The player sees it: the hub shows a one-line notice
  ("This save is from a newer version and will not be changed") the first time the hub loads in such a session.
- No migration exists yet (all files are at 1); this phase adds the mechanism and a test migration.
- Settings (`audio.gd`) use `write_json` and the version check, but keep their lenient read: a missing, unreadable or newer
  settings file gives full volume and is **not** renamed `.bad` (today's behaviour, checked by `tests/sound_settings.gd`); a newer
  one is read-only like the others.
- Test: `tests/save_file.gd` (new): write/read round trip; `.tmp` fallback; `.bad` on garbage; a v0 test root migrated through a
  test `step`, with the `.v0` backup written once and left alone by later saves; a version-2 file is left untouched and every later
  write in the same session is refused; a garbage settings file is not renamed; `suffixes()` covers every file the existing save
  tests create. The existing `tests/camp/camp_save.gd`,
  `tests/inventory/inventory_save.gd`, `tests/overworld/journey_save.gd` and `tests/sound_settings.gd` pass unchanged.

## 9. Phase E: content plumbing and code hygiene (F11 to F13, F16 to F21, F25)

### 9.1 Registries (F12)

Each registry (`CharacterRegistry`, `ItemRegistry`, `RelicRegistry`, `MapRegistry`, `AttributeRegistry`) loads its list once into a
`static var _by_id: Dictionary` on first use; `all()` returns a copy of the cached list in the same order, `find(id)` is a
Dictionary lookup. `ItemRegistry.test_items` keeps working (it bypasses the cache while non-empty). The path lists stay explicit
(exported builds cannot list folders), and each registry gains the test `MapRegistry` already has (`tests/maps/map_content.gd`):
every content entry on disk is listed and every listed path exists (`tests/registries.gd`, new). Entries are folders with the
resource file for characters, items, relics and maps, and flat `.tres` files for attributes (`content/attributes/*.tres`); the
`_template` and `_default` folders are excluded. The new static caches get a `clear()` and count toward F25 (9.7).

### 9.2 Typed options (F11)

- `ProjectileOptions` (`scripts/abilities/projectile_options.gd`, `RefCounted`): `hits`, `bounces`, `bounce_reach`, `arrow`,
  `steady`, `steady_full`, with today's defaults. `PlayerProjectile.launch` and `PlayerProjectiles.fire` take
  `opts: ProjectileOptions = null`. In `scripts/` and `content/` there are 5 `PlayerProjectiles.fire` callers and 1 `launch`;
  the 3 that pass options move to it (the enemy `Projectiles.fire` is not touched).
- `ZoneEffects` (`scripts/systems/zone_effects.gd`, `RefCounted`): `sfx`, `shake`, `visual`, `stun`, `freeze_seconds`,
  `freeze_vulnerable`, `slow_factor`, `slow_seconds`, `ignite_dps`, `ignite_seconds`. `DamageZones.add_burst` and `add_field` take
  `extras: ZoneEffects = null`; zones become an inner class instead of Dictionaries. The 6 callers in `scripts/` and `content/`
  move to it.
- The Phase Shift belt (`Player.start_phase(belt)`) takes an `OrbBeltParams` or stays a Dictionary with a doc comment listing the keys
  (the builder chooses; one caller in the game).
- Tests that pass Dictionaries change with it: `tests/archer_arrows.gd:86, 132, 318`, `tests/enemy_status.gd:355, 372`,
  `tests/relic_orbs_trail.gd:129`, and `tests/phase_belt.gd:26` if the belt changes. The edit is mechanical (the same values in
  the typed object); no assertion changes. Behaviour is unchanged; the ability and relic tests are the guard.

### 9.3 Small hot-path cleanups (F18 to F20)

- `AbilityCaster.value` caches the composed `StringName` per (ability id, stat) in a Dictionary.
- `Stats.value` skips the conditional loop when `_conditional` is empty (the common case).
- `Pickups.roll_item_drop` uses one `RandomNumberGenerator` field (seeded once, settable by tests) and computes
  `lying_item_ids()` once.
- `Effects` keeps its public API; its bits move to packed arrays (`PackedVector2Array` positions and velocities, `PackedFloat32Array`
  ages and lives, `PackedColorArray` colours) with swap-remove, and numbers and effects are removed in place instead of `filter()`.
  Its tests (`tests/impact_feedback.gd`, `tests/movement_feel.gd`, `tests/ambience.gd`) must pass unchanged.

### 9.4 Overworld data per zone (F13)

- `HordeRules` and `NatureRules` are loaded once by `Overworld._ready` into fields (`hordes.tres` is no longer loaded twice).
- `NatureRules` already names its zone (`nature_rules.gd:10`) and the layout already keeps to that zone's tiles
  (`nature_layout.gd:164, 176`). So `WorldProps` takes a list of rule sets (`setup_all(world, rules: Array[NatureRules], terrain,
  sprites)`) and, for each chunk, runs **every** rule set whose zone has tiles in that chunk; a border chunk gets the props of both
  zones, each on its own tiles. There is no fallback to zone 0's rules (they would place nothing outside zone 0). The existing
  3-argument `setup` stays (it is `setup_all` with one rule set; `tests/overworld/nature_props.gd:36` uses it). The overworld loads
  the rule sets from a `const` list of paths in `Overworld` (today only `mossy_hollow.tres`), so the world looks the same; adding a
  zone's props becomes a data file plus one entry.
- Test: added to `tests/overworld/nature_layout.gd`: with a second test rule set for zone 1, a chunk on the zone 0 / zone 1 border
  gets props from both, each on its own zone's tiles; a chunk wholly in zone 0 is the same as today.

### 9.5 `GameSession` (recorded, not built here)

`GameSession` (374 lines) holds the stage path, the dungeon run, the camp shop, the inventory, the journey, the purse and the scene
routing. The plan for its own spec: `RunState` (path, column, stage, kills, purse, progress, dungeon), `CampState` (gold,
attributes, inventory, saving) and `GameSession` as the router with forwarding properties so the 97 script and 367 test references
keep working during the move. F21 (`_stage_kills` reading the scene's `run_manager`) is fixed here already: `RunManager` registers
itself with `GameSession` in `_ready` and unregisters in `_exit_tree`.

### 9.6 Overworld spikes (F16)

With `tools/bench/overworld.gd` listing the frames over 16.6 ms:
- If the spike is a chunk build plus its props: `WorldTerrain` already emits `chunk_built` (`world_terrain.gd:10`) and
  `WorldProps` builds in the same call (`world_props.gd:27`). The handler queues the chunk instead and `WorldProps` builds at most
  one queued chunk's props per physics frame, never in a frame in which a terrain chunk was built. A chunk freed while queued is
  dropped from the queue.
- If it is a horde materialisation: `HordeDirector` already caps `materialise_per_frame`. Splitting one horde's enemies over
  frames would show a half-made horde, so instead the prewarm is raised (`prewarm(count)` sized so the pools of the zones the hero
  is in never run empty on the zone 0 route; the bench logs pool misses) and a pool miss is logged.
- Otherwise the build notes record the cause and the step stops there.
- Done when the p99.9 frame of three one-minute bench runs is under 16.6 ms on the baseline machine, or the cause is recorded.

### 9.7 Shared banner (F17) and exit leaks (F25)

- `ItemBanner` (`scripts/ui/item_banner.gd`, `class_name ItemBanner extends Label`): `show_text(text, color, hold, fade := 0.5)`
  with today's pause-proof timer and tween and the "a newer call wins" id. The script is attached to `UI/ItemBanner` in
  `scenes/main.tscn` (hold 3.0 s, `main.gd:5`) and `UI/Banner` in `scenes/overworld.tscn` (hold 2.5 s, `overworld.gd:12`); the
  times stay as they are. `main.gd` and `overworld.gd` call it; their banner tests pass unchanged.
- Static caches gain a `clear()` used by tests that check exit cleanliness; the exit warning is reduced to the resources Godot
  itself keeps. If it cannot reach 0 cheaply, the build notes list what is left.

## 10. Phase F: tooling (F14, F15, F23, F26)

### 10.1 GDScript warnings (F15)

Tests are untyped on purpose (CLAUDE.md: a typed variable of a class that uses an autoload does not compile in a `--script`
test), so the warnings must not become errors there.
- In `project.godot` (`[debug]`): `gdscript/warnings/untyped_declaration=1`, `unsafe_property_access=1`,
  `unsafe_method_access=1`, `unsafe_cast=1`, `unsafe_call_argument=1` (warn), `inferred_declaration=0`,
  `return_value_discarded=0`. If Godot 4.7 supports per-directory warning rules (`debug/gdscript/warnings/directory_rules`), the
  step sets `untyped_declaration` to error for `res://scripts`, `res://content` and `res://tools` and to ignore for `res://tests`;
  if it does not, the setting stays a warning everywhere and a check in the test suite (`tests/typing.gd`, new: scans the `.gd`
  files of `scripts/` and `content/` for untyped `var` declarations, untyped parameters and functions without a return type)
  fails on a new one, with an allow-list for the deliberate duck types.
- The step types what can be typed in `scripts/` and `content/` (about 8 untyped `var`s, 8 untyped parameters and 1 function
  without a return type: `map_builder.gd:15`, `path_generator.gd:86`, `world_props.gd:16, 23`, `horde_plan.gd:78, 147, 315, 332`,
  `nature_layout.gd:55, 64, 112, 245, 250`, `nature_sprites.gd:26, 37`, `audio.gd:262`) and annotates the deliberate duck types
  (`sprites`, `sites`, `horde`, `trail`) with a comment and an allow-list entry.

### 10.2 Parallel runner (F26)

`tests/run_all.sh` gains `-j N` (default: the number of cores minus one) running tests through `xargs -P`, each with its own save
path and its own time limit, output collected per test and printed in file order. Tests that time themselves run serially after
the parallel batch, from a list in `tests/timing_tests.txt`: `crowd_performance`, `maps/crowd_bone_warren`, `maps/map_large`,
`maps/map_layout`, `overworld/world_obstacles`, `overworld/nature_props`, `enemy_status`, `stage_flow` (the builder greps for
`get_ticks` and `TIME_PHYSICS_PROCESS` in `tests/` to complete it). The serial mode stays (`-j 1`). The time of a full run before
(13 min 50 s, 3.4) and after is recorded in `tests/README.md`.

### 10.3 CI (F14)

`.github/workflows/tests.yml`: on push and pull request, an `ubuntu-latest` runner installs `zsh` (the runner is a zsh script;
`ubuntu-latest` does not ship it), downloads the Godot 4.7.2 `linux.x86_64` editor binary (pinned URL and SHA-256; it runs with
`--headless`, there is no separate headless build), caches it, checks out with `lfs: true` if 10.4 is accepted, runs
`godot --headless --path . --import`, then `tests/run_all.sh -j 2`. Known failures (section 13) are listed in
`tests/known_failures.txt` and reported but do not fail the job; any other failure does. The tests in `tests/timing_tests.txt`
(10.2) skip their timing assertions when `HERO_HORDE_CI=1` is set (shared runners are not the baseline machine) but still run their
behaviour checks and still print `PASS`, so the runner counts them.

### 10.4 Git LFS for music (F23)

`.gitattributes` tracks `assets/music/*.mp3` (and `*.ogg`, `*.wav` under `assets/music/`) with Git LFS for new and changed files.
Rewriting history to move the existing 45 MB is **not** done (it would need a force-push, which the project does not allow); the
README says LFS must be installed to clone. The existing mp3s match the pattern but are plain blobs, so Git LFS prints "should
have been pointers" for them; the step records that this warning is expected (or narrows the pattern to new file names). Asked in
O3.

## 11. Minor findings not given a step

- The HUD, minimap and world map draw text with `ThemeDB.fallback_font` in `_draw`; a project `Theme` with the pixel font would let
  menus and HUD share one look and make localisation possible. A later UI spec.
- `PlaceholderSprite.facing` redraws every frame for a moving enemy (it changes every frame while chasing); with real art on every
  enemy this goes away. Not worth a step.
- `Overworld._update_markers` loops all 108 markers every physics frame; cheap today (108), a grid like `HordeDirector`'s if the
  marker count grows past about 1,000.
- `HordeDirector._behave` iterates `_of_enemy.keys()` (a new Array per frame); fine at the 120 cap.

## 12. Files

New: `tools/bench/crowd.gd`, `tools/bench/overworld.gd`, `tools/bench/README.md`, `scripts/enemy/enemy_director.gd`,
`scripts/systems/save_file.gd`, `tools/save_suffixes.gd`, `scripts/abilities/projectile_options.gd`,
`scripts/systems/zone_effects.gd`, `scripts/ui/item_banner.gd`, `.github/workflows/tests.yml`, `tests/known_failures.txt`,
`tests/timing_tests.txt`, `.gitattributes`; tests `tests/enemy_grid.gd`, `tests/maps/flow_memo.gd`, `tests/enemy_director.gd`,
`tests/save_file.gd`, `tests/registries.gd`, and `tests/typing.gd` if 10.1 needs it (with their `.uid` files). New tests that
create `Enemy` or `Player` use the fixture and untyped variables (CLAUDE.md); tests of new `class_name` types `preload` them.

Changed: `scripts/systems/enemy_grid.gd`, `scripts/maps/flow_field.gd`, `scripts/maps/obstacle_map.gd`,
`scripts/overworld/world_obstacles.gd`, `scripts/enemy/enemy.gd`, `scripts/systems/player_registry.gd`,
`scripts/systems/spawn_director.gd`, `scripts/overworld/horde_director.gd`, `scripts/systems/effects.gd`,
`scripts/systems/damage_zones.gd`, `scripts/systems/player_projectiles.gd`,
`scripts/abilities/player_projectile.gd`, `scripts/systems/arena.gd`,
`scripts/systems/save_game.gd`, `scripts/inventory/inventory_save.gd`, `scripts/overworld/journey_save.gd`,
`scripts/systems/audio.gd`, the five registries, `scripts/abilities/ability_caster.gd`, `scripts/systems/stats.gd`,
`scripts/systems/pickups.gd`, `scripts/overworld/overworld.gd`, `scripts/overworld/world_props.gd`,
`scripts/overworld/nature_layout.gd`, `scripts/main.gd`, `scripts/systems/game_session.gd`, `scripts/systems/run_manager.gd`, the
ability and relic scripts that pass `opts` or `extras`, `scripts/hub.gd` (the read-only save notice, 8.2), `project.godot`,
`tests/run_all.sh`, `tests/README.md`, `README.md` (layout: `tools/bench/`, the new classes); the tests listed in 9.2 and the
timing tests of 10.2 (the `HERO_HORDE_CI` switch). `content/maps/README.md` is not touched.

Scene changes: the `ItemBanner` script on `UI/ItemBanner` in `scenes/main.tscn` and `UI/Banner` in `scenes/overworld.tscn`
(9.7), and removing the enemy `Hitbox` from `scenes/enemy.tscn` only if 6.4 finds it worth it.

## 13. Build order

Each step is one commit with its tests and, for Phase B, its bench numbers. A phase is merged before the next one starts, unless the
user says otherwise.

**Phase A**
1. `tools/bench/crowd.gd`, `tools/bench/overworld.gd`, the README with section 3's baselines, the Bone Warren pile baseline and
   its profile (3.2), and the LOS cache hit rate (6.3).

**Phase B** (steps 2 to 4 in the order the pile profile of step 1 ranks them; the order below is the default)
2. Flat `EnemyGrid` (6.1) and its test.
3. Flow direction memo (6.2) and its test.
4. Shared line of sight (6.3) and its test, only if step 1's hit rate is at least 30%.
5. Single-player fast path and the contact-hit measurement (6.4); the `Area2D` removal only if the measurement says so.
6. Off-screen ticking (6.5), only if the targets are missed. Then the rendered check (5.3).

**Phase C**
7. `EnemyDirector`, both directors on it, `on_stuck` without `has_method` (7.1), and its test.
8. The `Arena` assert (7.3).

**Phase D**
9. `SaveFile`, the four files on it, migrations and the read-only rule (8.1, 8.2), and its test.
10. The runner deletes `SaveFile.suffixes()` (F10).

**Phase E**
11. Registries cached and checked (9.1).
12. Typed options (9.2).
13. Hot-path cleanups and `Effects` on packed arrays (9.3).
14. Per-zone overworld data (9.4) and `RunManager` registration (F21, 9.5).
15. Overworld spikes (9.6).
16. `ItemBanner` and exit leaks (9.7).

**Phase F**
17. Warnings (10.1) and the fixes they report.
18. Parallel runner (10.2).
19. CI (10.3), after the user's answer to O2.
20. LFS (10.4), after the user's answer to O3.

Tests the spec expects to fail until fixed: `tests/maps/crowd_bone_warren.gd` (the only failure in 3.4), until Phase B. Phase B is
done when it passes and `crowd_performance.gd` still does.

## 14. Open questions / assumptions

- **O1.** The targets of 5.2 are for the M1 Pro baseline machine. The minimum hardware the game should run on is not defined; once it
  is, the targets are restated for it.
- **O2.** CI uses GitHub Actions on the existing GitHub remote (`boki-io`). Private repository minutes are a cost; the job runs
  only the headless suite (about the length of a local serial run divided by two). Confirm before step 19.
- **O3.** Git LFS for new music only (no history rewrite). Confirm before step 20, or drop it.
- **O4.** 6.3 trades exact per-enemy line of sight for a per-cell answer; assumed acceptable because the flow field is the fallback.
  If a play-through shows enemies hugging walls they used to round, the sub-cell key is the fix. 6.1 likewise accepts a different
  neighbour order and a one-frame position snapshot in separation.
- **O9.** The read-only notice of 8.2 is one line of text in the hub; its exact wording and place are the builder's choice.
- **O5.** Raising `alive_cap` above 300 or `HordeRules.max_alive` above 120 is not part of this spec, even if the budget allows it.
- **O6.** The save migration mechanism is built before any schema change needs it. The first real schema change (a later spec) adds
  the first migration and a test with a real old file.
- **O7.** `GameSession` is split in its own spec (9.5); only F21 is fixed here.
- **O8.** If the remaining Phase B budget is still missed, a C++ GDExtension for the crowd loop is the next step; that is a decision
  for the user, not an automatic follow-up.

## 15. Definition of Done

Per phase:
- **A:** the two bench tools run and print the numbers of section 3 within 15% on the baseline machine; the README has the table,
  the Bone Warren pile baseline, its profile and the LOS cache hit rate.
- **B:** the 5.2 targets are met (bench numbers in the README), `crowd_bone_warren.gd` passes all three of its runs and
  `crowd_performance.gd` still passes, every
  enemy, steering, horde and ability test passes unchanged, the new grid and flow tests pass with 30 seeds, and the rendered check is
  recorded as done or not done.
- **C:** `Enemy` has no `has_method`, `HordeDirector` does not extend `SpawnDirector`, the reward code exists once, the `Arena` assert is in, and the suite passes.
- **D:** all four files are written through `SaveFile`; a newer-version file is never written in that session; a migrated file
  leaves a `.v<N>` backup; a test migration runs; a garbage settings file is still not renamed; the runner leaves no save files
  behind (checked by listing the temp folder before and after a run); the existing save tests pass unchanged.
- **E:** registries are cached and checked against disk; the typed options replace the Dictionaries (with the test edits of 9.2);
  the hot-path cleanups of 9.3 are in (`AbilityCaster.value` cache, `Stats.value` fast path, one RNG in `Pickups`, `Effects` on
  packed arrays) with the effects tests passing unchanged; `hordes.tres` is loaded once and nature rules are per zone;
  `RunManager` registers with `GameSession` (F21); the overworld p99.9 frame is under 16.6 ms or its cause is recorded; the banner
  exists once; the exit warning is reduced, or what is left is listed (F25).
- **F:** `scripts/` and `content/` are typed except the allow-listed duck types and stay so (an error, or `tests/typing.gd`); tests
  are not forced to type; the parallel runner gives the same results as the serial one, with the timing tests run serially; CI runs
  on a pull request (if O2 is confirmed); LFS tracks new music (if O3 is confirmed).

For the whole spec: `README.md` and `tests/README.md` are current, the build notes (a section added at the end of this spec) say what
was built, what differs, the before and after numbers, and what was not checked by hand (a play-through, a rendered crowd, an
exported build).
