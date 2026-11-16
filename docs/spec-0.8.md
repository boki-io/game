# Spec v0.8: Feel I (movement and impact)

Builds on spec v0.7 and on the camera dead zone (PR #6, `CameraFollow`). Status: draft rev 2 (rev 2 applies an independent review: tests must switch off `PlayerInput`'s per-frame reset, pickups wait for their pop, a spark budget, kill shake moves to enemy data, teleport guards for dust, and a Flow section).

Terms: **feel** is feedback that changes how the game reads and handles without changing its numbers: how the character
speeds up and stops, and what you see when something is hit or dies. A **bit** is one tiny square particle (new, section 4).
A **burst** is a handful of bits spawned together. The **hurt pulse** is the red edge flash when the player is hit.

## Flow

You walk: the character eases up to speed in a fraction of a second and kicks up a small puff every few steps; let go and it
skids a pixel or two with one puff. You hit an enemy: sparks fly from it, it flashes and recoils a hair. It dies: a burst
in its own colour, and the XP gem it drops hops outward a few pixels before flying to you. A tough enemy's death also kicks the
camera. You get hit: the screen edges pulse red. Nothing ever pauses or slows.

## 1. Scope

The game plays correctly but feels flat: the Player reaches full speed on the first frame and stops dead, nothing marks a
step, and a hit or a kill is a number and a puff. v0.8 adds the missing feedback. It is the first of two feel specs;
v0.9 covers atmosphere and audio.

In scope:
- **Acceleration and friction** for walking (section 2), tuned snappy, in character data, the same for both characters.
- **Footstep dust** and a short skid puff when stopping (section 3).
- **A small particle system** inside `Effects` that dust, sparks and death bursts share (section 4).
- **Stronger hit feedback** on enemies: sparks, a longer flash and a visual recoil (section 5).
- **Death feedback**: a burst in the enemy's colour, a camera kick on tough kills, XP gems and coins that pop outward
  (section 6).
- **A hurt pulse** on the HUD when the Player takes damage (section 6.4).
- Tests, and the README and test README rows that go with them.

Out of scope (decided):
- **Hit-stop** (freezing or slowing time on a hit) is not done, at any strength. Impact comes from the visuals above.
- **No gameplay number changes**: top speed, dash, abilities, damage, health, enemy movement and real knockback are untouched.
- **No new sounds** and no audio changes (v0.9).

Out of scope (later, v0.9: atmosphere and audio): a light glow around the Player, ambient life per map, screen transitions,
pitch variation, layered impact sounds. Blob shadows already exist (`PlaceholderSprite._draw_shadow` under every character and
enemy), so v0.9 does not add them. Also later: a dash afterimage, per-ability spark colours, per-character feel values (the
fields in section 2 are per character, so that is a data edit), per-map dust colour.

## 2. Acceleration and friction

Today `Player._physics_process` sets `velocity = move * stats.value(&"move_speed", move_speed) * speed_scale` every frame
(`scripts/player/player.gd`). Abilities that take over movement set `override_active` and `velocity_override` (Dash & Slash),
or scale the target through `speed_scale` (Spin, Slam, Phase Shift). Agility (a camp attribute) and upgrades scale
`move_speed` through `Stats`.

### 2.1 Data
Two new fields on `CharacterData` (`scripts/characters/character_data.gd`, "Stats" group), set in both `.tres` files:

| Field | Default | Meaning |
|---|---|---|
| `accel_time` | 0.06 | seconds from standstill to top speed |
| `friction_time` | 0.08 | seconds from top speed to standstill |

Both are `@export_range(0.0, 0.5)`. Zero means instant, today's behaviour. Both characters use the defaults.

### 2.2 Algorithm
The walking path only; the override path is described in 2.3. Each physics frame:

```
top    = stats.value(&"move_speed", move_speed) * speed_scale
target = move_vector * top
rate   = top / accel_time      if move_vector != ZERO
         top / friction_time   otherwise
if the time is 0 or top is 0:  _move_vel = target                 (no division: instant, as today)
else:                          _move_vel = _move_vel.move_toward(target, rate * delta)
velocity  = _move_vel
move_and_slide()
_move_vel = velocity           # keeps the wall's effect: pushing into a wall leaves no speed in that direction
```

- `_move_vel` is a new private `Vector2` on `Player`. `velocity` stays what tests and `move_and_slide` read.
- A stick pushed halfway gives half of `top` as the target, as today.
- Reversing direction passes through zero at `rate`, so it takes up to `2 * accel_time` (0.12 s); a 90 degree turn cuts the corner and dips
  to about 70% speed for about 0.085 s. Accepted (O2).
- `speed_scale` and Phase Shift change `top`, and so the target and the rate, at once; the velocity follows within the same ramp. Spin
  and Slam set `speed_scale` to 0.4, so casting one while walking slows 90 to 36 px/s over about 0.09 s instead of instantly, and
  speeds back up over about 0.04 s when it ends. The top speeds and durations are unchanged; the changes of speed are eased.
- `SceneFader.busy` already zeroes `move_vector`, so a fade out stops the Player through friction.

### 2.3 Dash, death and other overrides
- While `override_active`, `velocity = velocity_override` as today. After `move_and_slide`, `_move_vel` is set to
  `move_vector * top`: a dash that ends with a key held hands over at walking speed, with no ramp up from zero; with no key
  held it ends at zero, as it does now. (`DashSlashBehavior.finish()` clears `override_active` after the dash's last frame, so
  the next walking frame reads that `_move_vel`. This is the only place `_move_vel` is set from the input directly.)
- `_on_died` already zeroes `velocity`; it also zeroes `_move_vel`. The early return for `dead` stays.
- The hub uses the same Player, so it gets the same feel. Tests that teleport the Player (`global_position = ...`) are unaffected.

### 2.4 Effect on play
Top speed is unchanged. For the Knight (90 px/s) the cost of the ramp is under 3 px of distance (`0.06 * 90 / 2`) and the coast on
release is about 3.6 px (`0.08 * 90 / 2`); the Wizard (85 px/s) is slightly less. Arcane Focus (`arcane_focus.gd`) reads `move_vector`, not `velocity`, so it still arms the
moment the key is released, up to 0.08 s before the Player has stopped; accepted.

## 3. Footstep dust

`Player` keeps `_last_pos` (set in `_ready`), a stride counter, and `_was_moving` (the previous frame's `move_vector != ZERO`).
`Effects` is an instance, so the call is `var fx := Effects.get_for(self)` and `if fx: fx.dust(...)`, as `_tick_phase` does.
- Each physics frame, while not `dead`, not `override_active` and `phase_left <= 0.0` (Phase Shift has its own trail), add the
  distance moved since `_last_pos` to the counter. A step longer than `2 * top * delta` is a teleport (tests, the hub, a Phase
  or camp placement): reset the counter and ignore it. Each time the counter passes `DUST_STRIDE` (14 px) subtract the stride
  and call `fx.dust(global_position, dir)` (`dir` is the direction moved), at most once per frame.
- **Skid:** on the frame `move_vector` becomes zero (`_was_moving` true), while not `override_active`, `speed_scale == 1.0` and the
  speed before this frame's ramp (`_move_vel.length()`) is at least `0.7 * stats.value(&"move_speed", move_speed)`, call
  `fx.dust(global_position, _move_vel.normalized(), 3)`.
- Constants, by name: `DUST_STRIDE` 14.0, `SKID_SPEED_FRACTION` 0.7 in `player.gd`; `DUST_COLOR`, `DUST_SPEED`, `DUST_DRIFT`,
  `DUST_LIFE` in `effects.gd` (section 4). They are visual constants, not tuning data (O11).
- Dust is drawn at the feet, so it sits above the character's sprite: `Effects` is `z_index = 10`. Accepted; it is 2 px squares.

## 4. Particle bits in Effects

`Effects` (`scripts/systems/effects.gd`) draws timed visuals from one canvas item; its `_fx` list holds dictionaries and has no
cap. v0.8 adds a second list, `_bits`, so the new load cannot crowd out the existing effects and tests that inspect `_fx` keep
reading what they read now (`monster_variants.gd` counts the death puffs in `_fx`; section 12).

```
func burst(pos: Vector2, color: Color, count: int, speed: Vector2, life: float, size: float,
           dir := Vector2.ZERO, spread := TAU, drift := Vector2.ZERO, low_priority := false) -> void
func dust(pos: Vector2, dir: Vector2, count: int = 2) -> void
```

- `speed` is a (min, max) range. `spread` is the total cone angle: a bit's angle is `dir.angle()` plus a random value in
  `±spread/2` (the whole circle when `dir` is ZERO). `drift` is a constant velocity added to every bit (dust rises).
- `dust` is a `burst` with `DUST_COLOR` `Color(0.8, 0.75, 0.65, 0.6)`, `DUST_SPEED` (6, 14), `DUST_LIFE` 0.3 s, size 2, `dir = -dir`
  (backwards), `spread` 60 degrees, `DUST_DRIFT` `Vector2(0, -14)`.
- A bit is `{pos, vel, age, life, color, size}`. Each bit gets a speed in the `speed` range (min, max), at a random angle
  within `spread` of `dir` (the whole circle when `dir` is ZERO).
- **Cap `MAX_BITS = 256`.** Over the cap the oldest bits are dropped in one slice per call, not one by one. 300 enemies dying in a few
  seconds cannot cost more than 256 small rectangles per frame.
- **Spark budget:** a `low_priority` burst (hit sparks) is skipped while `_bits.size() > 192`, so deaths win over sparks in a crowd.
  Deaths and dust are normal priority.
- Bits fade linearly (`alpha * (1 - age/life)`) and are drawn as `draw_rect` squares at rounded positions (pixel look).
- `_process` returns early only when `_numbers`, `_fx` and `_bits` are all empty. `clear()` also empties `_bits`.
- Bits move in world space, never collide, and are removed when `age >= life`.

## 5. Hit feedback on enemies

`Enemy.take_damage(amount)` is the one entry point every ability uses (`enemy.gd`); the new behaviour lives there and no
ability changes. `away` is the unit vector from the nearest Player (`PlayerRegistry.nearest`) to the enemy; ZERO if none.

- **Sparks:** on a hit that does not kill, `Effects.burst` at the body centre (`global_position + (0, -body_size.y / 2)`), 3 bits,
  colour `sprite.body_color.lightened(0.5)`, speed 60 to 110 px/s, life 0.18 s, size 2, `dir = away`, `spread = 100°`.
  The sparks are emitted in the `health.current > 0.0` branch of `take_damage`, so a killing hit gets only the death burst of
  section 6 (`_on_died` runs inside `health.take_damage`, before that branch). Sparks are low priority (section 4).
- **Flash:** `FLASH_TIME` 0.06 s becomes 0.09 s. It only applies to enemies without drawn `hit` frames; the slime art flashes itself.
- **Recoil:** a visual shove of the body only. `sprite.position` is set to `away * 2.0` px and eases back to zero in `RECOIL_TIME`
  (0.1 s). The ease runs in `Enemy._physics_process` beside the `_flash_left` tick, before the `target == null` return, guarded by
  `if _recoil_left > 0.0` (300 enemies run this every tick). `global_position`, the hitbox, the knockback and the grid are not touched. Skipped for
  `data.immovable` enemies (the hub dummies must not move or tint; `hub_dummies.gd` checks `global_position` and `sprite.modulate`, and `impact_feedback.gd` checks `sprite.position`). Reset in `activate()`.
  The drawn art is a child of `sprite`, so it recoils with it.
- Training dummies do get the sparks.

## 6. Death and pickup feedback

### 6.1 Death burst
`Enemy._on_died` (before `died.emit`): `Effects.burst` at the body centre, in `sprite.body_color` (the map variant's colour),
`count = clampi(roundi(body_size.x * body_size.y / 30.0), 5, 14)` (Grunt 6, Ranged 7, Dasher 14), speed 50 to 100 px/s over the
full circle, life 0.35 s, size 2. The existing death animation or the colour puff in `_fx` stays (one puff per death still).

### 6.2 Kill shake
`EnemyData` gets `kill_shake: float = 0.0` (strength; the time is the constant 0.1 s). `data/enemies/dasher.tres` sets 1.2; Grunt,
Ranged and the dummy stay at 0, because at 300 enemies a shake per kill would never stop. When `kill_shake > 0`, `_on_died` calls
`CameraFollow.shake(self, data.kill_shake, 0.1)`. It is deliberately a subtle kick (the Player's own hit shake is 1.5 for 0.12 s, and
the camera takes the larger of overlapping shakes).

### 6.3 Pickups pop out
`XPGem` and `Coin` (`scripts/systems/xp_gem.gd`, `coin.gd`) sit still until `attract()`. But `XPCollector` (radius 48 px, `area_entered`)
calls `attract()` the moment a pickup overlaps, which for melee kills is the next physics frame, so a pop that stopped on `attract()`
would almost never be seen. Decision: **the pull-in waits for the pop to finish.** `attract()` still sets `target` at once, as now.
- `activate` sets `_pop_vel` to a random direction times 150 to 170 px/s.
- Each `_physics_process`, while `_pop_vel != ZERO`, the pickup moves by `_pop_vel * delta`, `_pop_vel` moves toward zero at
  1000 px/s², the position is clamped as `Enemy._physics_process` clamps (`ARENA_PADDING + Arena.wall_margin` on every side of
  `Arena.world_size`), and the function returns before the pull-in code. It travels 11 to 15 px and rests after 0.15 to 0.17 s.
- `deactivate()` zeroes `_pop_vel`. Pickups ignore walls (areas), so one that pops into a wall stays collectible (O8).
- The cost: XP and coins reach the Player at most about 0.17 s later than today. Speeds, the acceleration and the collect distance are
  unchanged. The pop direction uses the global RNG (visual only, like the shake); tests allow the whole range.

### 6.4 Hurt pulse
`Hud` (`scripts/ui/hud.gd`) already connects to the player in `bind` (the run and the hub both call it with a fresh Player, so
there is no double connect; `bind` also resets `_hurt_pulse` to 0). Connect `player.hurtbox.hit_taken` to set `_hurt_pulse` to
`HURT_PULSE_TIME` (0.35 s); it counts down in `_process`. While above zero, `_draw` draws the pulse after its `is_instance_valid(player)` check and before everything else: 8 bands, 6 px wide,
stepping in from each screen edge, band `i` coloured `Color(0.9, 0.1, 0.1, 0.3 * (1 - i / 8.0) * _hurt_pulse / 0.35)`. `hit_taken`
only fires for a hit that landed, so i-frames and Phase Shift never pulse. At 640x360 the 8 bands are 48 px, about 7.5% of the width;
corners where two bands overlap are a little darker, which is fine. The existing `Vignette` is the map's look and is not touched.

## 7. Sounds

None added or changed. The existing player-hurt, enemy-hit and enemy-death sounds play as before.

## 8. File layout

New: `tests/movement_feel.gd`, `tests/impact_feedback.gd`.
Changed: `scripts/characters/character_data.gd`, `data/characters/knight.tres`, `wizard.tres` (two fields; set explicitly even though
the defaults match), `scripts/enemy/enemy_data.gd` and `data/enemies/dasher.tres` (`kill_shake`), `scripts/player/player.gd`, `scripts/systems/effects.gd`, `scripts/enemy/enemy.gd`,
`scripts/systems/xp_gem.gd`, `scripts/systems/coin.gd`, `scripts/ui/hud.gd`, `README.md` (a line about the feel), `tests/README.md`.
No scene changes, no new autoloads, no new physics layers.

## 9. Tests

Test mechanics (CLAUDE.md and `tests/README.md`): `extends SceneTree`, `await process_frame` first, untyped variables, `load("res://tests/fixture.gd")`,
run a new test with a time limit. **`PlayerInput._physics_process` overwrites `move_vector` from the (empty) device input every
tick**, so a test that holds a direction calls `p.player_input.set_physics_process(false)` first (as `wizard_animations.gd` does)
and then sets `move_vector`. Without that the ramp would never get past one frame.

New `tests/movement_feel.gd` (a run scene, Knight):
- One frame after holding right the speed is above 0 and below top; after `accel_time` plus two frames it equals top (90, and 108.9
  with Agility 7); it never exceeds top.
- Releasing: speed falls to 0 within `friction_time` plus two frames and is not 0 on the first frame.
- A diagonal never exceeds top. A Player pushing into a wall has no speed along the wall's normal.
- `accel_time = 0` and `friction_time = 0` reproduce today's instant behaviour.
- A dash that ends with a key held leaves speed at top the next frame; without a key, at 0. Phase Shift (`speed_scale` 1.5) reaches
  135. A dead Player has zero velocity. Speed 0 or time 0 gives no NaN.
- Dust: walking 100 px adds about 14 bits (7 strides of 2; compare `fx._bits.size()` before and after, with generous bounds); none while
  standing, dashing, phased or dead; a 400 px teleport adds none; one skid (3 bits) on stopping from top speed, none from a crawl or under Spin.

New `tests/impact_feedback.gd`:
- A non-lethal hit gives 3 bits (none while `_bits.size() > 192`), a 0.09 s flash on a placeholder enemy and a recoil of at most 2 px.
  The fixture's frozen enemies have `set_physics_process(false)`, so the test steps the ease by calling `e._physics_process(1.0 / 60.0)`
  itself and checks `sprite.position` is 0 after 0.1 s of steps. A dummy gives sparks, `sprite.position == ZERO`, an unchanged
  `global_position` and no tint.
- A kill gives the death burst count by size (6, 7, 14), no hit sparks, and exactly one puff in `fx._fx` (what `monster_variants.gd`
  expects). A Dasher kill (`kill_shake` 1.2) shakes the camera; a Grunt kill does not.
- A gem and a coin spawned at a point end 10 to 17 px away and still after 0.3 s, then collect normally; `attract()` mid-pop does not
  stop the pop and the pull-in starts only after it (check a gem inside the 48 px radius); a pickup near an arena edge stays inside the arena.
- The cap: 1000 bursts leave 256 bits; `clear()` empties them; bits are gone after their life.
- The hurt pulse: a landed hit sets `_hurt_pulse` above 0 and it is 0 after 0.4 s; a hit during Phase Shift or grace does not.

Existing tests touched:
- `tests/camp/camp_attributes.gd` lines 120 to 122 and 146 to 148 read `velocity` one frame after setting `move_vector`; they call
  `p.player_input.set_physics_process(false)`, set `move_vector`, and wait `accel_time + 0.1` s (`F.seconds`) first, then restore the input.
- `tests/crowd_performance.gd` and `tests/maps/crowd_bone_warren.gd` must stay under their 12 ms budget. They measure physics time only (the
  recoil and spark code is in it; drawing the bits is not), so a manual check in a real window with a meteor on a crowd is also needed (DoD). `crowd_bone_warren` failed once on a loaded machine at 13.4 ms and passed when re-run, so a
  failure there is re-run before it is blamed on this change.
- `monster_variants.gd` and `slime_sprites.gd` stay as they are: bits live in `_bits`, not `_fx`; the flash and puff paths are unchanged.
- `hub_dummies.gd`, `hub_walk.gd`, `wizard_animations.gd`, `dash_immunity.gd` and `double_dash.gd` should pass unchanged; the run proves it.

## 10. Build order

One step, one commit, tests with the step.
1. **Movement:** `CharacterData` fields, the `.tres` values, `Player` ramp, the dash handoff, `camp_attributes.gd` update; the movement part of `movement_feel.gd`.
2. **Bits:** `Effects.burst`, `dust`, the cap, the spark budget, `clear`, `_process`, `_draw`; creates `impact_feedback.gd` with the cap tests.
3. **Dust:** the stride counter, the skid; the dust tests.
4. **Hit feedback:** flash time, sparks, recoil; the hit tests added to `impact_feedback.gd`.
5. **Death and pickups:** death burst, `EnemyData.kill_shake`, gem and coin pop (the pull-in waits); the death and pickup tests.
6. **Hurt pulse:** `Hud`; its test.
7. **Play and tune:** play a run with each character in a real window (a meteor on a crowd for the bits' draw cost), then tune the numbers in
   sections 2 to 6 by feel; exit when the user is happy with how it plays; the final numbers are written back into this spec;
   `README.md`, `tests/README.md`; run the full suite and record the crowd means.

## 11. Compatibility

- Top speed, abilities, enemy health, damage, knockback, spawn rules and the level-up pool are unchanged. The Knight is about 3 px
  slower to start and coasts about 3.6 px on release (2.4). Spin and Slam change speed by easing, not instantly (2.2).
- XP and coins reach the Player up to about 0.17 s later (6.3), the one gameplay-visible change; it is a decision to confirm (O10).
- Setting both times to 0 restores the old movement exactly, which makes the change easy to compare and to back out.
- A Player built without these fields (tests, `fixture.gd`, the map preview) uses the defaults and so also ramps; tests that read `velocity` wait.
- Visual only: recoil moves `sprite.position`, never `global_position`; bits never collide or affect gameplay.

## 12. Open questions / assumptions to revisit

- **O1: all numbers are first guesses** (0.06 and 0.08 s, the stride, counts, speeds, lives, the 0.3 pulse alpha). They are tuned in build step 7.
- **O2: reversing takes up to 0.12 s** and a 90 degree turn dips to about 70% speed, because the ramp is in vector space. A snappier turn
  would use a higher rate when the target opposes the current velocity. Revisit if turning feels sticky.
- **O3: kill shake only for tough kills** (`max_health >= 50`). Worth asking whether Ranged enemies should also shake.
- **O4: sparks and bursts use the enemy's colour**, not the ability's. Per-ability colours need every damage call site to pass its source.
- **O5: dust colour is one beige** on every map. A per-map colour from `MapTheme` is possible later.
- **O6: Arcane Focus arms up to 0.08 s early** (section 2.4); it could read the real speed instead.
- **O7: recoil assumes `$Sprite` rests at `(0, 0)` in `enemy.tscn`.** Verified: no position is set there and `PlaceholderSprite.shake` is draw jitter, not `position`.
- **O8: pickups pop even when they spawn in a wall.** They are areas with no collision, so they stay collectible; clamped to the arena only (same clamp as enemies).
- **O9: the hurt pulse is one intensity** whatever the damage. A scale with the hit's size is a later option.
- **O10: the pickup pull-in is delayed by the pop** (up to 0.17 s) so the pop is visible for melee kills; the alternative is a pop that
  only plays for ranged kills. Revisit if collecting feels slow.
- **O11: recoil, spark, burst and pulse numbers are named constants in the scripts**, not data: they are the look of a feature, not
  balance. Only `accel_time`, `friction_time` and `kill_shake` are data, because they vary per character or per enemy kind.

## 13. Definition of Done for v0.8

Each visual item has a measurable proxy that the tests check, and is also looked at once in a real window (an unchecked PR box).
- Walking ramps up and coasts to a stop with the `CharacterData` times: speed after one frame is above 0 and below top, equals top after
  `accel_time` plus two frames, is 0 within `friction_time` plus two frames of release; top speed is unchanged; both times 0 give today's
  instant movement; dash, Phase Shift, Spin and Slam keep their top speeds and durations (Spin and Slam ease into and out of the slow speed).
- Footstep dust: `_bits` grows by 2 per 14 px of walking and by 3 on a skid from speed; nothing during dash, phase, death or a teleport.
- A non-lethal hit on an enemy adds 3 sparks (skipped over 192 bits), a 0.09 s flash (placeholder body) and a 0.1 s recoil of at most 2 px
  that never changes `global_position` and never touches the dummies; a kill adds the body-coloured burst of 6, 7 or 14 bits and still one puff
  or death animation; a Dasher kill shakes the camera.
- XP gems and coins end 10 to 17 px from where they spawned after about 0.17 s; the pull-in and the collection then work as before.
- A landed hit sets `_hurt_pulse` to 0.35 s and it is 0 after 0.4 s; i-frames and Phase Shift never set it.
- The bits never exceed 256 and `Effects.clear()` empties them.
- Both new tests pass, the existing suite passes (the listed `camp_attributes.gd` update aside), the crowd tests stay under 12 ms, and
  `tests/run_all.sh` passes on a fresh clone. A meteor on a crowd was watched in a real window for frame rate (the crowd tests do not
  measure drawing).
- Nothing in v0.8 stops, slows or freezes time.
