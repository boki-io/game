# Spec v0.3: The Wizard

Builds on `spec-0.1.md` and `spec-0.2.md` (all built). Adds a second playable character, the **Wizard**,
a ranged spellcaster that plays very differently from the melee Knight. Placeholder art and generated
sounds remain acceptable.

Revision 2: updated after an independent review of revision 1 against the code. Section 13 lists what
changed.

## 1. Scope

**In v0.3:**
- The Wizard character, selectable on the Character Select screen next to the Knight.
- Four Wizard abilities: Arcane Bolt (auto), Phase Shift (Q), Chain Lightning (E), Meteor Strike (R).
- A Wizard upgrade pool (13 ability upgrades and the 6 shared passives).
- The Wizard trait **Arcane Focus**.
- The shared systems this needs: player projectiles, conditional stat modifiers, damage fields, burst
  effects (sound and shake), lightning visuals, and a "no target" cast check.

**Out of v0.3:** new enemies, new maps, real art for either character, meta-progression, enemy status
effects (burn and slow were considered and cut; the Wizard uses only damage, stun and knockback).

**The question this version answers:** does a ranged, mobility-and-burst character feel different enough
from the Knight to justify more characters, and does the ability framework hold up for a second kit?

## 2. The Wizard at a glance

| | Knight (v0.1) | Wizard |
|---|---|---|
| Role | Close-range brawler | Ranged spellcaster |
| HP | 100 | **90** |
| Move speed | 90 px/s | **85 px/s** |
| Max mana / regen | 100 / 8 per s | **140 / 10 per s** |
| Auto | Slash (90px targeting, melee arc) | **Arcane Bolt** (150px targeting, projectile) |
| Q | Dash & Slash | **Phase Shift** |
| E | Spin | **Chain Lightning** |
| R | Slam | **Meteor Strike** |
| Body color (placeholder) | blue | **gold** (not blue, red, green or purple: those belong to the Knight and enemies) |

- Character id `wizard`, display name "Wizard", description "Ranged spellcaster. Strikes from afar and
  teleports out of trouble." (placeholder text).
- On the Character Select screen the Knight stays first and the Wizard is second. The existing Prev and Next
  buttons appear automatically when there are two characters.
- A full Q+E+R rotation costs 12 + 15 + 29 = 56 mana against a 140 pool.

## 3. Wizard abilities

All numbers are first guesses and live in `data/abilities/*.tres` (see 8 for the new `AbilityData` fields).
Damage is before the Wizard's modifiers (upgrades and Arcane Focus). Each ability needs a `.tres`, a behavior
script (`bolt_behavior.gd`, `phase_behavior.gd`, `lightning_behavior.gd`, `meteor_behavior.gd`) and a
description for Character Select. `icon` is optional (without one the HUD draws a colored circle).

### 3.1 Arcane Bolt (auto, no mana)

| Stat | Value |
|---|---|
| Cooldown | 0.65s |
| Mana | 0 |
| Damage | **10** |
| Targeting range | 150px (`target_range`) |
| Projectile | speed 260 px/s, flies up to 200px (`range`), radius 4 |
| Pierce | 0 (stops at the first enemy it hits) |

- Behavior: the auto-cast picks the closest **active** enemy within 150px (as the Knight's Slash does, but
  with the longer range). It fires one bolt from the Wizard toward that enemy. Does nothing if no enemy is in
  range.
- **Zero direction:** if the target is within 1px of the Wizard, the bolt uses the player's `aim_vector`
  instead of a zero vector.
- The bolt is a player projectile (section 6.1). It damages the first enemy it touches and disappears.
- Damage is read when the bolt is **fired** (so Arcane Focus at the moment of the shot is what counts).
- The sprite faces the shot direction for 0.25s, like other casts.
- It holds off while a Q, E or R cast is running, like the Knight's Slash. Meteor Strike does not count (it
  does not keep the caster busy, see 3.4).

### 3.2 Phase Shift (Q)

(Replaces Blink from revisions 1 and 2, which was found confusing as a teleport. See section 15.)

