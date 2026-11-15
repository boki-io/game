# Spec v0.3: The Wizard

Builds on `spec-0.1.md` and `spec-0.2.md` (all built). Adds a second playable character, the **Wizard**,
a ranged glass cannon that plays very differently from the melee Knight. Placeholder art and generated
sounds remain acceptable.

## 1. Scope

**In v0.3:**
- The Wizard character, selectable on the Character Select screen next to the Knight.
- Four Wizard abilities: Arcane Bolt (auto), Blink (Q), Chain Lightning (E), Meteor Strike (R).
- A Wizard upgrade pool (12 ability upgrades and the 6 shared passives).
- The Wizard trait **Arcane Focus**.
- The shared systems this needs: player projectiles, conditional stat modifiers, repeating damage fields,
  lightning visuals, and a "no target" cast check.

**Out of v0.3:** new enemies, new maps, real art for either character, meta-progression, enemy status
effects (burn and slow were considered and cut; the Wizard uses only damage, stun and knockback).

**The question this version answers:** does a ranged, mobility-and-burst character feel different enough
from the Knight to justify more characters, and does the ability framework hold up for a second kit?

## 2. The Wizard at a glance

| | Knight (v0.1) | Wizard |
|---|---|---|
| Role | Close-range brawler | Ranged glass cannon |
| HP | 100 | **70** |
| Move speed | 90 px/s | **85 px/s** |
| Max mana / regen | 100 / 8 per s | **140 / 10 per s** |
| Auto | Slash (90px targeting, melee arc) | **Arcane Bolt** (150px targeting, projectile) |
| Q | Dash & Slash | **Blink** |
| E | Spin | **Chain Lightning** |
| R | Slam | **Meteor Strike** |
| Body color (placeholder) | blue | **gold** (not blue, red, green or purple: those belong to the Knight and enemies) |

- Character id `wizard`, display name "Wizard", description "Fragile spellcaster. Strikes from range and
  teleports out of trouble." (placeholder text).
- On the Character Select screen the Knight stays first and the Wizard is second. The existing Prev and Next
  buttons appear automatically when there are two characters.
- A full Q+E+R rotation costs 12 + 15 + 45 = 72 mana against a 140 pool.

## 3. Wizard abilities

All numbers are first guesses and live in `data/abilities/*.tres` (see 8 for the new `AbilityData` fields).
Damage is before the Wizard's modifiers (upgrades and Arcane Focus).

### 3.1 Arcane Bolt (auto, no mana)

| Stat | Value |
|---|---|
| Cooldown | 0.65s |
| Mana | 0 |
| Damage | 8 |
| Targeting range | 150px (`target_range`) |
| Projectile | speed 260 px/s, flies up to 200px (`range`), radius 4 |
| Pierce | 0 (stops at the first enemy it hits) |

- Behavior: the auto-cast picks the closest enemy within 150px (as the Knight's Slash does, but with the
  longer range). It fires one bolt from the Wizard toward that enemy. Does nothing if no enemy is in range.
- The bolt is a player projectile (section 6.1). It damages the first enemy it touches and disappears.
- The sprite faces the shot direction for 0.25s, like other casts.
- It holds off while a Q, E or R cast is running, like the Knight's Slash.

### 3.2 Blink (Q)

| Stat | Value |
|---|---|
| Cooldown | 1.8s |
| Mana | 12 |
| Distance | 80px (`range`) along the aim vector |
| Immunity | 0.25s (`immunity_after`) starting at the teleport |
| Burst at the origin | radius 36px (`radius`), 15 damage, knockback 130 px/s |

- Behavior: instant. The Wizard teleports up to 80px along the aim vector. The move stops at walls and
  props (`move_and_collide`), so it never leaves the arena or lands inside a prop. Enemies do not block it.
- An arcane burst goes off at the **starting** position: it damages and shoves away enemies within 36px.
  This is the "get out of the crowd" tool.
