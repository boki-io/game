# Overworld Map: Build Guide

This is for the agent building the real world from `map-v3`.

## 1. What the map is
- `map-v3.png` is a 2000×2000 px top-down overview. **1 map pixel = 1 Godot tile = 16 px.** The origin is top-left and y points down.
- Tile → world position: `world = tile * 16 + 8` (the tile centre). The world is 2000×2000 tiles, or **32,000×32,000 px**.
- The game viewport is 640×360 px, which is 40×22.5 tiles. The map is about 50 screens wide and 89 screens tall.
- The charger is 64 px, or 4 tiles. The player is smaller.
- The map is both the layout spec and the in-game map art. Build the world to match it tile for tile.

## 2. Files (`/Users/bok/Documents/game-characters/map/`)

| File | Use |
|---|---|
| `map-v3.png` / `.aseprite` | The visual reference. Layers are `ground`, `blockers`, `shadows`, `paths`, `props`, `structures`, `markers`, `labels`. Hidden layers are `grid_250` and `collision_walkable`. |
| `collision_v3.png` | White is walkable, black is blocked. **This is the source of truth for collision.** |
| `zones_v3.png` | The zone index for each tile is the pixel value ÷ 30, so values 0–7 map to 0–210. This is the *blended* biome per tile. |
| `map_data_v3.json` | All markers (`kind`, `x`, `y`, `world_x`, `world_y`, `zone`, `name`, `map_id`, `boss`, `subtype`). Also the zone route ranges and the main path as a polyline sampled every 8 tiles. |
| `layers_v3/*.png` | Individual 2000×2000 layers. |
| `generate_map.py`, `render_map.py` | The generator. Don't edit the output by hand if you can re-run the generator. |

## 3. Route and zones
The main route is an S shape of **6,723 tiles** (107,568 px). It starts at the camp in the bottom-left (51, 1936). It runs east along the bottom, north up the right side, west through the middle, north up the left side, and east along the top to the final vault at (1880, 155).

| # | Zone (overland) | Dungeon `map_id` | Route tiles | Theme / blockers |
|---|---|---|---|---|
| 1 | Mossveil Wilds | `mossy_hollow` | 0–736 | Forest: dense trees, rock |
| 2 | Drownmire Fens | `flooded_gallery` | 736–1744 | Swamp: deep water, mangroves |
| 3 | Sporefall Thicket | `spore_cavern` | 1744–2625 | Giant mushrooms, stone |
| 4 | Ossuary Moors | `bone_warren` | 2625–3417 | Graveyard: bone ridges, dead wood |
| 5 | Yellowreek Flats | `sulfur_pits` | 3417–4169 | Sulfur chasms, ochre rock |
| 6 | Cinderreach | `ember_depths` | 4169–5034 | Volcanic: lava rivers, basalt |
| 7 | Frostbite Reach | `frostbite_grotto` | 5034–5906 | Snow: ice cliffs, frozen pines |
| 8 | Shardlands | `crystal_vault` | 5906–6723 | Crystal walls and spires |

**Biomes blend gradually.** Each fades into the next over about 460 route tiles, centred on the gate. A tile's biome is a per-pixel mix of two neighbours, so read `zones_v3.png`. Don't use hard zone rectangles.

**Seven gates** sit at the zone boundaries: Mossgate Pass, Drowned Causeway, Sporegate Gorge, Boneyard Gate, Sulfur Gap, Ashen Rift and Frostbite Pass. Each is a choke point about 12 tiles wide (about 192 px). Use them as progression gates for scripting, difficulty steps, a boss lock or story beats.

## 4. Marker kinds

| `kind` | Count | Meaning |
|---|---|---|
| `start_camp` | 1 | Spawn, hub and first checkpoint |
| `checkpoint` | 16 | 2 per zone, beside the road. Respawn and save points. |
| `gate` | 7 | Zone choke points. Carries a normal vector (`nx`, `ny`). |
| `camp` | 31 | Enemy camps, off the main path |
| `cave` | 18 | Short instanced dungeons. Use the zone's `map_id` with a small layout. |
| `dungeon` | 8 | Full boss dungeon, 1 per zone. `boss: true`. |
| `final_dungeon` | 1 | The final boss, "The Last Vault" |
| `special` | 18 | Shrines, ruins, altars and hermit huts, via `subtype` |
| `cache` | 4 | Lost-treasure dead ends |
| `arena` | 4 | Open pockets on the main corridor, for roaming enemies (`radius` in tiles) |

A marker's `zone` is the zone of the route where its trail begins. Near a gate, the biome in `zones_v3.png` may differ slightly, so use the pixel biome for art and the marker zone for gameplay tier.

