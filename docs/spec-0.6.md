# Spec v0.6: Stage maps (eight themed arenas)

Builds on spec v0.5 (the stage path, built on branch `map-selector`). Status: built, rev 6 (rev 5 text below, with the deviations listed at the end of this note) (walls and pillars block
enemies, section 6.6; per-map monster looks, section 7; working directory, section 3). Rev 5 applies an independent
review: the obstacle/flow-field design is hardened (6.6), the monster variant is trimmed to colours and a mark (7), the
directory design drops empty stub folders (3), and the build order, export and test details are corrected.

Rev 6 (built, on branch `spec-0.6-maps`; every step of section 14 is done, the decisions are in `AGENT_DECISION_LOG.md`
under "v0.6 ..." and "v0.6 final"). Deviations from the text below:
- **Tests use 30 seeds** (as CLAUDE.md says), not the 1000+ the early text asked for.
- **Stuck failsafe** is measured as a 3 s window (position compared with the one at the window's start), so a stuck enemy is
  recycled between 3 and 6 s after it gets stuck, not exactly at 3 s (O8).
- **The first flow-field search starts at once**; the 0.25 s minimum applies from the second on (O6).
- **The preview scene** is `scenes/dev/map_preview.tscn` with `map_preview.gd` beside it, as in 3.6; it also has `Z` (whole-arena
  zoom) and arrow keys (pan) besides Tab, R, L and O.
- **`shot_maps.gd`** needs a real renderer (do not pass `--headless`); it renders into off-screen SubViewports and also writes
  one PNG per map at normal zoom, the whole arena and the monster row. Map `i` uses seed `N + i`.
- **Thresholds that moved while building:** the "two themes differ by 0.05" rule counts the rock distance plus the floor distance
  (M6), since the thumbnails share dark rocks; the thumbnail colour tolerance is 0.07 (it started at 0.12). New rules from the
  rendered review (step 10): a wall's top and a pillar are at least 0.10 OKLab from the plain floor, a monster's mark at least
  0.30 from its body; marks are at least 3 px.
- **Count checks** ask for at least eight maps (so a ninth map from `new_map.py` does not break them); `map_themes.gd` still
  fails on an unchanged copy of the template, on purpose.
- **`crowd_bone_warren.gd`** is a timing gate on the machine it runs on: it can fail when the machine is busy (see the log).
- Not verified by playing: how enemies path on each map in a full run, and the look in motion.

Terms: a **map** is the arena a stage is played in, built from a **map theme** (new). The eight themes match the
eight thumbnails and stage names that v0.5 already generates (`assets/stages/stage_0..7.png`,
`PathGenerator.NAMES`); from v0.6 they live in one folder per map (section 3). "Rock band" is the 16 px wall along the arena edge, "wall" is a freestanding rock slab
(`CaveWall`) and "pillar" is a `Prop`, as in v0.4 section 15.

## 1. Scope

In v0.5 every stage reuses one cave arena and differs only by numbers. In v0.6 the stage you pick on the select
screen decides what the arena **looks like and how its obstacles are laid out**, and the map matches the thumbnail on
its card: pick the icy thumbnail and you fight in an icy cave.

In scope:
- A `MapTheme` resource per theme (8 in all): palette, rock and floor look, decor mix, light, obstacle layout rules.
- **A working directory built around the map** (section 3): one folder per map holding everything that is about it,
  a registry, a scaffold script, a preview scene and a test that keeps them honest. Adding a ninth map is one folder
  and one registry line.
- **Per-map monster looks** (section 7): the same three enemy types the game already has get a slightly different
  look on each map (frost monsters on the frost map: a shifted colour and one small mark) through a `MonsterVariant`
  resource. They behave **identically**: same health, speed, damage, hitbox,
  attacks and telegraphs. Appearance only.
- A seeded layout generator with three layout styles (scatter, lanes, clusters), driven by the theme.
- **Walls and pillars block enemies as well as the Player** (section 6.6): enemies cannot walk through them and
  steer around them, in every arena including the default one.
- The look: floor tiles, rock band, walls, pillars, decor, torch or glow colour and an ambient tint all take the
  theme's values.
- New decor kinds (crystals, icicles, big fungi, puddles, vents, ember cracks, moss) that are drawn only.
- `StageData` gets a theme; `main.gd` builds the arena from it.
- Tests that a theme's palette matches its thumbnail, that layouts are legal, and that a seed reproduces a map.
- A tool that renders every map to a PNG so they can be reviewed by eye (headless tests cannot render).

Out of scope (later): different monster **behaviour** per map (other attacks, damage, health or speed; section 7.7
says where that will plug in), real monster art (the variants use the existing drawn stand-ins), hazards
or any new gameplay rule beyond blocking (lava damage, slowing water, slippery ice), player
projectiles and abilities being stopped by walls, changing the arena
size (it stays 1600x896 for every map), hand-authored layouts, new enemies per map, ambient sounds or music per map,
a different hub, a minimap, saving anything to disk.

**The question this version answers:** does a stage feel like a place, and is the choice on the select screen a
choice of *where* to fight, not only of numbers?

## 2. How a map is picked

```
select screen: card (name, thumbnail i)  --pick-->  GameSession.current_stage (StageData, theme i)
        --> main.gd builds the arena from MapTheme i, seeded from the path seed  --> stage
```

- The theme **is** the stage's identity: its `display_name` becomes the stage name and its `thumbnail` the card's
  picture (v0.5 already pairs them; the pairing is now simply "they come from one theme"). A path has 7 different
  themes out of the registry's eight.
- The theme also decides how the monsters look (section 7). The three enemy types and their numbers are the same on
  every map.
- The tier and the modifiers (population, difficulty, experience, gold) stay **independent** of the theme. An Easy
  "Ember Depths" and a Hard "Ember Depths" are the same place with different numbers.
- With no `StageData` (running `main.tscn` from the editor) the arena uses the **default theme**: today's cave, with
  today's fixed seeds, so the editor workflow and the existing tests see no change (section 11).
- Nothing changes in the hub or on the select screen.

## 3. Working directory

The goal: **to work on a map you open one folder**, and to add a ninth map, or more per-map content later (sprites,
decor art, different attacks), without moving anything. Today the project sorts files by *type* (`scripts/`,
`scenes/`, `data/`, `assets/`). That is right for code and shared data, but one map's content would scatter over five
of those (a theme in `data/`, its thumbnail in `assets/stages/`, monster art in `assets/sprites/`, ...). v0.6 keeps
the by-type layout for **code and behaviour** and adds one by-feature tree, `content/`, for **per-map content**.

### 3.1 Rules
1. **Code by type, content by map.** Scripts stay in `scripts/<area>/`, scenes in `scenes/`, tests in `tests/`, tools in
   `tools/`. Everything that is *about one map* lives in `content/maps/<id>/`.
2. **Behaviour stays where it is.** Enemy numbers and brains, abilities and upgrades stay in `data/`. A map never edits
   them; it only supplies appearance (section 7).
3. **Convention over configuration.** A map folder has fixed file names, so the registry, tools and tests find things
   without lists inside the files.
4. **A leading underscore means "not a playable map":** `_default` and `_template`. They are never offered on a card.
5. **Generated files are committed** next to the data they belong to; the script that makes them lives in `tools/maps/`.
6. **A map folder is self-contained.** It refers to shared code and to itself only, never to another map, so a map can
   be copied, renamed or deleted as a unit.

### 3.2 The tree
```
content/
  maps/
    README.md                  how to add a map (3.5)
    _template/                 a complete, valid map to copy; never offered in a path
      map.tres
      thumbnail.png
      monsters/  grunt.tres  ranged.tres  dasher.tres
    _default/                  today's cave: the arena when no stage is set (editor, most tests)
      map.tres                 (no monsters/: enemies keep the look in their EnemyData)
    mossy_hollow/
      map.tres                 MapTheme: palette, light, layout rules, decor weights, the monster variants
      thumbnail.png            64x40, made by tools/maps/gen_thumbnails.py
      monsters/                one MonsterVariant per enemy type
        grunt.tres  ranged.tres  dasher.tres
    crystal_vault/  ember_depths/  frostbite_grotto/  spore_cavern/  bone_warren/  flooded_gallery/  sulfur_pits/
                               (same shape as mossy_hollow; eight maps in all)

scripts/
  maps/                        NEW: all map code, no content
    map_theme.gd  monster_variant.gd  map_registry.gd
    map_layout.gd  map_layout_data.gd  map_builder.gd
    obstacle_map.gd  flow_field.gd
  cave/                        unchanged place: drawing of rock, walls and decor (they now take a theme)
  stages/                      unchanged: StageData, PathGenerator, StagePath
  enemy/                       unchanged + applying a variant (section 7.5)
scenes/
  dev/map_preview.tscn         NEW: the map workbench (3.6); not part of a run, left out of exported builds
tools/
  maps/                        NEW: everything that makes or checks map content
    gen_thumbnails.py          (was tools/gen_stage_thumbs.py)
    new_map.py                 scaffold a map from _template (3.5)
    shot_maps.gd               render every map and a contact sheet (section 13)
  gen_sfx.py  prepare_knight_sprites.gd      unchanged
tests/
  maps/                        NEW: the tests v0.6 adds (section 12); run_all.sh also runs tests/maps/*.gd
  *.gd                         existing tests stay where they are
data/                          unchanged (abilities, characters, enemies, upgrades)
assets/stages/                 REMOVED: the thumbnails move into the map folders (3.7)
```

### 3.3 File conventions
| File | Rule |
|---|---|
| Folder name | The map `id`: lowercase `snake_case`, unique. Equals `MapTheme.id`. |
| `map.tres` | One `MapTheme` (section 4). Required. |
| `thumbnail.png` | 64x40 PNG. Required. Loaded by `MapTheme.thumbnail`. |
| `monsters/<enemy_id>.tres` | One `MonsterVariant` per enemy type, file name = `EnemyData.id` (`grunt`, `ranged`, `dasher`). Required for the eight maps, optional for `_default`. |
| Other files and folders | Not used in v0.6. Later content (monster sprites, decor art, a map scene) gets its own subfolder inside the map folder, created when it is first needed. The test in 3.4 rejects stray top-level files so the folder stays readable. |

### 3.4 The registry
`MapRegistry` (`scripts/maps/map_registry.gd`) holds an **explicit list** of playable map ids, like
`CharacterRegistry` does for characters, because an exported build cannot reliably list a directory. It offers
`all()` (the loaded `MapTheme`s in list order), `by_id(id)` and `default()` (the `_default` map). `PathGenerator`
draws its 7 maps from `all()`, so a ninth map is picked up with no other change.

`tests/maps/map_content.gd` closes the gap the explicit list leaves: it lists `content/maps/` on disk and fails if a
folder (not starting with `_`) is missing from the registry, or a registry id has no folder; if a required file is
missing or has the wrong size or id; if a map lacks a variant for any enemy type the director can spawn; or if a map
folder holds a stray top-level file.

### 3.5 Adding a map
1. `python3 tools/maps/new_map.py <id> "<Display Name>"` copies `_template` to `content/maps/<id>/`, fills in the id
   and name, and appends the id to `MapRegistry`.
2. Open `scenes/dev/map_preview.tscn`, pick the new `map.tres` and edit palette, layout rules and decor weights; the
   preview rebuilds on demand (3.6).
3. Edit `monsters/*.tres` for the three monster looks; the preview shows a sample of each.
4. Add the map's colours to `tools/maps/gen_thumbnails.py` and run it to make `thumbnail.png`.
5. Run `tests/run_all.sh`. `map_content.gd`, `map_themes.gd`, `map_layout.gd` and `monster_variants.gd` cover the new
   folder with no test changes.
6. `godot --path . --script tools/maps/shot_maps.gd -- <folder>` (not `--headless`: it needs a renderer) to review all maps side by side.

`content/maps/README.md` carries these steps so they are next to the files they are about.

### 3.6 The map preview scene
`scenes/dev/map_preview.tscn` (F6 in the editor) is the workbench. It builds an arena with **`MapBuilder`, the same
code `main.gd` uses**, so a map cannot look different here than in a run.
- Exports: `map` (drag a `map.tres` in), `seed`, `walk` (a Player to test blocking and flow, off by default). A row of
  the three monster variants always stands near the arena centre so their look can be checked.
- Keys: `Tab` next map, `R` new seed, `L` reload the map files from disk and rebuild (so an edit in the inspector or a
  text editor shows without restarting), `O` overlay of obstacle footprints and the flow field.
- It reads and writes nothing in `GameSession`. It is excluded from exported builds (3.7).

### 3.7 Migration from v0.5
Done in build step 1 (section 14), as moves so history is kept:
- `assets/stages/stage_<i>.png` -> `content/maps/<id>/thumbnail.png` (`git mv`), with `<i>` matching today's name
  order: `0` mossy_hollow, `1` crystal_vault, `2` ember_depths, `3` frostbite_grotto, `4` spore_cavern, `5` bone_warren,
  `6` flooded_gallery, `7` sulfur_pits. `assets/stages/` is deleted. The old `.import` files point at the old source
  path, so they are deleted, `godot --headless --path . --import` is run to create the new `.import` files, and these
  and any new `.uid` files are committed.
- `tools/gen_stage_thumbs.py` -> `tools/maps/gen_thumbnails.py`, writing into the map folders.
- `PathGenerator`: `NAMES`, `THUMBNAIL_COUNT` and `THUMBNAIL_PATH` are replaced by `MapRegistry.all()`; each stage
  takes its `name` and `thumbnail` from its theme. `StageData` keeps its v0.5 fields, and gains `theme` (section 9).
- `tests/path_generator.gd` keeps its checks (7 distinct names and thumbnail paths, seeds) against the new source.
- `export_presets.cfg`: both presets get `exclude_filter="scenes/dev/*, tools/*, tests/*, content/maps/_template/*"`
  (they are empty today), so the workbench, the tools and the template never ship.
- `tests/run_all.sh` runs `godot --headless --path . --import` first (a fresh clone has no class-name cache, which new
  `class_name` types such as `MapTheme` need) and also runs `tests/maps/*.gd`.
Nothing else moves: `scripts/cave/`, `scripts/stages/`, `scripts/enemy/`, `data/` and the existing tests stay put. Scripts
named by `.tres` files (`MapTheme`, `MonsterVariant`) keep their paths from now on, as moving them breaks the files.

### 3.8 How it grows
- **A new map** is a folder and one registry line (3.5). Nothing in the code names a specific map.
- **A new enemy type** is a new `EnemyData` plus one `monsters/<id>.tres` in every map; `map_content.gd` fails until
  every map has it, so a map can never silently show the wrong monster.
- **Real monster art:** a `sprites/` folder in the map and a `sprite_frames` field on `MonsterVariant`, as
  `CharacterData` has for characters. Neither exists in v0.6 (section 7.2).
- **Different attacks per map (later):** new exported fields on `MonsterVariant` (section 7.7). Variant files are
  already per map and per type, so nothing moves.
- **A hand-built scene for one map (the v0.5 "distinct map scenes"):** an optional `scene.tscn` in the folder that
  `MapBuilder` prefers over the procedural build. Not built in v0.6; the folder and builder leave room for it.
- **Map-specific sounds, music, hazards** get their own optional subfolders the same way.

## 4. The `MapTheme` resource

A new resource, one file per theme at `content/maps/<id>/map.tres` (section 3), listed in `MapRegistry` (3.4). All
colours are `Color`, all counts ints.

| Group | Field | Meaning |
|---|---|---|
| Identity | `id` | `&"mossy_hollow"` ..., unique, equal to the folder name |
| | `display_name` | "Mossy Hollow"; becomes `StageData.name`, unique |
| | `thumbnail` | `Texture2D`, the folder's `thumbnail.png` |
| Monsters | `monsters` | `Array[MonsterVariant]`, one per enemy type (section 7) |
| Floor | `floor_plain` | 4 colours, the plain tile shades |
| | `floor_dark`, `floor_light` | The dark patch and worn-path shades |
| | `floor_flecks` | Fraction of tiles that are pebbled or cracked (default 0.12) |
| Rock | `rock`, `rock_dark`, `rock_light` | The rock band (`CaveWalls`) |
| | `wall_top`, `wall_top_light`, `wall_side`, `wall_outline` | Freestanding walls (`CaveWall`) |
| | `pillar` | The pillar's stone colour |
| Light | `torch_color` | Flame colour of the torches |
| | `glow_color` | Halo colour (additive) |
| | `torch_count` | Torches along the walls (4..12) |
| | `ambient` | Multiplied over the world (a colour near white; section 8.5) |
| | `vignette` | Edge darkness 0.4..0.8 (today 0.62) |
| Layout | `style` | `SCATTER`, `LANES` or `CLUSTERS` (section 6) |
| | `wall_count` | Freestanding walls |
| | `wall_lengths` | Allowed lengths in px (a subset of `CaveWall.LENGTHS`) |
| | `horizontal_bias` | Chance a wall runs left-right, 0..1 |
| | `pillar_count` | Pillars |
| Decor | `decor_count` | Pieces of decor (at most 140) |
| | `decor_weights` | Dictionary `Kind -> weight` (section 8.4) |

The default theme is a `MapTheme` too (`content/maps/_default/map.tres`) holding today's exact values, so colours and
looks come from one place. It has `legacy_layout = true`, which makes `MapLayout` call the existing layout code
(`CaveWall.layout`, `CaveDecor.layout`, the fixed pillar seed) instead of the new styles, so today's arena is
reproduced exactly (6.1). It is not one of the eight, has no thumbnail and no monster variants, and is never offered
on a card.

## 5. The eight maps

Each map keeps the thumbnail's palette (section 10) and adds its own obstacle character. Wall and pillar numbers are a
first guess: tune them while playing.

| # | Name (folder id) | Look | Style | Walls | Lengths | Horiz. | Pillars | Decor | Signature decor |
|---|---|---|---|---|---|---|---|---|---|
| 0 | Mossy Hollow | Green-brown earth, mossy grey rock, warm green glow | SCATTER | 6 | 48-160 | 0.5 | 8 | 110 | moss patches, glowing mushrooms |
| 1 | Crystal Vault | Blue-violet rock, cold cyan glow | LANES | 6 | 160-320 | 0.3 | 4 | 90 | crystal clusters (glowing) |
| 2 | Ember Depths | Dark red-brown rock, orange glow, warm ambient | CLUSTERS | 6 (3 pairs) | 64-160 | 0.5 | 10 | 80 | ember cracks in the floor, scorched rocks |
| 3 | Frostbite Grotto | Pale blue-white floor, icy rock | SCATTER | 9 | 48-128 | 0.5 | 6 | 100 | icicle stalagmites, frost patches |
| 4 | Spore Cavern | Purple floor, violet glow | CLUSTERS | 8 (4 pairs) | 64-128 | 0.5 | 6 | 120 | big fungi, spore motes |
| 5 | Bone Warren | Tan dust floor, bone-coloured rock | LANES | 10 | 96-208 | 0.8 | 2 | 100 | bone piles (more and larger) |
| 6 | Flooded Gallery | Blue-grey rock, dark wet floor | SCATTER | 3 | 208-320 | 0.5 | 3 | 90 | puddles with a ripple, wet rocks |
| 7 | Sulfur Pits | Ochre floor, yellow-brown rock, yellow glow | CLUSTERS | 8 (4 pairs) | 64-160 | 0.5 | 8 | 90 | steam vents, sulfur crusts |

Why they feel different (this is the design intent a reviewer checks against):
- **Open vs tight.** Flooded Gallery (3 long walls, 3 pillars) is the most open map: good for kiting. Bone Warren (10
  walls in rows) is the tightest and funnels movement into horizontal corridors. Frostbite Grotto's 9 short walls
  break up sight lines without long barriers.
- **Lanes (Crystal Vault, Bone Warren)** give long straight corridors; **clusters (Ember Depths, Spore Cavern, Sulfur
  Pits)** give islands of cover with open ground between; **scatter (Mossy Hollow, Frostbite, Flooded)** is the
  v0.4/v0.5 feel.
- Pillars are the cheap, small obstacles. Ember Depths and Sulfur Pits have the most (10 and 8).
- Because walls block enemies, **layout is gameplay**: lanes and clusters funnel the crowd as well as the Player, and
  Bone Warren's rows make enemies queue at the openings. Flooded Gallery stays open, so the crowd reaches you fast.
- No map has hazards. Walls and pillars block movement only; enemy projectiles already vanish on them (v0.4).

## 6. Layout generation

One function, `MapLayout.generate(theme, seed, size) -> MapLayoutData`, pure logic (no scene, no autoload), returning
`walls: Array[Rect2]`, `pillars: Array[Vector2]`, `decor: Array[{kind, pos, variant}]` and `torches: Array[Vector2]`.
Everything comes from **one** `RandomNumberGenerator` seeded with the map seed, so a seed reproduces the map.

### 6.1 Seed
- `map_seed = hash("%d:%s" % [GameSession.path_seed, theme.id])` (a string hash, so it does not depend on how the
  engine hashes arrays or `StringName`s). A path uses each theme at most once, so each map is
  stable for a given path seed, and the same theme in another run (another seed) is a different layout of the same
  character. Tests pass the seed directly.
- The default theme (`legacy_layout`) uses the **legacy fixed seeds** (walls 31, decor 7, pillars 1) and the legacy
  algorithms, so today's map is unchanged byte for byte. The static `CaveWall.layout()`, `CaveDecor.layout()` and
  `main.rock_walls`, which `arena_cave.gd`, `cave.gd` and the hub use, stay as they are; `MapBuilder` also sets
  `main.rock_walls` for every theme. The rules and tests of 6.2 and 12 apply to the eight themes, not to the legacy
  layout, which `arena_cave.gd` and `cave.gd` keep pinned and a test compares with `MapLayout`'s legacy output.

### 6.2 Rules every layout must satisfy (all styles)
- **Spawn clearing:** the start rectangle (the 110 px square around the arena centre, `START_CLEARING`) is free of
  everything. Walls also stay 24 px outside it (as `CaveWall.layout` does today, so 134 px from the centre); pillars and
  decor stay out of the rectangle itself.
- **Rock band:** every wall keeps at least `band + MARGIN` (16 + 56) from the arena edge, as today.
- **No enclosed space:** two walls are at least `GAP_MIN` (40 px) apart, and at least `MARGIN` (56) in SCATTER. The
  Player's collision circle is 5 px and a mob's footprint radius is 6 (ranged) or 7 (grunt, dasher); the hub's dummy
  (8) never moves. So 40 px lets two mobs pass side by side. A wall never touches the rock band.
  Therefore no area of the floor can be sealed off, for the Player or for enemies.
- **Obstacle budget:** `wall_count + pillar_count` is at most 16 (today 14).
- **Pillars:** at least 60 px from the centre, at least `band + 24` from the rock band, and at least 40 px from any
  wall and from any other pillar (no notches or pockets narrower than the 40 px gap rule). Today's pillars only keep
  16 px from walls; the new styles are stricter.
- **Decor** is never on the spawn clearing, a wall or a pillar, and at least 8 px from the rock band.
- Failing to place everything within the try budget (1500 tries for walls) is allowed: fewer walls are placed. The
  tests count what was placed against a floor of 80% of `wall_count`.

### 6.3 Styles
- **SCATTER:** the v0.4 algorithm: pick a length from `wall_lengths`, an orientation by `horizontal_bias`, a random
  position, reject on the rules above. Gap rule: `MARGIN`.
- **LANES:** choose `lane_count` lines across the arena (3 for walls <= 6, 4 above), perpendicular to the dominant
  orientation (`horizontal_bias >= 0.5` means horizontal walls on horizontal lanes), spaced evenly with a jitter
  of up to 24 px. Walls are laid along the lanes in segments with gaps of at least 64 px between segments, so a
  lane is a broken line with openings to cross. The remaining orientation share (`1 - horizontal_bias` for
  horizontal maps) is placed by SCATTER rules as cross pieces. The lane through the spawn clearing is cut around it.
- **CLUSTERS:** choose `ceil(wall_count / 2)` anchor points at least 280 px apart, outside the clearing and the
  band margin. Each anchor receives 2 walls placed roughly parallel or as an L, with 40-56 px between them, to make
  an island of cover. Pillars are placed near anchors (within 90 px) first, the rest by SCATTER rules.

### 6.4 Decor
Decor is placed as in v0.5's `CaveDecor.layout` (about a third hugging the walls, the rest across the floor), but
the kind is picked by the theme's `decor_weights`, and the signature kinds get most of the weight. Decor is drawn
only and has no collision, so it never changes gameplay.

### 6.5 Torches
`torch_count` torches spread along the four rock walls (today 12 and positions are fixed by hand). They are spaced
evenly per side with the seeded jitter, never in the corners (within 40 px).

### 6.6 Obstacles block enemies

Walls (`CaveWall`) and pillars (`Prop`) are both **obstacles** (decided: pillars block enemies as well, not only the
long walls). The Player is already stopped by their `StaticBody2D` colliders. From v0.6 every enemy is stopped by them too, and finds its way round. This applies to **every** arena,
including the default theme (editor runs), so it is a gameplay change as well as a map feature. The rock band was
already respected by enemies (`Enemy.ARENA_PADDING`) and is unchanged.

**Why not physics bodies.** Enemies are plain `Node2D`s moved in code (up to 300 of them, v0.3 performance budget),
with no physics body. That stays. Blocking is done geometrically against the (at most 16) obstacle shapes.

**`ObstacleMap`** (new, pure logic plus a thin node in the arena scene, built by `main.gd` from the `MapLayoutData`):
- Holds the wall rectangles (the footprint of each `CaveWall`) and the pillar circles. A pillar's collider is a circle
  of radius 6 centred **6 px above its base position** (`prop.gd` puts the shape at `(0, -6)`), so the map stores the
  base positions and adds that offset.
- Has a coarse spatial grid (64 px cells) listing which obstacles touch each cell, so a query costs a lookup and a
  test against 0-3 shapes.
- `push_out(pos, radius) -> Vector2`: the nearest position not overlapping any obstacle, for a circle of the given
  radius (rectangle: nearest-point test; circle: distance test). `blocked(pos, radius) -> bool`.
- `segment_clear(a, b, radius) -> bool`: whether a swept circle from `a` to `b` touches no obstacle (used for line of
  sight, section below).

**Enemy movement.** After `Enemy._physics_process` applies velocity, knockback and separation (separation is part of
the velocity), it calls `ObstacleMap.push_out(global_position, data.hitbox_radius)` as the **last position change of
the frame** (the arena clamp and the teleport-back follow it and cannot push an enemy into an obstacle). Knockback into
a wall simply stops there. Because the push is the shortest way out, an enemy pressing on a wall slides along it.

**Getting round obstacles: a flow field.** Pushing out alone leaves a crowd stuck on the wall between it and the
Player, so enemies steer with a flow field:
- `FlowField` (new, pure logic) covers the arena on a 16 px grid (100 x 56 cells). A cell is **blocked when its centre
  lies inside an obstacle grown by 8 px** (not when it merely overlaps one), so a 40 px gap (24 px free after the
  growth) always keeps at least one free cell across it. The same function (`FlowField.cell_blocked`) is used by the
  sealed-area test in 12, so the test checks exactly what runs.
- **Sources.** The search starts from the cells of all living Players. A source cell is always treated as free, even
  if it falls inside the growth zone (a Player may stand 6 px from a wall), and if its neighbours are blocked the
  search starts from the nearest free cell instead. The field is therefore never empty while a Player is alive.
- **Distance, then direction.** A 4-connected breadth-first search over a `PackedInt32Array` fills a walking distance
  per cell. The steering direction is **not stored**: it is found on demand from a cell's 8 neighbours (the lowest
  distance wins; a diagonal is allowed only if both side cells are free, so no corner cutting), and cached per enemy
  with its line-of-sight result.
