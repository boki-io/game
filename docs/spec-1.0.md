# Spec v1.0: Relics

Builds on spec v0.9 and on everything in `main` at `3b9a2db` (PR #9, the stone-tablet level-up cards). Status: built (rev 3 records the build's deviations in section 13); rev 2 (rev 2 applies an independent review: the wave's wall test uses a ray, the bramble ticks once per 0.5 s, `RelicData` names its behavior script, Fire Trail damages each enemy once per tick, burn ticks are quiet, relic nodes are `top_level`, Storm Orbs owns its own belt, the roller takes an untyped player, and a Compatibility section was added).

Terms: a **relic** is an automatic power the player carries in one of **4 relic slots** shown on the right of the screen. It has 3 levels and
works by itself (a timer, an orbit or a trail), with no key and no mana. A **relic card** is a level-up card that gives a new relic or raises
one you own. A **status** is a timed effect on an enemy: slow, freeze, burn or vulnerable (new, section 2). The existing stat cards ("Power",
"Twin Bolt" ...) are called **stat upgrades** here, to keep them apart from relics (their tag on the card is still "Passive").

## Flow

You level up and the usual three cards appear. One or two of them may carry a **RELIC** tag: "Tidal Wave, NEW" or "Storm Orbs, Lv 1 -> 2".
Pick a new relic and it drops into the first empty slot on the right of the screen and starts working at once. Level 3 adds one special
effect. Once all 4 slots are full, no new relic is offered, only upgrades for the relics you own (and the stat upgrades as before). A relic
stays through the next stages of the run and is gone when the run ends. Five relics exist and there are four slots, so every run leaves one out.

## 1. Scope

In scope:
- **Five relics, 3 levels each**: Tidal Wave, Frost Comet, Thorn Nova, Storm Orbs, Fire Trail (section 4). Same for every character.
- **A status system on enemies** (section 2): slow, freeze, burn, vulnerable.
- **Relic cards in the level-up menu** (section 5) and **the four slots on the HUD** (section 6).
- **Carrying relics between the stages of a run** (section 7).
- Placeholder drawn effects and four generated placeholder sounds, tests, README rows.

Out of scope (decided): relics in the hub (no level-ups there), more than 5 relics, rerolling or dropping a relic, relic icon art (a drawn
placeholder is used), mana costs, character-specific relics.

Out of scope (later): Haste applying to relic cooldowns, relic evolutions or combos between relics, relics from chests or the camp shop, a
relic list on the end screen, per-relic sounds beyond the four in section 8.

## 2. Enemy statuses

Verified in code: `Enemy` has `stun(seconds)` (cancels the brain, tints yellow, `immovable` enemies ignore it) and `apply_knockback`. It has no slow,
no freeze, no burn and no damage multiplier. Enemies are pooled: `activate()` resets `_stun_left` and `sprite.modulate`, so statuses must reset there too.

New `scripts/enemy/enemy_status.gd`, `class_name EnemyStatus extends RefCounted`, one per Enemy (created in `_ready`, `reset()` in `activate()`
and `deactivate()`). It holds numbers only, no nodes:

| Status | Applied by | Effect | Stacking |
|---|---|---|---|
| slow | `Enemy.apply_slow(factor, seconds)` | enemy speed x `factor` (0.6 = 40% slower) | the lowest factor wins; time = the longest of the two |
| freeze | `Enemy.freeze(seconds, vulnerable := 1.0)` | like stun (the brain is cancelled, no contact hits), ice tint; also applies vulnerable `vulnerable` for the same seconds | time = the longest |
| vulnerable | `Enemy.apply_vulnerable(mult, seconds)` | `take_damage` multiplies the amount by `mult` | the highest mult wins; time = the longest |
| burn | `Enemy.ignite(dps, seconds)` | every 0.5 s one `take_damage(dps * 0.5)` | the highest dps wins; time is reset to `seconds` |

Rules:
- **Slow applies inside `Enemy.chase()` and `Enemy.settle()`**, to their `speed` argument (verified: every brain walks through those two). It
  does not touch a Dasher's dash (`dasher_brain.gd` returns a velocity of its own during DASH, and a slowed dash would end short of its drawn lane), a Ranged
  enemy's shots, or knockback.
- **Freeze reuses the stun path**: add `_freeze_left` next to `_stun_left`; both stop the brain and block contact hits (`_stun_left <= 0.0` at the
  contact check becomes `not is_stunned()`). `_check_stuck` already treats a stunned enemy as not stuck. Its "asked to move" test (`asked.length() < data.speed * 0.5`) becomes
  `< data.speed * slow_factor * 0.5`, so a slowed enemy that really is stuck is still recycled and one at a slow of 0.4 or lower is not wrongly exempt.
- **Tint priority** (one function `_refresh_tint()` replaces the three places that set `sprite.modulate`: `activate`, `stun`, and the stun expiry in `_physics_process`): stun yellow `(1, 1, 0.45)`, then freeze ice
  `(0.55, 0.8, 1.0)`, then burn `(1.0, 0.6, 0.35)`, then slow `(0.75, 0.95, 0.75)`, else white.
- **`immovable` enemies (the training dummies) ignore all four** so their Last / Total / DPS readout stays honest.
- **Burn damage goes through `take_damage(amount, quiet := false)`**, multiplied by vulnerable *before* the damage number is shown, so the number matches the HP lost. A burn tick passes
  `quiet = true`: damage number and health change only, no spark, recoil, hit animation or flash, no hit sound (a burning crowd must not twitch twice a second). The dps is the final value, read when the burn is applied (so Arcane Focus
  is sampled at application, not per tick).
- **Cost**: a plain flag `any_active` lets `_physics_process` skip all status work for the 99% of enemies with nothing on them. A new status
  test at 300 enemies must stay inside the `crowd_performance.gd` budget.
- `DamageZones.add_field` gets an optional `extras: Dictionary` as its **last** parameter, after `delay` (so the existing callers, Meteor and Slam, are unaffected): `slow = {factor, seconds}` and
  `ignite = {dps, seconds}` are read in `_fire` like `stun` and applied to every enemy inside at each tick; `_fire` skips `take_damage` when `z.damage <= 0` (a field of statuses only: no spark, no sound).
  `add_burst`'s extras gain `freeze = {seconds, vulnerable}`. A field has one `interval`, so the bramble uses 0.5 s ticks with a slow `seconds` of 0.75 (no gap between ticks).

## 3. Relics: data and scaling

New files (layout):
```
scripts/relics/relic_data.gd        RelicData (Resource): id, display_name, color, glyph, behavior: Script (a RelicBehavior subclass), levels: Array[Dictionary]
scripts/relics/relic_registry.gd    RelicRegistry: explicit PATHS list like AttributeRegistry (exported builds)
scripts/relics/player_relics.gd     PlayerRelics (Node child of Player): slots, levels, add/raise, saving
scripts/relics/relic_behavior.gd    RelicBehavior (Node base): a Player ref, level, stats helper, cooldown_fraction()
scripts/relics/tidal_wave.gd  frost_comet.gd  thorn_nova.gd  storm_orbs.gd  fire_trail.gd
scripts/ui/level_up_choice.gd       LevelUpChoice (RefCounted): what one card shows and does
scripts/relics/level_up_roller.gd   LevelUpRoller: builds the three cards (section 5)
scripts/enemy/enemy_status.gd       EnemyStatus (section 2)
data/relics/<id>.tres               one RelicData per relic, the numbers of section 4
```
Moved or changed: `scenes/player.tscn` gains a `Relics` node; `RunProgress`, `LevelUpMenu`, `Hud`, `OrbBelt`, `DamageZones`, `Enemy` change as listed in
each section. After adding the new `class_name` scripts and the four `.wav` files, run `godot --headless --path . --import` and commit the generated `.uid` and `.import` files.
Existing tests: `crowd_performance.gd` gets a relic case; `phase_belt.gd` and `run_progress.gd` keep passing unchanged (see Compatibility, section 11) and each gets a few added asserts.
- **A relic's behavior node** is created by `PlayerRelics.add` from `RelicData.behavior`. Nodes that draw or hit in world space (the wave, the flames, the comets' markers) set `top_level = true` so they do not follow
  the player, and `z_index = 5` like `DamageZones`; Storm Orbs deliberately follows the player.