| Stat | Value |
|---|---|
| Cooldown | 1.8s |
| Mana | 12 |
| Duration | 0.8s (`duration`) |
| Speed | +50% walking speed while phased (`speed_multiplier` 1.5) |
| Immunity | unhittable for the whole duration, plus 0.2s afterward (`immunity_after`) |
| Orb belt | 5 orbs circle the Wizard for 2.0s **after the phase ends**: orbit radius 28px (`radius`), 2 turns per second, 8 damage per hit (`damage`), each enemy hit at most once per 0.5s |
| Ghost Touch (upgrade) | 6 damage per tick per level while phased (75% of the orb damage) |

- Behavior: instant to cast, then a **timed ghost state** on the Player (`Player.start_phase`). It does not
  block the caster, so the Wizard can move, shoot, and cast Chain Lightning or Meteor Strike while phased.
- While phased the Wizard is invulnerable (the hurtbox is invulnerable, so contact hits, Dasher lunges and
  projectiles pass through; projectiles are not consumed), moves 50% faster, and is drawn translucent
  blue with a fading trail of puffs.
- Enemies have no collision bodies, so "walking through enemies" needs no extra code. Phase Shift's value is
  the immunity and speed.
- When the duration ends (or the Wizard dies) the state is cleaned up; after a normal end the 0.2s grace
  flicker plays.
- **Orb belt:** when the phase ends normally, a ring of 5 blue orbs appears around the Wizard, follows them, and
  orbits for 2.0s (fading in over 0.15s and out over 0.35s). Any enemy an orb touches takes 8 damage; an enemy
  can be hit by the belt at most once per 0.5s however many orbs pass it. The belt damage is read when the
  phase is cast. It stops on death. Casting Phase Shift again restarts the belt when that phase ends.
- The Q icon uses the normal cooldown sweep. There is no follow-up chain.

### 3.3 Chain Lightning (E)

| Stat | Value |
|---|---|
| Cooldown | 1.8s |
| Mana | 15 |
| First target range | 150px, within **40 degrees either side** of the aim vector (`cone_degrees` is the half-angle) |
| Jumps | 4 (so up to 5 targets) |
| Jump radius | 60px from the previous target |
| Damage | **22** to the first target, then x0.85 per jump (22, 19, 16, 14, 12, rounded for display) |

- Behavior: instant. The first target is the nearest **active** enemy to the Wizard inside the aim cone. From
  each target the bolt jumps to the nearest active enemy not yet hit within the jump radius. It stops when there
  is no next target or the jump count is used.
- **No target:** if no enemy is inside the cone, the cast does not happen (see `can_cast` in 6.2). No mana is
  spent and no cooldown starts. The HUD flashes the icon and plays the blip (`cast_failed`, reason `no_target`).
- Visual: a jagged line is drawn from the Wizard to the first target and between each pair of targets,
  lasting about 0.15s. Each target gets the normal hit flash.
- It does not stun by default (see the Static Shock upgrade).

### 3.4 Meteor Strike (R)

| Stat | Value |
|---|---|
| Cooldown | 5.0s |
| Mana | 29 |
| Impact point | 120px along the aim vector (`range`), fixed when cast, clamped to 8px inside the arena |
| Warning | **0.7s** ground marker (`windup`) |
| Blast | radius 64px, 90 damage, knockback 140 px/s |