## 5. Real-world size and time
- The route is about 107,568 px. At the knight's `move_speed` of 90 px/s, walking it straight takes about **20 minutes**.
- Gates take 3–4% longer to reach than the route's length, because of corridor wiggle. That is intentional.
- The overworld alone is not 15–20 hours. Most of that has to come from dungeons (9 bosses plus 18 caves), 31 camps, backtracking, loot and progression. Budget about 1.5–2.5 hours of overworld play with fights. Dungeons need to carry the rest.

## 6. Hard rules (do not break)
1. **No shortcuts.** The legs are separated by solid blocker belts. Never open a walkable tile that isn't white in `collision_v3.png`. Re-run the generator's check if you change layout: it reports unreachable areas and gate distance against route length.
2. **Collision comes from the mask, not sprites.** Build one `TileMapLayer` (or physics bake) straight from `collision_v3.png`. Blocked means solid. Don't hand-place tree colliders in blocked areas.
3. **Blockers need to look impassable.** The map shows forest, mountain, canyon, water, lava, ice cliff or crystal wall in each zone. Paint matching terrain tiles under every blocked tile, and give them a visible edge. A player should never wonder why they can't walk there.
4. **Keep the gates narrow.** Don't widen the 12-tile gaps. They are the pacing mechanism.
5. **One coordinate system.** Position everything from `map_data_v3.json` (`world_x`/`world_y`). Never re-derive from screenshots.

## 7. What to consider when building

**Terrain and tiles**
- Generate terrain from `zones_v3.png` (biome) plus `collision_v3.png` (walkable or not). Use Godot terrain sets with a transition tile set for each pair of neighbouring biomes. Avoid a hard seam: use noise or dither in the transition band to match the map.
- Roads and trails are in the `paths` layer. Paint those as a separate path layer over the ground. Trails are about 4–5 tiles wide, the main road about 6–7.
- Corridor widths: main corridor about 22–50 tiles, side trails about 13–18, clearings about 26–72, gates about 12. The camera shows 40×22 tiles, so on the main corridor the player always sees both edges at most. Trails feel tight by design.
- Props (trees, rocks, bones, mushrooms) are only decoration on walkable tiles. Their positions are in the `props` layer, but you can re-scatter them by biome. Keep roads, trails and a 14-tile radius around markers clear.
- Use y-sorting for trees and structures. Add shadow tiles on the lower-right of blockers (see `shadows`), since the art assumes top-left light.

**Streaming and performance**
- 32,000×32,000 px is too large for one scene. **Chunk it** into 32×32 or 64×64 tile chunks and load only the ones around the player (about 3×3). Keep gameplay objects (enemies, props) in the chunk too.
- Only about 15% of the map (about 600k tiles) is walkable. Don't generate blocked-interior tiles in detail. You only need a visible edge ring (about 8–12 tiles deep) around walkable areas, then a cheap filler beyond that. The player can't reach the interior.
- Godot float precision is fine at 32,000 px. Keep positions in world pixels and avoid unbounded float accumulation.
- Use `RenderingServer` for the large static layers if the tile count gets heavy, and bake navigation per chunk.

**Gameplay and content**
- **Difficulty:** enemy tier follows zone index 0–7, and it should ramp inside a zone too (low near the entry gate, higher towards the exit gate). Use `route_start_tile`/`route_end_tile` to compute progress along the route.
- **Camps:** these are fixed enemy encounters off the main path. They should be optional but rewarding. Spawn them only when the player is near.
- **Arenas:** these are open pockets on the main road. Use them for roaming or ambush spawns, not fixed camps.
- **Checkpoints:** use them as respawn points and fast-travel nodes. Place the first one right after each gate. Check the player can always reach the next one without crossing a boss.
- **Caves and dungeons:** the marker is only an entrance. Instance a scene using `map_id` from `content/maps/<map_id>`. Caves are short. Dungeons end in a boss. The final vault is the last boss. The player returns to the same marker.
- **Gates:** gate the player's progress with a story or boss condition if you want, but the world must not allow bypassing. If you add a lock, put it at the 12-tile gap.
- **Special sites:** `subtype` is `shrine`, `ruins`, `altar` or `hermit`. Each should give a different reward (buff, lore, challenge or rest).
- **Fog of war and minimap:** `map-v3.png` is the in-game world map. Reveal it with a fog mask by tile. Downscale a copy for the minimap, with markers drawn from the JSON.

**Art and consistency**
- Keep each zone's palette from the map. Match the existing charger and UI style: dark, grim, hard pixel edges, no anti-aliasing.
- Structures in the `structures` layer (camp, gate, cave, dungeon, shrine) are small placeholders at 1 px per tile. Re-draw them at proper 16 px/tile art size, centred on the marker coordinate.
- Zone names are working titles. `map_id` and `dungeon` are the stable keys. Use those, not the display names, in code.

