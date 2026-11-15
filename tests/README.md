# Tests

Headless regression scripts. Each one starts the real game scenes, drives them with simulated input, and prints
`PASS` or `FAIL` (with the reason). The exit code is 0 on a pass.

```
godot --headless --path . --script tests/<name>.gd
tests/run_all.sh            # every test, one line each
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
| `hub_browse.gd` | Hub pedestals, browse input, the info panel's numbers against the data, a click, Choose |
| `hub_walk.gd` | Walk mode: one Player, infinite mana, interact and `clear()`, confirm/interact lockout, the door |
| `hub_dummies.gd` | Every ability of both characters hurts the dummies; they never die, move, tint or stun; the readout |
| `scene_flow.gd` | Hub to run to hub to run: Arena size, unpausing, the hub pause menu |

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
