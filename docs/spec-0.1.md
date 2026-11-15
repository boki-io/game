# Spec v0.1 (POC): Hero Horde (working title)

Decisions locked in: solo play, 5-minute timed run, one enemy type, no boss, co-op-ready architecture without networking.

## 1. Scope

**In v0.1:** one character (Sword), one map, one enemy, one 5-minute run (survive to win, die to lose), XP and level-ups with a Sword-only upgrade pool, mana, a HUD, a pause menu, and sample sounds. Runs on keyboard and mouse or a gamepad, and exports to Windows and macOS.

**Out of v0.1:** meta-progression, bosses, more characters, networking, settings or rebinding menus.

**The one question this POC answers:** is the Q/E/R ability combat fun in a survivors-like?

## 2. Technical Setup

- **Engine:** Godot 4.x, GDScript, 2D renderer.
- **Internal resolution:** 480x270, stretch mode `viewport`, scale mode `integer`, default texture filter `Nearest`.
- **Character sprites:** 32x32. Enemies 24x24 or 32x32 depending on the asset pack.
- **2.5D approach:** all gameplay happens in plain 2D screen space. The depth look comes from Y-sorting (`y_sort_enabled` on the world node), a blob shadow under every sprite, and a ground tileset drawn in a tilted view. No vertical squash on movement or hitboxes in v0.1.
- **Collision layers:** 1 World, 2 Player, 3 Enemy, 4 Player attacks, 5 Pickups.

## 3. Scene Structure

```
Main (Node2D)
├─ World (Node2D, y_sort_enabled)
│  ├─ Ground (TileMapLayer)
│  ├─ Players (Node2D, y-sorted)       <- Player instances
│  ├─ Enemies (Node2D, y-sorted)
│  └─ Effects (Node2D)                 <- slashes, slams, damage numbers
├─ Pickups (Node2D)                    <- XP gems
├─ SpawnDirector (Node)
├─ RunManager (Node)                   <- timer, win/lose, pause
└─ UI (CanvasLayer)
   ├─ HUD
   ├─ LevelUpMenu
   ├─ PauseMenu
   └─ EndScreen

Player (CharacterBody2D)
├─ AnimatedSprite2D + Shadow
├─ PlayerInput        <- outputs move_vector, aim_vector, ability signals
├─ Health
├─ Mana
├─ Stats              <- base values + modifiers (upgrades write here)
├─ AbilityCaster      <- owns cooldowns, checks mana, runs ability behaviors
├─ XPCollector (Area2D)
└─ Hurtbox (Area2D)

Enemy (Node2D or Area2D, not CharacterBody2D)
├─ AnimatedSprite2D + Shadow
├─ Health
└─ Hitbox (contact damage)
```

**Co-op readiness:**
- Nothing references a global "the player". Enemies ask a `PlayerRegistry` for the nearest player.
- `PlayerInput` takes a `device_id` (-1 for keyboard and mouse, 0+ for gamepads).
- Every component belongs to a player instance.
- XP and level-ups are tracked per player (trivial now, painful to retrofit).

## 4. Input

All input goes through Input Map actions. Combat code only ever reads `move_vector` and `aim_vector`.

| Action | Keyboard / Mouse | Gamepad |
|---|---|---|
| Move | WASD | Left stick |
| Aim | Mouse position | Right stick |
| Ability Q | Q | West button (X / Square) |
| Ability E | E | North button (Y / Triangle) |
| Ability R | R | Right trigger |
| Pause | Esc | Start |
| Menu navigate / confirm | Arrows or mouse / Enter | D-pad / South button |

**Aim vector rules:**
- **Mouse:** `(mouse_world_position - player_position).normalized()`
- **Stick:** deadzone of 0.25. On release, keep the last aim direction.
- **Fallback:** if there has been no aim input yet, use the last movement direction.
- The sprite faces the aim vector when casting, and the movement direction otherwise.

## 5. Ability System

Numbers live in data, shapes live in code.

