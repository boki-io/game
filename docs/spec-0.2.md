# Spec v0.2: Menus, Character Select, New Enemies, Double Dash

Builds on `spec-0.1.md` (all of v0.1 is built and works). Requirements and the decisions behind this
spec are in `requirements-0.2.md`. Placeholder art and generated sounds remain acceptable.

## 1. Scope

**In v0.2:**
- A main menu and a character select screen in front of the existing game.
- Menu buttons to return to the main menu from the pause menu and the end screen.
- Two new enemies: the **Dasher** and the **Ranged** enemy, with a weighted, phased-in spawn mix.
- One new Q upgrade: **Double Dash**.

**Out of v0.2:** settings or rebinding menus, extra characters (the select screen only has to support
more later), bosses, meta-progression, networking, real art.

**The questions this version answers:**
- Do enemies that demand dodging (a telegraphed dash, projectiles) make the Q/E/R combat more interesting?
- Does the mix of three enemy types stay readable at 480x270?

## 2. Flow

```
Main Menu --Start New Game--> Character Select --Select--> Game (existing Main scene)
    ^                               |  Back                     |
    +-------------------------------+                           |
    +------------- Main Menu button (pause menu, end screen) ---+
```

- The game launches into the Main Menu (`run/main_scene` changes).
- A new autoload, `GameSession`, holds the selected `CharacterData`. The Game scene reads it on start.
- **Restart** on the end screen reloads the game with the same character.
- Scene changes use `get_tree().change_scene_to_file`. Always unpause the tree before changing scene.

## 3. Main Menu

- Title "Hero Horde" (working title), then buttons: **Start New Game** and **Exit**.
  (Exit is an addition for desktop; it is the only button beyond the request.)
- Navigable by mouse, keyboard (arrows, Enter) and gamepad (D-pad, South), like the other menus.
- Start New Game is focused by default. Menu click sound on press.

## 4. Character Select

**Layout (480x270):** the character on the left, details on the right, buttons at the bottom.

- **Character display:** the character's sprite drawn large (3x) with a shadow, plus name and a one-line
  description.
- **Abilities:** four rows or cards in cast order: Slash (Auto), Q, E, R. Each shows the key (or "Auto"),
  icon placeholder, name, a one-line description, and cooldown, mana cost and damage taken from the
  ability's `AbilityData`. Numbers come from data, never typed into the UI.
- **Buttons:** **Select** and **Back**. With one character, Select is focused. Left and Right switch
  characters when more than one exists (the list is built from a character registry).
- Select stores the character in `GameSession` and starts the game.

**Sword text:**
- Name: Knight. Description: "Close-range fighter. Fast combos, heavy slams." (Placeholder; change in data.)
- Ability descriptions:
  - Slash: "Automatically cuts the nearest enemy."
  - Dash & Slash: "Dash through enemies. You can't be hurt while dashing."
  - Spin: "Hit everything around you. Move slowly while spinning."
  - Slam: "Mark the ground, then smash it. Knocks enemies back."

**Data:** a new `CharacterData` resource (`data/characters/knight.tres`):

```gdscript
class_name CharacterData
extends Resource

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var body_color: Color
@export var max_hp: float = 100.0
@export var move_speed: float = 90.0
@export var ability_auto: AbilityData
@export var ability_q: AbilityData
@export var ability_e: AbilityData
@export var ability_r: AbilityData
@export var upgrade_pool: Array[UpgradeData]
```

`AbilityData` gains an `@export_multiline var description: String`.

The Player is configured from `CharacterData` on spawn (abilities, base stats, color, upgrade pool),
replacing the Sword-specific values now wired in `player.tscn` and `PlayerUpgrades`.

## 5. Pause Menu and End Screen

- **Pause menu:** Continue, **Main Menu**, Exit.
- **End screen:** Restart, **Main Menu**.
- Main Menu from either unpauses the tree and returns to the Main Menu. No confirmation dialog in v0.2.

## 6. Enemy Framework

The Grunt's chase-and-touch logic is no longer the only behavior. Enemies become data plus a behavior.

- `EnemyData` gains: `body_color`, `body_size`, `spawn_weight`, `unlock_time`, `full_weight_time`, and a
  `brain: Script`.
- **Brains** are small scripts like ability behaviors: `GruntBrain`, `DasherBrain`, `RangedBrain`. Each
  receives the enemy and a delta and moves or acts. The Enemy node keeps everything common: health,
  knockback, stun, flash, death, separation, contact hits, teleport-back, pooling.
- Typed data subclasses hold the extra numbers: `DasherData extends EnemyData`,
  `RangedData extends EnemyData`.