- The Wizard is unhittable for 0.25s from the moment of the teleport (the same `Hurtbox.grant_grace` as the
  Knight's post-dash immunity, including the sprite flicker).
- A short puff effect plays at both ends.
- Blink is not a dash: the player is not moved over time, and `override_active` is not used.

### 3.3 Chain Lightning (E)

| Stat | Value |
|---|---|
| Cooldown | 1.8s |
| Mana | 15 |
| First target range | 150px, within 40 degrees either side of the aim vector |
| Jumps | 4 (so up to 5 targets) |
| Jump radius | 60px from the previous target |
| Damage | 18 to the first target, then x0.85 per jump (18, 15, 13, 11, 9; rounded for display) |

- Behavior: instant. The first target is the nearest enemy to the Wizard inside the aim cone. From each
  target the bolt jumps to the nearest enemy not yet hit within the jump radius. It stops when there is no
  next target or the jump count is used.
- **No target:** if no enemy is inside the cone, the cast does not happen. No mana is spent, no cooldown
  starts, and the HUD flashes the icon and plays the "no mana" blip (`cast_failed` with reason `no_target`).
- Visual: a jagged line is drawn from the Wizard to the first target and between each pair of targets,
  lasting about 0.15s. Each target flashes (the normal hit flash).
- It does not stun by default (see the Static Shock upgrade).

### 3.4 Meteor Strike (R)

| Stat | Value |
|---|---|
| Cooldown | 5.0s |
| Mana | 45 |
| Impact point | 120px along the aim vector (`range`), fixed when cast |
| Warning | 1.0s ground marker (`windup`) |
| Blast | radius 64px, 90 damage, knockback 140 px/s |

- Behavior: **fire and forget.** Casting is instant: it places a red ground marker of radius 64px at the
  impact point and schedules the blast 1.0s later through the damage-zone system (`DamageZones.add_burst`).
  The caster is **not busy** while the meteor falls, so the Wizard can keep shooting, Blink, or Chain
  Lightning during the warning. (This differs from the Knight's Slam, which locks the caster.)
- The marker is the same style as the Slam telegraph, but it fills and brightens over the 1.0s.
- At impact: a falling meteor visual lands, a shockwave ring plays, the screen shakes (3px, 0.2s), and every
  enemy in the radius takes damage and is knocked back.
- The blast hits enemies, never the player. The marker only warns the player not to walk away from enemies
  there. It is not dangerous to the Wizard.

## 4. Trait: Arcane Focus

- After standing still for **1.0s**, the Wizard deals **+25% damage** (all abilities) until they move again.
- "Standing still" means no movement input and no Blink in the last 1.0s. Casting does not break it.
- Effect: a conditional damage multiplier on the Wizard's `Stats` (section 6.3) that turns on at 1.0s of
  stillness and off the moment the move vector is non-zero.
- Feedback: a faint gold ring pulses around the Wizard's feet while it is active, and a small gold "FOCUS"
  mark shows by the HP bar (so the player can read the state).
- Implemented as a character trait script (`CharacterData.trait_script`), added to the Player at spawn.
- This trait is the only place that rewards stopping, and it is meant to pull against the Wizard's kiting.

## 5. Wizard upgrade pool

Same rules as the Knight: 3 levels per upgrade unless noted, choices exclude maxed upgrades, each level
applies the modifier again through `Stats`. 12 ability upgrades and the 6 shared passives (Vitality, Focus
regen, Deep Well, Fleet Foot, Magnet, Power), 18 in total.

**Arcane Bolt**
- **Twin Bolt:** +1 bolt per level, fired in a spread (2 bolts: 0 and 10 degrees; 3: -10, 0, 10; 4: -15, -5,
  5, 15). Every bolt does full damage. (`bolt.extra` add 1)
- **Piercing Bolt:** the bolt passes through +1 enemy per level. (`bolt.pierce` add 1)
- **Rapid Fire:** -15% cooldown per level. (`bolt.cooldown` x0.85)

**Blink**
- **Long Blink:** +30% distance per level. (`blink.range` x1.3)
- **Rift:** the burst at the origin leaves a damaging field for 2s: 4 damage per level every 0.5s, same
  radius as the burst. (`blink.rift` add 1)
- **Double Blink:** max level 2. After a Blink you may Blink again within 1.0s for free (no mana, no
  cooldown check); level 2 allows two follow-ups. The cooldown starts when the chain ends. This reuses the
  caster's chain mechanism built for Double Dash. (`blink.chain` add 1)

**Chain Lightning**
- **Extra Jumps:** +2 jumps per level. (`lightning.jumps` add 2)
- **Static Shock:** every target hit is stunned for 0.5s per level. (`lightning.stun` add 1)
- **Wide Arc:** +25% jump radius per level and +10 degrees on the first-target cone.
  (`lightning.radius` x1.25)

**Meteor Strike**
- **Bigger Blast:** +25% radius per level. (`meteor.radius` x1.25)
- **Twin Meteor:** max level 2. +1 extra meteor per level, landing 0.4s after the previous one at a random
  point within 50px of the first impact. Each has its own marker. (`meteor.extra` add 1)
- **Scorched Earth:** the impact leaves burning ground for 3s: 3 damage per level every 0.5s over the blast
  radius. (`meteor.scorch` add 1)

Damage (`damage`) and cooldown modifiers read by the Knight's keys keep working for the Wizard's ability ids
(`bolt`, `blink`, `lightning`, `meteor`).

## 6. New and changed systems

### 6.1 Player projectiles

- A new `PlayerProjectiles` node (a pool, group `player_projectiles`, in the World like the enemy
  `Projectiles` node) and an `PlayerProjectile` scene. Cap: 40 live.
- Movement is plain code. Hits use the **enemy spatial grid** (`EnemyGrid.query` at the bolt's position with a
  radius of the bolt radius + 6), not physics bodies, matching how the Knight's attacks hit.
- Each projectile has: direction, speed, damage, remaining range, remaining pierce. On touching an enemy
  it calls `Enemy.take_damage`, reduces pierce, and is retired when pierce is spent. It also retires when
  range is used up or when it leaves the arena.
- It **passes over props** (they are low scenery) and is not blocked by walls other than the arena edge.
- Visual: a bright cyan-white orb with a short trail. Sounds: fire and hit.
- A projectile never hurts the player and is not affected by the Knight's systems.

### 6.2 Cast checks and targeting

- `AbilityBehavior` gains `can_cast(caster, aim, data) -> bool` (default true). The caster calls it before
  spending mana or starting the cooldown. If it returns false the cast is rejected and `cast_failed` is
  emitted with reason `no_target`. The HUD handles this reason by flashing the icon (no mana flash on the
  bar). Used by Chain Lightning.
- `AbilityData` gains `target_range` (the auto-cast targeting range; 0 means use the caster default of 90px,
  which is the Knight's value). Arcane Bolt uses 150.
- `AbilityData` gains `cone_degrees` (half-angle used by aimed target selection; Chain Lightning uses 40).

### 6.3 Conditional stat modifiers

- `Stats` gains `set_conditional(source, key, factor)` and `clear_conditional(source)`. Conditional factors
  multiply into `value()` like normal multipliers but are keyed by a source name so a trait can switch its
  own bonus on and off without disturbing upgrade modifiers.

### 6.4 Damage fields

- `DamageZones` gains `add_field(pos, radius, damage, interval, ticks)`: a circle that damages everything
  inside it every `interval` seconds, `ticks` times, with a faint ground visual that fades. Used by Rift and
  Scorched Earth. (Today it has only lines and single bursts.)
- Fields never stack on the same enemy within one tick, but two separate fields can each hit.

### 6.5 Lightning visual

- `Effects` gains `lightning(points)`: draws a jagged polyline through the points for 0.15s with a bright
  core and soft glow.

### 6.6 Character data

- `CharacterData` gains: `max_mana`, `mana_regen`, `trait_script`.
- `Mana` gains `configure(max, regen)`, called by the Player when it applies the character, which also fills
  mana. (The Mana node's own `_ready` runs before the Player's, so the character values must be applied by
  the Player rather than by node exports.)
- The Knight's `.tres` is updated with `max_mana = 100` and `mana_regen = 8` so nothing changes for it.
- `CharacterRegistry` lists `wizard.tres` after `knight.tres`.

## 7. Sounds

New sounds, generated by `tools/gen_sfx.py` like the others: `bolt_fire`, `bolt_hit`, `blink`, `lightning`,
`meteor_fall`, `meteor_impact`, `focus_on` (soft chime when Arcane Focus switches on). Added to the `Audio`
autoload list. Each ability's `sfx` is set in its `AbilityData`; the meteor impact and lightning play from
their behaviors.

## 8. Data summary

New `AbilityData` fields: `target_range`, `cone_degrees`. Existing fields used: `cooldown`, `mana_cost`,
`damage`, `range`, `radius`, `windup`, `duration`, `immunity_after`, `knockback`, `sfx`, `effect`.

| Ability | id | cooldown | mana | damage | range | radius | other |
|---|---|---|---|---|---|---|---|
| Arcane Bolt | `bolt` | 0.65 | 0 | 8 | 200 | 4 | target_range 150 |
| Blink | `blink` | 1.8 | 12 | 15 | 80 | 36 | immunity_after 0.25, knockback 130 |
| Chain Lightning | `lightning` | 1.8 | 15 | 18 | 150 | 60 | cone_degrees 40 |
| Meteor Strike | `meteor` | 5.0 | 45 | 90 | 120 | 64 | windup 1.0, knockback 140 |

Constants kept in the behavior scripts (as the Knight's are): bolt speed 260, lightning jumps 4 and falloff
0.85, meteor shake 3px, Arcane Focus delay 1.0s and bonus 1.25, Rift and Scorched Earth tick 0.5s.

## 9. Interaction notes

- **Dashers:** Blink's immunity and its teleport avoid a locked lane; Chain Lightning with Static Shock or a
  Meteor knockback can interrupt a charge (stun cancels a telegraph; knockback does not).
- **Ranged enemies:** the Wizard out-ranges them (150px vs their 130px hold distance) but their shots can
  still hit during Arcane Bolt's long cooldown, so Blink is the main answer.
- **Double Blink and Arcane Focus:** Blink counts as movement for Arcane Focus.
- **Level-up menu, pause, end screen, restart:** unchanged. Restart keeps the Wizard.
- **HUD:** unchanged apart from the `no_target` flash and the FOCUS mark. The Q icon shows the same chain
  ring as Double Dash when Double Blink has a follow-up ready.

## 10. Build order

1. **M16 Character plumbing:** `CharacterData` mana fields and `trait_script`, `Mana.configure`, the Knight's
   values moved into data, `wizard.tres` with placeholder-numbers abilities that reuse the Slash behavior,
   Wizard on Character Select, `AbilityData.target_range` and `cone_degrees`. *The Wizard is selectable
   and playable as a re-skinned Knight with Wizard stats.*
2. **M17 Player projectiles and Arcane Bolt:** `PlayerProjectiles`, the bolt behavior, sounds. *Review stop
   (does the Wizard's basic attack feel right?).*
3. **M18 Blink:** behavior, wall-safe teleport, burst and immunity, `DamageZones.add_field` (needed by Rift),
   chain reuse test.
4. **M19 Chain Lightning:** `can_cast`, the `no_target` path and HUD flash, targeting cone, the jump logic,
   the lightning visual.
5. **M20 Meteor Strike:** fire-and-forget scheduling, marker that fills, falling meteor visual, impact.
   *Review stop (the full kit).*
6. **M21 Upgrades and trait:** the 12 upgrades, the Wizard pool, Arcane Focus with its feedback, the new
   sounds.
7. **M22 Polish and check:** tuning, balance against the Knight, performance with projectiles, update
   `docs/` and the README. *Final review.*

## 11. Definition of Done for v0.3

- The Wizard appears on Character Select with his four abilities and correct data-driven numbers, and a
  full run is playable with him.
- Arcane Bolt auto-fires at enemies up to 150px away and pierces with the upgrade.
- Blink moves 80px, never ends inside a wall or prop, grants 0.25s of immunity, and shoves enemies at the
  starting point.
- Chain Lightning jumps through up to 5 enemies and costs nothing when there is no target.
- Meteor Strike can be cast while the Wizard is moving, shooting or blinking, and lands exactly where and
  when the marker shows.
- All 12 Wizard upgrades work and show correctly on the level-up cards.
- Arcane Focus switches on after 1.0s of standing still and off on movement, with visible feedback.
- The Knight plays exactly as before.
- About 60 FPS at 300 enemies with Wizard projectiles in flight.
- Tuning values live in data or constants.

## 12. Assumptions to Revisit Later

- All Wizard numbers are first guesses; 70 HP with 85 px/s may be too fragile against Dashers and Ranged
  enemies.
- Arcane Focus may be too weak (or encourage standing still too much); it is the easiest piece to cut.
- Gold is a placeholder color and clashes with the pale-yellow damage numbers.
- Meteor Strike being fire-and-forget is a deliberate difference from Slam and may need a cooldown increase
  if it is too easy to spam.
- Chain Lightning's cone-based targeting may feel wrong with the mouse close to the Wizard; a fallback to the
  nearest enemy in any direction is a possible change.
- Piercing and Twin Bolt together can multiply damage quickly.
- Projectiles ignore props; this is simple but makes props irrelevant against Wizard shots.