- **Numbers are data**: `RelicData.levels[i]` is the dictionary of level `i + 1` (keys per relic in section 4) plus a `description` line shown on the card.
  Cooldowns, counts, radii and damage are in the `.tres`; the behaviors only read them.
- **Damage scales with the player**: every relic damage number (hit, tick, zap, burn dps) is multiplied by `stats.value(&"damage", 1.0)` at the moment it is dealt, so
  Might, Fury, Power cards and the Wizard's Arcane Focus (+25% while standing still, a conditional on the same key) all apply. Statuses (slow factor, freeze seconds) do not scale.
- **Haste does not apply** to relic cooldowns in v1.0 (it is a Q / E / R stat, `Stats` key `cooldown`).
- **No mana**, and relics do not run in the hub, or while `player.dead`, or while the tree is paused (they are children of the Player, so the level-up menu pauses them).
- **Randomness is seeded**: any random pick (Frost Comet's target) uses a `RandomNumberGenerator` the relic owns; a test sets `seed`. The gameplay does not use the global RNG. (Cosmetics such as `Effects.lightning`'s jitter still do.)
- **Pausing and scene changes**: relics and any pending comet pause with the tree and are gone when the stage scene is freed; only levels carry over (section 7).
- **Aim**: Tidal Wave fires along `player_input.aim_vector` at the moment of the cast (verified: the mouse direction when the mouse is in use, the right stick on a pad, and the last
  movement direction when neither has been used). It is not `Player.facing`, which is the last movement direction.

