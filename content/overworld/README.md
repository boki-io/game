# The overworld

The world is **one fixed, hand-authored map** (the guide in `art/source/overworld/map-instructions.md`, made by
`generate_map.py`): nothing about it is generated per game. A journey saves only what a character has done and found.

## Data (`data/`)
| File | What |
|---|---|
| `collision.png` | 2000 x 2000, white walkable, black blocked: the source of truth for collision. 1 pixel = 1 tile = 16 px |
| `zones.png` | the zone index of every tile is the pixel value divided by 30 (0 to 7), blended biomes |
| `world_map.png` | the map art, used by the minimap and the world map |
| `markers.json` | the 108 markers (`kind`, `x`, `y`, `world_x`, `world_y`, `zone`, `name`, `map_id`, ...), the zones and the main path |
| `edge_depth.png` | derived: for a blocked tile the distance in tiles to the nearest walkable one (capped at 15). Rebuild with `python3 tools/overworld/build_edge_depth.py` (`--check` compares) |

`WorldData` (`scripts/overworld/world_data.gd`) loads them. To change the world, change the generator's output, copy the files
here and rebuild `edge_depth.png`; `tests/overworld/world_data.gd` checks the data (every marker walkable and reachable).

## Terrain (`terrain/`)
`terrain/<zone id>.tres` (a `ZoneTerrain`) names, per zone, the atlas cells of its sheet `assets/tilesets/<zone id>.png` for the
roles `ground` (variants), `blocker`, `blocker_deep`, `edge` and `shadow`, and a fallback colour for each. The eight sheets are
floor-tile sheets with the same layout: ground and blocker are real tiles; `blocker_deep`, `edge` and `shadow` have no tile in the
sheets and use flat fallback colours in every zone. Drawing real tiles for those three roles is a matter of changing the catalog.

## Dungeons (`dungeon_rules.tres`)
`DungeonRules`: stages per kind (cave 1, dungeon 3, final vault 3), the tier offset, the population bonus and step, per-zone values,
the zone tiers and `max_population`. First-pass numbers, meant to be tuned in play.

## What a marker does
| Kind | Today |
|---|---|
| `start_camp`, `checkpoint` | F lights it (saves, heals, sets the respawn) |
| `cave`, `dungeon`, `final_dungeon` | F enters it as 1 or 3 arena stages on the zone's map; clearing is saved per marker |
| `special` | F shows its name and type (no reward yet) |
| `gate` | drawn across its gap, open; `OverworldRules.gate_locked` and `Journey.gate_open` are the lock hook |
| `camp`, `cache`, `arena` | placed, inert (the enemy spec uses them) |
