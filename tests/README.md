# Tests

Headless regression scripts. Each one starts the real game scenes, drives them with simulated input, and prints
`PASS` or `FAIL` (with the reason). The exit code is 0 on a pass.

```
godot --headless --path . --script tests/<name>.gd
tests/run_all.sh            # imports first, then every test in tests/ and tests/maps/, one line each (120 s limit per test)
```

| Script | Checks |
|---|---|
| `double_dash.gd` | Knight's Double Dash: free follow-up, frozen cooldown, expiry |
| `dash_immunity.gd` | Unhittable while dashing and for `immunity_after` seconds afterwards |
| `dasher_lane.gd` | A Dasher's locked lane hurts a player standing in it and misses one who stepped out |
| `wizard_abilities.gd` | Arcane Bolt, Arcane Focus, Phase Shift, Chain Lightning, Meteor Strike |
| `phase_belt.gd` | Phase Shift's orb belt: appears, hurts, follows, ends, Orbital Ring |
| `chain_lightning.gd` | Jump count, damage falloff, Extra Jumps, an enemy standing on the Wizard |
| `crowd_performance.gd` | 300 unkillable enemies on a stationary Player stay inside the physics budget |
| `hub_data.gd` | Trait text in the data files matches the trait scripts' constants |
| `arena_cave.gd` | The run's rock walls: varied lengths, clear of the start and each other, seeded, solid; enemies stay out of the band |
| `hub_browse.gd` | Hub pedestals, browse input, the info panel's numbers against the data, a click, Choose |
| `hub_walk.gd` | Walk mode: one Player, infinite mana, interact and `clear()`, confirm/interact lockout, the door |
| `hub_dummies.gd` | Every ability of both characters hurts the dummies; they never die, move, tint or stun; the readout |
| `cave.gd` | Cave walls are solid, the door still triggers, decor stays clear of reserved areas, floor and decor are seeded |
| `scene_flow.gd` | Hub to select to run to hub to select: Arena size, unpausing, the hub pause menu |
| `stage_modifiers.gd` | Additive percentage maths, the 300 alive cap ceiling, XP scaling, the SpawnDirector applying a stage |
| `gold.gd` | Coin drop chance (25% + gold, clamped), drops, pickup through the XPCollector, gold persistence |
| `path_generator.gd` | Path shape, the connections, tier rules, value ranges, names, thumbnails, each stage's theme (7 different), seed reproducibility (30 seeds) |
| `run_progress.gd` | GameSession path state; level, XP and upgrades carried between stages; cleared on death, abandon, victory |
| `select_screen.gd` | Card states per column, the cursor (skips locked, wraps), keyboard and mouse picking, the abandon prompt |
| `maps/map_content.gd` | `content/maps/` on disk against `MapRegistry`, required files, 64x40 thumbnails, ids, unique names, a monster variant per enemy type, no stray files (also `_template`, `_default`) |
| `maps/map_themes.gd` | Every `MapTheme` field in range, ambient near white, the eight maps differ, monsters readable on the floor, thumbnail colour close to the theme |
| `maps/theme_look.gd` | A theme's colours reach `Ground`, `CaveWalls` and torches, `CaveWall`, `Prop`, `CaveDecor` and `MapLook` (vignette, ambient); null theme equals today's values; decor kinds keep their numbers |
| `stage_flow.gd` | Stage cleared banner and its 2 s, level-up first, victory, death screen, the pause menu's abandon prompt |

## Writing one

- A test is a script that `extends SceneTree`, does its work in `_init()` (awaiting frames) and ends with
  `quit(1 if failed else 0)`.
- **In a `--script` run the autoloads (`GameSession`, `Audio`, `PlayerRegistry` ...) only exist from the first frame.**
  A test that names a class using one of them (`Player`, `Enemy`, `AbilityCaster`) fails to compile. So
  `await process_frame` first, keep the test's own code to untyped variables, and use `fixture.gd`, which is
  loaded at runtime: `var F: GDScript = load("res://tests/fixture.gd")`.
- `fixture.gd` starts a run with the spawner off, spawns (optionally frozen) enemies, applies upgrades and casts.
- The enemy grid is rebuilt once per physics frame, so wait a frame or two after spawning before casting.
- Rendering-dependent checks (anything that reads pixels) are not covered: headless uses a dummy renderer.
- A script error inside a test leaves its SceneTree running, so a broken test hangs rather than failing. Run one by
  hand with a time limit when in doubt.
- After adding a `class_name` script, run `godot --headless --path . --import` once so the global class cache knows it.
- `GameSession.scene_hook` (a Callable) replaces the fade to a new scene, so a test can see which scene a flow
  would load without leaving the scene it is testing.