- **Cost.** One full search is about 5,600 cells, several milliseconds in GDScript, so it is **spread over frames**:
  the search runs in a second buffer, at most 1,000 cell expansions per physics frame, and the finished buffer replaces
  the live one in one step. A new search starts when a Player has entered a different cell and the last one began at
  least 0.25 s ago. Enemies may therefore steer by a field up to about 0.3 s old, which is fine at their speed
  (45 px/s).
- **Straight or flow.** `Enemy.chase()` goes straight at the target (as today) when `segment_clear` says the way is
  open **with a 6 px extra margin** around the enemy's radius, and otherwise moves along the flow direction. To stop
  flip-flopping at a wall corner (straight is clear, drives into the corner, flow pushes away, straight is clear
  again), an enemy that switches to flow **stays on flow for at least 0.5 s**. The line-of-sight result is cached per
  enemy and refreshed every 4th physics frame (like the separation cache). Separation between enemies is applied
  on top as before.
- **Several Players.** The field has all living Players as sources, so it leads each enemy to the Player nearest by
  *walking* distance, while an enemy aiming straight (`PlayerRegistry.nearest()`) aims at the nearest by straight
  distance. The two can differ behind a wall; this is intended: when straight is blocked the field decides.
- With no obstacles (a test arena, the hub) nothing changes: the straight-line path is always clear and the field is
  never built.

