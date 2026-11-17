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
| `archer_upgrades.gd` | Spec 1.1 upgrades (data only): the 14 new Archer upgrade files load, have unique ids, valid max levels, text, a known stat key, and change a `Stats` node as the spec table says; the four general ones exist |
| `archer_character.gd` | Spec 1.1 character: the Archer is last in the registry with four free abilities, Steady Aim, 18 upgrades with valid keys and none for mana, all seven animations, a panel text without Mana; a run as the Archer has 0 mana, no FOCUS label, Q plays the `dash` animation, and level-up cards are Archer upgrades or relics |
| `archer_plumbing.gd` | Spec 1.1 plumbing: `uses_mana = false` (no MP bar, no MP flash, panel text without Mana/Regen, free casts at 0 mana), `AbilityData.animation`/`param()`, `dash` as a one-shot, `AbilityBehavior.clamp_to_arena` |
| `archer_arrow_dash.gd` | Spec 1.1 Arrow and Dash Shot on a Wizard fixture with the abilities set by hand: Arrow targets the nearest enemy within 180 px, cooldown, `arrow.extra` (2 and the cap of 4), Steady Aim and damage-stat scaling, `steady.full`, no mana; Dash Shot: 80 px dash towards the aim, immune while dashing and in the grace after, no path damage, 7 arrows in a 60 degree fan centred on the opposite of the aim from the landing point, `dashshot.arrows`, `dashshot.range`, `dashshot.chain`, `dash` animation data |
| `archer_ricochet_rain.gd` | Spec 1.1 Ricochet Volley and Arrow Rain on a Knight run with E and R set by hand: arrow 1 at the cast and the 6th at 0.5 s, each along the swept aim of its moment with the spread pattern, 3 hits and 3 bounces, the caster never busy (Q mid-volley), the volley stops on death, a full pool skips shots, `ricochet.extra`/`bounces`/`hits`; Rain: 3 zones of radius 34 on an n-gon 84 px apart (4, 5 zones and radius 64 always more than `2 * (radius + 6)`), first corner towards the player, 0.9 s windup then 5 ticks 0.3 s apart, an enemy hit by one zone only, range and arena clamps, no mana, damage stat, `arrow_rain.ticks` |
| `maps/map_props.gd` | Sprite props (test-props): the catalog loads (unique ids, regions on the sheet, five groups); for every map with props and 30 seeds a seed repeats, at least 80% of `prop_count` is placed, blockers stay inside the room, off the start square, 40 px from walls and 28 px from each other, the free area stays connected, and adding props moves no wall, pillar, decor piece or torch |
| `wizard_abilities.gd` | Arcane Bolt, Arcane Focus, Phase Shift, Chain Lightning, Meteor Strike |
| `wizard_animations.gd` | The Wizard's SpriteFrames (nine animations, drawn timings, loops) and the Player playing them: bolt alternates attack1/attack2, lightning and meteor their own, phase loops while phased, hurt, and death surviving a killing hit |
| `phase_belt.gd` | Phase Shift's orb belt: appears, hurts, follows, ends, Orbital Ring |
| `relic_orbs_trail.gd` | Storm Orbs (own belt, counts, radius, damage scaling, shared hit cooldown, Lv3 zaps, Phase Shift's belt unaffected) and Fire Trail (flame spacing, life, once-per-tick damage, Lv3 burn, cap of 80, nothing while dead) |
| `chain_lightning.gd` | Jump count, damage falloff, Extra Jumps, an enemy standing on the Wizard |
| `enemy_status.gd` | Enemy statuses: slow x factor through `chase` and `settle` (strongest wins, longest time, expires), freeze stops movement and contact hits and gives vulnerable, vulnerable multiplies `take_damage`, burn ticks every 0.5 s for dps x seconds (quiet: no flash or recoil) and refreshes, 30 seeds of stacking and burn totals, a pooled enemy comes back clean, dummies ignore all four, a slowed Dasher's dash length is unchanged, tint priority, the `DamageZones` slow / ignite / freeze extras and damage-0 fields, 300 enemies with statuses inside the crowd budget |
| `crowd_performance.gd` | 300 unkillable enemies on a stationary Player stay inside the physics budget |
| `hub_data.gd` | Trait text in the data files matches the trait scripts' constants (the delay only for traits that have one); the Archer's Steady Aim text shows +30% and 160 |
| `arena_cave.gd` | The run's rock walls: varied lengths, clear of the start and each other, seeded, solid; enemies stay out of the band |
| `hub_browse.gd` | Hub pedestals (three, at x 340 / 480 / 620), browse input and wrap-around, the info panel's numbers against the data, a click, Choose |
| `camera_dead_zone.gd` | Camera follow: starts centred, stays still inside the dead zone, ends with the player on the zone's edge after a big move, eases rather than snapping, stops at the arena walls |
| `movement_feel.gd` | Walking ramp: above 0 and below top after one frame, top after `accel_time`, never above it, stopped after `friction_time`, diagonal capped, Phase Shift's top speed, no speed into a wall, a dash hands over at walking speed, a time of 0 is instant, no NaN, a dead Player stands still; footstep dust per 14 px, a skid on stopping from speed, none while standing, teleporting, dashing, phased, from a crawl or slowed by Spin |
| `impact_feedback.gd` | Particle bits (burst direction, drift, dust, the 256 cap, the spark budget, `clear()`, expiry); enemy hits (3 sparks, 0.09 s flash, 2 px recoil that eases back, dummies unchanged); deaths (6, 7 and 14 bits in the body colour, one puff, only the Dasher shakes the camera); gems and coins hop 10 to 17 px, wait for the hop before the pull-in, stay inside the arena; the hurt pulse (0.35 s, none for hits that do not land) |
| `ambience.gd` | Ambient motes: `MapLook.apply_ambience` creates, updates and removes the node (null theme gives 40 dust), the same seed gives the same motes, every kind stays inside the visible area and moves as specified (dust sideways, embers up, frost down, glints still), alpha 0 at birth and death, the ten map files carry the spec's table, a run and the hub have one apart from the Effects bits |
| `iris_transition.gd` | The circle iris: first boot starts closed and opens, `busy` from the call to the end of the opening, the hole closes to 0 and opens again, the focus is the first player's screen position (dead or alive, the centre with none) and waits for the camera, the rect is hidden when open; the beat layer sits under the scenes' UI, `iris_hold` leaves a hole of 70 around the dead player without `busy` and works while paused, `flash` fades out, a wipe after a beat starts from the hole |
| `audio_layers.gd` | Pitch variation within each sound's spread, exactly 1.0 without one (also on a reused voice), the voice log, every sound has a file and a generator line, a hit starts 2 or 3 voices by strength and a kill 2 or 3, a missing layer is skipped, Slam starts 2 voices and Slash 1 |
| `hub_walk.gd` | Walk mode: one Player, infinite mana, interact and `clear()`, confirm/interact lockout, the door |
| `camp/camp_site.gd` | The camp in the hub: place, clear of other things, interact opens a stub screen (walk mode only, lockout, radius), prompt text near the camp and a pedestal |
| `hub_dummies.gd` | Every ability of both characters hurts the dummies; they never die, move, tint or stun; the readout |
| `cave.gd` | Cave walls are solid, the door still triggers, decor stays clear of reserved areas, floor and decor are seeded |
| `scene_flow.gd` | Hub to select to run to hub to select: Arena size, unpausing, the hub pause menu |
| `stage_modifiers.gd` | Additive percentage maths, the 300 alive cap ceiling, XP scaling, the SpawnDirector applying a stage |
| `gold.gd` | Coin drop chance (25% + gold, clamped), drops, pickup through the XPCollector, the run purse and banking |
| `path_generator.gd` | Path shape, the connections, tier rules, value ranges, names, thumbnails, each stage's theme (7 different), seed reproducibility (30 seeds) |
| `camp/camp_screen.gd` | The camp screen in the hub: Esc and Enter with it closed, buy/undo by key and mouse, unaffordable (no_mana), MAX, Reset all, row keys ignored on a focused button, Esc closes without the pause menu, the hub rebuilds its Player on a change |
| `camp/camp_banner.gd` | The hub after a run: the "+N gold" banner shows once (also with the last-character early return), the counter counts up from the old total, no banner without a reward |
| `run_progress.gd` | GameSession path state; level, XP, upgrades and relics carried between stages; cleared on death, abandon, victory |
| `relic_progress.gd` | The five relics' data tables, RelicRegistry, PlayerRelics (add, raise to 3, no 5th slot, no relics in the hub, behaviors stop while dead), relics captured and restored in slot order, old snapshots without `relics` |
| `relic_cards.gd` | LevelUpRoller over 30 seeds: three distinct cards; no new relic with 4 full; upgrade cards only for owned relics below level 3; a new relic is always among the three while none is owned; the relic share over 3000 rolls is within 5 points of what the 2 to 1 weights give; all maxed falls back to stat cards, nothing left gives none; a card applied changes the level (`NEW` / `Lv a -> b` text) and a new relic takes the first free slot |
| `relic_hud.gd` | HUD relic slots: `relic_slot_rect` positions (x = view.x - 28, y 36, 22 px, gap 4), the 0.3 s slot flash on gain and raise, no flash when restoring (pixels not tested) |
| `archer_arrows.gd` | Archer arrows (spec 1.1, section 5): `fire` without `opts` as before (pierce, passes pillars); bounce to the nearest unhit enemy within reach, never to a hit one, no target or a wall in the way keeps direction and bounce, ends on the `hits`-th enemy; ricochet off walls, a pillar (head on and at the side), the arena edge and its corner, none left retires, no bounce burned from inside a wall, the hub (no `ObstacleMap`) reflects only at the edge; `SteadyAim.multiplier` and Steady Aim by straight launch distance; `PlayerInput.target_point`; the shared cap; 30 seeded crowds (each enemy hit at most once, at most `hits` hits, seed reproduces) |
| `relic_wave_comet_nova.gd` | Tidal Wave, Frost Comet and Thorn Nova per level: cadence, damage x the damage stat, wave direction follows `aim_vector`, no cast without a target and retry, a wall shortens the wave, Lv3 returns and hits once per pass; comet target count and distinctness, freeze, 1.5x vulnerable not applied to the comet's own hit, seeded picks over 30 seeds; nova thorn count and spacing, bramble slow, Lv3 tick damage and 4 s life, a nearly full projectile pool, nothing while dead |
| `camp/camp_save.gd` | SaveGame: round trip, missing, zero-length and corrupt (`.bad`) files, clamping, unknown ids, tmp fallback, saving off when headless; GameSession saves on buy, undo, reset and banking |
| `camp/camp_gold.gd` | The run purse: coins go to `run_gold`; death screen, abandon and victory bank once and set `last_reward`; `take_reward`; nothing banked on `complete_stage` |
| `camp/camp_shop.gd` | Camp attribute costs (40 to 456, 1288 each), buy, undo, reset, gold plus spent conserved over 30 seeds, the GameSession attribute API |
| `camp/camp_attributes.gd` | Attribute data: totals at levels 0, 1 and 7 through `CampAttributes.apply`, `display_values` and summary text against the data; in play: Haste/Fury `cooldown_of`, Recovery, Agility, Might x Power, `RunProgress.restore`, the hub Player, Greed in the director |
| `select_screen.gd` | Card states per column, the cursor (skips locked, wraps), keyboard and mouse picking, the abandon prompt |
| `maps/map_content.gd` | `content/maps/` on disk against `MapRegistry`, required files, 64x40 thumbnails, ids, unique names, a monster variant per enemy type, no stray files (a type's `<type>_sheet.png` and `<type>_frames.tres` may sit in `monsters/`; also `_template`, `_default`, whose `monsters/` holds only the cave grunt) |
| `maps/map_themes.gd` | Every `MapTheme` field in range, ambient near white, the eight maps differ, monsters readable on the floor, thumbnail colour close to the theme |
| `maps/map_layout.gd` | `MapLayout.generate`: the default theme equals today's arena; for the eight maps and 30 seeds the layout rules (clearing, rock band margin, wall gaps, pillar distances, 16-obstacle budget, 80% placed, lengths, no sealed area, a free cell across every gap, decor and torches; the flood fill uses `FlowField.cell_blocked`) and that a seed reproduces |
| `maps/theme_look.gd` | A theme's colours reach `Ground`, `CaveWalls` and torches, `CaveWall`, `Prop`, `CaveDecor` and `MapLook` (vignette, ambient); null theme equals today's values; decor kinds keep their numbers |
| `maps/monster_variants.gd` | A variant per enemy type on every map, the same behaviour and `EnemyData` under every theme (and MonsterVariant has only the appearance fields, `sprite_frames` among them), the sprite, death puff and hub dummies |
| `maps/obstacle_blocking.gd` | Walls and pillars block enemies: push-out and sliding, knockback, going round a wall, the director's spawn rule, flow-field budget and rebuild rules, Ranged and Dasher line of sight, the stuck failsafe, corner hysteresis, the hub unchanged (about 60 s) |
| `maps/map_preview.gd` | The workbench scene `scenes/dev/map_preview.tscn` builds all eight maps (counts equal the layout, three monsters in the map's looks, an ObstacleMap), Tab / R / L / O / Z, `walk`, GameSession untouched |
| `maps/slime_sprites.gd` | The drawn grunt slimes: every map's (and the cave's) grunt variant has `bounce` / `hit` / `death` frames (4 / 4 / 5, loop flags, Aseprite durations, 32x32 regions of the map's own sheet, feet on row 29), ranged and dasher have none; an Enemy with frames bounces on activate, plays `hit` on damage and bounces again, flips with its facing, dies as an independent `Effects.play_once` animation (capped, pooled) while the node deactivates at once; a variant without frames keeps the drawn body, white flash and puff; `tools/slimes/build_slimes.py --check` reproduces the committed sheets |
| `maps/map_build.gd` | `MapBuilder` in the real run scene, for each of the eight maps and the default cave: wall, pillar, decor and torch counts equal the layout, theme colours reached the rock, floor, ambient and vignette, the Player and an enemy still collide with a wall, `MapBuilder` alone gives the run's layout |
| `maps/crowd_bone_warren.gd` | 300 enemies on MapLayout's real Bone Warren layout (fixed seed), stationary and moving Player, under the crowd frame limit (logs worst frame and the mean without obstacles) |
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
- Rendering-dependent checks (anything that reads pixels) are not covered: headless uses a dummy renderer. To look at
  the maps, run `godot --path . --script tools/maps/shot_maps.gd -- <folder>` (not headless; `--script` mode does render)
  and read the PNGs it writes (see `content/maps/README.md`).
- Saves: `run_all.sh` gives each test its own `HERO_HORDE_SAVE` temp file, and headless with no path disables saving, so
  tests never touch the player's save. Non-headless runs (renders, `shot_maps.gd`) must set `HERO_HORDE_SAVE` themselves.
- A script error inside a test leaves its SceneTree running, so a broken test hangs rather than failing. Run one by
  hand with a time limit when in doubt.
- After adding a `class_name` script, run `godot --headless --path . --import` once so the global class cache knows it.
- `GameSession.scene_hook` (a Callable) replaces the fade to a new scene, so a test can see which scene a flow
  would load without leaving the scene it is testing.
