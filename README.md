# Hero Horde (working title)

A 2D survivors-like built in Godot 4 (GDScript). Survive 5 minutes of enemies, level up, and use each
character's Q / E / R abilities. Proof of concept.

## Characters
- **Knight** (close range): auto Slash, Q Dash & Slash, E Spin, R Slam.
- **Wizard** (ranged): auto Arcane Bolt, Q Phase Shift (ghost form, then a ring of orbs), E Chain Lightning,
  R Meteor Strike. Trait: Arcane Focus (+25% damage after standing still for 1s).
- **Archer** (ranged, no mana): auto Arrow, Q Dash Shot (dash, then a fan of arrows back along the way you came),
  E Ricochet Volley (six arrows that bounce between enemies and off walls), R Arrow Rain (three damage circles
  around the cursor). Trait: Steady Aim (up to +30% damage with arrows that have flown 160 px or more). It has no
  MP bar and no mana upgrades.

Each character has 18 to 19 upgrades. The game opens in the **hub**: look at each character on their pedestal
(left / right or click), read their stats and abilities, and choose one. Then walk around the hub as them (infinite
mana, no damage; F next to a pedestal changes character) and walk through the door in the north wall to start a run.
The **chest** right of the door (F next to it) opens the **inventory** of the character you are playing (spec 1.4): seven slots (helmet, chestplate, necklace, two rings, pants, shoes) and the items you have unlocked; click or Enter wears an item or takes it off, Esc closes. Each character has their own loadout, an item is worn by one character at a time, and equipped items change the hero's stats in the hub and in runs. The loadouts and the pool are saved next to the camp save (`camp.json.inventory`). There are 18 items (spec 1.5): three per type in three ratings, **standard** (a small bonus to one stat), **epic** (more, two stats) and **legendary** (the most, and for all types but the ring a **relic** you start every run with, in an extra relic slot: four picked relics plus one from the item makes five passives; it can still be raised to level 3 by level-up cards). Killing a charger has a 10% chance (`item_drop_chance` in `content/enemies/dasher.tres`, to be lowered to 1%) to drop an item that unlocks when you walk onto it; wear it from the chest in the hub.
The hub and the run arena are torch-lit dirt caves (the arena has rock walls of varied length). Three indestructible training dummies in the north-west corner show Last / Total / DPS for your hits.

## Run it
1. Install Godot 4.7 (`brew install --cask godot` on macOS).
2. `godot --path .` from this folder, or open `project.godot` in the editor and press F5.

## Display
The game renders at a 640x360 base resolution (window 1280x720, 2x integer scale) with nearest-neighbor filtering.
The base size is set in `project.godot` (`display/window/size`); the HUD, menus, camera and spawn ring adapt to it.

## Controls
| Action | Keyboard and mouse | Gamepad |
|---|---|---|
| Move | WASD | Left stick |
| Aim | Mouse | Right stick |
| Ability Q / E / R | Q / E / R | X / Y / Right trigger |
| Hub: browse / choose | A D or arrows, click, Enter | D-pad, A (South) |
| Hub: change character / open camp or chest / info | F / F / I | A (South) / Back |
| Pause | Esc | Start |
| Debug overlay | F3 | |

Slash is automatic. Level-up cards: click, keys 1/2/3, or D-pad and confirm.

## Relics (v1.0)
Four relic slots sit on the right of the screen in a run. A level-up can offer a **relic card** (tag RELIC): a new relic, or a level for one
you own (3 levels each). Relics work by themselves and are the same for every character: **Tidal Wave** (a wave along your aim, Lv3 returns),
**Frost Comet** (comets that freeze, Lv3 two comets and frozen enemies take 1.5x), **Thorn Nova** (a ring of thorns and a slowing bramble, Lv3 a damaging
one), **Storm Orbs** (orbs circle you, Lv3 they zap) and **Fire Trail** (flames behind you, Lv3 they set enemies burning). With all four slots full only
upgrades for the relics you own are offered. Relic damage scales with your damage stat. Their numbers are in `content/relics/<id>/relic.tres`; enemy slow,
freeze, vulnerable and burn live in `EnemyStatus`. See `docs/spec-1.0.md`.

## Feel
Walking eases up to speed and coasts to a stop (`accel_time` and `friction_time` in `content/characters/<id>/character.tres`; 0 is instant), with
a puff of dust every few steps. Hits throw sparks and recoil the enemy's body a hair, a kill throws a burst in the enemy's colour
(`EnemyData.kill_shake` kicks the camera for tough ones), XP gems and coins hop out before they are pulled in, and the screen edges
pulse red when the player is hit. A killed enemy rarely (1%) drops a glowing horseshoe **vacuum magnet** (one at a time; it lies 30 s and blinks for the last 10): walking onto it pulls every XP gem and coin on the map, including new drops, to you at 1000 px/s for 5 s (spec 1.3; `content/pickups/vacuum_magnet.tres`, `VacuumMagnet`, `Pickups`). Particles are tiny squares in `Effects` (capped at 256). Nothing ever stops or slows time.