```gdscript
# ability_data.gd
class_name AbilityData
extends Resource

@export var id: StringName
@export var display_name: String
@export var icon: Texture2D
@export var cooldown: float = 1.5      # seconds
@export var mana_cost: float = 10.0
@export var damage: float = 20.0
@export var range: float = 48.0        # px
@export var radius: float = 32.0       # px (AoE / spin / slam)
@export var windup: float = 0.0        # seconds before the hit lands
@export var behavior: Script           # e.g. DashSlashBehavior
@export var sfx: AudioStream
```

- Each ability behavior is a small script with `cast(caster, aim_vector, data)`.
- Hits use physics shape queries (`intersect_shape`) at the moment of impact, rather than spawning long-lived Area2D nodes. This is cheaper with hundreds of enemies.
- `AbilityCaster` rejects a cast if the ability is on cooldown or mana is insufficient. It also gives feedback on a failed cast (a "no mana" HUD flash and sound).
- Upgrades never edit the `.tres` files. They add modifiers (damage multiplier, cooldown multiplier, flags like `spin_hits_twice`) in `Stats`, and behaviors read those.

## 6. Character 1: Sword (starting values, all tunable)

**Player base stats:** HP 100, move speed 90 px/s, max mana 100, mana regen 8/s.

| Ability | Input | Cooldown | Mana | Damage | Shape | Behavior |
|---|---|---|---|---|---|---|
| Slash | Auto | 0.6s | 0 | 10 | 90° arc, 40px range | Targets the closest enemy within 90px, then slashes toward it. Does nothing if no enemy is in range. |
| Dash & Slash | Q | 1.5s | 10 | 25 | 64px dash, hits enemies along the path | 0.15s dash toward the aim vector. Player is briefly invulnerable. A small slash arc plays at the end. |
| Spin | E | 2.0s | 15 | 20 | 48px radius circle around the player | 0.4s spin that hits everything in range once. Player can still move slowly during it. |
| Slam | R | 2.0s | 30 | 60 | 56px radius circle, centered up to 80px away along the aim vector | 0.3s windup with a ground telegraph, then a slam that knocks enemies back slightly. |

## 7. Mana and Cooldown Balance (noted for tuning)

- With 1-2 second cooldowns, cooldowns alone won't limit casting, so **mana is the real limiter**.
- A full Q+E+R rotation costs 55 mana against a 100 pool: about two rotations, then the player falls back to basic attacks and slow regen (about 7 seconds per rotation).
- Target feel: mana runs dry after roughly 8-10 seconds of continuous spamming, and rewards choosing when to spend it.
- **Tuning order if it feels wrong:** (1) mana regen, (2) R's cost, (3) max mana, (4) cooldowns last.
- Add a debug overlay (F3) showing mana, cooldowns, kills per minute, and FPS.

## 8. Enemy and Spawning