- **Pooling is per enemy type.** The SpawnDirector keeps one pool per `EnemyData`.
- HP scaling (+15% per minute), the 300 alive cap (shared by all types) and the spawn ring all apply to
  every type.
- **Stun** cancels a Dasher's telegraph or dash and a Ranged enemy's shot wind-up. **Knockback** does not.
  A cancelled Dasher goes straight to its recovery state.

## 7. Spawn Mix and Phasing

Total spawn rate is unchanged (1/s rising to 8/s). The type is chosen per spawn by weight.

| Type | Target share | Unlocks at | Full weight at |
|---|---|---|---|
| Grunt | 70% | 0:00 | 0:00 |
| Ranged | 15% | 0:45 | 2:30 |
| Dasher | 15% | 1:30 | 2:30 |

- Weights are 70, 15, 15. A type's weight is `spawn_weight * clamp((t - unlock) / (full - unlock), 0, 1)`.
  Grunts keep full weight throughout, so their share is above 70% while the others ramp in, and settles
  at 70/15/15 from 2:30.
- The debug overlay (F3) shows alive counts per type.

## 8. Enemy: Dasher

A big, slow bruiser whose danger is a single readable lunge.

| Stat | Value |
|---|---|
| HP | 60 (before scaling) |
| Move speed | 30 px/s |
| Size | 20x36 placeholder, hitbox radius 7 |
| Contact damage | 5 every 0.5s (like a Grunt) |
| XP drop | 3 |

**Behavior (state machine):**
1. **Approach:** walks toward the nearest player, with separation, like a Grunt.
2. **Telegraph (1.0s):** when within 110px of its target, it stops. A ground lane projects from the
   Dasher toward the player: 26px wide, 140px long (the dash distance). The width matches the real hit
   width (2 x (Dasher hitbox 7 + player hurtbox 6)), so what the player sees is what can hit them.
   - For the first 0.6s the lane follows the player's position (aiming).
   - For the last 0.4s the lane is **locked** and its color changes from yellow to bright red so the
     player knows to move.
   - The sprite shakes and a "!" marker shows above it.
3. **Dash:** it moves along the locked lane for 140px at 300 px/s (about 0.47s). The first hit on a player
   deals **15 damage**, once per dash. The dash does not damage other enemies and does not pass through
   walls (it stops at them).
4. **Recovery (0.8s):** stands still, dimmed. This is the punish window.
5. Returns to Approach. If it has no target, it idles.

- The player's Dash & Slash i-frames avoid the dash damage. Moving out of the lane also avoids it.
- The 1.5s in the original request is shortened to 1.0s because the player crosses the lane's width in
  about 0.15s; the readable part is the 0.4s lock. Both are tunable (see 13).

**Telegraph visuals (must be unmistakable):** a filled lane with an outline and a pulsing arrow tip, drawn
above the ground and below the characters; yellow while aiming, red when locked; a charge sound that rises
during the telegraph.

## 9. Enemy: Ranged

A mid-range shooter that forces the player to move toward it or sidestep.

| Stat | Value |
|---|---|
| HP | 25 (before scaling) |
| Move speed | 40 px/s |
| Size | 12x16 placeholder, in a different color from the Grunt |
| Contact damage | 0 (it shoots, it does not melee) |
| XP drop | 2 |

**Behavior:**
1. **Approach:** walks toward the nearest player until within 130px.
2. **Hold and shoot:** stops. Every 2.0s it starts a 0.4s wind-up (the sprite flashes), then fires one
   projectile toward where the player is at the end of the wind-up.