**Per enemy type.**
- **Grunt:** uses `chase()`, so it gets the above for free.
- **Ranged:** keeps its distance as today. It fires **only with a clear line of sight** to its target. Its HOLD state
  uses `settle()` today, which cannot steer, so `RangedBrain` gains an **APPROACH** state: from HOLD, when line of
  sight has been lost for 0.3 s (a margin so it does not flicker at a corner) it approaches along the flow field, and
  it returns to HOLD when line of sight is back and it is within `hold_distance`. Its shots still vanish on walls and
  props.
- **Dasher:** it needs a clear line of sight to the target to enter AIM (so it never winds up and dashes into a wall).
  During AIM the lane's length is recomputed each frame as the distance to the first obstacle along the aim, capped at
  `dash_distance` (`DashTelegraph.length` is set once in `setup()` today and becomes a per-frame value), so the
  telegraph is drawn at the shortened length and no hit is possible beyond it. It stops at the obstacle like any
  other enemy, then goes on chasing.
- **Training dummies** (hub) are immovable and unaffected.

**Spawning.** `SpawnDirector.ring_position()` rejects a position for which `ObstacleMap.blocked()` is true for a mob
radius (7), using its existing 8 tries. The ring is only about half the screen diagonal plus 24 px out on a 1600x896
arena, so a rejection can exhaust the tries more often; after the tries it takes the best candidate and
`push_out`s it to the nearest free position, so a spawn or a teleport-back is never lost because of an obstacle (it
still returns null when no candidate is inside the arena, as today).