**Grunt:** HP 20, speed 45 px/s (half the player's), contact damage 5 every 0.5s while touching, drops 1 XP gem.

**Behavior:** move straight toward the nearest player, with light separation from neighbors so they don't stack into one pixel. No pathfinding in v0.1.

**Spawn Director:**
- Spawns in a ring just outside the visible screen at a random angle.
- **Spawn rate:** 1/s at 0:00, rising linearly to 8/s at 5:00.
- **Alive cap:** 300. Spawning pauses at the cap.
- **HP scaling:** HP x (1 + 0.15 x minutes elapsed), so grunts are 75% tougher at the end.
- Enemies that fall too far off screen are teleported back to the spawn ring rather than despawned.

## 9. XP and Upgrades

**XP:**
- Gems drop where enemies die, are pulled in within the pickup radius (48px), and are collected on touch.
- XP needed for next level = `round(8 * 1.35^(level-1))`. Expect roughly 12-14 levels in a full run.
- On level-up the game pauses and shows 3 random upgrades. The player picks with mouse click, keyboard 1/2/3, or gamepad D-pad and confirm.

**Sword upgrade pool.** Each upgrade has up to 3 levels. Choices exclude maxed upgrades.

*Ability upgrades:*
- **Slash:** Wider Arc (+25% arc), Quick Hands (-15% cooldown), Sharpened (+30% damage)
- **Dash & Slash:** Long Dash (+30% distance), Blade Trail (dash path damages enemies for 2s), Efficient (-25% mana cost)
- **Spin:** Double Spin (hits twice), Wide Spin (+25% radius), Cyclone (-20% cooldown)
- **Slam:** Shockwave (second, larger ring), Stunning Blow (stuns for 1s), Heavy Hand (+30% damage)

*Passives:*
- +20 max HP (and heal 20)
- +2 mana regen/s
- +20 max mana
- +10% move speed
- +30% pickup radius
- +10% all damage

## 10. HUD, Menus, Audio

**HUD:** HP bar, mana bar, four ability icons with a cooldown sweep and a dimmed state when mana is too low. Also an XP bar with level number, the run timer (counting down from 5:00), and the kill count.

**Pause menu:** Esc or Start pauses the game (`get_tree().paused = true`) and shows **Continue** and **Exit**. Exit quits the game.

**End screen:** Win ("Survived!") or Lose ("You died"), showing time survived, level, and kills, with a **Restart** button.

**Sounds (free assets):** basic slash, one each for Q, E, and R, enemy hit, enemy death, XP pickup, level-up, player hurt, player death, a "no mana" blip, and menu click. A single looping music track is optional.

## 11. Performance Approach

- Nearest-enemy queries use a **spatial hash grid** rather than scanning all enemies.
- Pool enemies, XP gems, and damage numbers instead of instantiating and freeing them.
- Cap simultaneous damage numbers and merge nearby ones.
- Keep enemy logic to one `_physics_process` that moves toward the player and does a cheap separation check. If this struggles near 300 enemies, switch to batch updates driven by the `SpawnDirector`, and consider `MultiMesh` for drawing.
- **Target:** 60 FPS at 300 enemies on a mid-range machine. Check early on real hardware, not just your Mac.

## 12. Build Order

1. **M0 Setup:** project settings, folder layout, Git, macOS and Windows export presets, and an early test on a Windows machine.
2. **M1 Player:** movement, camera follow, Y-sort, placeholder map, input abstraction (keyboard and gamepad).
3. **M2 Enemies:** the Grunt, chasing, contact damage, player death, spawner with the escalating curve.
4. **M3 Basic attack:** auto-target, the Slash, enemy health and death, damage numbers.
5. **M4 Ability framework:** `AbilityData`, `AbilityCaster`, cooldowns, aim vector, and Q (Dash & Slash).
6. **M5 E and R:** Spin and Slam, with slam telegraph and knockback.
7. **M6 Mana and HUD:** mana bar, cooldown icons, "no mana" feedback.
8. **M7 Progression:** XP gems, leveling, level-up screen, upgrade pool wired into `Stats`.
9. **M8 Run flow:** timer, win and lose states, pause menu, end screen.
10. **M9 Polish and ship check:** sounds, hit flash, optional screen shake and hit-stop, performance pass, test exports on both platforms.

## 13. Definition of Done for v0.1

- A full 5-minute run is playable start to finish on both Windows and macOS.
- Keyboard and mouse and a gamepad both work for everything, including menus.
- All four Sword abilities work, respect cooldowns and mana, and have sound and a visible effect.
- Level-ups present working choices, and upgrades visibly change gameplay.
- Pause and Exit work at any point in a run.
- The game holds about 60 FPS with 300 enemies on screen.
- Tuning values (sections 6, 7, 8, 9) live in data or constants, not buried in code.

## 14. Assumptions to Revisit Later

- Mana and cooldown numbers are first guesses (section 7).
- Sword Slash targeting range (90px) and the stun and trail upgrades may be cut if the pool feels bloated.
- Gameplay stays in plain screen space. If the tilted ground makes vertical distances feel off, add a Y-squash factor to movement and hitboxes later.
- Sprite size (32x32) and 480x270 are the expensive decisions to change, so lock them before gathering art.