3. If the player moves beyond 160px it resumes approaching (hysteresis so it doesn't flicker).
4. If the player gets closer than 130px, it just keeps shooting. It does not retreat.

**Projectile:**
- 8 damage, 110 px/s, radius 3, travels in a straight line, 3s lifetime.
- Disappears on hitting the player, a wall or a prop.
- Passes over other enemies.
- **Dodge only.** No player ability destroys projectiles.
- The player's Dash & Slash i-frames avoid it.
- Pooled. Visible as a bright orb with a small trail. Fire and hit sounds.
- Layers: projectiles detect the Player hurtbox (layer 2) and World (layer 1).

## 10. Upgrade: Double Dash (Q)

Added to the Sword upgrade pool as an Ability upgrade on Dash & Slash.

- **Name:** Double Dash. **Max level:** 2 (a deliberate exception to "up to 3 levels").
- **Effect:** after a Dash & Slash, you may cast Q again within 1.0s as a **follow-up dash**:
  - Level 1: one follow-up (two dashes in total).
  - Level 2: two follow-ups (three dashes in total).
- **Follow-up rules:**
  - Costs no mana and has no cooldown check.
  - Each dash re-aims from the current aim vector, so you can change direction.
  - Each dash has its own i-frames, damage and end arc. Enemies hit by an earlier dash in the chain can be
    hit again.
  - The window for each follow-up is 1.0s from the end of the previous dash.
  - The normal 1.5s cooldown starts when the chain ends (last dash done, or the window runs out).
- Blade Trail, Long Dash and Efficient all still apply to every dash in the chain. Efficient lowers only
  the first dash's cost (follow-ups are free).
- The HUD Q icon shows a highlighted ring with the remaining follow-ups while the window is open.
- Stats keys: `dash.chain` (add 1 per level), read by the caster.
- Each dash in a chain also gets the post-dash immunity and pushback below.

### Post-dash immunity and pushback (Dash & Slash, all builds)
- After every dash the player stays unhittable for 0.3s (`immunity_after` in `AbilityData`), and the sprite
  flickers while it lasts. Enemy hits and projectiles pass through during it.
- When the dash ends, enemies within the end-arc radius (28px) are shoved away at 110 px/s (`knockback`,
  about 9px) so the player isn't left standing inside a crowd.

## 11. Technical Notes

- **Collision layers (unchanged):** 1 World, 2 Player, 3 Enemy, 4 Player attacks, 5 Pickups.
  Enemy projectiles are Area2Ds with layer 0 and mask 1 and 2. They are not on the Enemy layer.
- **Dasher dash vs player:** use the Dasher's existing Hitbox area; its contact-hit logic is enabled for
  the dash with the dash damage and a once-per-dash flag.
- **Telegraph drawing:** a child node on the Dasher draws the lane in a high enough z_index to sit above
  the ground and below characters and effects, and is hidden when the enemy is released to the pool.
- **Pools** must reset state completely on activate (state machine, timers, telegraph, stun).
- **Performance:** target is unchanged, 60 FPS at 300 enemies. Projectiles use a small pool with a cap of
  60 live projectiles.
- **Sounds (generated by `tools/gen_sfx.py`):** dasher charge, dasher dash, ranged wind-up, ranged shot,
  projectile hit. Existing sounds are reused otherwise.

## 12. Build Order

1. **M10 Flow and data:** `GameSession`, `CharacterData` (Knight), ability descriptions, Main Menu,
   Character Select, Main Menu buttons on the pause menu and end screen, Player configured from
   `CharacterData`. *Review stop.*
2. **M11 Enemy framework:** `EnemyData` fields, brains, per-type pools, weighted phased spawning, F3 shows
   per-type counts. Grunt behavior is unchanged. Test with a temporary color-only second type.
3. **M12 Ranged enemy:** `RangedData`, `RangedBrain`, projectile pool, wind-up flash, sounds.
4. **M13 Dasher:** `DasherData`, `DasherBrain`, state machine, telegraph lane, dash damage, recovery,
   sounds. *Review stop (the two enemies are the main feel test).*
5. **M14 Double Dash:** `dash.chain`, follow-up casting in the caster and DashSlash behavior, HUD ring,
   upgrade data file.
6. **M15 Polish and check:** tuning pass, mix readability pass, performance check at 300 enemies including
   projectiles, update `docs/`. *Final review.*

## 13. Definition of Done for v0.2

- The game launches to the Main Menu, goes through Character Select, and plays a full run.
- Pause and End screens can return to the Main Menu, and Restart keeps the character.
- Character Select shows the Knight and all four abilities with correct, data-driven numbers, and works with
  mouse, keyboard and gamepad.
- Dashers and Ranged enemies phase in and reach about 15% each of spawns from 2:30.
- A Dasher's telegraph is clearly visible, and a player who moves out of the locked lane takes no damage.
- A Ranged enemy's projectile can be dodged by moving or with the Q dash, and no ability destroys it.
- Double Dash works for two and three dashes, with correct mana, cooldown and window behavior.
- Tuning values live in data or constants.
- About 60 FPS at 300 enemies including projectiles.

## 14. Assumptions to Revisit Later

- Dasher telegraph time (1.0s with a 0.4s lock), dash distance and speed, and recovery time are guesses.
- Ranged fire rate (one per 2.0s), 130px hold distance and the projectile speed are guesses.
- Spawn unlock and full-weight times (0:45, 1:30, 2:30) are guesses.
- Double Dash capped at 2 levels and free follow-ups may be too strong or too weak.
- "Knight" and its description are placeholders.
- Exit on the Main Menu was added beyond the request.