**Stuck failsafe.** An enemy is "stuck" only when it **asked to move and did not**: its requested speed
(`brain.think` plus knockback, before the push-out) is at least half of `data.speed`, but it has moved less than 2 px
over 3 s, and it is more than 60 px from its target. Holding shooters (HOLD), a Dasher in AIM, LOCK or RECOVER, and
stunned enemies ask for no movement, so they are never counted. A stuck enemy is recycled through the existing
teleport-back (to a ring position near the Player). This covers any case the field misses.

**Not changed.** Player projectiles and abilities still fly over walls and pillars (open question, section 15), and the
Player's own movement and dash are as before. Enemies still do not collide with each other, only separate softly.

## 7. Monster variants

**The rule: same monsters, different appearance.** On every map the three enemy types (grunt, ranged, dasher) have
exactly the same health, speed, contact damage, hitbox, brain, attacks, telegraphs, spawn weights and XP/gold drops as
today. Only how they *look* changes, so frost monsters on the frost map and bone monsters on the bone map, with
nothing for a player to relearn. v0.6 is the foundation: later versions may give a map's monsters different attacks
(7.7), but v0.6 forbids it (the tests in 7.6 enforce it).

### 7.1 Where the line is
The monsters stay the ones that exist today (the drawn grunt, ranged and dasher: a coloured body, an outline and an
eye). A map only gives them a **slightly different look**: a shifted colour and a small extra detail.

