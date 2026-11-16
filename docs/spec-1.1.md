# Spec v1.1: The Archer

Builds on spec v1.0 (merged, PR #10, `main` at `2866f79`: relics and enemy statuses) and on the character system of v0.1 to v0.4. Status: built (rev 3 records the build's deviations in section 14); rev 2 (rev 2 applies an independent review and your answer on bouncing: arrows bounce off enemies first, then walls; E is fire-and-forget; geometry, test and build-order fixes).

Terms: the **Archer** is the third playable character: ranged, no mana, four arrow-based abilities (auto, Q, E, R). An **arrow** is a player projectile (a `PlayerProjectile` in the existing pool) with an arrow look. A **bounce** is an arrow changing direction: off an enemy it hits (towards the next nearest enemy) or off a wall, a pillar or the arena edge. **Steady Aim** is the Archer's trait: arrows hit harder the further they have flown.

## Flow

In the hub a third pedestal shows the Archer: stats, trait and abilities. Choose them and walk the hub as them, then start a run. The Archer shoots by itself at the nearest enemy (a slow, long-range arrow) and has no mana bar. **Q** is a dash; when it ends a fan of arrows flies out behind where you came from. **E** fires six arrows in quick succession along your aim; each arrow hits up to three enemies, bouncing from one to the next, and ricochets off walls when nothing else is near. **R** sends a cloud of arrows up into the sky and they come down in three circles around the mouse cursor, damaging everything inside for a moment. Level-ups offer 18 Archer upgrades (the same pattern as the Knight and Wizard) and the relics of v1.0 work as for everyone.

## 1. Scope

In scope:
- **The Archer character**: `data/characters/archer.tres`, registered in `CharacterRegistry`, with the supplied art (section 2).
- **No mana** (section 3): `CharacterData.uses_mana`, the HUD and the hub panel hide mana for the Archer.
- **Four abilities** (section 4): Arrow (auto), Dash Shot (Q), Ricochet Volley (E), Arrow Rain (R), each a data file plus a behavior script.
- **Arrows** (section 5): `PlayerProjectile` learns ricochet and a look; the arrow pool.
- **The trait Steady Aim** (section 6).
- **18 upgrades** (section 7).
- Three placeholder sounds, hub and HUD changes, tests, README rows.

Out of scope (decided): mana for the Archer, a bow animation per ability beyond the supplied seven, real ability icons (placeholders from the existing icon sheet), a fourth hub pedestal row (three pedestals fit on one row), gamepad-specific R aiming beyond the aim stick (section 4.4), relics that react to the Archer.

Out of scope (later): arrow types or ammo, an Archer-only relic, sound beyond three placeholders, per-arrow trails.

## 2. The art and the character

The art is at `/Users/bok/Documents/game-characters/archer/export/` (outside the repo): `strips/archer_{idle,walk,attack1,attack2,hurt,death,dash}.png` (horizontal strips of 64 x 64 frames; verified: idle 7, walk 6, attack1 7, attack2 8, hurt 4, death 6, dash 6 frames, the figure faces right and holds the bow on the right), `archer_frames.tres` (a `SpriteFrames` that already points at `res://assets/sprites/archer/archer_*.png`) and `frame_durations.json`.

- Copy the strips to `assets/sprites/archer/`, the `.tres` to `data/characters/archer_frames.tres` (like `wizard_frames.tres`), then `godot --headless --path . --import` and commit the `.import` files.
- `archer.tres` follows `wizard.tres`: `sprite_frames`, `sprite_scale = 0.65`, `sprite_offset` tuned so the feet sit on the origin (the 64 px frame is the Wizard's size; the offset is set by looking at a rendered frame, spec 0.8's method), `sprite_faces_left = false` (the art faces right, like the Wizard's).
- Stats: `max_hp 85`, `move_speed 95`, `accel_time 0.06`, `friction_time 0.08`, `uses_mana = false`, `max_mana 0`, `mana_regen 0`.
- Animation names: `idle walk attack1 attack2 hurt death dash`. The auto attack and E play `attack1` and `attack2` in turn (the default in `Player._on_cast_started`), R plays `attack2` (set by `animation = &"attack2"` in `arrow_rain.tres`, otherwise it would alternate), Q plays **`dash`** (section 4.2).
- Hub: `CharacterRegistry.PATHS` gets `archer.tres` last. `Hub._build_pedestals` spaces pedestals 140 px apart around `CENTER_X` 480, so three sit at x = 340, 480 and 620 (verified in `hub.gd`: `first_x = CENTER_X - SPACING * (n - 1) / 2`).

## 3. No mana

Verified: `Player._apply_character` always configures `Mana`; `Hud._draw` always draws the MP bar; `HubInfoPanel.stats_text` always prints Mana and Regen; mana upgrades exist in the Knight's and Wizard's pools.
- `CharacterData` gets `@export var uses_mana := true`. For the Archer all four abilities have `mana_cost = 0`, so `Mana.can_afford` is always true (verified: it only compares cost with `current`); `max_mana`/`mana_regen` are 0.
- `Hud._draw` skips the MP bar (and the "no mana" flash) when `not player.character.uses_mana`; in the run the HP bar stays at y 6 and the freed row at y 17 is left empty. The hub's mana-only bar is skipped too.
- `HubInfoPanel.stats_text` prints "HP 85   Speed 95" for such a character (no Mana or Regen); `ability_stats_text` already omits Mana for a cost of 0.
- The Archer's pool has no mana upgrades (section 7). The camp attribute Focus (`max_mana`, `mana_regen`) is a dead purchase for a character without mana (it would quietly give a pool that nothing uses); noted, not changed (O13).

## 4. The abilities

All damage is multiplied by the damage stat (`caster.damage_of`), as everywhere. Cooldowns are the only limit. Stats keys are `<ability id>.<name>` (`Stats`, verified in `AbilityCaster.value`). Numbers are first guesses (O1).

**Where the numbers live.** `AbilityData` has fields for cooldown, damage, range, radius, arc, windup, duration and immunity only (verified). The rest (arrow counts, speeds, hits, bounces, tick counts and intervals, zone count, spread) go in a new `@export var params: Dictionary` on `AbilityData` with `func param(key: StringName, fallback: float) -> float`, so tuning stays data. A behavior reads a number as `caster.value(d, &"bounces", d.param(&"bounces", 3.0))`, which is what lets upgrade keys such as `ricochet.bounces` work.

`AbilityData` gets `@export var animation: StringName` (the animation played when cast; empty = today's rule: the id if listed in `Player.ABILITY_ANIMS`, else attack1/attack2). `Player._on_cast_started` uses it first, and `Player.ONE_SHOT_ANIMS` gains `dash` so it hands back to idle/walk.

### 4.1 Arrow (auto)
`id arrow`, `cooldown 0.8`, `damage 14`, `target_range 180`, `range 220`, speed 320. A `BoltBehavior`-style instant cast (`ArrowBehavior`): one arrow at the nearest enemy within `target_range` (the caster already does the targeting, `_auto_cast`), pierce 0, stat keys `arrow.extra` (extra arrows in a fan, as `bolt.extra`, 1 to 4 arrows, same `SPREADS`), `arrow.pierce`, `arrow.cooldown`. Sound `arrow_fire`.

### 4.2 Dash Shot (Q)
`id dashshot`, `animation dash`, `cooldown 4.0`, `range 80` (dash distance, px), `duration 0.15`, `immunity_after 0.2`, `damage 12` (per arrow), `arc_degrees 60`, arrows `7` (param `arrows`), arrow range 180 (so it can reach Steady Aim's full distance of 160), speed 300 (param `speed`); the arrows use `steady = true`.
`DashShotBehavior extends DashSlashBehavior`: the dash goes **towards the aim**, as the Knight's does, and the spray flies back along the way you came (aim north: dash north, arrows fly south). The dash itself (the velocity override, invulnerability, `face_towards`, the 2x guard against a wall, the puffs) is inherited unchanged; it overrides:
- `_hit_path` to do nothing (the dash deals no damage);
- `_finish_slash`, which in the base class slashes, to: grant the grace time (`immunity_after`), then fire `arrows` arrows from the **landing** position in a fan of `arc_degrees` centred on **`-aim`** (behind where you were heading), evenly spaced, pierce 0.
Stat keys: `dashshot.range` (Long Dash), `dashshot.arrows` (extra arrows in the spray), `dashshot.chain` (Double Dash; the caster's chain machinery is generic, verified in `AbilityCaster._try_cast`).
Sound: the existing `dash` for the dash, `arrow_fire` for the spray.

### 4.3 Ricochet Volley (E)
`id ricochet`, `cooldown 7.0`, `damage 12` (per hit), `range 420` (the path of each arrow), params: `speed 360`, `arrows 6`, `interval 0.1`, `hits 3`, `bounces 3`, `bounce_reach 140`; the arrows use `steady = true`.
**Fire and forget, like Meteor**: the cast is instant (it fires arrow 1 at once and returns true), so the caster is never busy and Q or R can be pressed during the volley (a busy cast would drop a press after the 0.15 s input buffer; verified `INPUT_BUFFER`). The remaining arrows are fired by a small node `RicochetVolley` (a child of the Player, created on first cast), which fires one arrow every `interval` seconds along the **aim at that moment** (`player_input.aim_vector`), so the player can sweep the volley, with spread `pattern[i % 6]` degrees from `[0, -3, 3, -6, 6, 0]`; it stops when the player is dead, ends after the last arrow, and pauses with the tree. A shot that cannot be fired (the pool is full) is skipped, not queued. A new E cast cannot overlap a volley (the 7 s cooldown is longer than it).
**Bounce and hit rules (the arrow, section 5)**: each arrow damages at most `hits` (3) different enemies, never the same one twice; after a hit it **bounces to the nearest enemy it has not hit** within `bounce_reach` (140 px) if it has a bounce left; with no such enemy in reach it keeps flying straight; a wall, pillar or arena edge it meets makes it ricochet (also costing one bounce). It ends on its third enemy hit, at a wall with no bounces left, or at the end of its range.
Stat keys: `ricochet.extra` (more arrows), `ricochet.bounces` (+1 bounce), `ricochet.hits` (+1 enemy hit). Sound `arrow_fire` per shot, `arrow_bounce` on each bounce.

### 4.4 Arrow Rain (R)
`id arrow_rain`, `animation attack2`, `cooldown 12.0`, `range 240` (the furthest the zones may be from you), `radius 34` (each zone), `windup 0.9` (the arrows are in the air), `damage 16` per tick; params: `zones 3`, `interval 0.3`, `ticks 5` (so a zone is dangerous from 0.9 s to 2.1 s after the cast).
`ArrowRainBehavior`: the **target point** is the mouse cursor in world space when the mouse is in use, else the player position plus `aim_vector * range` (a pad, or a keyboard before the mouse has moved); clamped to `range` from the player and to the arena inset (the Meteor's `_clamp_to_arena` moves to a static `AbilityBehavior.clamp_to_arena(pos)` that both use; `wizard_abilities.gd` must still pass). `PlayerInput.target_point(origin, mouse_world, mouse_active, aim, range)` is a **pure static function** (so it can be tested) and `PlayerInput.aim_point(range)` calls it with the live mouse state (verified: `_mouse_active` is private and the mouse needs a viewport).
**Layout**: `n` zones sit on a regular n-gon around the target point with circumradius `R = (radius + 8) / sin(pi / n)` and the first corner towards the player; adjacent centres are then `2 * (radius + 8)` apart, which is always more than `2 * (radius + 6)`, the reach `DamageZones._fire` really uses (verified: it queries `radius + 6`), so an enemy is hit by one zone only at **any** radius and zone count (n = 3 at radius 34: R = 48.5, 84 px apart). Each zone: a telegraph circle (`Effects.telegraph`, filled) for the whole windup, a falling-arrows effect over the last 0.35 s (new `Effects.arrow_fall(pos, radius, life)`, placeholder streaks), and `DamageZones.add_field(pos, radius, damage, 0.3, 5, color, windup)` (verified: `add_field` has a delay and ticks). On the cast, a rising-arrows effect from the Archer (`Effects.arrow_rise`). Stat keys: `arrow_rain.radius`, `arrow_rain.extra` (more zones: 4, then 5), `arrow_rain.ticks` (+2 ticks). Sound `arrow_rain` (a whistle, like `meteor_fall`).

## 5. Arrows (projectiles)

Verified: `PlayerProjectile` moves in code and hits through `EnemyGrid.query`; `pierce` lets it continue through that many enemies and **then damages one more** (so `pierce 3` hits four; that is why the Archer's arrows use `hits`, below); it ignores props and retires at the arena edge; `PlayerProjectiles.fire(pos, dir, speed, damage, range_px, pierce)` is the only way to fire (the Wizard's bolts and relic Thorn Nova call it positionally, so a trailing parameter is safe) and has a cap of `MAX_LIVE = 40` shared by all. It draws a bolt, not an arrow.
- `fire` gets an optional last parameter `opts: Dictionary = {}` (existing callers unchanged). Keys: `hits` (int, default 0 = the old pierce rule; the Archer sets it, and the arrow then retires on its `hits`-th distinct enemy), `bounces` (int, 0), `bounce_reach` (px, 140), `arrow` (bool: draw an arrow), `steady` (bool: apply Steady Aim) and `steady_full` (float, read by the firing behavior from `stats.value(&"steady.full", SteadyAim.FULL_DISTANCE)`, because a projectile has no access to the player's `Stats`). The projectile remembers its **launch point** (for Steady Aim). Auto Arrow, Dash Shot and Ricochet Volley all pass `steady = true`; Arrow Rain is not a projectile.
- **Bounce off an enemy**: on a hit, if `bounces > 0` and the arrow has hits left, it picks the nearest enemy within `bounce_reach` that is not in its hit set (and that `ObstacleMap.segment_clear(from, to, 3.0)` says is reachable, when there is an `ObstacleMap`), turns towards it and spends a bounce. With no target it keeps its direction and keeps the bounce. The hit set is **never cleared**: each arrow hits an enemy at most once, so one arrow does at most `hits` hits and a volley at most `arrows * hits`.
- **Ricochet off an obstacle**: after each step, if the arrow overlaps an obstacle (`ObstacleMap.get_for(self).blocked(pos, 3.0)`; verified: `blocked` accepts a radius up to 16) or leaves the playable rectangle (the arena inset by `Arena.wall_margin`), it steps back, the normal is `(obstacles.push_out(pos, 3.0) - pos).normalized()` for walls and pillars (verified: `push_out` returns the nearest clear position, so it is right for a round pillar) or the axis of the edge for the arena, `dir = dir.bounce(normal)`, and a bounce is spent. With no bounces left it retires, as bolts do at the edge today. **Starting inside a blocked cell** (fired next to a pillar): blocking is ignored until the arrow has been clear once, so it cannot burn its bounces on frame 1. **No `ObstacleMap`** (the hub: `ObstacleMap.get_for` is null there): only the arena edge reflects; `archer_arrows.gd` tests this. Bolts and arrows without `bounces` keep today's rule (they pass props and retire at `world_size`).
- **Arrow look**: a thin shaft with a head and fletching, drawn along its direction, 14 px long (`_draw` branches on `arrow`).
- **Cap**: the Archer can need up to 6 (E) + 7 (Q) + 4 (auto, extras) arrows live at once plus relic thorns (12): the shared cap of 40 holds, and `fire` already returns false at the cap, so each behavior checks and skips.
- **Steady Aim** is applied where the damage is dealt: with `steady`, the damage is multiplied by `SteadyAim.multiplier(distance, steady_full)` where `distance` is the straight line from the **launch point** to the enemy hit (not the path length), so bouncing around does not raise it.

## 6. Trait: Steady Aim

`scripts/characters/steady_aim.gd`, `class_name SteadyAim extends Node` (the trait script, added by `Player._apply_character` as `Trait`). Constants `BONUS := 1.30` (the multiplier at full distance), `FULL_DISTANCE := 160.0`, `MIN_DISTANCE := 40.0`, `static func multiplier(distance: float, full_distance: float = FULL_DISTANCE) -> float`: 1.0 up to `MIN_DISTANCE`, rising linearly to `BONUS` at `full_distance`, and `BONUS` beyond (static with no autoload use, so a test can `preload` it). `var active := false` (verified: `Player.trait_active()` reads `Trait.active`, which drives the HUD's FOCUS label; Steady Aim never shows it). `trait_name = "Steady Aim"`, `trait_description = "Up to +30% damage with arrows that have flown 160 px or more."`.
`tests/hub_data.gd` checks `c.trait_script.BONUS` and `DELAY` against the description text (verified); it changes to check `DELAY` only when `c.trait_script.get_script_constant_map().has("DELAY")`, and adds a check that the Steady Aim text shows `+30%` and `160` (`BONUS` and `FULL_DISTANCE`).

## 7. Upgrades (18)

Same shape as the others: `data/upgrades/*.tres` (`UpgradeData`, 3 levels unless noted, `adds`/`mults` on stat keys), listed in `archer.tres`. Existing files are reused where the key fits.

| Ability | Upgrade (id) | Effect | Key |
|---|---|---|---|
| Arrow | Twin Arrow (`arrow_twin`) | +1 arrow per shot, in a fan | `arrow.extra` +1 |
| Arrow | Piercing Arrow (`arrow_pierce`) | arrows pass through +1 enemy | `arrow.pierce` +1 |
| Arrow | Quick Draw (`arrow_rapid`) | Arrow fires 15% faster | `arrow.cooldown` x0.85 |
| Dash Shot | Long Dash (`dashshot_range`) | dash distance +30% | `dashshot.range` x1.3 |
| Dash Shot | Wide Spray (`dashshot_spray`) | +2 arrows in the spray | `dashshot.arrows` +2 |
| Dash Shot | Double Dash (`dashshot_chain`, max 2) | dash again within 1 s, free (Lv 2: twice more) | `dashshot.chain` +1 |
| Ricochet | More Arrows (`ricochet_count`) | +1 arrow in the volley | `ricochet.extra` +1 |
| Ricochet | Bouncier (`ricochet_bounce`) | +1 bounce per arrow | `ricochet.bounces` +1 |
| Ricochet | Armour Piercing (`ricochet_hits`) | each arrow can hit +1 enemy | `ricochet.hits` +1 |
| Arrow Rain | Wider Rain (`rain_radius`) | zone radius +25% | `arrow_rain.radius` x1.25 |
| Arrow Rain | Extra Zone (`rain_zones`, max 2) | +1 zone | `arrow_rain.extra` +1 |
| Arrow Rain | Lingering Rain (`rain_linger`) | zones last +2 ticks | `arrow_rain.ticks` +2 |
| General | Power (`damage`, existing) | +10% damage | `damage` x1.1 |
| General | Vitality (`max_hp`, existing) | +20 max HP and heal 20 | `max_hp` +20 |
| General | Fleet Foot (`move_speed`, existing) | +10% move speed | `move_speed` x1.1 |
| General | Magnet (`pickup_radius`, existing) | +30% pickup radius | `pickup_radius` x1.3 |
| General | Fast Hands (`archer_haste`) | Dash Shot, Ricochet and Arrow Rain cooldowns -8% | `cooldown` x0.92 (the Haste key) |
| General | Eagle Eye (`archer_eagle`) | the auto arrow's range +10%, and every arrow reaches Steady Aim's full bonus 20 px sooner per level | `arrow.range` x1.1, `steady.full` -20 |

`arrow.range` is read by `ArrowBehavior` (like `bolt.range`). `steady.full` is read by each firing behavior as `stats.value(&"steady.full", SteadyAim.FULL_DISTANCE)` and passed in `opts.steady_full` (section 5). There are no mana upgrades. Fast Hands uses the existing Haste key, which multiplies Q, E and R but not the auto arrow (verified in `cooldown_of`).

## 8. Sounds

Three placeholder sounds in four places (`audio.gd` `SOUNDS`, `audio.gd` `PITCH_SPREAD` for `arrow_fire` and `arrow_bounce`, 0.06 each, `tools/gen_sfx.py`, `assets/audio/` with `.wav.import`): `arrow_fire` (a short twang), `arrow_bounce` (a tick), `arrow_rain` (a rising whistle then a patter). The `save(...)` lines are **appended at the very end of `gen_sfx.py`**, after `relic_zap` (the generator draws from one seeded RNG in call order, so anything inserted earlier changes every existing file). Behaviors play `arrow_fire` with `Audio.play`, not the ability's `sfx` (which `caster.play_sfx` plays with its own fixed 0.04 spread). Hits reuse `bolt_hit` (arrows hit through `PlayerProjectile`); Q's dash reuses `dash`. After running the generator `git status` shows only the new files.

## 9. File layout and what it touches

New:
```
data/characters/archer.tres  archer_frames.tres
data/abilities/arrow.tres  dash_shot.tres  ricochet.tres  arrow_rain.tres
data/upgrades/<the 14 new ids of section 7>.tres
assets/sprites/archer/archer_*.png (+ .import)
assets/audio/arrow_fire.wav arrow_bounce.wav arrow_rain.wav (+ .import)
scripts/abilities/arrow_behavior.gd  dash_shot_behavior.gd  ricochet_behavior.gd  ricochet_volley.gd  arrow_rain_behavior.gd
scripts/characters/steady_aim.gd
tests/archer_*.gd
```
Changed: `character_registry.gd` (path), `character_data.gd` (`uses_mana`), `ability_data.gd` (`animation`, `params`, `param()`), `ability_behavior.gd` and `meteor_behavior.gd` (the static `clamp_to_arena`), `hub.tscn` (the ground path under the pedestals, `Rect2(330, 360, 300, 40)`, widened to cover x 320 to 640), `player.gd` (`ONE_SHOT_ANIMS`, animation choice), `player_input.gd` (`aim_point`), `player_projectile.gd` and `player_projectiles.gd` (`opts`, ricochet, arrow look, steady), `effects.gd` (`arrow_rise`, `arrow_fall`), `hud.gd` (no MP bar), `hub_info_panel.gd` (stats text), `audio.gd`, `tools/gen_sfx.py`, `README.md`, `tests/README.md`.
Existing tests that change: `hub_browse.gd` (pedestals at x = 340, 480 and 620 instead of 410 and 550; `hub_right` from the middle goes to 2 and `hub_left` from 0 wraps to 2; the camera ends at x 480 for focus 1; the click test), `hub_data.gd` (section 6). Tests and code that use `CharacterRegistry.all()[0]` or `chars[1]` (`scene_flow`, `run_progress`, `hub_walk`, `camp_site`, `game_session`, the select screen) are unaffected because the Knight and Wizard keep indexes 0 and 1. `tests/audio_layers.gd` checks every sound has a file and a generator line.

## 10. Build order

One commit per step, in this order; tests with the step; the suite after each; `godot --headless --path . --import` after new `class_name` scripts and assets. Step 3 (sounds) only needs the file list of section 8 and can be built in parallel with steps 1 and 2; the rest are sequential because each needs the one before.
1. **Mana, animation and data plumbing**: `CharacterData.uses_mana`, `AbilityData.animation`/`params`, `Player` (`ONE_SHOT_ANIMS`, animation choice), HUD and hub panel without mana, the static `AbilityBehavior.clamp_to_arena`. Test `archer_plumbing.gd` (a stand-in character with `uses_mana = false`).
2. **Arrows**: `PlayerProjectile` `opts` (hits, bounces, bounce reach, look, steady), `PlayerInput.target_point`/`aim_point`, `SteadyAim`, the `Effects` arrow effects. Test `archer_arrows.gd`.
3. **Sounds** (section 8).
4. **Abilities**: the four behaviors, `RicochetVolley` and the four `.tres` files with their upgrade stat keys (the `sfx` of an ability is left unset; behaviors use `Audio.play`). The test sets `caster.ability_*` on a fixture player by hand, since the character does not exist yet.
5. **The character**: the art copied in, `archer_frames.tres`, `archer.tres`, the registry, the 14 upgrade files, the hub changes and test updates, a rendered frame of the hub and a run, looked at; the feet offset tuned. Test `archer_character.gd`.
6. **Docs and tuning**: README, tests README, a play-through, the numbers (O1).

## 11. Tests

| Test | Checks |
|---|---|
| `archer_plumbing.gd` | `uses_mana = false`: no MP bar drawn data (the HUD helper), the panel text has no Mana, every cast succeeds with 0 mana; the default for the Knight and Wizard is true; `AbilityData.animation` overrides the attack toggle and `dash` is one-shot |
| `archer_arrows.gd` | `fire` without `opts` behaves as before; an arrow hit-bounces to the nearest unhit enemy within 140 px, never to one it has hit, keeps its direction with none in reach, spends a bounce only on a turn, ends on its 3rd distinct enemy and never hits one twice; a wall, a pillar (round: the normal is right at the side) and the arena edge reflect it and spend a bounce, with none left it retires; an arrow fired next to a pillar does not burn bounces on frame 1; in the hub (no `ObstacleMap`) only the edge reflects; an arrow without `bounces` still passes pillars; `steady` multiplier 1.0 at 40 px, 1.3 at 160 px, 1.15 at 100 px, on the straight distance from the launch point (bouncing does not raise it); `PlayerInput.target_point` clamps to the range and falls back to `aim * range` without a mouse; the shared cap holds |
| `archer_abilities.gd` | Arrow: nearest target, range, the cooldown, `arrow.extra`; Dash Shot: the dash distance and invulnerability match the Knight's rules, **no** path damage, grace after, arrows fan 60 degrees centred on `-aim` from the landing point, `arrows` count, chain; Ricochet: arrow 1 at the cast and the 6th at 0.5 s, each along the aim at its moment, 3 hits and 3 bounces each, the caster is **not** busy (Q can be cast mid-volley), the volley stops if the player dies, a full pool skips a shot, `ricochet.extra`/`bounces`/`hits` work; Arrow Rain: 3 zones, radius 34, 84 px apart (and for 4 and 5 zones and a larger radius: always more than `2 * (radius + 6)` apart), 0.9 s before the first tick, 5 ticks 0.3 s apart, an enemy is hit by one zone only, range clamp, no mana spent; damage scales with the damage stat; Meteor still works after `clamp_to_arena` moved |
| `hub_browse.gd` (updated) | three pedestals at x = 340, 480, 620; focus and wrap over three |
| `hub_data.gd` (updated) | the Archer's info and Steady Aim text; the old checks still hold |
| `archer_character.gd` | the Archer is in the registry, has all four abilities, a trait, 18 upgrades with valid keys and no mana ones, all seven animations; a run starts as the Archer, 0 mana everywhere, and a level-up offers Archer upgrades and relics |
Tests use `SEED_COUNT` (30) where randomised. `PlayerProjectile`, `PlayerProjectiles` and `Effects` use autoloads, so tests reach them with untyped variables, `tests/fixture.gd` and `load()` after `await process_frame`; `SteadyAim` (static, no autoload) and `PlayerInput.target_point` can be `preload`ed.

## 12. Open questions / assumptions

- **O1: every number is a first guess**, tuned in step 6.
- **O2: bouncing (decided with you)**: an arrow bounces off enemies first (to the nearest enemy it has not hit, within 140 px) and off walls otherwise, 3 bounces in total.
- **O3: "pierce 3" is read as "each arrow hits 3 enemies"** (the `hits` rule of section 5; the old `pierce 3` would hit four). Hits are once per enemy per arrow, so a volley is at most 18 hits; with bouncing in a crowd this can be strong, so 12 damage per hit is likely to be lowered in tuning.
- **O4: E follows the aim as it fires** (a sweepable volley); the alternative is to fix the aim at the cast. It is fire-and-forget so Q and R stay available mid-volley.
- **O5: R's zones sit in a triangle around the cursor**; the alternative is three zones in a line towards it. Pad players aim with the right stick at a fixed range of 240.
- **O6: Dash Shot (decided with you)**: aim north and you dash north; the arrows are fired from the landing point towards the south (a fan of 60 degrees centred on the opposite of the aim); the dash itself does no damage.
- **O7: icons**: the four abilities use placeholder icons from `assets/32x32.png` (regions chosen at build); real art later.
- **O8: Steady Aim counts the straight distance to the enemy hit**, so ricochets cannot farm it; the zones of Arrow Rain are not arrows and do not get it.
- **O9: the freed mana-bar row** at y 17 stays empty rather than moving the other HUD elements.
- **O10: three pedestals fit on one row** (x = 340, 480, 620); a fourth character will need the hub to widen.
- **O11: Fast Hands uses the Haste key** `cooldown` (a multiplier on Q, E, R), like the camp's Haste attribute, so the two stack.
- **O13: the camp's Focus attribute is a dead purchase for the Archer** (section 3).
- **O12: relics are unchanged** and scale with the Archer's damage stat; Steady Aim does not apply to them.

## 13. Definition of Done for v1.1

- The Archer appears as a third pedestal with correct stats, trait and abilities, and can be chosen and played in the hub and in a run.
- Auto Arrow, Dash Shot, Ricochet Volley and Arrow Rain behave as in section 4 (the tests check each number); no mana is shown, spent or needed.
- Arrows ricochet and pierce as in section 5; Steady Aim as in section 6; the shared projectile cap still holds.
- 18 upgrades appear in level-ups, each with a working stat key; relics and the level-up flow work as before.
- The seven supplied animations play (idle, walk, attack alternation, `dash` on Q, hurt, death), looked at once in a real frame.
- Three sounds in the three places; `git status` clean of unrelated files.
- Existing tests pass (`hub_browse.gd` and `hub_data.gd` updated); `tests/run_all.sh` passes on a fresh clone; the crowd tests stay inside budget.
- README and `tests/README.md` list the new files and tests. Nothing in v1.1 stops or slows time.

## 14. Build notes (deviations from rev 2)

- **Tests**: `archer_abilities.gd` became `archer_arrow_dash.gd` and `archer_ricochet_rain.gd` (written in parallel); `archer_upgrades.gd` was added for the 14 new upgrade files. `archer_plumbing.gd` no longer assumes every registered character uses mana.
- **Build order**: steps 1 to 3 ran in parallel (step 2 did not need step 1's fields); abilities were split into two parts and the art and upgrades were built beside them.
- **`PlayerInput` cannot be `preload`ed in a test** (it references the `SceneFader` autoload); `archer_arrows.gd` uses `load()`. `SteadyAim` can be preloaded.
- **Ricochet "clear once" is relaxed for fast arrows**: an arrow also reflects if its previous position was clear, so a fast arrow cannot skip a reflection at a corner. On an enemy bounce the arrow stops checking other overlapping enemies that frame (they are picked up next frame; the hit set prevents repeats).
- **Arrow Rain**: the falling-arrows effect is started by a SceneTree timer `windup - 0.35` s after the cast (there is no scheduling facility); a single zone sits at the centre; only the rain's centre is clamped to the arena, so a large rain can poke slightly past the inset.
- **Dash Shot's spray** is `arrows` (7) plus `dashshot.arrows`, evenly spaced, with no upper cap beyond the shared 40-arrow pool.
- **Hub**: the ground path became `Rect2(310, 360, 340, 40)`. Three ability descriptions and the Archer's description were shortened so the hub info panel fits; the panel is still tight.
- **Icons**: the four Archer abilities use placeholder regions of `assets/32x32.png` (two are the same as existing abilities' icons).
- **Not verified by hand**: hits and bounces in a real crowd (the render check had no visible enemies), the feel of E and R, the effects' timing, sprite offset during Q.
