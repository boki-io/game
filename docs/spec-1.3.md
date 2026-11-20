# Spec v1.3: The Vacuum Magnet (a pickup that gathers every coin and XP gem for 5 seconds)

Builds on the pickups of spec v0.3 (`Pickups`, `XPGem`, `Coin`, the player's `XPCollector`) and on the doubled run arena of PR #13 (3200x1792). `main` at `cea4ff8`. Status: built (steps 1 to 4; deviations in section 12); rev 2 (applies an independent review: gems must not level the test player up, a freed vacuum target, a testable `roll_magnet`, the director setup the kill test needs, the magnet's hop rule, a numbered "Tests it touches" section, sound-generator ordering).

Terms: the **magnet** is the new item on the ground. The **vacuum** is its effect: for 5 seconds every XP gem and coin on the map flies to the player who took the magnet. The existing **Magnet upgrade** (`pickup_radius`, +30% pickup radius) is a different thing; the code and files here say "vacuum" to keep them apart.

## Flow

A killed enemy rarely drops a glowing horseshoe magnet. It hops out like a coin and lies on the ground for 30 seconds, blinking for the last 10. The player walks onto it: a sound plays, a burst of sparks marks the moment, and for the next 5 seconds every gem and coin on the map, including the ones dropped during those 5 seconds, flies to the player at high speed and is collected as usual (XP into the XP bar, coins into the run's gold). When the 5 seconds end the pull stops; anything already in flight still arrives, at normal speed. There is no HUD element (O1).

## 1. Scope

In scope:
- The magnet item: a drop from killed enemies, one at a time, drawn in code, with a lifetime and a flash (section 2).
- The vacuum: a timer and a target on `Pickups`, read by `XPGem` and `Coin` (section 3).
- Tuning as data: `content/pickups/vacuum_magnet.tres` (section 4).
- One sound (section 5), tests and docs (sections 7 and 8).

Out of scope (decided): a HUD icon or timer bar; placing magnets on the map by hand or by the map layout; a magnet in the camp or hub (the hub dummies drop nothing); a camp attribute or upgrade that changes the drop chance or the 5 seconds; art from a sprite sheet (the item is drawn in code, like the coin); stacking (a second pickup refreshes the 5 seconds, it does not add).

Out of scope (later): other pickup kinds (a heal, a bomb) sharing the same drop and lifetime code; a HUD timer if play shows the player cannot tell when the vacuum ends (O1).

## 2. The item (`VacuumMagnet`)

Verified against `main`: `Pickups` (`scripts/systems/pickups.gd`) owns two pools, gems and coins, instantiated from `@export` scenes set on the `Pickups` node of `scenes/main.tscn`; `SpawnDirector._on_enemy_died` (`spawn_director.gd:140`) spawns a gem for every kill and a coin by a 25% base chance (`StageData.BASE_COIN_CHANCE`), and mobs with `xp_drop == 0` (the hub dummies) drop nothing; a pickup hops out with `Pickups.random_pop()` and `pop_step` (150 to 170 px/s slowing at 1000 px/s^2) and waits for the hop to end before it can be pulled.

- **New files:** `scripts/systems/vacuum_magnet.gd` (`class_name VacuumMagnet`, a `Node2D`), `scenes/vacuum_magnet.tscn` (the node with the script), `scripts/systems/vacuum_data.gd` (`class_name VacuumData`, section 4).
- **One at a time.** `Pickups` holds a single `VacuumMagnet` instance, created on the first drop and reused. A drop is skipped while the magnet is on the ground or the vacuum is running (so a run never has two, and a magnet is never wasted inside a running vacuum).
- **The drop.** `Pickups.roll_magnet(pos) -> bool` (true when a magnet was placed) is called from `SpawnDirector._on_enemy_died` inside the existing `xp_drop > 0` branch, after the coin roll. It draws `randf() < data.drop_chance` and, on success, places the magnet at `pos` with the same hop as a coin (`Pickups.random_pop()` and `pop_step`). It uses the global RNG like the coin roll (a drop is not seeded content). It returns false without rolling while a magnet is on the ground or the vacuum runs.
- **Lifetime.** The magnet counts its age in `_physics_process` (so it stops while the game is paused, for example in the level-up menu). At `data.lifetime` (30 s) it is released (hidden, process disabled, as pooled pickups are). In the last `data.flash_time` (10 s) it blinks: its alpha alternates 1.0 and 0.25 at `data.flash_hz` (4 Hz). `is_flashing()` tells a test.
- **The hop.** While hopping (`_pop_vel != ZERO`, under 0.2 s) the magnet only moves (`pop_step`, with its arena clamp) and cannot be taken, as gems and coins cannot be pulled; its age counts from the drop.
- **Collecting.** After the hop ends, each physics frame the magnet asks `PlayerRegistry.nearest(global_position)`; if that player is alive and the distance from the magnet to the player's body point (`global_position + Vector2(0, -6)`, the point gems and coins fly to) is at most `data.pick_distance` (14 px), the magnet is taken. It does **not** have `attract()`, so the pickup radius and the Magnet upgrade never pull it in: the player has to walk to it.
- **On pickup:** `Pickups.start_vacuum(player)` (section 3), `Audio.play(&"vacuum_pickup")`, and `Effects.burst` at the player's body point (24 teal bits, a spread burst, `low_priority = false`); then the magnet is released. `start_vacuum` ignores a null or dead player.
- **Look** (`_draw`): a horseshoe magnet about 12 px across, red body with silver tips, a pulsing soft glow (two translucent circles whose radius breathes between 9 and 12 px over 1.2 s), and a small drop shadow. It sits in the `Pickups` node (z_index -5, under the units), as coins do.

## 3. The vacuum (on `Pickups`)

State on `Pickups`: `vacuum_target: Player` (null when no vacuum) and `vacuum_left: float`.

- `start_vacuum(player)`: `vacuum_target = player`, `vacuum_left = data.effect_time` (5 s). Called while one is running it replaces the target and restarts the time (a refresh, not an addition).
- `_physics_process(delta)` on `Pickups`: while `vacuum_target != null`, `vacuum_left -= delta`; it ends (`vacuum_target = null`, `vacuum_left = 0`) when the time is up, or when `not is_instance_valid(vacuum_target)` or the target is dead (the validity check comes first: a freed instance is not null, and reading `.dead` on it errors). `XPGem` and `Coin` use the same `is_instance_valid` check on `pool.vacuum_target` and on their own `target` before they read `.dead`. `Pickups` is the parent, so it runs before its items in a frame: when the target dies, the vacuum ends on the next frame at the latest, and an item that sees the dead target drops its own `target` as today.
- `vacuuming() -> bool`: `vacuum_target != null`.
- **`XPGem` and `Coin`** each frame, after the hop (the existing early return while `_pop_vel != ZERO` stays first): if `pool.vacuuming()`, set `target = pool.vacuum_target`. Because the items look at the vacuum each frame, nothing has to be looped over at the start, an item dropped during the 5 seconds is pulled the moment its hop ends, and a second player's pickup retargets everything. The rest of the movement is unchanged, except the speed: while vacuuming the item accelerates at `data.pull_accel` (3000 px/s^2) up to `data.pull_speed` (1000 px/s) instead of `ACCEL` and `MAX_SPEED` (500 and 320). When the vacuum ends the cap goes back to `MAX_SPEED` (an item at 1000 slows to 320 at once) and the item keeps its `target`, so everything the vacuum caught is still delivered.
- The collect code is untouched: a gem still calls `target.xp.add(value)`, a coin still adds to `GameSession.run_gold`, each with its own sound.
- **Distances:** the worst case is an item in one corner and the player in the opposite one: the diagonal of 3200x1792 is about 3670 px. At 1000 px/s (about 0.31 s to reach it from 70 px/s, 170 px covered) that is about 3.8 s plus the end of the hop (0.15 to 0.17 s), so a pickup anywhere on the map arrives within the 5 seconds if the player stands still, and the player walking towards it only shortens it. Items still far away when the 5 seconds end slow to 320 px/s and keep flying (something 3000 px away then needs about 9 s); that is accepted. A test checks the diagonal.
- **Pause:** `Pickups` and the items stop with the tree (the level-up menu pauses it), so the 5 seconds are game time.
- **Reset:** the state lives on the `Pickups` node, which is part of `main.tscn`, so a new run or stage starts clean.
- A stun, death or level-up of the target needs no special handling beyond the dead check above: a dead target already makes an item drop its own `target`.

## 4. Data: `content/pickups/vacuum_magnet.tres` (`VacuumData`)

| Field | Value | Meaning |
|---|---|---|
| `drop_chance` | 0.01 | chance per killed mob with `xp_drop > 0` (O2) |
| `effect_time` | 5.0 s | how long the vacuum runs |
| `lifetime` | 30.0 s | how long the magnet lies on the ground |
| `flash_time` | 10.0 s | the blink at the end of the lifetime |
| `flash_hz` | 4.0 | blinks per second |
| `pick_distance` | 14.0 px | how close the player must be to take it |
| `pull_speed` | 1000.0 px/s | the top speed of gems and coins during the vacuum |
| `pull_accel` | 3000.0 px/s^2 | their acceleration during the vacuum |

`Pickups` gets `@export var vacuum_data: VacuumData` and `@export var magnet_scene: PackedScene`; `scenes/main.tscn` sets both (the `Pickups` node already sets `gem_scene` and `coin_scene`). Doc comments on each field, as the other data scripts have.

## 5. Sounds

One new sound, `vacuum_pickup`: a short rising sweep with a shimmer (a sine from 400 to 1600 Hz over 0.25 s mixed with a quieter square an octave up). Per CLAUDE.md it goes in three places: `Audio.SOUNDS`, `tools/gen_sfx.py` and the generated `assets/audio/vacuum_pickup.wav` (+ `.import`). The new `save("vacuum_pickup", ...)` line goes at the end of `gen_sfx.py`, after the last block: the generator uses one seeded RNG in call order, so appending keeps every older WAV byte-identical. After running the generator, `git status` must show only the new files; restore any existing file it changed.

## 6. Files

New: `docs/spec-1.3.md`, `scripts/systems/vacuum_magnet.gd` (+ `.uid`), `scripts/systems/vacuum_data.gd` (+ `.uid`), `scenes/vacuum_magnet.tscn`, `content/pickups/vacuum_magnet.tres`, `assets/audio/vacuum_pickup.wav` (+ `.import`), `tests/vacuum_magnet.gd` (+ `.uid`).

Changed: `scripts/systems/pickups.gd` (data, scene, the magnet, the vacuum state, `roll_magnet`, `start_vacuum`, `vacuuming`), `scripts/systems/xp_gem.gd` and `scripts/systems/coin.gd` (the target and speed lines in section 3), `scripts/systems/spawn_director.gd` (one call in `_on_enemy_died`), `scenes/main.tscn` (two exports), `scripts/systems/audio.gd`, `tools/gen_sfx.py`, `README.md` (project layout, pickups), `tests/README.md` (a row).

New directory: `content/pickups/`. See section 7a for the tests the change touches.

## 7a. Tests it touches

Checked against the code: none change. `tests/gold.gd` takes the `Pickups` child count after its kills and filters children by script; `tests/camp/camp_attributes.gd` and `tests/impact_feedback.gd` loop over the `Pickups` children by script or `visible` and do not kill through the director. The magnet instance is created lazily on the first drop, so the child count only changes after a drop. Tests that kill many enemies with the global RNG (`gold.gd` runs 40 kills) can see a magnet at about 1% per kill: it sits inert in the `Pickups` node and changes none of their assertions. A test that must be exact sets `drop_chance` to 0 on a duplicate of the data.

## 7. Tests: `tests/vacuum_magnet.gd` (new, fixture start, 30-seed rule does not apply: nothing here is seeded)

1. **Data:** `vacuum_magnet.tres` loads as `VacuumData` with the numbers in section 4; `main.tscn`'s `Pickups` has the data and the scene.
2. **Drop:** the test works on `data.duplicate()` assigned to `pickups.vacuum_data` (never the cached resource), and sets up the director as `tests/gold.gd` lines 63 to 70 do (`_pools[data] = []`, `alive_by_type[id] += 1`, because `SpawnDirector.release` needs them). With `drop_chance = 1.0` a kill (via `SpawnDirector._on_enemy_died` on a fixture enemy) leaves exactly one active magnet at its position; a second kill leaves still one; with 0.0 none; a mob with `xp_drop == 0` never; no drop while the vacuum runs; the chance over 2000 `roll_magnet` calls at 0.01, releasing the magnet after each success, is between 5 and 40 (a loose band around the expectation of 20; it fails about once in a million runs).
3. **Lifetime:** at age 30 s - 0.1 the magnet is active, shortly after it is released; `is_flashing()` is false at 19.9 s and true at 20.1 s; the age does not advance while the tree is paused.
4. **Pickup:** a player more than 14 px away does not take it; within 14 px it is taken, the vacuum starts (`vacuum_left == 5.0`, `vacuum_target == player`), the sound call and the burst happen, the magnet is released. With one living and one dead player both on the magnet the living one takes it (`PlayerRegistry.nearest` skips the dead); with only a dead player nothing happens. `start_vacuum(null)` and `start_vacuum(dead player)` do nothing. During its hop the magnet cannot be taken. The Magnet upgrade's pickup radius does not pull it (it has no `attract`).
5. **Vacuum:** the test player's level is set to 60 first (`needed_for(60)` is far above the test's XP) so the gems do not level it up: a level-up opens the menu, which pauses the tree and freezes the items (`tests/impact_feedback.gd` works around the same thing). 40 gems and 20 coins spread over the arena, with the player in one corner and a gem and a coin in the opposite corner, all reach the player within 4.5 s, the player's XP and `GameSession.run_gold` rise by exactly their summed values, and no item remains active. A gem dropped 2 s into the vacuum also arrives. A gem dropped after the vacuum ended, farther than the pickup radius, stays where it is. An item in flight when the vacuum ends is still collected, and its speed after the end never exceeds 320 px/s.
6. **Refresh and co-op:** the second `Player` is built as `main.gd` does (instantiate `scenes/player.tscn`, set `character`, add it to `World/Players`; it registers itself with `PlayerRegistry`); a second magnet taken at 3 s resets `vacuum_left` to 5.0; with a second `Player` registered, a pickup by the second player retargets every item to it, and the first player collects nothing afterwards. The vacuum ends when its target dies (`vacuum_target == null`) and the items drop their target; when the target is freed (`queue_free` on the second player mid-vacuum) nothing errors and the vacuum ends.
7. **Pause:** with the tree paused `vacuum_left` and a magnet's age do not change; the test sets `paused = false` afterwards (CLAUDE.md).