| Same on every map (`EnemyData` in `data/enemies/`, untouched) | May differ per map (`MonsterVariant`) |
|---|---|
| `max_health`, `speed`, `contact_damage`, `contact_interval`, `xp_drop` | `body_color`: the type's colour shifted toward the map |
| `hitbox_radius`, `body_size` (the footprint and the silhouette), `brain` | `outline_color` and `eye_color` |
| spawn weights and unlock times, `immovable` | one small `mark` drawn on the body (a stripe, spots or a crest) |
| attack telegraphs (warn blink and colour, dash lane), the white hit flash | |

### 7.2 The `MonsterVariant` resource
One file per map and enemy type at `content/maps/<id>/monsters/<enemy_id>.tres`.

| Field | Meaning |
|---|---|
| `enemy_id` | The `EnemyData.id` it dresses (`grunt`, `ranged`, `dasher`). Equals the file name. |
| `body_color` | The body colour. Starts from the type's base colour and is moved toward the map's colours (7.3). |
| `outline_color`, `eye_color` | The outline (today: the body darkened) and the eye (today: white). Defaults are today's values. |
| `mark` | `NONE`, `STRIPE`, `SPOTS` or `CREST`: one small detail drawn inside or on top of the body rectangle. |
| `mark_color` | Colour of the mark. |

That is all: six appearance fields. There is deliberately **no gameplay field**, and no scale, name or sprite field
either (they can be added when needed: 7.7 and 3.8). The silhouette is the body rectangle from `EnemyData.body_size`,
so it cannot change.

### 7.3 The looks
Each map shifts the three base colours toward its own palette and adds one small mark. Base colours today: grunt red
(`0.8, 0.25, 0.25`), ranged green (`0.3, 0.72, 0.5`), dasher violet (`0.62, 0.36, 0.86`). Exact values live in the
`.tres` files; this table is the intent.

| Map | Colour shift (all three types move this way) | Mark | Example: the grunt becomes |
|---|---|---|---|
| Mossy Hollow | toward olive and moss green | `SPOTS` (lichen) | Moss Crawler, olive |
| Crystal Vault | toward cyan and blue | `CREST` (crystal) | Shard Walker, cyan |
| Ember Depths | toward orange and dark red | `STRIPE` (glowing) | Cinder Imp, ember orange |
| Frostbite Grotto | toward pale and steel blue | `CREST` (frost) | Frost Ghoul, pale blue |
| Spore Cavern | toward purple and magenta | `SPOTS` (spores) | Fungal Shambler, purple |
| Bone Warren | toward bone white and tan | `STRIPE` (ribs) | Skeleton, bone white |
| Flooded Gallery | toward teal and blue-grey | `STRIPE` (wet sheen) | Drowned, teal-grey |
| Sulfur Pits | toward yellow and ochre | `SPOTS` (crust) | Sulfur Imp, yellow |

Within one map the three types still differ from each other: the shift keeps each type's own lightness and a hue
offset between them, so a map's grunt, ranged and dasher are three related but distinct colours. There are 24
variant files (8 maps x 3 types).

### 7.4 Readability rules (what keeps it fair)
A themed monster must still be read at a glance in a crowd of 300:
- **Same silhouette per type.** Body size and proportions come from the type's `EnemyData`; a variant only recolours,
  adds one mark. Types are told apart by size and colour as today.
- **Contrast with the floor.** A variant's `body_color` is at least **0.12** from each of its own map's four
  `floor_plain` colours, and at least 0.12 from `floor_dark` and `floor_light`, where the distance is the Euclidean
  distance in the OKLab colour space (lightness 0..1), so monsters never vanish into the ground.
- **The three types differ from each other** on a map by an OKLab distance of at least 0.08.
- **Danger signals are not themed.** The warn blink and `!` marker, the dash lane telegraph and its colours, the white
  hit flash and the dim after an attack are the same on every map, so an attack reads the same everywhere.