- Behavior: **fire and forget.** Casting is instant. It places a ground marker at the impact point and
  schedules the blast 0.7s later through the damage-zone system (6.4). The caster is **not busy** while the
  meteor falls, so the Wizard can keep shooting, Phase Shift, or Chain Lightning during the warning. (This differs
  from the Knight's Slam, which locks the caster.)
- **Captured at cast time:** impact point, radius and damage are fixed when cast (later upgrades or Arcane
  Focus changes do not alter a meteor already in the air).
- The marker uses the Slam telegraph style but **fills** from the center outward over the 0.7s and brightens
  (`Effects.telegraph` gains a fill option).
- At impact (all from the zone's burst payload, 6.4): a falling-meteor visual lands, a shockwave ring plays,
  the impact sound plays, the screen shakes (3px, 0.2s), and every enemy in the radius takes damage and is
  knocked back.
- The blast hits enemies only. The marker is not dangerous to the Wizard.
- The blast still lands if the Wizard dies or the game is paused (pause simply freezes the timer). It is
  removed with the scene on restart or return to the menu, because zones belong to the Game scene.
- Twin Meteor: see section 5.

## 4. Trait: Arcane Focus

- After standing still for **1.0s**, the Wizard deals **+25% damage** (all abilities) until they move again.
- "Standing still" means no movement input. Casting (including Phase Shift) does not break it.
- Effect: a conditional damage multiplier on the Wizard's `Stats` (6.3) that turns on at 1.0s of stillness
  and off the moment the move vector is non-zero.
- **Detecting Blink:** the trait listens to `AbilityCaster.cast_started` and resets its timer when the cast's
  `AbilityData.id` is `blink` (including free follow-up blinks).
- **Bolt timing:** Arcane Bolt reads damage when fired (3.1); Chain Lightning reads it at the cast; Meteor reads it at cast time (3.4). So moving after casting does not reduce a bolt already in flight.
- Feedback: a faint gold ring pulses around the Wizard's feet while it is active, a soft chime plays when it
  switches on, and a small gold "FOCUS" mark shows by the HP bar.
- Implemented as a character trait script (`CharacterData.trait_script`, a `Node` subclass) that the Player
  instances and adds as a child inside `_apply_character`. It finds `Stats`, `PlayerInput` and
  `AbilityCaster` as siblings (all exist by then).
- This trait is the only place that rewards stopping, and it is meant to pull against the Wizard's kiting.

## 5. Wizard upgrade pool

Same rules as the Knight: 3 levels per upgrade unless noted, choices exclude maxed upgrades, each level
applies the modifier again through `Stats`. 12 ability upgrades and the 6 shared passives (Vitality, Focus
regen, Deep Well, Fleet Foot, Magnet, Power), 18 in total. Each new upgrade needs a `.tres` with
`display_name`, `description` and `tag` (the ability name) for the level-up card.

Stat keys are `<ability id>.<stat>`. The ids are `bolt`, `phase`, `lightning`, `meteor`. Stats read through
`caster.value(data, &stat, base)`, so every key below must be read through that call in the behavior.

**Arcane Bolt**
- **Twin Bolt:** +1 bolt per level, fired in a spread (2 bolts: 0 and 10 degrees; 3: -10, 0, 10; 4: -15, -5,
  5, 15). Every bolt does full damage. (`bolt.extra` add 1)
- **Piercing Bolt:** the bolt passes through +1 enemy per level. (`bolt.pierce` add 1)
- **Rapid Fire:** -15% cooldown per level. (`bolt.cooldown` x0.85)

**Phase Shift**
- **Long Phase:** +30% duration per level (0.8s, 1.04s, 1.35s, 1.76s at level 3). (`phase.duration` x1.3)
- **Swift Phase:** +20% walking speed per level on top of the +50% (so +70%, +90%, +110%).
  (`phase.speed_bonus` add 0.2)
- **Ghost Touch:** enemies you are touching while phased take 6 damage per level every 0.25s (within 16px).
  The damage uses `damage_of`, so Power and Arcane Focus apply. (`phase.touch` add 1)
- **Orbital Ring:** +2 orbs and +0.5s of belt time per level (5 to 11 orbs, 2.0s to 3.5s). (`phase.orbs` add 2
  and `phase.belt_time` add 0.5)

**Chain Lightning**
- **Extra Jumps:** +2 jumps per level. (`lightning.jumps` add 2)
- **Static Shock:** every target hit is stunned for 0.5s per level. (`lightning.stun` add 1)
- **Wide Arc:** +25% jump radius per level and +10 degrees on the first-target cone half-angle.
  (`lightning.radius` x1.25 and `lightning.cone_degrees` add 10; the behavior reads
  `caster.value(d, &"cone_degrees", d.cone_degrees)`.)

**Meteor Strike**
- **Bigger Blast:** +25% radius per level. (`meteor.radius` x1.25)
- **Twin Meteor:** max level 2. +1 extra meteor per level. The extra meteors land 0.4s after the previous
  one, each at a random point within 50px of the first impact (clamped to the arena). **All markers appear at
  cast time**, each filling over its own delay (0.7s, 1.1s, 1.5s), and each has full damage and radius.
  (`meteor.extra` add 1)
- **Scorched Earth:** the first impact leaves burning ground for 3s: every 0.5s it deals
  `meteor damage x 0.04 x level` (about 3.6 per level at base) over the blast radius. The first tick is
  immediate, 7 ticks in total. Extra meteors from Twin Meteor do not leave extra fire. (`meteor.scorch` add 1)

Damage (`damage`) and cooldown modifiers read by the Knight's keys keep working for the Wizard's ability ids.
The global Power passive and Arcane Focus both apply to fields (Scorched Earth), because field damage
is computed through `damage_of`.

## 6. New and changed systems

### 6.1 Player projectiles

- A new `PlayerProjectiles` node (a pool, group `player_projectiles`, in the World like the enemy
  `Projectiles` node) and a `PlayerProjectile` scene. Cap: 40 live; at the cap a new shot is dropped.
- Movement is plain code. Hits use the **enemy spatial grid** (`EnemyGrid.query` at the bolt's position with a
  radius of the bolt radius + 6), not physics bodies, matching how the Knight's attacks hit.
- Each projectile has: direction, speed, damage, remaining range, remaining pierce, and a **hit set** of the
  enemies it has already damaged (so one enemy is hit once per bolt, and pierce is spent only on new enemies).
- It retires when pierce is spent, when range is used up, **or when its lifetime runs out** (lifetime =
  range / speed + 0.5s, a guard against a zero-velocity or stuck bolt), or when it leaves the arena.
- A projectile only damages **active** enemies.
- It **passes over props** (they are low scenery) and is not blocked by walls other than the arena edge.
- Visual: a bright cyan-white orb with a short trail. Sounds: fire and hit.
- A projectile never hurts the player.

### 6.2 Cast checks and targeting

- `AbilityBehavior` gains `can_cast(caster, aim, data) -> bool` (default true). It runs in
  `AbilityCaster._try_cast` **after the cooldown check and before the mana check**. A false result rejects the
  cast with `cast_failed` (reason `no_target` or `blocked`) and spends nothing. It does **not** run for
  chained follow-up casts (Double Dash), which already skip those checks.
- `AbilityCaster.cast_failed`'s reason list (a comment in `ability_caster.gd`) gains `no_target` and `blocked`.
  `Hud._on_cast_failed` treats them like a failed cast: flash that slot's icon and play the blip, but do not
  flash the mana bar.
- `AbilityData` gains `target_range` (the auto-cast targeting range; 0 means use the caster default of 90px,
  which is the Knight's value). Arcane Bolt uses 150.
- `AbilityData` gains `cone_degrees` (the **half-angle**, in degrees, used by aimed target selection; Chain
  Lightning uses 40, meaning 40 degrees either side of the aim).

### 6.3 Conditional stat modifiers

- `Stats` gains `set_conditional(source, key, factor)` and `clear_conditional(source)`. Conditional factors
  multiply into `value()` like normal multipliers but are keyed by a source name so a trait can switch its
  own bonus on and off without disturbing upgrade modifiers. `AbilityCaster.damage_of` already reads the global
  `damage` key through `Stats.value`, so the bonus applies automatically.

### 6.4 Damage zones: fields and bursts

`DamageZones` (today: lines and one-shot bursts, drawn only for lines) is extended:

- `add_field(pos, radius, damage, interval, ticks)`: a circle that damages every enemy inside it, once per
  tick, every `interval` seconds, for `ticks` ticks. The **first tick is immediate** (cd = 0). A field never
  plays a ring effect on its ticks. It is drawn as a faint ground circle that fades as ticks run out (the
  draw code gains a circle case). Separate fields from separate casts are independent.
- `add_burst(pos, radius, damage, delay, knockback, extras)` gains an `extras` dictionary for the Meteor:
  `sfx` (an `AudioStream` played at impact), `shake` (strength and time passed to `CameraFollow.shake`),
  `visual` (`&"meteor"`: plays `Effects.meteor_fall(pos)` at impact), and `stun` (seconds). Existing callers
  (Shockwave) pass nothing and behave as before.
- Zones belong to the Game scene, tick in `_physics_process` (so they pause with the tree) and are freed with
  the scene.

### 6.5 Effects

- `Effects.lightning(points)`: a jagged polyline through the points for 0.15s with a bright core and glow.
- `Effects.meteor_fall(pos)`: a short streak and flash at impact (about 0.25s).
- `Effects.telegraph(pos, radius, duration, fill := false)`: with `fill` true, a circle grows from the center
  to the full radius over `duration` and brightens, instead of only fading in.

### 6.6 Character data and mana

- `CharacterData` gains: `max_mana` (default **100**), `mana_regen` (default **8**), `trait_script`. The
  defaults equal the Knight's values, so the Knight's `.tres` needs no change (and is checked as a diff, 11).
- `Mana` gains `configure(max, regen)`, which the Player calls in `_apply_character`. It sets the base values,
  resets `_known_max` and `current` to the new maximum, and emits `changed`. (`Mana._ready` runs before
  `Player._ready`, so the values must be applied by the Player. `Hud.bind` runs after the player is added, so
  the HUD sees the final values.)
- `CharacterRegistry` lists `wizard.tres` after `knight.tres`.

### 6.7 Enemy grid hygiene

- `EnemyGrid.query` and `EnemyGrid.nearest` skip enemies whose `active` flag is false. (Today `_cells` is rebuilt
  once per physics frame and `deactivate()` only removes from `_enemies`, so an enemy killed earlier in the same
  frame can still be returned.) This also protects the Knight's attacks.

### 6.8 Character Select text

- Ability rows print `AbilityData.damage` as "Damage". For Phase Shift this is the Ghost Touch tick damage and
  is not shown unless the ability deals damage by itself; the row for an ability with no direct damage omits
  the Damage field. Cooldown and mana still come from data.

## 7. Sounds

New sounds, generated by `tools/gen_sfx.py` like the others: `bolt_fire`, `bolt_hit`, `phase`, `lightning`,
`meteor_fall`, `meteor_impact`, `focus_on` (soft chime when Arcane Focus switches on). Added to the `Audio`
autoload list. Each ability's `sfx` is set in its `AbilityData` (the meteor impact sound goes through the burst
`extras`).

## 8. Data summary

New `AbilityData` fields: `target_range`, `cone_degrees`. Existing fields used: `cooldown`, `mana_cost`,
`damage`, `range`, `radius`, `windup`, `duration`, `immunity_after`, `knockback`, `sfx`, `effect`.

| Ability | id | cooldown | mana | damage | range | radius | other |
|---|---|---|---|---|---|---|---|
| Arcane Bolt | `bolt` | 0.65 | 0 | **10** | 200 | 4 | target_range 150 |
| Phase Shift | `phase` | 1.8 | 12 | 8 (orbs) | - | 28 (orbit) | duration 0.8, speed_multiplier 1.5, immunity_after 0.2 |
| Chain Lightning | `lightning` | **1.2** | 15 | **22** | 150 | 60 | cone_degrees 40 |
| Meteor Strike | `meteor` | 5.0 | 29 | 90 | 120 | 64 | windup **0.7**, knockback 140 |

Constants kept in the behavior scripts (as the Knight's are): bolt speed 260, lightning jumps 4 and falloff
0.85, meteor shake 3px for 0.2s, Twin Meteor delay 0.4s and scatter 50px, Arcane Focus delay 1.0s and bonus
1.25, Scorched Earth tick 0.5s with ratio 0.04, Ghost Touch radius 16px, tick 0.25s and ratio 0.75, orb belt
5 orbs for 2.0s at 2 turns per second with a 0.5s per-enemy hit cooldown.

## 9. Interaction notes

- **Dashers:** Phase Shift's immunity and speed avoid a locked lane; Chain Lightning with Static Shock or a
  Meteor can interrupt a charge (stun cancels a telegraph; knockback does not).
- **Ranged enemies:** Ranged enemies hold at 130px and resume walking at 160px, and their shots (110 px/s,
  3s lifetime) travel far, so the Wizard's 150px reach does **not** out-range them. The answers are Phase Shift,
  closing in to kill them, or breaking line of sight with distance.
- **Phase Shift and Arcane Focus:** moving while phased counts as movement; casting Phase Shift alone does not.
- **Meteor and other abilities:** the Wizard can cast anything else while a meteor falls; the meteor never
  blocks the caster.
- **Level-up menu, pause, end screen, restart:** unchanged. Restart keeps the Wizard.
- **HUD:** unchanged apart from the `no_target` and `blocked` flashes and the FOCUS mark. The Q icon is
  unchanged for Phase Shift.

## 10. Build order

1. **M16 Character plumbing:** `CharacterData` fields and `trait_script`, `Mana.configure`, `EnemyGrid` active
   filter, `wizard.tres` with placeholder abilities that reuse the Slash behavior, Wizard on Character
   Select, `AbilityData.target_range` and `cone_degrees`. *The Wizard is selectable and playable as a
   re-skinned Knight with Wizard stats.*
2. **M17 Player projectiles and Arcane Bolt:** `PlayerProjectiles`, the bolt behavior, sounds. *Review stop
   (does the Wizard's basic attack feel right?).*
3. **M18 Phase Shift (was Blink):** the timed ghost state on the Player, `can_cast`, `DamageZones.add_field`
   (needed by Scorched Earth).
4. **M19 Chain Lightning:** the `no_target` path and HUD flash, targeting cone, jump logic, lightning visual.
5. **M20 Meteor Strike:** burst `extras`, fire-and-forget scheduling, filling marker, falling meteor visual,
   impact. *Review stop (the full kit).*
6. **M21 Upgrades and trait:** the 12 upgrades, the Wizard pool, Arcane Focus with its feedback, the new
   sounds.
7. **M22 Polish and check:** tuning, balance against the Knight, performance with projectiles, update
   `docs/` and the README. *Final review.*

## 11. Definition of Done for v0.3

Each item has a check:

- **Selectable:** the Wizard appears on Character Select with four abilities whose cooldown, mana and damage
  match the table in section 8 exactly, and a full run is playable.
- **Arcane Bolt:** auto-fires at an enemy up to 150px away, none beyond; a bolt aimed at an enemy on top of the
  Wizard still travels; with Piercing Bolt level 1 one bolt damages two different enemies once each.
- **Phase Shift:** while phased the Wizard takes no damage from contact hits, Dasher lunges or projectiles, walks 50%
  faster, and can cast other abilities; the state ends after 0.8s and on death; with Ghost Touch an enemy standing
  in the Wizard takes damage every 0.25s; after the phase a ring of 5 orbs orbits for 2.0s, hits an enemy
  at most once per 0.5s for 8 damage, and stops on death.
- **Chain Lightning:** hits up to 5 distinct enemies; with no enemy in the cone, no mana is spent and the icon
  flashes; it never targets an enemy killed earlier in the same frame.
- **Meteor Strike:** the blast lands on the marker's center within 1 physics frame of the marker finishing
  filling; the Wizard can Phase and shoot during the 0.7s; marker and blast use the radius and damage from the
  cast time.
- **Upgrades:** all 12 work and show correct text on the level-up card; Twin Meteor stops at level 2.
- **Arcane Focus:** switches on after 1.0s of no movement, off on movement, with the ring, mark and
  chime.
- **Knight unchanged:** the Knight's `.tres` files have no value changes (checked as a diff) and
  `AUTO_TARGET_RANGE` still gives 90px when `target_range` is 0; the existing scripted checks from v0.2
  (Double Dash chain, post-dash immunity, Dasher lane) still pass.
- **Performance:** at least 60 FPS measured on the development Mac with the spec-mix worst case from the v0.2
  check (end-of-run spawn rate, 300 alive cap) plus a Wizard firing Arcane Bolt and Chain Lightning, using the
  F3 overlay.
- **Tuning** values live in data or constants.

## 12. Assumptions to Revisit Later

- All Wizard numbers are first guesses. At 90 HP the Wizard is only slightly more fragile than the Knight
  (100), so he is a spellcaster rather than a true glass cannon; his 85 px/s and ranged role are what keep
  him distinct. Ranged enemies' shots out-range him.
- Arcane Focus may be too weak (or encourage standing still too much); it is the easiest piece to cut.
- Gold is a placeholder color and clashes with the pale-yellow damage numbers.
- Meteor Strike being fire-and-forget is a deliberate difference from Slam and may need a longer cooldown if
  it is too easy to spam. At 29 mana per 5s it uses about 6 of the 10 mana/s regen.
- Chain Lightning's cone targeting may feel wrong with the mouse close to the Wizard; a fallback to the
  nearest enemy in any direction is a possible change.
- Twin Bolt at full damage per bolt combined with Piercing Bolt multiplies damage quickly (up to 4 bolts, each
  piercing). A reduced damage per extra bolt is a possible change.
- Projectiles ignore props; this is simple but makes props irrelevant against Wizard shots.
- Phase Shift's value is immunity and speed; with 0.8s duration and a 1.8s cooldown it is up for 44% of the time, which may be too much (or too little) uptime for an untouchable state.

## 13. Changes from revision 1 (after review)

Decided by the product owner: Chain Lightning damage 18 to 22; Arcane Bolt damage 8 to 10; Blink knockback
130 to 220 px/s; Meteor warning 1.0s to 0.7s.

Fixed in the spec from the review: Meteor impact hooks (sound, shake, visual) through burst `extras`; field
definition and drawing; zero-direction bolts, lifetime and a per-bolt hit set; the enemy grid returning
recently killed enemies; `can_cast` placement and the `blocked` and `no_target` reasons; Wide Arc's two keys and
the half-angle meaning; field damage scaling and Rift not repeating on follow-up blinks; blocked Blink rule;
Meteor clamping, marker timing and capture of values at cast time; Mana and trait plumbing; Arcane Focus
timing; the Ranged enemy range claim; and checkable Definition of Done items.

## 14. Implementation notes (M18 to M20)

- A failed `can_cast` also applies to **follow-up** casts (Double Blink): the press is rejected with the same
  reason and the chain stays open. Section 6.2 said follow-ups skip the check; blocked follow-ups needed it.
- `DamageZones.add_field` takes a `color` and a `delay` (`add_field(pos, radius, damage, interval, ticks,
  color, delay)`), used by Rift (violet, no delay) and Scorched Earth (orange, delayed to the impact).
- `AbilityCaster.casting_follow_up` is true while a chained follow-up starts; Blink reads it so Rift only
  comes from the first Blink of a chain.
- Meteor Strike's falling whistle (`meteor_fall`) plays at cast and the impact boom (`meteor_impact`) plays
  from the burst.

## 15. Revision 3: Blink replaced by Phase Shift

Decided by the product owner after playing M18 to M20: Blink as a teleport was too confusing, so Q is now
**Phase Shift** (the "Phase Shift" option from the original move suggestions): a timed ghost state with
immunity and extra speed. Also: **Chain Lightning cooldown 1.8s to 1.2s**.

- Removed: Blink's teleport, wall-blocked rule, origin burst, Long Blink, Rift, Double Blink. Sections 3.2, 5, 8 and
  11 describe the replacement. The `blocked` cast-failure reason and the follow-up flag are still supported by the
  caster but unused by the Wizard.
- `DamageZones.add_field` is still built (Scorched Earth uses it).
- New: `AbilityData.speed_multiplier`, `Player.start_phase`/`end_phase`, `PhaseBehavior`, the `phase` sound.
- The Wizard's upgrade pool keeps 12 ability upgrades (3 each for Arcane Bolt, Phase Shift, Chain Lightning and
  Meteor Strike, with Twin Meteor at 2 levels) plus the 6 shared passives.

## 16. Revision 4: Orb belt and M21 as built

Decided by the product owner: Phase Shift also creates an **orb belt** (5 orbs, 2 seconds, damaging) once the
phase ends (section 3.2).

- Phase Shift has 4 upgrades (Long Phase, Swift Phase, Ghost Touch, Orbital Ring), so the Wizard has **13 ability
  upgrades** (Arcane Bolt 3, Phase Shift 4, Chain Lightning 3, Meteor Strike 3) and the 6 shared passives:
  19 in the pool. Twin Meteor has 2 levels; the rest have 3.
- Arcane Focus is built as designed (1.0s still, +25% damage through a conditional multiplier on `Stats`, a gold
  ring at the feet, a "FOCUS" mark under the mana bar, and a chime).
- The shared passive formerly called "Focus" (+2 mana regen) is renamed **Mana Flow** so it is not confused with
  Arcane Focus.
- Code: `OrbBelt` (a child node of the Player, created on first use), `Player.start_phase` takes the belt
  parameters, `Stats.set_conditional` and `clear_conditional`, `ArcaneFocus` (trait script instanced by the Player).