Atmosphere and audio (v0.9): every map has drifting motes (`ambience_kind`, `ambience_color`, `ambience_count` in its `map.tres`, see `content/maps/README.md`); scene changes
close a circle iris on the player (`SceneFader`, `shaders/iris.gdshader`), the death screen closes the screen to a small hole behind it and a
stage clear washes a warm flash over the banner. Repeated sounds vary in pitch (`Audio.PITCH_SPREAD`) and hits, kills and Slam have layered
sounds (`Audio.impact`, `AbilityData.sfx_layer`); the layers are generated placeholders from `tools/gen_sfx.py`.

## Project layout
- `scenes/`: the hub (`hub.tscn`, the main scene), the run (`main.tscn`), player, enemy, pickups, projectile.
- `scripts/`: `hub/` (pedestals, door, chest), `inventory/` (`ItemData`, `ItemRegistry`, `Inventory`, `ItemEffects`, `InventorySave`), `player/`, `enemy/` (brains), `abilities/` (behaviors), `systems/`, `ui/`, `upgrades/`, `relics/` (`RelicData`, `RelicRegistry`, `PlayerRelics`, `RelicBehavior` and one behavior per relic), `characters/`, `stages/` (path), `maps/` (`MapTheme`, `MonsterVariant`, `MapRegistry`, `MapLayout`, `MapBuilder` which builds a run's arena from a theme, `ObstacleMap`, `FlowField`; map code only, no content).
- `content/characters/<id>/`: everything about one character: `character.tres`, `frames.tres`, `sprites/`, `abilities/<ability id>/` (`ability.tres`, `behavior.gd` and that ability's `upgrades/`) and passives only that character has in `upgrades/`. `content/shared/upgrades/` holds the upgrades several characters use. `_template` is a complete character to copy. See `content/characters/README.md`.
- `content/items/<id>/item.tres`: one folder per item (18), `content/items/loot.tres` the drop table; see `content/items/README.md`.
- `content/pickups/vacuum_magnet.tres`: the vacuum magnet's tuning (`VacuumData`: drop chance, times, pull speed).
- `content/relics/<id>/` (`relic.tres` and its behavior script), `content/enemies/*.tres`, `content/attributes/*.tres`: the rest of the game's data. Tuning is data, not code.
  `scripts/` keeps the engine: bases (`AbilityBehavior`, `DashSlashBehavior`, `BoltBehavior`), `SteadyAim`, registries and systems. Specs before 1.2 name the old `data/` and `assets/sprites/` paths.
- `content/maps/<id>/`: everything about one map: `map.tres` (a `MapTheme`), `thumbnail.png` and `monsters/*.tres`
  (a `MonsterVariant` per enemy type). `_default` is today's cave (used with no stage set), `_template` is a complete map to copy;
  neither is offered on a card. A new map is a folder plus one id in `MapRegistry`.
- `assets/audio/`: placeholder sound effects, generated by `python3 tools/gen_sfx.py`.
- `scenes/dev/map_preview.tscn`: the map workbench (see below), not part of exported builds.
- `tools/`: `gen_sfx.py` (sounds), `maps/` (`gen_thumbnails.py` makes the thumbnails, `new_map.py` adds a map, `shot_maps.gd` renders all maps to PNGs), `slimes/build_slimes.py` (builds the grunt slime sheets and SpriteFrames of every map from `art/source/slimes/*.aseprite`) and `prepare_knight_sprites.gd` (cleans raw Knight animation sheets; run with
  `godot --headless --script tools/prepare_knight_sprites.gd`).
- `tests/`: headless regression scripts, see `tests/README.md` (`tests/run_all.sh` imports first, then runs them all, including `tests/maps/`).
- `docs/`: specs. Start with `spec-0.1.md`, then `spec-0.2.md` (menus, new enemies, Double Dash), `spec-0.3.md`
  (the Wizard), `spec-0.4.md` (the hub) and `spec-0.6.md` (the eight stage maps). Each later spec has revision notes and a status section at the end.

## The map workbench
Open `scenes/dev/map_preview.tscn` in the editor (F6) or run `godot --path . scenes/dev/map_preview.tscn`. It builds one map
the way a run does (`MapBuilder`), with the three monster looks in a row near the middle. Keys: `Tab` next map, `R` new seed,
`L` reload the map files from disk, `O` overlay of obstacle footprints and the flow field, `Z` whole-arena zoom, arrows pan;
the `walk` export puts a Player in. To render all maps to PNGs for review (not `--headless`):
`godot --path . --script tools/maps/shot_maps.gd -- <folder>`. Details and the steps for a new map: `content/maps/README.md`.

## Adding things
- **Map:** `python3 tools/maps/new_map.py <id> "<Name>"`, then follow `content/maps/README.md`.
- **Enemy:** new `EnemyData` resource in `content/enemies/` with a brain script in `scripts/enemy/`, then add it to
  `SpawnDirector.enemy_types` in `scenes/main.tscn`.
- **Upgrade:** new `UpgradeData` in the `upgrades/` folder of the ability it upgrades (or the character's, or `content/shared/upgrades/`), then add it to the character's `upgrade_pool`.
- **Character:** copy `content/characters/_template/`, then list it in `CharacterRegistry`. Abilities and relics are folders too: `content/characters/README.md`.