## 4. The five relics

Units: seconds, pixels, damage in HP (a Grunt has 20 HP, a Dasher 60, a Ranged 25; the auto Slash and Arcane Bolt deal 10). All values are first guesses (O1).

### 4.1 Tidal Wave
Every `cooldown` seconds a wave leaves the player along the aim and rolls `range` px at `speed` px/s. It is a circle of radius `width / 2` travelling along the line; each enemy
is hit once per pass, knocked back by `knockback` px/s (decays at the existing `KNOCKBACK_DECAY`, 640, so 160 is about 20 px). Walls: `ObstacleMap.blocked` only accepts a radius up to 16 (verified), so at the cast the range is
shortened once with `ObstacleMap.ray_distance(from, dir, range, 16.0)` (as `DasherBrain` does); the return leg of level 3 reuses that shortened range.
No cast unless an enemy is within `range + width / 2` of the player **and** within `width / 2 + 6` px of the aim line (it would only waste the cooldown); it retries every 0.25 s.

| Level | cooldown | damage | width | range | speed | knockback | returns |
|---|---|---|---|---|---|---|---|
| 1 | 4.0 | 10 | 48 | 140 | 220 | 160 | no |
| 2 | 3.2 | 14 | 72 | 160 | 220 | 160 | no |
| 3 | 3.2 | 14 | 72 | 160 | 220 | 160 | **yes**: at the end of its range it turns back to the player and hits again (a second pass, enemies hit once more) |

### 4.2 Frost Comet
Every `cooldown` seconds, `comets` enemies within 200 px of the player are picked at random (different enemies while enough exist); at each one a telegraph circle shows for 0.5 s on the ground
where the enemy was at the pick, then the comet lands (`DamageZones.add_burst`, delay 0.5, ring effect): `damage` to every enemy within `radius`, and **freeze** for `freeze` seconds with `vulnerable`. No target: no cast, retry every 0.25 s.

| Level | cooldown | comets | radius | damage | freeze | vulnerable while frozen |
|---|---|---|---|---|---|---|
| 1 | 5.0 | 1 | 40 | 12 | 1.0 | 1.0 (none) |
| 2 | 4.2 | 1 | 52 | 16 | 1.5 | 1.0 |
| 3 | 4.2 | **2** | 52 | 16 | 1.5 | **1.5** |