Run it with the time limit CLAUDE.md asks for. The whole suite runs before the PR; the known `crowd_bone_warren` failure (O3) stays.

## 8. Docs

`README.md`: the project layout (the new script, scene and `content/pickups/`) and one line in the game description (the magnet). `tests/README.md`: the row for `vacuum_magnet.gd`. The spec's status line is updated at the review and at the build.

## 9. Build order

Each step is one commit with its tests.

1. **Data and sound:** `VacuumData`, `vacuum_magnet.tres`, the sound in the three places. Test: section 7 item 1 (data).
2. **The vacuum:** the `Pickups` state and process, the `XPGem` and `Coin` changes, `start_vacuum`. Tests: items 5, 6 (without the item: `start_vacuum` called directly) and 7.
3. **The item:** `VacuumMagnet`, its scene, the exports in `main.tscn`, `roll_magnet`, the call in `SpawnDirector`. Tests: items 2, 3 and 4.
Step 2 tests call `start_vacuum` directly on the `Pickups` node (no item yet); step 3 tests use `drop_chance`.
4. **Docs and the suite:** README rows, a look at a real frame (`--write-movie`, with `HERO_HORDE_SAVE` set) of the magnet on the ground and in its flash, the whole suite.

## 10. Open questions / assumptions

- **O1 (assumed: no HUD).** The answer to the look question was "glowing magnet item, no map", read here as no HUD indicator. If a bar or icon is wanted it is a small HUD addition (the HUD already draws a relic column); say so and it moves into scope.
- **O2 (assumed: 1%).** The drop chance is a guess, not measured. At 1% a run with a few hundred kills sees a handful of magnets; with only one on the map at a time and 30 s each, a player sees one about every 1 to 3 minutes. It is one number in a data file; tune after play.
- **O3 (existing).** `tests/maps/crowd_bone_warren.gd` fails its frame-time limit at the doubled arena size on `main` already (PR #13, #14). The vacuum adds a trivial per-item check (one pointer test per active gem and coin per frame) and no loop at the start; it does not change that test's outcome, but also does not fix it.
- **O4 (assumed: collects at normal pickup rules).** The vacuum only moves the items; they are collected by the existing arrival code, so XP and coins are scaled exactly as when picked normally (the stage's XP value is already in the gem).
- **O5 (assumed).** While the player is dead the vacuum ends and the magnet cannot be taken. Solo play today: the co-op behaviour is built and tested through the player parameter, not through a second playable character.
- **O6 (assumed).** A magnet on the ground when the stage ends is simply gone with the scene; nothing is saved.

## 11. Definition of Done

- A killed enemy can drop one magnet (never two at once); it lies for 30 s and blinks for the last 10.
- Walking onto it starts a 5 s vacuum: every gem and coin on the map, including ones dropped meanwhile, flies to that player and is collected normally; a corner of the arena is reached in time.
- A second pickup refreshes the 5 s; the player's death ends it; in-flight items are still delivered afterwards.
- No HUD change; one new sound; all numbers in `vacuum_magnet.tres`.
- `godot --headless --path . --import` was run and the `.uid` files are committed; after the sound generator `git status` shows only the new sound files.
- `tests/vacuum_magnet.gd` passes; the whole suite passes except the known `crowd_bone_warren` failure; README and tests README are current; nothing is claimed as tried by hand that was not.

## 12. Build notes

- Test item 4: the sound call is not asserted (headless has no audio); the burst of 24 bits is.
- `Pickups` also got `pull_speed(normal)` and `pull_accel(normal)` helpers, which `XPGem` and `Coin` call, instead of each reading the data themselves; `Pickups._ready` makes a default `VacuumData` when none is set (scenes other than `main.tscn`).
- `main.tscn` names the data in step 2 and the magnet scene in step 3.