- **No new animation or cost.** The mark is drawn into the existing body, which already redraws only on change.

### 7.5 How a variant is applied
- `SpawnDirector.apply_stage(data)` keeps its signature: the theme is `data.theme` (`StageData` carries it), so the
  existing tests that call `apply_stage` are unchanged. When the director creates an enemy (`_acquire`) it calls
  `enemy.apply_variant(stage.theme.variant_for(type.id))` **after** the enemy has entered the tree, because
  `Enemy._ready` sets the sprite colour and size from `data` and the variant must be applied over that.
- `Enemy.apply_variant()` hands the colours and the mark to its `PlaceholderSprite` (which gains `outline_color`,
  `eye_color`, `mark` and `mark_color`; the defaults reproduce today's look). The death puff, which uses
  `data.body_color` today (`Enemy._on_died`), uses the sprite's current body colour instead.
- It does **not** touch `data`, the hitbox, the brain or the health: the `EnemyData` instance stays the shared
  resource.
- The enemy pools are per stage (a new arena is built each stage), so a pooled enemy is never re-dressed.
- `variant_for()` returns null for an id the theme has no variant for (the default theme has none); the enemy then
  looks as it does today.
- The hub's training dummies are not dressed (no theme there).

### 7.6 Tests (`tests/maps/monster_variants.gd`)
- **Coverage:** every one of the eight maps has a variant for every enemy type the director can spawn, `enemy_id` equals
  the file name, and no map has a variant for an unknown type.
- **Same behaviour:** an enemy built under each theme has the same `EnemyData` object, hitbox radius, brain class,
  speed, health, damage, contact interval and spawn weight as the same type under the default theme; and a variant
  resource has no exported field beyond the appearance list in 7.2 (the test fails when a gameplay field appears without
  its own rule, as the guard for 7.7).
- **Readability:** the OKLab distances of 7.4 (floor and between types); danger-signal colours read from one place,
  unchanged by a variant.
- **Applied:** in a built arena the sprite of a spawned enemy shows the variant's colours and mark, the death puff
  colour is the variant's body colour, and the hub dummies and the default theme are unchanged.

### 7.7 Later: different attacks per map
The plan, so nothing built now has to be undone: a variant file is already **per map and per enemy type**, so
behaviour differences are new exported fields on `MonsterVariant` (for example stat multipliers, a different
`brain` script or attack parameters), applied by `Enemy.apply_variant()` next to the appearance. v0.6 only reserves
the idea: no such field exists, and the 7.6 guard test is updated together with the first one, so a gameplay field can
only enter through a deliberate change to the rule above.

## 8. The look

All values come from the theme; the code stops using hard-coded colours (listed in 8.1). The classes involved
(`Ground`, `CaveWalls`, `CaveWall`, `Prop`, `CaveDecor`) take an **optional** theme: with none they use today's
constants, so the hub, which uses `Ground`, `CaveWalls` and `CaveDecor` (`hub.gd`), is unchanged.

### 8.1 What changes from constants to theme values
| Drawn by | Today | v0.6 |
|---|---|---|
| `Ground._build_dirt` | `DIRT_PLAIN`, `DIRT_DARK`, `DIRT_LIGHT` consts, `DIRT_SEED` | the theme's `floor_*`; the floor seed is the map seed (default theme: `DIRT_SEED`) |
| `CaveWalls` | `ROCK`, `ROCK_DARK`, `ROCK_LIGHT` | `rock`, `rock_dark`, `rock_light` |
| `CaveWalls.TorchGlow` | orange flame and halo | `torch_color`, `glow_color` |
| `CaveWall` | `TOP`, `TOP_LIGHT`, `SIDE`, `OUTLINE` | `wall_top` ... `wall_outline` |
| `Prop._draw` | `5c5248` | `pillar` |
| `main.tscn` vignette | gradient alpha 0.62 | `vignette` |

### 8.2 Floor
Same tile system and the 8 tile variants, only recoloured, plus per-theme **patches**: the noise that picks dark
tiles uses the theme's `floor_dark`. `floor_flecks` sets how many tiles are pebbled or cracked.

### 8.3 Rock
The rock band and the slabs use the theme colours. Silhouettes stay the same (v0.4 section 15), so collisions and
the spawn ring are untouched.

### 8.4 New decor kinds (drawn only, in `CaveDecor`)
Existing: `STALAGMITE, ROCK, PEBBLES, BONES, MUSHROOM`. New:

| Kind | Look | Used by |
|---|---|---|
| `MOSS` | A flat green-brown patch with a few blades | Mossy Hollow |
| `CRYSTAL` | A 2-3 spike cluster, cyan or violet, with a soft additive glow | Crystal Vault, Spore Cavern |
| `ICICLE` | A tall pale-blue pointed shard, a stalagmite variant | Frostbite Grotto |
| `FROST` | A flat white-blue patch | Frostbite Grotto |
| `BIG_FUNGUS` | A tall stalk and a wide cap, violet, glowing | Spore Cavern |
| `PUDDLE` | A flat blue ellipse with a still ripple ring | Flooded Gallery |
| `VENT` | A rock ring with a thin rising steam wisp | Sulfur Pits |
| `CRACK` | A glowing jagged line on the floor | Ember Depths |

`CaveDecor.Kind` gets the new values appended (existing ones keep their numbers). Each kind draws with the theme's
colours where it has one (`glow_color`), so the same kind reads right on two maps. No decor animates in v0.6.

### 8.5 Ambient tint
`ambient` is applied by a `CanvasModulate` in the arena scene. The HUD, menus and the vignette sit on the `UI`
`CanvasLayer`, so they are not tinted, but everything in the world is: enemies, projectiles, damage numbers, torch
halos and the white hit flash (which becomes very slightly tinted; accepted). It stays close to white (each channel at
least 0.8) so they keep their contrast. Ember Depths
leans warm, Frostbite and Crystal Vault cool, the others near neutral.

## 9. Wiring

- **`MapBuilder`** (`scripts/maps/map_builder.gd`, new) turns a `MapTheme` and a seed into an arena: it calls
  `MapLayout.generate(...)` and builds the ground, rock band, walls, pillars, decor, torches, ambient tint and the
  `ObstacleMap` into given nodes, and returns the `MapLayoutData`. `main.gd`'s `_build_cave()` and `_spawn_props()` are
  replaced by one call to it (with the stage's theme, or the default theme with no stage), and the map preview scene
  (3.6) calls the same function.
- `StageData` gains `theme` (the `MapTheme`). The v0.5 fields `name` and `thumbnail` stay, set from the theme by
  `PathGenerator`. `SpawnDirector.apply_stage(data)` reads the theme from `data.theme` (section 7.5).
- `Ground`, `CaveWalls`, `CaveWall`, `Prop` and `CaveDecor` take their colours from an optional theme through an
  exported `theme` or a `setup(theme)` call before `_ready` (null: today's constants). None of them reads
  `GameSession`.
- `GameSession` is unchanged except that the map seed is derived on demand: `GameSession.map_seed()` (null-safe).
- `main.gd` builds an `ObstacleMap` from the layout and gives it to the `SpawnDirector` and to every `Enemy`
  (through the director, as it already gives `enemies_root`). A scene with no `ObstacleMap` (the hub) has none and
  enemies behave as before.
- `Enemy` gains the `push_out` call and a flow/line-of-sight step in `chase()`; `RangedBrain` and `DasherBrain` gain
  the line-of-sight and dash-cut rules above. `FlowField` is owned by the `ObstacleMap` node and rebuilt from
  `PlayerRegistry` positions.
- The hub and `select.tscn` keep using the default dirt look.

## 10. Thumbnails stay in sync

The eight thumbnails come from `tools/maps/gen_thumbnails.py` (moved from `tools/gen_stage_thumbs.py`, writing into
each map's folder), whose `THEMES` table holds a rock, floor and glow colour per map id. Those colours are the source
of truth: each `content/maps/<id>/map.tres` takes the same values for the matching fields (`rock`, `floor_plain[0]`,
`glow_color`), and then adds the rest of the palette around them.

- A test loads each map's `thumbnail.png` and its theme, and checks that the thumbnail's **average colour** is within a
  tolerance of the theme's `floor_plain[0]` / `rock` blend (section 12). This stops a theme and its thumbnail
  drifting apart when someone tweaks one.
- The thumbnails are regenerated (`tools/maps/gen_thumbnails.py`) so each shows the map's signature: moss, crystal,
  embers, frost, spores, bones, water, steam. Optionally with the theme's real obstacle silhouettes drawn in. The
  size (64x40) does not change, and the select screen reads `StageData.thumbnail` as before, so it is untouched.

## 11. Compatibility

- Default theme output equals today's arena layout and look: `tests/arena_cave.gd` and `tests/cave.gd` pass
  unchanged against it. What does change in the default arena is that enemies are now blocked by its walls and pillars
  (section 6.6).
- `tests/crowd_performance.gd` is not edited. It keeps its stationary Player and its existing mean-frame limit and
  runs in the default arena, which now has obstacles in the enemies' way (enemies it spawns inside an obstacle are
  pushed out). A new **`tests/maps/crowd_bone_warren.gd`** runs the same 300-enemy scenario on the densest layout (Bone
  Warren) in two variants: a stationary Player and a **moving** Player (a circle), because the flow field only
  rebuilds when the Player moves. Both have a hard gate at the existing limit and also log the worst single frame
  and the mean with and without obstacles (a log-only A/B: headless timing is too noisy for a fixed "0.5 ms" gate).
- No new physics layers. Decor and ambient are drawn only. Enemy blocking adds, per physics frame at 300 enemies, one
  `push_out` each (a grid lookup and 0-3 shape tests), a cached line-of-sight test and a flow-field search spread over
  frames (6.6).
- The legacy entry points stay (`CaveWall.layout`, `CaveDecor.layout`, `main.rock_walls`; 6.1), and `Ground`,
  `CaveWalls` and `CaveDecor` keep working without a theme, because the hub uses them.
- `MapTheme`, `MonsterVariant` and `MapLayoutData` are plain data; nothing is saved to disk.
- Enemy numbers are untouched, so `dasher_lane.gd`, `wizard_abilities.gd` and the other ability tests see the same
  monsters (they use the default theme, which has no variants).

## 12. Tests

Randomised tests run over 30 seeds (the v0.5 convention; `SEED_COUNT` is one constant). The tests v0.6 adds live in
`tests/maps/` (`run_all.sh` and the tests README are updated to include that folder); the existing ones stay where
they are.

- `map_content.gd`: the folder and registry checks of 3.4 (folders vs registry, required files, thumbnail size, id equals
  folder, unique display names, a variant for every enemy type, no stray files), also run on `_template` and `_default`.

- `map_layout.gd` (pure logic), for every theme and seed:
  - the spawn clearing is free; walls stay inside the rock band margin; walls do not overlap and respect the gap
    rule of their style; pillars are 16 px from walls and 60 px from the centre; `walls + pillars <= 16`;
  - at least 80% of `wall_count` is placed; lengths come from the theme's `wall_lengths`;
  - **no sealed area:** a flood fill over the same 16 px grid and with the same blocking rule as `FlowField`
    (`FlowField.cell_blocked`: centre inside an obstacle grown by 8 px) reaches at least 99% of the free cells from the
    arena centre, and **every gap between two obstacles keeps at least one free cell across it** (so a few sealed
    passages cannot hide in the 1% slack);
  - the same seed gives the same layout and a different seed a different one;
  - decor avoids walls, pillars and the clearing, and uses only kinds that have a weight in the theme.
- `obstacle_blocking.gd` (arena scene, hand-placed obstacles and fixed enemies):
  - an enemy driven into a wall or a pillar ends outside it, for each enemy type, and one pushed at 45 degrees into a
    long wall for 1 s ends at least 20 px along it, not where it started;
  - knockback into a wall stops at the wall;
  - a grunt on the far side of a long wall reaches the Player (in a bounded time) by going round the wall, and
    arrives from the open end, not through the wall;
  - 20 grunts spawned behind a lane wall all reach the Player;
  - a Ranged enemy with a wall between it and the Player fires nothing, and fires once the line is clear; its shot
    vanishes on a wall;
  - a Dasher's lane is shortened at a wall and it never ends a dash inside one;
  - spawn and teleport-back positions are never inside an obstacle (over 30 seeds);
  - the flow field: a path exists from every free cell, distances fall toward the Player, a search is not started
    again within 0.25 s or when the Player has not changed cell, a Player standing 6 px from a wall still gets a
    non-empty field, and no physics frame does more than 1,000 cell expansions;
  - a holding Ranged enemy, a Dasher in AIM and a stunned enemy are never recycled by the stuck failsafe, and an enemy
    that is asked to move but cannot is;
  - near a wall corner an enemy does not alternate straight and flow more than once per 0.5 s;
  - the Dasher does not enter AIM without line of sight; the Ranged enemy approaches when it loses line of sight and
    returns to HOLD when it regains it;
  - the hub (no `ObstacleMap`) is unchanged.
- `map_themes.gd`: every theme has a unique id equal to its folder and a loadable thumbnail; its colours are in range;
  `ambient` channels are at least 0.8; every theme differs from every other in at least its rock and floor colours
  (an OKLab distance of at least 0.05) and in its `(style, wall_count)` or `decor_weights`; thumbnail average colour
  is close to the theme (section 10).
- New tests that name the new `class_name` types (`MapTheme`, `MonsterVariant`, ...) use `preload`, as
  `tests/path_generator.gd` does, so they also work before the class-name cache exists.
- `map_build.gd` (scene level): for each theme, build `main.tscn` with a `StageData` of that theme and check that
  the wall count and pillar count equal the layout, that the Player and an enemy still move and collide normally,
  that the theme colour reached the `CaveWalls` and the floor, and that `MapBuilder` called by the preview scene
  gives the same layout as a run for the same theme and seed.
- `path_generator.gd` is extended: every stage's `name` and `thumbnail` equal its theme's `display_name` and
  `thumbnail`, and the 7 stages of a path use 7 different themes.
- `monster_variants.gd`: section 7.6.
- `stage_flow.gd` and `select_screen.gd` stay green (no UI change). The existing ability and enemy tests
  (`dasher_lane.gd`, `wizard_abilities.gd`, ...) run in arenas with the default theme, and any that depended on an
  enemy walking through a wall are adjusted as part of step 4 below, which ends with a full `run_all.sh` and a list of
  the tests that needed changes (written into the decision log of that step).
- Rendering is not covered by tests. `tools/maps/shot_maps.gd` (section 13) renders each map for review.

## 13. Tools

`tools/maps/shot_maps.gd`: a scene-less script run with `godot --path . --script tools/maps/shot_maps.gd -- <folder>` that, for each theme,
builds the arena with a fixed seed, saves one PNG per map to a folder given on the command line, and then writes
one contact sheet (8 maps in a 4x2 grid) so all eight can be compared at a glance. It shows the monster variants
too (a row of the three types per map). It builds its arenas through `MapBuilder`, like everything else. Used for the review and kept in the repo, with `gen_thumbnails.py` and `new_map.py`
in the same `tools/maps/` folder.

## 14. Build order

1. **Directory and data** (sections 3 and 4), in this order: `MapTheme` (identity and palette fields first), then
   `MapRegistry`; create `content/maps/` with `_default`, `_template` and the eight map folders; only then move the
   thumbnails and the generator (3.7: `git mv`, re-import, export filters, `run_all.sh`); `PathGenerator` reads
   `MapRegistry`; `map_content.gd`, `map_themes.gd` and the updated `path_generator.gd`. The v0.5 select screen shows the
   same cards as before.
2. `MapLayout.generate` with SCATTER first and the default theme (`legacy_layout`, calling the existing code);
   `map_layout.gd` with the legality, seed and flood-fill tests for the eight themes, plus a test that the legacy
   output equals today's.
3. LANES and CLUSTERS and the rest of the rules and tests.
4. Obstacles block enemies (section 6.6): `ObstacleMap`, `push_out`, the director's spawn rule, then `FlowField` (with
   the frame budget) and `chase()`, then the Ranged and Dasher rules and the stuck failsafe; `obstacle_blocking.gd`
   and `crowd_bone_warren.gd`; the full suite, fixing what breaks. Built on the default theme first, so it can be
   reviewed on its own.
5. Look: `Ground`, `CaveWalls`, `CaveWall`, `Prop` and the vignette take an optional theme (null: today's values, so the
   hub is unaffected); the new decor kinds; `CanvasModulate` ambient. Existing cave tests stay green on the default
   theme.
6. `MapBuilder` and wiring: `StageData.theme`, `main.gd` calls the builder, `SpawnDirector` gets the theme; `map_build.gd`.
7. **Monster variants** (section 7): `MonsterVariant`, `PlaceholderSprite` marks and colours, `Enemy.apply_variant`, the 24 variant
   files; `monster_variants.gd`.
8. **Tools and workbench** (sections 3.5, 3.6, 13): `new_map.py`, `scenes/dev/map_preview.tscn`, `tools/maps/shot_maps.gd`,
   `content/maps/README.md`.
9. Regenerate the thumbnails to show each map's signature (`gen_thumbnails.py`); add the thumbnail-colour test.
10. Render all eight maps and their monsters, review by eye, tune the numbers (section 15), rerun `crowd_bone_warren.gd`
    and play each map to check that enemies path sensibly.

## 15. Open questions / assumptions to revisit

- **Layout numbers are a first guess.** Wall counts, lengths and the 16-obstacle budget will want tuning after
  playing the maps.
- **Player projectiles and abilities pass over walls.** Enemy shots already vanish on walls; the Player's bolts,
  meteors and chain lightning ignore them, so the Player can shoot an enemy that is stuck behind a wall. Fine for now
  (it rewards using cover), but it may want line-of-sight rules later.
- **Monster art.** The variants are today's drawn stand-ins, recoloured with a small mark. Real sprites would add a
  `sprite_frames` field (as `CharacterData` has) and a `sprites/` folder in the map; who draws them and when is open.
- **Behaviour per map (7.7).** Deliberately not in v0.6. The first time a map's monsters get a different attack, the
  variant resource gains fields and the "same behaviour" test is updated with it.
- **Does the preview scene belong in the repo's `scenes/`?** It is excluded from exported builds; move it to a
  `tools`-style folder if it ever causes confusion.
- **Crowds behind walls.** Enemies do not collide with each other, only separate softly, so a crowd can stack at a
  wall opening. Revisit if that reads badly or hurts the performance numbers.
- **Flow field cost and accuracy.** The 16 px grid, the 0.25 s rebuild interval and the 1,000 expansions per frame are
  a first guess; if enemies cut corners visibly or lag behind a fast-moving Player, refine them.
- **Same theme at two difficulties.** The tier does not change the look. Revisit if players cannot tell an Easy
  from a Hard version of one place (for example a tier tint).
- **Hazards.** Lava, water and ice map naturally to Ember Depths, Flooded Gallery and Frostbite Grotto but are out
  of scope until a hazard system exists. The decor kinds are chosen so the hazard could later sit under them.
- **Per-map music and ambience.** Out of scope; sounds are shared.
- **A ninth map or fewer than 7 per path.** A path always draws 7 of the 8 themes. If more themes are added, the
  generator already works with any pool of at least 7.
- **Arena size per map.** Kept at 1600x896 for all. A smaller "tight" or larger "open" arena needs the spawn ring
  and performance numbers re-checked.

## 16. Definition of Done for v0.6

- Everything about a map is in `content/maps/<id>/`; `assets/stages/` does not exist; adding a ninth
  map with `tools/maps/new_map.py` produces a playable, test-passing map without editing any code except the one
  registry line the script adds.
- On each map the grunt, ranged and dasher are today's monsters in a slightly different look that fits that map (frost monsters on
  the frost map: a shifted colour and one small mark), keep their own silhouette and the unchanged warn and telegraph signals, and behave **exactly** as on every other map.
- Each of the eight stages opens an arena whose floor, rock, walls, decor, light and ambient match the thumbnail on
  its card. The same stage on another run (another path seed) has the same theme with a different layout.
- The eight maps are visibly different in a side-by-side render (`tools/maps/shot_maps.gd`): colour, decor and obstacle
  layout, and the layout style (lanes, clusters, scatter) is recognisable.
- Every layout satisfies the rules in 6.2 over 30 seeds per theme, including that no part of the floor is sealed off
  and no gap between obstacles is narrower than 40 px.
- A theme's tier and modifiers (v0.5) still apply as before and are independent of it.
- With no stage (editor) the arena is today's cave layout and look, unchanged: `arena_cave.gd`, `cave.gd` and
  `crowd_performance.gd` pass without edits.
- Walls and pillars block enemies as well as the Player, in every arena including the default one: enemies cannot
  enter them, slide along them and walk round them to reach the Player; Ranged enemies do not fire through them; a
  Dasher's lane stops at them; nothing spawns inside them.
- The crowd performance test passes with obstacles in the enemies' way, and `crowd_bone_warren.gd` passes on the
  densest layout with a stationary and a moving Player, both within the existing frame limit.
- A fresh clone passes `tests/run_all.sh` (the runner imports first), and exported builds exclude the workbench, tools,
  tests and the template.
- Tests pass: `map_content.gd`, `map_themes.gd`, `map_layout.gd`, `map_build.gd`, `monster_variants.gd`,
  `obstacle_blocking.gd` and the existing suite.
- `main.tscn` still launches directly from the editor.
