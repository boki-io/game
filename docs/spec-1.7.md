# Spec v1.7: Nature props for the green zone (trees, rocks and shrubs in the overworld's first zone)

Builds on the overworld (spec 1.6: `WorldData`, `WorldTerrain` chunk streaming, `OverworldRules`, `TerrainArt`, the markers) and the art in `/Users/bok/Documents/game-characters/Nature` ("the Nature pack"). Branch `spec-1.7-nature`, based on `spec-1.6-overworld` at `43cd28d` (the overworld PR is not merged yet, so this work stacks on it). Status: draft; rev 2 (applies an independent review: props could not y-sort inside the chunk nodes, per-rule seeded streams instead of "draw everything", densities scaled by walkable tiles, no random scale on pre-scaled sprites, a structural sort test, a pixel-level `--check`, a mandatory cell cache, signal wiring, a clearer `nature_reach`, a bigger big-rock collider).

Terms: the **green zone** is zone 0, `mossy_hollow` (59,833 walkable tiles in the x 0 to 1003, y 1539 to 1988 box; 10,432 of them are dirt path). A **prop** is one placed nature sprite (a tree, a rock or a shrub). A **clump** is a group of props of one kind placed together (a small forest, a rock pile, a shrub patch). A **loner** is a prop placed on its own. A **placement** is the pure data for one prop: kind, sprite index, base position, scale, flip.

## Flow

You walk the green zone and it no longer looks like an empty lawn. Lone trees stand here and there; in some places they bunch into small woods of five to twelve trees with shrubs at their feet; rocks sit alone or in piles; shrub patches line the edges of the path. The dirt path stays clear, the camps, checkpoints, gates and cave mouths stand in open ground, and you can always walk from the start camp to every marker in the zone. Trunks and big rocks stop you; small rocks and shrubs do not. You walk behind a tree (its canopy draws over you) and in front of it by your feet's height. Nothing is saved: the layout is the same every time, because it comes from fixed seeds and the map.

## 1. Scope

In scope:
- Slicing the Nature pack into three atlases plus a manifest (section 2).
- A pure, seeded layout of props for a chunk, with clumps and loners (sections 3 and 4).
- Drawing props y-sorted with the player and the markers, trunk and big-rock colliders (section 5).
- Streaming with the terrain chunks (section 6), tuning as data (section 7), tests and docs (sections 9 and 10).

Out of scope (later specs): props in zones 1 to 7 (the system is per-zone data so they can be added, section 7); seasonal or per-zone recolours beyond choosing the right tint variants; props that react (sway, rustle, being destroyed, hiding enemies); loot or resources from props; bones, mushrooms, ruins and other non-Nature-pack props; ambient wind or sound; a tree-top fade (the canopy simply overlaps the player); the art of markers (still code-drawn placeholders).

## 2. The assets and the atlas tool

What is in the Nature pack (measured):
- `treeeeeee.png`, 1248 x 912, one sheet of about 39 trees, not on a grid. Each is 80 to 215 px tall and 80 to 190 px wide (two spots are two overlapping trees, one is a 346 px wide pair). Colour groups: greens (broadleaf, dark-green firs), yellow, orange and red autumn trees.
- `Rock Pile - Spritesheet.png`, 510 x 2550: a regular grid of 85 x 85 cells, 6 columns (grey, blue grey, dark blue, warm grey, brown, olive) by 30 rows (30 rock and pebble shapes, from a few pebbles to a 80 px slab pile).
- `Bush 1` to `Bush 15`: one PNG per colour (GREEN, YELLOWISH GREEN, YELLOW, RED, TEAL), 17 to 90 px wide, 16 to 32 px tall, already trimmed.

The tool `tools/overworld/build_nature_atlas.py` (`[source_dir] [--check]`, default the path above, like `build_terrain_masks.py`; Python 3 with numpy and no other dependency, with its own small PNG reader and writer because Pillow is not installed on this machine) does the slicing and writes:
- `assets/nature/trees.png`, `assets/nature/rocks.png`, `assets/nature/shrubs.png`: each sprite trimmed to its opaque bounds, packed with 1 px transparent padding, in one atlas per kind (a few Godot imports; y-sorting interleaves kinds, so draws batch only per run of one kind, which is fine at this count). The output is deterministic (sprites in sorted order, fixed PNG filter bytes).
- `content/overworld/nature/sprites.json`: the manifest, `{"trees": [...], "rocks": [...], "shrubs": [...]}`; each entry `{id, region [x, y, w, h], anchor [x, y], tags}`. `anchor` is the base point inside the region: for a tree the trunk foot, for a rock or shrub the bottom centre. `tags` are strings the layout filters by (below).
- `--check` rebuilds in memory and exits 1 if the decoded RGBA pixels of the committed atlases or the manifest JSON differ (not the PNG bytes: zlib output varies between versions).