## 8. Suggested build order
1. Import `collision_v3.png` and `zones_v3.png`. Build the base tilemap and collision per chunk.
2. Add terrain art per zone and the transitions.
3. Paint roads and trails from the `paths` layer.
4. Place markers from `map_data_v3.json` as scenes (checkpoint, camp, cave, dungeon, gate, special).
5. Scatter props by biome.
6. Add enemy spawns and difficulty by route progress.
7. Hook up the dungeon entrances to `content/maps/<map_id>`.
8. Add the minimap and fog of war.
9. Playtest the route end to end, and test every gate for bypasses.

## 9. Enemies along the route
The map says **where encounters live** and **which zone tier they belong to**. It does not say which enemies spawn. The spawn tables have to be authored. Everything marked *suggested* below is a proposal, not something the map fixes.

**How a zone plays, in order along the route**
1. Entry gate, then a quiet stretch. Checkpoint 1 sits about 120 route tiles past the gate (about 280 in zone 1).
2. The main corridor, with arenas and side trails opening off it.
3. Checkpoint 2 at about mid-zone (+40 tiles).
4. The exit gate, which leads to the next zone's entry.

**Three kinds of enemy presence**
- **Camps (31):** fixed encounters at the end of a side trail. Each trail is a dead end that finishes in a clearing about 44 tiles across, so the player commits, fights and walks back. Camps are optional and are the main source of loot and XP away from the route. Suggested: 4–8 enemies plus a totem or banner, spawned when the player is within about 60 tiles and cleared for good once beaten. Save the cleared state per marker (`name` is unique).
- **Arenas (4):** open pockets (26–36 tile radius) on the main corridor. Suggested: ambush or roaming spawns that trigger when the player enters, rather than fixed camps.
- **Route patrols:** *suggested*, sparse and weak, so the main road isn't empty. Keep a **safe radius of about 14 tiles** around the start camp, checkpoints and gates, so they work as rest points.

**Roster and ramp**
- The game has `grunt`, `ranged` and `dasher` (each map folder has its own looks for them) plus the new `charger`. Suggested: zones 1–2 mostly grunts, then add ranged enemies, then dashers, with chargers appearing from the mid zones.
- Tier = zone index (0–7), and it ramps inside each zone from the entry gate to the exit gate (use `route_start_tile` and `route_end_tile`). Side trails run a little harder than the road beside them. Dungeons are harder still.
- Use the *blended* biome (`zones_v3.png`) for how enemies look, and the marker's `zone` for how strong they are.

## 10. Dungeons and caves
A cave or dungeon marker is **only an entrance**. The overworld is the hub, and entering swaps to an instanced run.

**How it hooks into the existing game**
- Each marker carries `map_id` (for example `bone_warren`). That is a folder in `content/maps/<id>/`: a `MapTheme` (`map.tres`) with a palette, layout rules (`style`, wall counts and lengths) and the monster variants `grunt`, `ranged` and `dasher`. `MapBuilder` builds the arena from it, so a dungeon is a run on that map. The overworld doesn't need its own dungeon art.
- Decide whether the layout seed is **fixed per marker** (a stable dungeon, with the marker index or name as the seed) or **re-rolled on each entry**. Fixed is better for a "dungeon you clear". Re-rolled is better for farming.
- The marker's own tile is the return point. When the run ends, put the player back at that marker.

**The three entrance types**

| Entrance | Count | Suggested role |
|---|---|---|
| `cave` | 18 | Short: one arena, a few waves, 5–10 min. Pays out loot or a relic. Not required for progress. |
| `dungeon` (`boss: true`) | 8 | Longer: several stages ending in a boss, 20–40 min. One per zone, on the longest side trail. |
| `final_dungeon` | 1 | The last run, at the end of the route. The biggest and hardest. |

- Each zone has one dungeon and about two caves that share the same `map_id`. Tell them apart by layout size, seed and enemy tier, so a zone's dungeon and its caves don't feel identical.
- The final vault and the zone 8 dungeon both use `crystal_vault`. Give the final vault its own layout parameters and enemy tier.

**Bosses are not built yet.** The game's enemies today are `grunt`, `ranged`, `dasher`, `charger` and `training_dummy`. The 9 bosses need to be designed. A boss's defeat should be saved as a flag per marker.

**Open decisions to confirm with the project owner before building**
1. What does beating a zone's boss unlock: the next gate, a reward, or only story?
2. Is a dungeon fixed-seed or re-rolled?
3. On death, does the player respawn at the last checkpoint or at the dungeon entrance?
4. Do camps respawn, and when?
5. Do caves count towards progress, or are they purely optional?
