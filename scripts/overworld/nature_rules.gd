class_name NatureRules
extends Resource
## The tuning of one zone's nature props (spec 1.7 section 7): one `.tres` per zone in content/overworld/nature. Every number
## `NatureLayout` uses is here; the sprite scales live in the atlas manifest. Counts and chances marked "x open" are multiplied
## by the layout cell's open-ground factor (its walkable tiles of this zone divided by `cell_tiles` squared).

## The layout seed. Each cell and each rule derives its own random stream from it, so changing one rule moves no other.
@export var seed: int = 1707
## The zone index whose walkable tiles get props (0 is `mossy_hollow`).
@export var zone: int = 0
## Side of a layout cell in tiles. Must equal `OverworldRules.CHUNK_TILES` (a chunk reads its cell and the eight around it).
@export var cell_tiles: int = 32

@export_group("Woods")
## Chance a cell holds a wood (x open).
@export var wood_chance: float = 0.22
## Trees asked for in a wood (min, max); a wood that places fewer than the minimum is dropped whole.
@export var wood_trees: Vector2i = Vector2i(5, 12)
## Radius of the wood's disc in tiles (min, max).
@export var wood_radius_tiles: Vector2i = Vector2i(3, 6)
## Poisson-disc minimum spacing between two trees of a wood, px (crowns overlap, trunks do not touch).
@export var tree_spacing_px: float = 28.0
## Above 1 the trees crowd toward the centre: the radius is `R * u ^ (0.5 * bias)` for a uniform u (1 is a uniform disc).
@export var centre_bias: float = 1.5
## Poisson dart throws per requested tree.
@export var wood_throws_per_tree: int = 14
## Shrubs on the wood's rim (min, max) and small rocks inside it (min, max). Not scaled by open ground.
@export var wood_shrubs: Vector2i = Vector2i(2, 6)
@export var wood_rocks: Vector2i = Vector2i(0, 2)
## Species groups a wood draws one from: dictionaries `{"weight": float, "tags": [tag, ...]}`; a tree matches when it has any of the tags.
@export var wood_groups: Array[Dictionary] = [
	{"weight": 6.0, "tags": ["green"]},
	{"weight": 2.0, "tags": ["fir"]},
	{"weight": 2.0, "tags": ["green", "fir"]},
]
## Chance a tree of a group that includes `green` is drawn from the `autumn` tag instead (the rare yellow or orange tree).
@export var autumn_weight: float = 0.08
## Random-centre tries for a wood, a pile or a patch before it gives up.
@export var centre_tries: int = 6

@export_group("Loners")
## Single trees per cell (min, max, x open); the count is drawn uniformly in the range, then scaled, then rounded stochastically.
@export var loner_trees: Vector2i = Vector2i(0, 3)
## A loner tree keeps this many tiles from any other tree (woods and loners).
@export var loner_clear_tiles: int = 4
## The groups loner trees draw from (same format as `wood_groups`).
@export var loner_groups: Array[Dictionary] = [
	{"weight": 7.0, "tags": ["green"]},
	{"weight": 3.0, "tags": ["fir"]},
]
## Single small rocks or pebbles per cell (min, max, x open).
@export var loner_rocks: Vector2i = Vector2i(0, 2)

@export_group("Rock piles")
## Chance a cell holds a rock pile (x open).
@export var rock_pile_chance: float = 0.16
## Small rocks and pebbles around the pile's big rock (min, max).
@export var pile_rocks: Vector2i = Vector2i(2, 5)
@export var pile_radius_tiles: int = 2
## A pile stands at least this many tiles from blocked terrain.
@export var pile_edge_tiles: int = 3

@export_group("Shrubs")
## Shrub patches per cell (min, max, x open), the shrubs in one patch (min, max) and the patch's disc radius in tiles.
@export var shrub_patches: Vector2i = Vector2i(0, 3)
@export var patch_shrubs: Vector2i = Vector2i(2, 5)
@export var patch_radius_tiles: int = 2
## Chance (x open) of one extra patch beside the dirt path (a path tile within `path_shrub_reach_tiles`).
@export var path_shrub_chance: float = 0.5
@export var path_shrub_reach_tiles: int = 3
## Shrub colour tag to weight; a patch is one colour.
@export var shrub_colours: Dictionary = {"green": 0.62, "yellowish": 0.33, "yellow": 0.05}

@export_group("Rules every placement passes")
## Trees and big rocks keep this many tiles from any path tile; shrubs and small rocks only stay off the path itself.
@export var path_clear_tiles: int = 2
## No blocked tile within this many tiles of a tree or big rock, and of any other prop.
@export var wall_clear_tiles: int = 2
@export var wall_clear_small_tiles: int = 1
## Clearing around start camp, checkpoint, gate and camp markers, in tiles (`OverworldRules.SAFE_RADIUS_TILES`); other markers get `marker_clear_minor_tiles`.
@export var marker_clear_tiles: int = 14
@export var marker_clear_minor_tiles: int = 7
## A shrub or rock base stays this far from a tree base, px.
@export var trunk_clear_px: float = 8.0
## At most this many props in one chunk; the last placements (fixed cell and rule order) are dropped.
@export var max_props_per_chunk: int = 160

@export_group("Colliders")
## Radius of a tree trunk's circle, px.
@export var trunk_radius_px: float = 4.0
## A big rock's circle is this factor times half its drawn width.
@export var big_rock_radius_factor: float = 0.6