Sprite detection and choice:
- **Trees:** found by connected components of the alpha channel after growing it by 4 px (so scattered leaf pixels join one tree); overlapping pairs are split by a small table in the tool (`TREE_SPLITS`, a list of source rects) after the contact-sheet check below. The trunk foot is the mean x of the opaque pixels in the lowest 6 rows and the lowest opaque y; an entry in `TREE_ANCHOR_FIX` (by index) overrides a bad guess (firs, whose lowest pixels are drooping needles). Tags are derived from the average colour of the opaque pixels: `green`, `fir` (dark green with a width greater than its height), `autumn` (yellow, orange or red); and from the height: `tall` (taller than 160 px) or `short`.
- **Rocks:** cells (row, column) for columns 1 (grey), 4 (warm grey) and 6 (olive) only (the blue and brown columns belong to later zones); each trimmed and tagged by trimmed width: `pebbles` (under 30 px), `small` (30 to 54), `big` (55 and wider). The tool also has `PILE_PEBBLE_ROWS`, a list of row indices whose shapes are pebble scatters; their entries get the tag `pile_pebbles`, and piles draw their companions from that tag plus `small`.
- **Shrubs:** `Bush 1` to `Bush 15` in GREEN and YELLOWISH GREEN; tagged `small` (under 30 px wide) or `wide` (30 and over).

The packing and the detection are reviewed by eye, not just by test: the tool also writes `<scratchpad>/nature_contact.png` (not committed; its path is printed) with every sprite and its anchor marked, and the build step looks at it and fixes the split and anchor tables until every tree is single and its anchor is on the trunk foot. The generated files are committed. The source pack stays outside the repo, like the map data (the guide's art and `art/source/overworld`).

## 3. The layout: `NatureLayout` (`scripts/overworld/nature_layout.gd`)

A `RefCounted` with static functions only, no nodes, so it is fast to test and reproducible from its seed. It reads `WorldData`, the `NatureRules` resource (section 7) and the sprite manifest (through `NatureSprites`, section 5).

`props_for_chunk(world, rules, sprites, chunk) -> Array[Placement]` returns every placement whose **base position** is inside the chunk's 32 x 32 tile square, in a stable order. It is a pure function of its arguments.

**Cells.** The world is cut into layout cells of `cell_tiles` (32, equal to a chunk) tiles. For a chunk it builds the placements of its own cell and its eight neighbours (a clump can lean over a chunk border), then keeps those whose base is inside the chunk. Each cell and each **rule** below has its own `RandomNumberGenerator` seeded with an explicit integer mix of `(rules.seed, cell.x, cell.y, rule_id)` (the same style as `WorldTerrain.tile_hash`; not `hash([..])`, which is not guaranteed stable across engine versions, and never the global RNG). The rule streams are therefore independent by construction: tuning one rule, or a rule using more draws because of rejections, never moves the props of another. A prop also does not depend on which chunk is built first or how often. Duplicates cannot happen: a placement belongs to exactly one chunk, the one holding its base.

**Density follows the open ground.** Only about 13 % of the tiles in the zone's box are walkable and they are unevenly spread (about 440 cells touch the box, with very different amounts of open ground). Every count and chance below is therefore multiplied by the cell's `open` factor, its walkable zone-0 tile count divided by `cell_tiles` squared (precomputed once per cell, cached); a cell with no walkable zone-0 tile produces nothing. The numbers in brackets are for a fully open cell.

**What a cell produces, in this order** (every number is data, section 7; defaults in brackets):
1. **Woods.** With probability `wood_chance` (0.22) the cell holds one wood. Its centre is a random walkable tile of the cell (a few tries; if none passes the checks below, no wood). The wood has `wood_trees` (5 to 12) trees scattered in a disc of radius `wood_radius_tiles` (3 to 6): positions are drawn by **Poisson-disc sampling** with a minimum spacing `tree_spacing_px` (28 px, so crowns overlap but trunks do not touch), denser toward the centre (the radius is `r * sqrt(u)` biased by `centre_bias`), so it looks grown, not a grid. Within a wood the sprites are drawn from one **species group** picked per wood (a mostly `green` wood, a `fir` wood, or a mixed wood) so a wood is coherent, and the largest trees go near the centre. A wood also places `wood_shrubs` (2 to 6) shrubs on its rim and `wood_rocks` (0 to 2) small rocks.
2. **Loner trees.** `loner_trees` (0 to 3) single trees at random walkable tiles of the cell, each with a clear radius `loner_clear_tiles` (4) around it from other trees so loners really stand alone.
3. **Rock piles.** With probability `rock_pile_chance` (0.16) a pile: one `big` rock (when available) surrounded by `pile_rocks` (2 to 5) `small` and `pebbles`, within `pile_radius_tiles` (2). A pile is placed at least `pile_edge_tiles` (3) from blocked terrain, so it reads as a boulder in the meadow, not part of the wall.
4. **Loner rocks.** `loner_rocks` (0 to 2): single `small` or `pebbles` rocks.
5. **Shrub patches.** `shrub_patches` (0 to 3) patches of `patch_shrubs` (2 to 5) shrubs of one colour, in a disc of `patch_radius_tiles` (2); in addition, with probability `path_shrub_chance` (0.5), one patch is placed beside the dirt path (on a walkable, non-path tile with a path tile within 3 tiles), so the road has bushes along its sides.

Counts are rounded stochastically from the rule's own stream (a count of 1.4 is 1 or 2), so a half-open cell gets half the props on average.

**Rules every placement must pass** (a failing candidate is dropped, not moved):
- The base tile is walkable (`collision` > 127) and its zone is 0 (`rules.zone`).
- The base tile is not on the dirt path and has no path tile within `path_clear_tiles` (2) for trees and big rocks (shrubs and pebbles may stand at the path's edge, path tile adjacent is allowed, on the path itself is not).
- No blocked tile within `wall_clear_tiles` (2) for trees and big rocks, `1` for small rocks and shrubs, so a trunk never fuses with the forest wall, and passages are not narrowed to nothing.
- Outside every marker's clearing: `marker_clear_tiles` (14, the guide's safe radius, `OverworldRules.SAFE_RADIUS_TILES`) from `start_camp`, `checkpoint`, `gate` and `camp` markers, and `marker_clear_tiles / 2` (7) for the other kinds, measured from the marker's world position (`WorldData.marker_world`). A gate's gap runs across its (nx, ny); the clearing is a circle of that radius, which is at least the gap's half-width of 5 to 10 tiles.
- No overlap rule between trees except the spacing above; a shrub or rock may overlap a tree's canopy (it is at the tree's foot) but not its trunk collider (its base is at least 8 px from a tree base, `trunk_radius_px` plus a margin).
- The count of props in one chunk is capped at `max_props_per_chunk` (160), applied after the cells are merged in a fixed cell order and each cell's rules in a fixed rule order; the cap drops the last placements.

