# Spec v0.9: Feel II (atmosphere and audio)

Builds on spec v0.8 (merged into `main`, PR #7: the particle bits in `Effects`, the hurt pulse) and on v0.6's map themes. Status: built; the player glow (section 2) was removed after play (rev 3: it looked funny), so sections 2, the glow tests and the glow lines of the file layout and Definition of Done no longer apply. Rev 2 (rev 2 applies an independent review: the death iris focuses on the dead player, the opening focus waits for the camera, the layer-order rule is by sibling index, kills no longer play the hit sound, ambience placement is defined, the glow follows the sprite's blink, and audio tests read a log the code owns).

Terms: **atmosphere** is what makes a place feel lived in without changing how it plays: a glow, drifting specks, the way a
scene opens and closes. A **mote** is one drifting speck of ambient life (new, section 3). The **iris** is a circular wipe: the
screen closes to a shrinking circle and opens from a growing one (section 4). A **layer** is a short extra sound played together
with an impact's main sound (section 5).

## Flow

You step into a map and the air is alive: embers climb in Ember Depths, spores drift in Spore Cavern, frost settles in Frostbite
Grotto. Your character carries a faint warm or cool glow that keeps them readable in a swarm. A hit lands with a crack, a thick
hit adds a thud, a kill adds a pop, and no two hits sound exactly the same. Walk into the door and the screen irises shut on your
character and opens on the next place. Die and the circle closes to a small hole around your body behind the death screen; clear a
stage and a warm flash washes over the banner. Nothing stops or slows time, and no gameplay number changes.

## 1. Scope

In scope:
- **A soft glow around each player** (section 2), tinted per character, drawn additively. Not real lights.
- **Ambient life per map** (section 3): a fixed number of drifting motes, five kinds, chosen per map in the map's data; the hub gets
  the default map's dust.
- **A circle iris** replacing the black fade between the hub, the stage select and a run (section 4), plus two short beats: the
  death circle and the stage-clear flash.
- **Pitch variation** on repeated sounds and **layered impact sounds** (section 5): four new generated placeholder sounds.
- Tests, and the README, `content/maps/README.md` and test README rows that go with them.

Out of scope (decided):
- **Real 2D lights** (`PointLight2D`, darkened ambient): the glow is a drawn additive shape.
- **Critters** (bats, fireflies that flee): motes only.
- **Hit-stop and any time change**: still no.
- **Real audio files**: the new sounds are generated placeholders like today's (`tools/gen_sfx.py`); the format and file names are
  the ones real files would replace.

Out of scope (later): meteor and other ability impact layers (only enemy hits, kills and Slam are layered, section 5.3), music, ambient
sound loops, per-map glow tint, motes that react to the player, weather that changes during a run, a transition style per scene pair.

## 2. Player glow

Shadows already exist (`PlaceholderSprite._draw_shadow`); this adds light. The torches already draw an additive halo (`CaveWalls.TorchGlow`:
three circles at 46, 30 and 18 px, alpha 0.08 each, a `CanvasItemMaterial` with `BLEND_MODE_ADD`); the player glow uses the same method.

### 2.1 Data
Three new fields on `CharacterData` (`scripts/characters/character_data.gd`), set in `knight.tres` and `wizard.tres`:

| Field | Knight | Wizard | Meaning |
|---|---|---|---|
| `glow_color` | `Color(1.0, 0.85, 0.6)` | `Color(0.6, 0.72, 1.0)` | warm for the Knight, arcane blue for the Wizard |
| `glow_radius` | 56.0 | 56.0 | outer radius in px, `@export_range(0.0, 160.0)`; 0 turns the glow off |
| `glow_alpha` | 0.16 | 0.16 | strength, `@export_range(0.0, 0.5)` |

### 2.2 The node
New `PlayerGlow` (`scripts/player/player_glow.gd`, `class_name PlayerGlow`, extends `Node2D`), created in `Player._apply_character` (after the
trait node, only when the character has `glow_radius > 0`) and named `Glow`. A `Player` built without a character has none.
- `position = Vector2(0, -10)` (the body's middle), `show_behind_parent = true` so it draws under the player's own sprite, a
  `CanvasItemMaterial` with `BLEND_MODE_ADD`.
- `_draw`: five circles at `r`, `0.8 r`, `0.6 r`, `0.4 r` and `0.2 r` with alpha `glow_alpha * 0.3` each (tuned in step 7: three circles looked like a bullseye; the centre strength is unchanged), where `r = glow_radius * (1 + 0.04 * sin(t * TAU * 0.6))`
  (a slow 4% breathing at 0.6 Hz, `t` from `Time.get_ticks_msec()`) and a helper `circles()` returns the three (radius, alpha) pairs for tests. `_process` calls `queue_redraw()`; one node per player.
- The glow's alpha is multiplied by `$Sprite`'s `modulate.a` each frame, so the post-dash blink and the Phase Shift ghost (0.5) dim the light with the body and the blink stays readable.
- `Player._on_died` hides it.
- The world's ambient `CanvasModulate` (`MapLook.apply_ambient`) tints it like everything else in the world, so a map's colour reaches it.
- The hub uses the same Player, so it gets the glow too.

## 3. Ambient life

### 3.1 Data
`MapTheme` (`scripts/maps/map_theme.gd`) gets a new `@export_group("Ambience")`:

| Field | Default | Range | Meaning |
|---|---|---|---|
| `ambience_kind` | `NONE` | enum `AmbienceKind { NONE, DUST, EMBERS, SPORES, FROST, GLINT }` | the motion rules (3.3) |
| `ambience_color` | white | any; its alpha is ignored (the kind sets it) | the mote colour |
| `ambience_count` | 40 | 0 to 80 | motes alive at once; 0 is the same as `NONE` |

Per map (set in `content/maps/<id>/map.tres`):

| Map | Kind | Colour | Count |
|---|---|---|---|
| `ember_depths` | EMBERS | `Color(1.0, 0.58, 0.2)` | 48 |
| `sulfur_pits` | EMBERS | `Color(0.85, 0.9, 0.3)` | 40 |
| `spore_cavern` | SPORES | `Color(0.55, 0.9, 0.5)` | 48 |
| `mossy_hollow` | SPORES | `Color(0.85, 0.95, 0.55)` | 32 |
| `frostbite_grotto` | FROST | `Color(0.8, 0.92, 1.0)` | 56 |
| `crystal_vault` | GLINT | `Color(0.7, 0.85, 1.0)` | 24 |
| `flooded_gallery` | DUST | `Color(0.7, 0.8, 0.85)` | 40 |
| `bone_warren` | DUST | `Color(0.85, 0.82, 0.72)` | 40 |
| `_default`, `_template` | DUST | `Color(0.8, 0.75, 0.65)` | 40 |

### 3.2 The node
New `Ambience` (`scripts/systems/ambience.gd`, `class_name Ambience`, extends `Node2D`, uses no autoload so a test can preload it). It keeps
a fixed array of `count` motes `{pos, vel, age, life, phase, size}` in world space and draws them from one canvas item with `draw_rect`
(positions rounded to whole pixels, the same pixel look as the v0.8 bits). It is **separate from `Effects`' bits** and their 256 cap,
so ambience cannot crowd out hit feedback and the reverse.
- **Where:** `World/Ambience`, `z_index = 4`: above the y-sorted world (0), below `DamageZones` (5, so the meteor and slam telegraphs stay on top of the motes), the projectiles (6), `Effects` (10) and the UI.
- **The visible area:** each frame `rect = get_canvas_transform().affine_inverse() * get_viewport_rect()` (the camera and its shake are
  included), grown by `MARGIN = 16` px. A mote outside the grown rect, or past its `life`, respawns at a random place inside `rect`
  (a mote that left on one side is as likely to appear anywhere inside, so there is no visible seam).
- **Fade:** alpha is the kind's alpha times `min(age / 0.5, (life - age) / 0.5, 1)`, so motes fade in and out and never pop.
- **Seeded:** `setup(theme, seed)` creates the motes and a `RandomNumberGenerator` seeded with `seed` (the run's `map_seed`); every later random choice
  (respawns included) uses that same generator, so a map starts and runs reproducibly and a test can count and compare.
- **First placement:** `setup` has no camera yet, so the motes are created unplaced and placed in the first `_process`, inside that frame's grown visible rect. Each starts at
  a random `age` in `[0, life]`, so they do not all fade in and die together.
- **Frame order in `_process(delta)`:** move every mote, then respawn the ones that are outside the grown rect or past their life (a respawn resets `age` to 0), then `queue_redraw()`.
  After any frame every mote is inside the grown rect.
- **GLINT** has its own alpha envelope (a rise and fall over its life) and ignores the shared 0.5 s fade, which would clash with a 0.8 s life.
- With `count 0` or kind `NONE` the node is removed. The preview scene's rebuild keeps one `Ambience` (find-or-create), not one per rebuild.

### 3.3 The five kinds
The numbers are constants in `ambience.gd` (visual, not tuning data; O5).

| Kind | Size | Motion | Life | Alpha |
|---|---|---|---|---|
| DUST | 1 px | drifts sideways 4 to 8 px/s, slow vertical sine of ±2 px/s | 6 to 10 s | 0.35 |
| EMBERS | 2 px | rises 14 to 28 px/s, sways ±6 px, flickers between 0.4 and 0.9 | 2 to 4 s | 0.4 to 0.9 |
| SPORES | 2 px | wanders at 3 to 7 px/s with a turning heading, bobs ±2 px | 6 to 10 s | 0.5 |
| FROST | 1 px (2 px for one in four) | falls 10 to 18 px/s, sways ±4 px | 5 to 8 s | 0.5 |
| GLINT | 2 px | does not move; alpha rises to 0.9 and back to 0 over 0.8 to 1.6 s, then it respawns elsewhere | 0.8 to 1.6 s | 0 to 0.9 |

### 3.4 Where it is built
- `MapLook.apply_ambience(parent: Node, theme: MapTheme, seed: int) -> Ambience` (`scripts/maps/map_look.gd`), in the pattern of `apply_ambient`:
  finds or creates a child named `Ambience`, sets it up from the theme, removes it when the kind is `NONE` or the count 0. A null theme uses
  `DUST`, colour `Color(0.8, 0.75, 0.65)`, count 40 (today's default cave).
- `MapBuilder.Targets` gets `ambience_parent: Node` (null skips, like the other targets); `MapBuilder.build` calls `apply_ambience` for it.
  `main.gd` sets it to `$World` (not the root, which is where `ambient_parent` goes: the motes must be in the world's canvas, under the UI); the map preview scene sets it too (`scenes/dev/map_preview.gd` builds through `MapBuilder`).
- The **hub** builds no theme (`hub.gd` has no `MapBuilder`), so `hub.gd` calls `MapLook.apply_ambience($World, MapRegistry.default(), 0)` once.

## 4. The circle iris

`SceneFader` (`scripts/systems/scene_fader.gd`, an autoload with a `CanvasLayer` at `layer = 100`) today fades a black `ColorRect`'s alpha over
`FADE_TIME` 0.3 s each way and exposes `busy` and `fade_to_scene(path)`; `GameSession._go` calls it, and tests read `busy` and use
`scene_hook` to skip it. v0.9 changes how it looks and keeps all three.

### 4.1 The shader
New `shaders/iris.gdshader` (`shader_type canvas_item`): uniforms `view_size` (vec2, pixels), `center` (vec2, pixels), `radius` (float, pixels),
`tint` (vec4). The fragment shader computes `p = UV * view_size` and outputs `tint` (opaque black for a wipe) where `distance(p, center) > radius`
and fully transparent inside: a **hard edge**, which suits the pixel art (no feathering). The `ColorRect` fills the layer and carries a
`ShaderMaterial` (its own `color` is ignored: the shader writes the output); `view_size` is `get_viewport().get_visible_rect().size`, set each time it changes.
`R_MAX` is a function of the centre: the distance from `center` to the farthest corner. When `radius >= R_MAX` the rect is **open** and is hidden (`visible = false`), so an idle iris
costs no full-screen draw; it is shown again as soon as a wipe or beat starts.

### 4.2 The wipe
- `fade_to_scene(path)` keeps its signature and `busy` semantics (a plain variable, true from the call until the opening tween's end; input is ignored meanwhile).
  It closes the iris from its **current** radius (`R_MAX` when open, or the death hole's radius after a beat, so there is no one-frame flash of open world) to 0 over `IRIS_TIME` 0.35 s
  (`TRANS_QUAD`, `EASE_IN`), changes the scene, then opens it to `R_MAX` over 0.35 s (`EASE_OUT`).
- **Focus:** `players[0]` of `PlayerRegistry` (`PlayerRegistry.players`, dead or alive: `nearest` skips the dead, so it would give no focus at the moment of death), at
  `get_viewport().get_canvas_transform() * (player.global_position + Vector2(0, -8))`; with no player (the select screen, menus) the screen centre. `SceneFader` may read
  the registry (an autoload that comes before it, `project.godot`). The opening focus is read after `scene_changed`, **after one `physics_frame` and then one `process_frame`**:
  `CameraFollow` places itself in `_physics_process`, so earlier its canvas transform is still the default and the player would be off screen; the opening tween does not start before.
- **First boot** starts fully closed (radius 0, `busy` true, as today's alpha 1) and opens from the screen centre.
- `get_tree().paused = false` before the change stays (the death and stage-clear flows pause the tree). `SceneFader` stays `PROCESS_MODE_ALWAYS`.

### 4.3 Beats (do not set `busy`)
A second `ColorRect` + `ShaderMaterial` in `SceneFader` on its own `CanvasLayer` at `layer = 1`, the same value as the scenes' `UI` layers (`UI` is a default `CanvasLayer` in `main.tscn` and `hub.tscn`).
Layers sort by `layer` and then by the node's `get_index()` among its siblings (not by global tree order), so the beat draws **under** the HUD and menus only if its index is lower than the
scene's `UI` node's index. `SceneFader`'s children are its wipe layer and the beat layer (indexes 0 and 1) and `UI` is far later in both scenes, so it holds; a test asserts it (section 7). Its
rect's `mouse_filter` is `IGNORE`, and it is hidden when open like the wipe.
- `SceneFader.iris_hold(radius: float, time: float)`: closes the beat iris from `R_MAX` to `radius` around `players[0]` (the same focus rule, so the dead player) over
  `time` (`EASE_OUT`) and leaves it there. `SceneFader.iris_release()` snaps it back open. Used for **death** (section 4.4).
- `SceneFader.flash(color: Color, time: float)`: a full-screen `color` rect on the beat layer whose alpha tweens to 0 over `time`. Used for **stage clear**.
- A scene change (`fade_to_scene`) does **not** release the beat: the wipe layer takes over from the same hole radius, and the beat is released when the new scene has loaded.

### 4.4 Where the beats are called
- **Death:** `main.gd` `_on_run_ended(false)` calls `SceneFader.iris_hold(70.0, 0.7)` (the end screen shows as it does now; the hole closes behind it).
- **Stage clear:** `main.gd` `_on_run_ended(true)` calls `SceneFader.flash(Color(1.0, 0.92, 0.6, 0.4), 0.4)` when the banner is shown.
- Both work while the tree is paused (the tweens belong to `SceneFader`).

## 5. Audio

`Audio` (`scripts/systems/audio.gd`, an autoload) has `play(sound, volume_db)`, a 12-voice pool, and a 40 ms throttle per sound name; ability streams
go through `play_stream` (`AbilityCaster.play_sfx` and `DamageZones` extras, which plays Meteor's impact); the camp screen calls `play`. No caller passes more than two arguments, so a third parameter breaks none.

### 5.1 Pitch variation
- `play_stream(stream, volume_db := 0.0, pitch_spread := 0.0)` and `play(sound, volume_db := 0.0)` set the voice's `pitch_scale` to
  `1.0 + randf_range(-spread, spread)` **every time**, 1.0 exactly when the spread is 0, because the pool reuses voices and a stale pitch must not stick.
- `play` takes the spread from `PITCH_SPREAD`, a dictionary in `audio.gd`: `enemy_hit` 0.08, `enemy_death` 0.08, `bolt_hit` 0.08, `projectile_hit` 0.07,
  `xp_pickup` 0.06, `slash` 0.06, `bolt_fire` 0.06, `coin` 0.05, `player_hurt` 0.05, `ranged_shot` 0.05, `lightning` 0.05, `spin` 0.04, `dash` 0.04,
  `slam` 0.04, `dasher_dash` 0.04. Every other sound (menus, hub, level-up, stage clear, door, no-mana, death, charges and wind-ups, the new layers) is 0.
- `AbilityCaster.play_sfx` passes 0.04 for ability streams. `DamageZones` extras pass 0 (Meteor keeps its single, unvaried sound, O7).
- **A log the code owns:** `Audio.recent` is an array of the last 32 voices started, `{name, pitch, ms}`, appended in `play_stream` (a stream with no name is logged by its resource path). Tests read it
  instead of polling `AudioStreamPlayer.playing`, which no existing test relies on under the headless dummy audio driver.

### 5.2 New sounds
Four generated placeholders, written by `tools/gen_sfx.py` into `assets/audio/` and listed in `Audio.SOUNDS` (CLAUDE.md: three places; a missing
file is skipped silently):

| Name | What | Recipe (in the generator's helpers) |
|---|---|---|
| `impact_crack` | bright crack | `save("impact_crack", noise(0.05, 0.8, 0.3, 2.5, 0.0), 0.5)` |
| `impact_thud` | low thud | `save("impact_thud", tone(120, 55, 0.14, "sine", 2.0), 0.7)` |
| `kill_pop` | pop on a kill | `save("kill_pop", mix(tone(600, 200, 0.1, "triangle", 2.0), noise(0.04, 0.6, 0.2, 2.0)), 0.45)` |
| `impact_boom` | sub boom under Slam | `save("impact_boom", mix(tone(70, 28, 0.4, "sine", 1.6), noise(0.25, 0.5, 0.05, 2.5, 0.0)), 0.8)` |

`impact_boom` is deliberately close to `meteor_impact` (a deeper, drier boom): it is its own file so a layer can be swapped for a real sample without touching Meteor.

The new `save(...)` lines go **at the end** of the generator, because it draws from one seeded `random` in order: earlier lines keep exactly the
files they make now, and after running it `git status` must show only the four new `.wav` files and, after the import, their four `.wav.import` files, which are committed (CLAUDE.md).

### 5.3 Layers
`Audio.impact(kind: StringName, strength: float)` (`strength` clamped to 0..1) plays layers together, each through the normal throttle:
- `&"hit"` (an enemy takes a hit that **does not kill**): `Enemy.take_damage` calls `Audio.impact(&"hit", ...)` only when `health.current > 0` after the damage. Today `enemy_hit` also plays on
  a killing blow, right after `enemy_death`; that stops: **a kill plays `enemy_death` and the kill layers only** (a deliberate change to the existing sound; O11). The hit plays `enemy_hit` as now, plus `impact_crack` at `-8 + 4 * strength` dB, plus `impact_thud` at `-10 + 6 * strength` dB
  when `strength >= 0.4`.
- `&"kill"`: `enemy_death` as now, plus `kill_pop` at -6 dB, plus `impact_thud` at `-8 + 6 * strength` dB when `strength >= 0.5`.
- `Enemy.take_damage` computes the hit strength as `amount / HEAVY_HIT` with `HEAVY_HIT = 30.0` (a constant in `enemy.gd`); `_on_died` has no damage amount, so it computes the
  kill strength from `data.body_size.x * data.body_size.y / 720.0` (the Dasher, 20x36, is 1.0; the Grunt 0.27; the Ranged 0.3). With the damage in play (Slash 10, Lightning 22, Dash & Slash 25,
  Slam 60, Meteor 90) the thud sits under Lightning, Dash & Slash, Slam and Meteor hits (`amount >= 12`) and not the plain Slash, and under Dasher kills only.
- A Slam's `sfx` and `sfx_layer` play once, at the cast; the per-enemy hits under it go through the named throttle (40 ms per name), which caps each of the four layer names at 25 starts a second.
- **Slam:** `AbilityData` gets `sfx_layer: AudioStream` (optional). `play_sfx` plays it too. `data/abilities/slam.tres` sets it to `impact_boom`; no other ability changes.
- `POOL_SIZE` rises from 12 to 16 so layers do not steal each other's voices.
- Meteor and other ability impacts stay as they are (out of scope).

## 6. File layout

New: `scripts/player/player_glow.gd`, `scripts/systems/ambience.gd`, `shaders/iris.gdshader`, `assets/audio/impact_crack.wav`, `impact_thud.wav`,
`kill_pop.wav`, `impact_boom.wav` (with their `.import` files), `tests/player_glow.gd`, `tests/ambience.gd`, `tests/iris_transition.gd`, `tests/audio_layers.gd`.
Changed: `scripts/characters/character_data.gd`, `data/characters/knight.tres`, `wizard.tres`, `scripts/player/player.gd`, `scripts/maps/map_theme.gd`,
`scripts/maps/map_look.gd`, `scripts/maps/map_builder.gd`, every `content/maps/*/map.tres` (ten files), `scripts/main.gd`, `scripts/hub.gd`,
`scenes/dev/map_preview.gd`, `scripts/systems/scene_fader.gd`, `scripts/systems/audio.gd`, `scripts/abilities/ability_data.gd`,
`scripts/abilities/ability_caster.gd`, `data/abilities/slam.tres`, `scripts/enemy/enemy.gd`, `tools/gen_sfx.py`, `README.md`,
`content/maps/README.md` (the new fields), `tests/README.md` (four rows). No new autoloads, no new physics layers, no scene files edited by hand.

## 7. Tests

Test mechanics (CLAUDE.md and `tests/README.md`): `extends SceneTree`, `await process_frame` first, untyped variables, `load("res://tests/fixture.gd")`,
autoloads through `root.get_node(...)`, classes that use no autoload (`Ambience`, `MapLook`) by `preload`, a time limit on a new test. Headless
has a dummy renderer: tests check state (nodes, materials, uniform values, tween targets, counts), and the look is checked once in a real window.

- **`tests/player_glow.gd`:** a Player with a character has one `Glow` with an ADD material, `show_behind_parent`, the character's radius and alpha and
  colour; `glow_radius 0` creates none; a Player without a character has none; it is hidden when the Player dies; the hub's Player has one; two circles' radii
  are `r`, `0.8 r`, `0.6 r`, `0.4 r`, `0.2 r` (read from a helper that returns them).
- **`tests/ambience.gd`:** `apply_ambience` creates `count` motes for each kind and removes the node for `NONE` and count 0; a null theme gives 40 dust motes;
  the same seed gives the same motes and a different seed a different set; after 600 frames of `_process` every mote is inside the grown visible rect and
  the count has not changed; every kind's motion matches its row (EMBERS rise, FROST falls, GLINT never moves, DUST drifts sideways); alpha is 0 at birth and
  at death; it uses no node of `Effects` and `Effects._bits` stays empty; the ten map files carry the kinds, colours and counts of section 3.1.
- **`tests/iris_transition.gd`:** `fade_to_scene` sets `busy`, the iris radius reaches 0 then `R_MAX`, `busy` is false after the opening; the closing centre is
  `players[0]`'s screen position, **including a dead Player** (and the screen centre with no Player); the opening centre is read after a physics frame and a process frame, with a
  `Camera2D` and a Player in the new scene (checked against `camera.get_canvas_transform() * (pos + (0, -8))`); the first boot starts closed; the rect is hidden when open; `iris_hold` leaves a hole of the given radius around the Player and does not set `busy`; a wipe after a beat starts from the hole's radius; `beat_layer.get_index() < $UI.get_index()` in both `main.tscn` and `hub.tscn`;
  `iris_release` reopens it; `flash` fades to 0; the beat layer's `layer` equals the scenes' `UI` layer and the beat rect ignores the mouse; the beats run while `get_tree().paused`. Timings use tolerances: the radius within 1 px of its end
  value when the tween ends, `busy` true from the call until the opening tween finishes (existing flow tests wait up to 300 physics frames, so 0.7 s is safe).
- **`tests/audio_layers.gd`:** every `Audio.SOUNDS` name has `assets/audio/<name>.wav` and a `save("<name>"` line in `tools/gen_sfx.py`; 40 plays of `enemy_hit` give pitches (read from `Audio.recent`, the entry of the voice that was started)
  within ±0.08 and not all equal; a sound with spread 0 always plays at exactly 1.0, **also after a varied sound used the same voice**; `impact(&"hit", 0.1)` starts
  2 voices, `impact(&"hit", 0.5)` starts 3, `impact(&"kill", 0.3)` starts 2 and `impact(&"kill", 1.0)` starts 3 (count the new `Audio.recent` entries; the 40 ms throttle is
  waited out between calls); a hit that kills plays `enemy_death` and no `enemy_hit`; the pool is 16 voices; an ability with `sfx_layer` starts 2 voices and one without starts 1; a missing layer file is skipped without an error.

Existing tests touched:
- `tests/maps/map_themes.gd`: the new field ranges (kind in the enum, count 0 to 80, colour opaque) and, for the ten files, the table of 3.1.
- `tests/maps/map_build.gd` and `tests/maps/theme_look.gd`: each built map has its `Ambience` with the theme's kind and count; a null theme gives dust.
- `tests/maps/map_preview.gd`: the workbench scene gets an `Ambience`.
- `tests/hub_walk.gd`, `tests/hub_browse.gd`, `tests/scene_flow.gd`, `tests/cave.gd`, `tests/stage_flow.gd`, `tests/select_screen.gd`: read `SceneFader.busy` (a plain variable, which stays a plain variable: `select_screen.gd` sets it directly) and use `scene_hook`; none touches `_rect`, `FADE_TIME` or `modulate`; they
  should pass unchanged (`busy` keeps its meaning). The run proves it, and the iris is 0.7 s end to end against 0.6 s now.
- `tests/hub_dummies.gd`, `tests/camp/*.gd`, `tests/wizard_animations.gd`: Player and Audio users; unchanged, the run proves it.
- `tests/crowd_performance.gd` and `tests/maps/crowd_bone_warren.gd` (physics time only; the glow and the ambience draw, they do not run in physics). The Bone Warren test
  is borderline and flaky (it failed once on plain `main`), so a failure is re-run before it is blamed on this change.

## 8. Build order

One step, one commit, tests with the step.
1. **Pitch variation:** `Audio.play`/`play_stream` pitch, `PITCH_SPREAD`, `play_sfx` 0.04; the pitch half of `audio_layers.gd`.
2. **Layered impacts:** the four sounds in `gen_sfx.py` (at the end) and the generated files, `Audio.SOUNDS`, `Audio.impact`, `POOL_SIZE` 16, `AbilityData.sfx_layer`, `slam.tres`,
   the `Enemy` calls and constants; the rest of `audio_layers.gd`.
3. **Player glow:** the `CharacterData` fields and both `.tres`, `PlayerGlow`, `Player._apply_character` and `_on_died`; `player_glow.gd`.
4. **Ambience:** the `MapTheme` fields, `Ambience`, `MapLook.apply_ambience`, `MapBuilder.Targets`, `main.gd`, `hub.gd`, the map preview, the ten map files, `content/maps/README.md`;
   `ambience.gd` and the map test updates.
5. **The iris:** `shaders/iris.gdshader`, `SceneFader` (wipe, focus, boot); the wipe half of `iris_transition.gd`.
6. **Beats:** the beat layer, `iris_hold`, `iris_release`, `flash`, the two calls in `main.gd`; the rest of `iris_transition.gd`.
7. **Look and tune:** render each map, the glow, a wipe frame by frame and a death beat in a real window (`tools/maps/shot_maps.gd` style); tune the numbers in sections 2 to 5 by eye and ear;
   `README.md`, `tests/README.md`; run the full suite and the crowd tests; the final numbers are written back into this spec.

## 9. Compatibility

- Gameplay numbers, abilities, enemy stats, spawn rules and the level-up pool are unchanged. The only thing the player can notice in play is the look and the sound.
- The first boot's opening is about 0.4 s instead of 0.3 s (it waits a physics and a process frame for the camera), and `PlayerInput` ignores input while `busy`, so a test that moves the Player in its first frames waits for `busy` to end (`map_build.gd` now does; found at build).
- A scene change takes 0.7 s end to end instead of 0.6 s; `busy` is true for the same span, so input is ignored a little longer.
- Everything new is additive and optional: a `MapTheme` without the new fields defaults to `NONE` (no ambience); a character with `glow_radius 0` has no glow; a sound whose file is missing is skipped;
  a null theme keeps today's cave and gets the dust.
- The existing ambient tint, vignette, torch glow and shadows are untouched.

## 10. Open questions / assumptions to revisit

- **O1: all numbers are first guesses** (glow alpha 0.16 and radius 56, mote counts, speeds and alphas, 0.35 s iris, 70 px death hole, the strength thresholds). They are tuned in step 7.
- **O2: the beat layer's order** relies on same-valued `CanvasLayer`s sorting by sibling index (section 4.3). The test checks the indexes; headless cannot see the pixels, so step 7 looks at a real death.
  If it is wrong, the beat layer moves to another `layer` value or into the scene's own `UI`.
- **O3: the glow tint is per character, not per map.** The map's ambient `CanvasModulate` still colours it. A per-map glow is a later option.
- **O4: motes draw above the world sprites** (`z_index = 4`), including over the player and enemies, like air. Dust at 1 px barely shows; if embers over the player distract, the kind's alpha drops near the player.
- **O5: the other numbers are named constants in the scripts**, not data: mote motion and alpha, `PITCH_SPREAD`, `HEAVY_HIT`, the 0.4 and 0.5 strength thresholds, `IRIS_TIME`, the 70 px hole and the flash colour. They are the feel of a feature, not balance (the v0.8 precedent: `SPARK_COUNT`). Only the
  kind, colour and count are per-map data and the glow is per-character data, because they vary per map or character.
- **O6: the iris focus needs a Player.** With none (the select screen) it closes on the screen centre; on the stage select a focus on the clicked card would be nicer and is later.
- **O7: Slam is the only layered ability** and Meteor keeps its single sound; extending `sfx_layer` to `DamageZones` extras is a later, small change.
- **O8: pitch variation shifts duration too** (it resamples), so a sound at +8% is 8% shorter. Fine for placeholders; real files may want a different method.
- **O9: the stage-clear flash is plain** (a warm full-screen fade). A ring or a burst of motes is a later option.
- **O10: motes are not collidable and ignore the player.** They never block anything and cost only drawing.
- **O11: kills no longer play `enemy_hit`.** Today a kill plays both `enemy_death` and `enemy_hit`; v0.9 plays `enemy_death` plus its own layers. Revisit if kills sound thinner.
- **O12: the iris and the beat each cost one full-screen draw while active** and nothing while open (the rects are hidden). The crowd tests do not measure drawing, so a real-window frame-rate
  check during a wipe is part of step 7.

## 11. Definition of Done for v0.9

Each visual and audible item has a measurable proxy that the tests check, and is also looked at and listened to once in a real window (an unchecked PR box).
- Every player has a `Glow` with an ADD material, the character's colour, radius and alpha (scaled by the sprite's alpha), hidden when dead; a character with `glow_radius 0` has none.
- Every built map has an `Ambience` with its theme's kind and count (the ten map files carry the table of 3.1), the hub has the default dust, motes stay inside the grown visible rect, the same
  seed gives the same motes, and `Effects._bits` is untouched by ambience.
- A scene change closes an iris on `players[0]` (or the screen centre) to 0 and opens it back, `busy` true from the call until the opening ends; the death beat leaves a hole of radius 70 around the dead Player under the end screen;
  the stage-clear flash fades to 0; the beat layer is the scenes' `UI` layer and ignores the mouse; the existing flow tests pass unchanged.
- Repeated sounds vary in pitch within their spread, sounds with spread 0 are exactly 1.0 even on a reused voice, a hit that does not kill plays 2 or 3 voices by strength, a kill plays `enemy_death` plus 1 or 2 layers (and no `enemy_hit`), Slam 2.
- `tools/gen_sfx.py` makes the four new files and `git status` shows only them and their `.import` files; every `Audio.SOUNDS` name has a file and a generator line.
- All new tests pass, the existing suite passes, the crowd tests stay under 12 ms (a borderline failure is re-run), and `tests/run_all.sh` passes on a fresh clone. A map, the glow, a wipe and a death
  were looked at in a real window.
- Nothing in v0.9 stops, slows or freezes time.