The comet's own damage lands before the freeze is applied, so it does not get the 1.5x.

### 4.3 Thorn Nova
Every `cooldown` seconds `thorns` thorns fly out evenly spaced from the player (`PlayerProjectiles.fire`, pierce 0, speed 200 px/s, range `range`; the pool is capped at 40, a
cast needs at most 12; the pool is shared with the Wizard's bolts, so `fire` may return false: a short volley is accepted, the return value is checked, and a test covers a nearly full pool), and a **bramble** field is dropped at the player's position: a circle of radius `bramble_radius` that lasts `bramble_life` seconds and applies slow (`slow_factor`, ticks every 0.5 s with a slow of 0.75 s, so there is no gap)
to every enemy inside; from level 3 it also deals `bramble_tick` damage every 0.5 s. `DamageZones.add_field` (section 2) does the bramble.

| Level | cooldown | thorns | range | damage | bramble radius | bramble life | slow factor | bramble tick |
|---|---|---|---|---|---|---|---|---|
| 1 | 6.0 | 8 | 80 | 8 | 36 | 2.0 | 0.6 | 0 |
| 2 | 5.0 | 12 | 100 | 10 | 44 | 2.0 | 0.6 | 0 |
| 3 | 5.0 | 12 | 100 | 10 | 44 | **4.0** | 0.6 | **4** |

### 4.4 Storm Orbs
Always on. `count` orbs circle the player at `radius`, `turns` turns a second, damaging what they touch for `damage`. It reuses `OrbBelt` (verified: it already uses `EnemyGrid.query` and a 0.5 s hit
cooldown per enemy shared by all orbs): `OrbBelt` gets an **endless mode** (`duration <= 0`: the `_time_left` countdown in `_physics_process` is skipped and `_draw`'s alpha is 1 after the fade-in, because today it divides by `_time_left` and `_total`), a `color`, and `set_shape(count, radius, turns, damage)` so a level-up does not reset the hit cooldowns.
Phase Shift's belt keeps its own look and behavior (`tests/phase_belt.gd`).

| Level | count | radius | turns/s | damage | zap |
|---|---|---|---|---|---|
| 1 | 3 | 40 | 0.6 | 6 | none |
| 2 | 4 | 52 | 0.8 | 7 | none |
| 3 | 5 | 52 | 0.8 | 7 | **each orb zaps the nearest enemy within 100 px of it every 2.0 s for 8** (orbs start offset so a zap lands every 0.4 s; `Effects.lightning`) |

**The relic owns its own `OrbBelt` instance**, never `Player._belt`: `end_phase` and `_on_died` stop `_belt`, which would kill a shared one. The relic stops its belt itself when `player.dead`.

### 4.5 Fire Trail
Always on while moving. Every 12 px the player walks, a flame is dropped on the ground at the feet position, lasting `life` seconds, radius `radius`. Flames overlap (12 px apart, radius 9 to 12), so damage is per enemy, not per flame: one global tick every 0.5 s queries each flame with `EnemyGrid.query` and hits each enemy **at most once per tick** (a set per tick), and applies the level 3 ignite once. Capped at 80 flames (the oldest is dropped); one node draws them all and holds them as data (like `DamageZones`), not 80 nodes. No flames while standing still. A step longer than 24 px (a dash, a teleport) drops flames interpolated along the step, at most 8 (see O11).

| Level | radius | life | tick | burn |
|---|---|---|---|---|
| 1 | 9 | 1.5 | 5 | none |
| 2 | 12 | 2.5 | 6 | none |
| 3 | 12 | 2.5 | 6 | **ignite 4 dps for 3 s** on every enemy a flame touches (continues after it leaves the fire) |

## 5. Level-up cards

Verified in code: `LevelUpMenu` calls `PlayerUpgrades.roll(3)`, which returns `UpgradeData`; `UpgradeData` applies the same modifiers at every level. A relic level cannot be
expressed as one, so cards become **`LevelUpChoice`** (title, tag, description, `from_level`, `to_level`, `apply: Callable`). `LevelUpMenu._choices` is `Array[LevelUpChoice]`; the tablet style,
keys 1/2/3, focus glow and queueing stay as in PR #9. A card for a new relic reads `NEW` where the others read `Lv a -> b`.

`LevelUpRoller.roll(player, count, rng) -> Array[LevelUpChoice]` builds the pool from three sources and draws `count` (3) without repeats:
1. **New relics**: every relic not owned, only while `player.relics.free_slots() > 0`.
2. **Relic upgrades**: every owned relic below level 3.
3. **Stat upgrades**: `PlayerUpgrades.pool` entries not maxed (as today).

Rules:
- Weighted draw without replacement: relic cards (1 and 2) weigh 2, stat upgrades weigh 1.
- **While the player owns no relic** (so normally the first level-up, and again each level-up until one is taken) and a slot is free, at least one of the three is a new relic.
- With all 4 slots full, source 1 is empty: no new relic is ever offered. (Slots never empty during a run.)
- If fewer than 3 cards exist the menu shows what exists; with none it closes, exactly as today.
- `PlayerUpgrades.roll` stays as it is (tests use it); `LevelUpRoller` calls `PlayerUpgrades` for the stat cards through a new `open_upgrades()` so the open-pool rule lives in one place.
- `rng` is a parameter so a test can seed it. `LevelUpMenu` is rebuilt every stage, so the menu seeds it from `GameSession.path_seed` plus the player's level (verified at build time that `path_seed` exists; otherwise `Time`).
- `player` is untyped (`Node`) in `roll`, so a test can `load()` the roller after `await process_frame` without naming `Player`.
- A card's description is at most 3 lines of about 18 characters (the card is 120 x 84 at font 8); the `description` of each relic level is written to fit.

## 6. Slots on the HUD

Four slots in a column on the right edge, drawn in `Hud._draw` with the ability icons' style (the HUD is a single canvas item). Verified: the top right uses y 6 to 26 (Kills at 12, gold at 24),
the xp bar is at the bottom, so the column starts at y 36: slot size 22 x 22, gap 4, right margin 6 (x = view.x - 28), ends at y 136 (at the 640 x 360 base).
- **Empty**: a dim outline.
- **Owned**: a square filled with the relic's colour at low alpha, its glyph (first letter, drawn), three level pips under the glyph, and for timed relics (Tidal Wave, Frost Comet, Thorn Nova) a **cooldown sweep**
  from `RelicBehavior.cooldown_fraction()` (0 = ready). Storm Orbs and Fire Trail show no sweep.
- Gaining a relic or a level flashes the slot for 0.3 s (like `FLASH_TIME`).
- Not drawn in the hub (no run manager), like the XP bar. Real icons replace the glyph later.

## 7. Carrying relics between stages

`RunProgress.capture` adds `relics = player.relics.levels.duplicate()` (id to level; slot order is the dictionary's insertion order, which Godot keeps). `restore` re-adds them in that order, at their saved level, **without** opening cards or
flashing; it uses `progress.get("relics", {})` so an older snapshot (tests) still loads. Cooldowns restart at the stage start, like everything else (HP, mana, cooldowns are not carried).

## 8. Sounds

Three places each (`audio.gd` `SOUNDS`, `tools/gen_sfx.py`, `assets/audio/`): `relic_wave` (wave leaves), `relic_comet` (comet lands), `relic_nova` (nova), `relic_zap` (orb zap). Storm Orbs and Fire Trail have no sound of their own
(they are continuous). All four are throttled by `Audio.MIN_INTERVAL_MS`. After running the generator, `git status` must show only the new files.

## 9. Build order

One commit per step, tests with the step, the suite after each.
1. **Statuses**: `EnemyStatus`, `Enemy` (slow in `chase`/`settle`, freeze, vulnerable, burn, tint, reset), `DamageZones` extras. Test `enemy_status.gd`.
2. **Relic data and the player node**: `RelicData`, `RelicRegistry`, `PlayerRelics`, `RelicBehavior`, the five `.tres` files with their level tables and **five stub behavior scripts** (they do nothing yet, so steps 2 and 3 can add relics in tests; steps 5 and 6 fill them in), then `godot --headless --path . --import`, `player.tscn`, `RunProgress`. Test `relic_progress.gd` (and `run_progress.gd`).
3. **Cards**: `LevelUpChoice`, `LevelUpRoller`, the menu changes. Test `relic_cards.gd`.
4. **HUD slots** (placeholders glyphs, sweeps). A real-frame render of the HUD with four relics, looked at.
5. **Storm Orbs and Fire Trail** (`OrbBelt` endless mode first, `phase_belt.gd` must still pass). Start `relic_behaviors.gd` with these two.
6. **Tidal Wave, Frost Comet, Thorn Nova**, and their slices of `relic_behaviors.gd`.
7. **Sounds** (section 8).
8. **Docs and tuning**: README, `tests/README.md` rows, a play-through, the numbers in section 4 if play says so (then updated here too).

## 10. Tests

| Test | Checks |
|---|---|
| `enemy_status.gd` | slow x factor through `chase` and `settle`, strongest wins, expires; freeze stops movement and contact hits and gives vulnerable, ends; vulnerable multiplies `take_damage`; burn ticks every 0.5 s for the right total and refreshes; a pooled enemy comes back clean; dummies ignore all four; a slowed Dasher's dash length is unchanged; tint priority; 300 enemies with statuses inside the crowd budget |
| `relic_progress.gd` | add, raise to 3, no raise past 3, no 5th slot; free slots; capture and restore keep ids, levels and order; an old snapshot without `relics` loads |
| `relic_cards.gd` | 30 seeds: three distinct cards; no new relic with 4 full; upgrade cards only for owned and below 3; a new relic is always among the three while none is owned; weights (over 3000 rolls the relic share is within 5 points of the one the weights give); all maxed falls back to stat cards; a card applied changes the level and, for a new relic, takes the first free slot |
| `relic_orbs_trail.gd` and `relic_wave_comet_nova.gd` (the one `relic_behaviors.gd` of rev 2, split in two so two steps could be built in parallel) | per relic and level: fires at the cooldown, the numbers of section 4 (counts, radius, damage within the `damage` stat scaling, 1.25x while Arcane Focus is on), no cast without a target; wave direction follows `aim_vector`; the wave stops at a wall and Lv3 returns; comets: the target count, freeze and 1.5x; nova: thorn count and bramble slow, Lv3 ticks; orbs: count, per-enemy hit cooldown, Lv3 zaps; trail: flame spacing, life, cap of 80, burn at Lv3; nothing runs while dead |
| `crowd_performance.gd` (added case) | 300 enemies with four relics at level 3 stay inside the physics budget; the player **walks in a circle** during the measurement so Fire Trail drops flames; a separate case calls the flame-drop function directly to reach the cap of 80 |

Randomised cases use `SEED_COUNT` (30) seeds and reproduce from their seed. Tests do not name `Player`, `Enemy` or `AbilityCaster` in typed variables (use `tests/fixture.gd`).

## 11. Open questions / assumptions

- **O1: every number in section 4 is a first guess**, tuned in step 8.
- **O2: Haste does not shorten relic cooldowns.** Easy to add later (`stats.value(&"cooldown", 1.0)`).
- **O3: relics are scaled by Arcane Focus** (the Wizard's +25% while standing still) because it sits on the same `damage` key; the Knight has no equivalent. Probably fine.
- **O4: Fire Trail and burn ticks play the normal enemy hit sound and sparks** (Scorched Earth does today); the audio throttle (40 ms per sound) keeps a crowd bearable. If it is noisy, a quiet-tick flag on `take_damage`.
- **O5: Tidal Wave on keyboard before the mouse has moved** fires along the last movement direction (`aim_vector`'s own fallback).
- **O6: the freeze visual is only a tint** and the comet reuses the telegraph and ring effects; art comes later.
- **O7: Frost Comet picks a target position once** (where the enemy was); a fast enemy may walk out of the 0.5 s telegraph, as with Meteor.
- **O8: all relics of a level-up weigh 2 against stat cards' 1** to make relics show up early; it may crowd out stat cards.
- **O9: no relic is removed or swapped when the slots are full** (the "only upgrades" rule).
- **O10: stage clear and death** do not clear relics; `GameSession.run_progress` (in memory) is the only carrier, so quitting the run loses them like level and upgrades.

- **O11: Fire Trail and dashes**: a dash or a Phase Shift moves the player fast, so flames are interpolated along the step (at most 8 per step), like `_tick_dust`'s teleport guard (`player.gd`); no flames are dropped when the position jumped more than 120 px in one frame (a teleport).

## 11b. Compatibility

- `PlayerUpgrades.roll` and the `upgrades` node are unchanged; stat cards keep working through `LevelUpRoller`. `run_progress.gd` still passes (`progress.upgrades` is still read and written); it gains asserts for `relics`, and old snapshots load via `.get("relics", {})`.
- `OrbBelt.start(count, radius, turns, damage, duration)` keeps its signature and behavior, so `phase_belt.gd` passes unchanged (it gains one assert that Phase Shift's belt is not the relic's belt).
- `DamageZones.add_field`'s new `extras` comes last, after `delay`; `add_burst` keeps its signature. `Enemy.take_damage`'s new `quiet` parameter defaults to false.
- The hub is unchanged: no relics, no slots.

## 12. Definition of Done for v1.0

- The five relics behave as in section 4 at each level (the tests of section 10 check each number), and scale with the `damage` stat.
- A level-up offers relic cards under the rules of section 5; with 4 slots full only upgrades for owned relics are offered; the first level-up offers a new relic.
- The four slots draw on the right of the screen in a run (not in the hub), with levels and cooldown sweeps; looked at once in a real window.
- Relics survive a stage change and are gone on a new run.
- Slow, freeze, vulnerable and burn work as in section 2, dummies and Dasher dashes are unaffected.
- Four new sounds in the three places; `git status` clean of unrelated files.
- Existing tests pass (`phase_belt.gd`, `run_progress.gd` updated where listed); `tests/run_all.sh` passes on a fresh clone; the crowd tests stay inside budget with four level-3 relics.
- README and `tests/README.md` list the new files and tests. Nothing in v1.0 stops or slows time.

## 13. Build notes (deviations from rev 2)

- **Tests**: `relic_behaviors.gd` became `relic_orbs_trail.gd` and `relic_wave_comet_nova.gd`; `relic_hud.gd` was added (slot rects and the flash timer).
- **`freeze_left` lives in `EnemyStatus`**, and `Enemy.is_stunned()` combines it with `_stun_left`. `apply_vulnerable` ignores a multiplier of 1.0 or less.
- **`LevelUpChoice` has `weight` and `is_relic`**; the `NEW` text is only for relics (a stat upgrade at level 0 still reads `Lv 0 -> 1`). When `GameSession.path_seed` is 0 the roller's seed also mixes in `Time`.
- **Storm Orbs' belt is hidden and its processing disabled while the player is dead** (not `stop()`), so cooldowns are kept. `OrbBelt`'s cooldown sweep no longer crashes when an enemy in it was freed (an existing bug an always-on belt would hit constantly).
- **Hit radii**: Tidal Wave hits within `width / 2 + 6` and `DamageZones._fire` queries `radius + 6`, so a comet or wave reaches 6 px further than the table's number.
- **Warm-up cost**: in the crowd test the first seconds after the first relic starts hitting a never-hit crowd of 300 cost more (mean 24 to 29 ms, worst 55 ms) before settling near 10 ms; the test measures after a warm-up. Cause not yet found (suspect first-hit setup per enemy); to look at in a play-through.
- Not verified by hand: how the orbs, flames, wave, comets and nova look; the slot flash in pixels; a full run with relics (PR box left unchecked).