A `Placement` is a small `RefCounted` or inner class with `kind` (`tree`, `rock`, `shrub`), `sprite` (index into that kind's manifest list), `base` (world px, the foot), `flip`, `solid_radius` (0 if walkable). Sprite and flip come from the placing rule's stream; there is no random scale (section 5).

## 4. How it should look (and the tests that stand for it)

The user's wish: trees feel natural, some stand alone, others are bunched into small forests, same for rocks. Concretely, over the whole green zone (test and eyeballed from a render):
- 35 to 60 % of trees belong to a wood, 40 to 65 % are loners or in a loner pair (a tree is "in a wood" when it has at least 3 other trees within 6 tiles). Clumps of 5 or more trees exist in at least 20 places.
- Tree count is 8 to 18 per 1,000 walkable tiles (a rough 480 to 1,080 trees in the zone's 59,833 walkable tiles, so a 640 x 360 view of open ground, about 900 tiles, shows about 7 to 16 trees). The per-cell `open` scaling is what keeps this true on narrow stretches and wide meadows alike.
- Rocks: at least 15 rock piles; 30 to 60 % of rocks belong to a pile.
- Shrubs: at least a quarter sit within 3 tiles of the dirt path.
- The first screen the player sees at the start camp has no prop closer than 14 tiles to the camp marker.

These ranges are first-pass numbers for the first draw of the rules; the build step renders a few real frames (the camp, a wood, a pile, the road) to check feel, then tunes the data and writes the final values into this spec's build notes.

## 5. Drawing, sorting and collision

New files (section 8): `NatureSprites` (loads the atlases and the manifest once; `region(kind, i)`, `anchor(kind, i)`, `texture(kind)`, lists by tag), `WorldProps` (the nodes).

- **Scale.** The hero is a 32 px sprite, so trees are shown at 0.4 of the source (about 32 to 86 px tall: two or three heroes high), rocks at 0.5 (about 5 to 40 px) and shrubs at 0.7 (about 12 to 63 px wide). Scaled pixel art blurs, so the atlas tool pre-scales: `trees.png` is built at `--tree-scale` (default 0.4), `rocks.png` at `--rock-scale` (0.5) and `shrubs.png` at `--shrub-scale` (0.7) with a box filter, and the manifest header records `{"scales": {...}}`. At runtime every sprite is drawn at scale 1 (or -1 in x for a flip): no random scale, since a non-integer nearest scale would bring the blur back; variety comes from the sprite choice and the flip. `NatureRules` holds no scale; `NatureSprites` exposes the manifest's. A box-filtered 0.4 downscale is soft by nature (O3), so step 1 looks at a rendered frame before the assets are committed, and the tool may switch to nearest sampling.
- **Nodes.** `WorldProps` is the node `World/Props`, a `Node2D` with `y_sort_enabled = true`, placed in `scenes/overworld.tscn` before `Markers` and `Players` (siblings at equal y fall back to tree order). It holds the sprites directly, in a dictionary chunk to array of nodes, and frees a chunk's sprites and its `props_body` when told. (They are not children of `Chunk_x_y`: that node sits under `World/Terrain`, which is not y-sorted, so sprites there would never sort against the hero.) One `Sprite2D` per prop: `region_enabled`, `region_rect` into the atlas, `offset` so the anchor is at the node's origin, `position` = the placement's base, `scale.x` -1 for a flip, `texture_filter` nearest, `z_index` 0 like the hero and the markers. A hero standing south of a trunk draws over it and one standing north is behind its canopy (the player's collision circle stops its origin about 4 px north of a trunk base when walking from the north, so it draws behind the tree as wanted). The terrain's ground and overlay layers stay below (`z_index` -10 and -9).
- **Collision.** One `StaticBody2D` per loaded chunk, named `props_body_x_y`, a child of `World/Props`, `collision_layer` 1 (walls; the player's mask is 1), mask 0, with one `CircleShape2D` per solid prop at its base: trees get radius `trunk_radius_px` (4 px, a small circle at the foot, not the crown), rocks tagged `big` get `big_rock_radius_factor` (0.6) times half the drawn width (about 8 px on a 27 px rock). Small rocks, pebbles and shrubs have no collider. The player is a `CharacterBody2D` with sliding, so it slides around a trunk.
- **Not blocked:** projectiles and enemies are unaffected (nothing in layer 1 changes for them; the overworld has no enemies yet and layer 1 already stops what walls stop).

## 6. Streaming and integration

- `WorldTerrain` gets two signals, `chunk_built(chunk)` and `chunk_freed(chunk)`, emitted at the end of `build_chunk_now` and of `free_chunk_now` (the budgeted path and the immediate path both go through them). `WorldProps` listens, so props appear and disappear with the ground within the same per-frame budget, and `WorldTerrain` keeps no reference to it.
- `Overworld` (`overworld.gd`, which today only calls `terrain.setup(world)`) also calls `props.setup(world, rules, sprites)` and connects the terrain's signals. A scene without `World/Props` or without rules builds no props, so `terrain.gd` (which builds `WorldTerrain` alone) behaves as before; the tests that now build props are `overworld_scene` and `overworld_walk`.
- The cost: the layout of a chunk needs 9 cells. A **cell cache** (a dictionary keyed by cell, holding that cell's placements and its `open` factor; cells are immutable, so this is exact) is part of the design, not an optimisation: the first load builds 9 chunks (81 cell lookups, 25 distinct cells) at one build per frame. Cells are evicted with the chunks that need them no longer (when a cell is farther than the unload radius). Target: under 8 ms for the nodes of one chunk in a rendered run, looked at in step 4; the headless bound is section 9.
- **The overworld only.** Arena stages, caves and dungeons are not touched (they use `MapBuilder`); the world map and minimap do not draw props.
- **Save compatibility.** Nothing about props is saved: the layout is a function of the committed data and `rules.seed`. A journey saved before this spec loads unchanged. Changing the seed or the rules changes where trees stand (and a player standing inside a new trunk's collider is pushed out by the physics; acceptable for a first draft since the layout is final before release; if needed, a later step can nudge a spawn).
- **Reachability guarantee.** The rules keep trunks 2 tiles from walls and 2 from the path, and clump discs hold at most 12 trees at 28 px spacing; a passage the map makes at least 3 tiles wide cannot be sealed by a tree line. The test (section 9) checks it by a flood fill rather than trusting this.

## 7. Tuning as data

`NatureRules` (`scripts/overworld/nature_rules.gd`, a `Resource` with typed `@export` fields) and one `.tres` per zone, `content/overworld/nature/mossy_hollow.tres`: the seed, `zone` index (0), `cell_tiles`, every number in section 3 (as `Vector2i` ranges for the "5 to 12" style values), the collider radii of section 5 (the scales live in the atlas manifest), the tag lists each rule draws from (`wood_groups`: arrays of tag sets with weights, so "mostly green, a fir wood, a mixed wood"; the autumn weight is the rare standout the user chose: about 1 tree in 12 is yellow or orange, none red, in the default `green` groups through an `autumn_weight` of 0.08), the colours of shrubs (`GREEN`, `YELLOWISH GREEN` and a rare `YELLOW`) and the rock columns. A later zone adds its own `.tres` and a `nature_zones` entry in `WorldProps.setup`; the layout function is not zone specific except through the rules it receives. `OverworldRules` keeps the structural constants only (`SAFE_RADIUS_TILES` is read, not copied).

## 8. Files

New:
- `docs/spec-1.7.md` (this file).
- `tools/overworld/build_nature_atlas.py`.
- `assets/nature/trees.png`, `rocks.png`, `shrubs.png` and their `.import` files.
- `content/overworld/nature/sprites.json`, `content/overworld/nature/mossy_hollow.tres`.
- `scripts/overworld/nature_rules.gd`, `nature_sprites.gd`, `nature_layout.gd`, `world_props.gd` (+ `.uid`).
- `tests/overworld/nature_atlas.gd`, `nature_layout.gd`, `nature_props.gd`, `nature_reach.gd` (+ `.uid` files). After adding the `class_name` scripts and the atlases, `godot --headless --path . --import`.

Changed:
- `scripts/overworld/world_terrain.gd` (the two signals).
- `scripts/overworld/overworld.gd` (the props setup and signal connection) and `scenes/overworld.tscn` (the `World/Props` node).
- `README.md` (layout, the green zone note), `tests/README.md` (rows), `content/overworld/README.md` (props), `tests/run_all.sh` only if a new directory is added (none: the tests go in `tests/overworld/`).
- `docs/spec-1.6.md` open question O13 (props not scattered) gets a one-line pointer to this spec.

Existing tests touched: none expected. `overworld_scene` and `overworld_walk` run with the real overworld and so build props; the walk test's player walks the route and must still reach every checkpoint (it is itself a reachability check on the path, which props keep clear). `terrain` builds `WorldTerrain` alone and is unchanged.

## 9. Tests (in `tests/overworld/`)

- `nature_atlas`: every manifest entry's region is inside its atlas and non-empty; every anchor is inside its region; the tree list has at least 20 entries with tags `green` (at least 8), `fir` (at least 2), `autumn` (at least 3); at least 8 rock entries per tag; at least 15 shrub entries; the manifest header has a positive scale for each kind. `build_nature_atlas.py --check` is not run by the suite (no Python in it); it is listed in the build notes.
- `nature_layout`: for a fixed chunk the result is identical on two calls and when a neighbour chunk was built first; every placement's base is inside its chunk; across all chunks of the zone's box (about 440 cells, 13 x 15 chunks: cheap) there are no duplicate placements; every placement passes the rules (walkable, zone 0, off the path, wall and marker clearances, spacing); the section 4 statistics fall inside their ranges; loners are at least `loner_clear_tiles` from other trees; setting `wood_chance` to 0 changes no rock or shrub placement (independent rule streams); `max_props_per_chunk` holds; a cell with no open tile has none.
- `nature_props`: with the real `WorldTerrain` and `WorldProps`, build a chunk: the sprite count equals the placements, solid props have circles in the chunk's `props_body` and others do not, freeing the chunk frees every sprite and the body (no orphans), a flipped placement has scale.x -1, and the sort is checked **structurally** (Godot exposes no sorted-order API, and the dummy renderer has none): `World/Props`, `World` and the root have `y_sort_enabled`, each sprite's `global_position.y` equals its base y, and sprites, `Players` and `Markers` children share `z_index` 0. The real draw order is looked at in the rendered check of step 4.
- `nature_reach`: rasterise the zone's bounding box (x 0 to 1003, y 1539 to 1988: about 451,000 tiles, an array and a breadth-first fill, feasible in GDScript under the time limit) at 1 tile resolution; obstacles are blocked tiles, wall tiles of depth 1 and 2 (the real colliders) and prop circles (a solid prop blocks the tiles its disc touches); the hero's 5 px radius circle needs a gap of 11 px, so a passable gap must be 2 tiles wide: the fill treats a tile as open only when its 2 x 2 neighbourhood has no obstacle. The fill from the start camp must reach every zone-0 marker (the gate, caves, camps, dungeon and specials), and reach at least 98 % of the tiles the same fill reaches without props.
- Performance: in `nature_props` a timing of building one chunk's props (layout from a cold cache plus nodes), the mean over 20 chunks of the zone, under 30 ms in the headless dummy renderer: a loose regression bound; the 8 ms target is looked at in a rendered run.
- Placement rules are also run for 30 alternative seeds (`SEED_COUNT`) over a sample of 40 chunks each (all must pass for any seed, not just the shipped one); the statistics use the shipped seed only. Every new test is run with a time limit (`perl -e 'alarm 175; exec @ARGV' ...`) as CLAUDE.md requires.

## 10. Docs

`README.md` (the project layout lines for `assets/nature` and the new scripts; one sentence in the overworld description), `tests/README.md` (a row per new test), `content/overworld/README.md` (the props: where the data is, how to rebuild the atlases, how to tune a zone), and this spec's build notes (the tuned values and what was checked by eye).

## 11. Build order

1. The atlas tool and its output: slice, tag, scale, write atlases and manifest, contact sheet, fix splits and anchors by eye; `NatureSprites`; `nature_atlas` test. Commit the assets, import them (`godot --headless --path . --import`).
2. `NatureRules`, `mossy_hollow.tres` and `NatureLayout` with its tests (`nature_layout`, `nature_reach`, run on real world data without any nodes). Commit.
3. `WorldProps` (sprites, y-sorting, colliders), the call in `WorldTerrain`, the scene node, `nature_props`. Run the overworld tests (`overworld_scene`, `terrain`, `overworld_walk`). Commit.
4. Render real frames (the start camp, a wood, a rock pile, the road, a chunk border), tune the rules data, update the numbers in this spec, README, tests README and the content README. Run the whole suite. Commit.

Each step is one commit with its tests; a step that can run independently (step 2 is independent of the art after the manifest exists) may be given to a worktree subagent.

## 12. Open questions / assumptions

- **O1.** Tree art: the pack's autumn trees dominate; the green zone uses green and fir trees with a rare yellow or orange one (the user's choice). Which of the 39 are used is decided by the tags and checked in the contact sheet; a sprite that looks wrong is excluded by an `EXCLUDE` list in the tool.
- **O2.** The shrub colours GREEN and YELLOWISH GREEN suit the grass; `TEAL` and `RED` are not used in this zone. A rare YELLOW is assumed fine.
- **O3.** Pre-scaled atlases (a 0.4 box-filtered tree) lose some pixel crispness versus a hand-redrawn small tree; if it looks soft in the render, step 4 may switch to nearest-neighbour downscaling. Native 1x is not used (decided).
- **O4.** A player standing where a trunk would appear is possible only after the rules change (the first draw has no saved positions): ignored for now.
- **O5.** The seed is a fixed number in the `.tres`; a "different world per character" is not wanted (one map, one layout).
- **O6.** Tree tops are not faded when covering the hero; with 0.4 scale the canopy is at most about 86 px, the view is 360 px high, and the hero is still partly visible; revisit only if the render shows the hero lost behind a wood.
- **O7.** No props on the path's dirt itself, so the path always reads; whether the path itself should get occasional fallen pebbles is a later art question.

## 13. Definition of Done

- The atlases, manifest, rules and scripts exist; `build_nature_atlas.py --check` passes on the committed files.
- The green zone shows lone trees, woods, rock piles and shrub patches that match the section 4 statistics; the path, the markers' clearings and every marker are reachable (`nature_reach`).
- Trunks and big rocks block, shrubs and small rocks do not, and the hero is drawn behind and in front of trees by y.
- Props stream with the chunks within the existing per-frame budget and free with them; nothing is saved.
- All new tests pass, earlier tests still pass (the full suite's only known failure is `crowd_bone_warren`), the READMEs and this spec's build notes are updated.
- A rendered check of the start camp, a wood, a rock pile and the road was looked at by the builder, and what was not checked by hand (a real play-through) is said plainly in the PR.
