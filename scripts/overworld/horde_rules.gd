class_name HordeRules
extends Resource
## The tuning of the overworld's enemy hordes (spec 1.8 section 9): one `.tres`, content/overworld/hordes.tres. Every number
## `HordePlan` and the horde director use is here; the structural constants stay in `OverworldRules` and the enemy stats in
## content/enemies. The composition tables have eight rows, one per zone: a Dictionary of enemy type id to weight.

## The plan seed. Each horde derives its own random streams from it and its id, so tuning one rule moves no other.
@export var seed: int = 1807

@export_group("Route hordes")
## Members of a small road horde (min, max).
@export var route_size: Vector2i = Vector2i(4, 7)
## Spread radius of a small road horde, px.
@export var route_radius_px: float = 96.0
## Chance a route site holds a big horde instead (drawn from the site's own stream).
@export var route_big_chance: float = 0.17
## Members of a big road horde, and of an arena's horde (min, max).
@export var route_big_size: Vector2i = Vector2i(12, 18)
## Spread radius of a big road horde, px.
@export var route_big_radius_px: float = 176.0
## An arena's horde spreads over this fraction of the marker's own `radius` (tiles).
@export var arena_radius_scale: float = 0.5
## Type weights per zone of a small road horde (grunts only in the first zones).
@export var route_weights: Array[Dictionary] = []
## Type weights per zone of a big road horde and of an arena horde.
@export var route_big_weights: Array[Dictionary] = []

@export_group("Trail hordes")
## Members of a trail horde before the ramp (min, max).
@export var trail_size: Vector2i = Vector2i(5, 9)
## The size is scaled by `1 + trail_size_ramp * t`, t being 0 at the road and 1 at the end of the trail.
@export var trail_size_ramp: float = 0.6
@export var trail_radius_px: float = 120.0
@export var trail_weights: Array[Dictionary] = []

@export_group("Guard hordes")
## Members of the horde that guards a cave, dungeon or special marker (min, max).
@export var guard_size: Vector2i = Vector2i(6, 10)
@export var guard_radius_px: float = 128.0
## Distance from the guarded marker to the horde's home, in tiles (min, max); the first is outside the nature clearing.
@export var guard_distance_tiles: Vector2i = Vector2i(8, 14)
@export var guard_weights: Array[Dictionary] = []

@export_group("Dens")
## Members of a camp's den and of a cache's den (min, max).
@export var den_size: Vector2i = Vector2i(18, 28)
@export var cache_den_size: Vector2i = Vector2i(14, 22)
## Spread radius of a den, px (18 tiles: inside the camp's clearing).
@export var den_radius_px: float = 288.0
@export var den_weights: Array[Dictionary] = []
## Coins on top of the kills' drops when a den is cleared.
@export var den_bonus_coins: int = 25

@export_group("Scaling")
## Tier added to the zone index per kind (`route`, `route_big`, `trail`, `guard`, `den`).
@export var kind_tier_bonus: Dictionary = {"route": 0, "route_big": 1, "trail": 1, "guard": 1, "den": 2}
## `hp_mult = 1 + hp_per_tier * tier + hp_per_route * route_t`.
@export var hp_per_tier: float = 0.25
@export var hp_per_route: float = 0.2
## `xp_mult = 1 + xp_per_tier * tier`.
@export var xp_per_tier: float = 0.2

@export_group("Sites and placement")
## Every this many points of the main route a route site is made (read by the sites tool; kept here with its neighbours).
@export var route_stride: int = 8
## Tiles between two trail sites (the same).
@export var trail_stride: int = 40
## Members per squad (min, max).
@export var squad_size: Vector2i = Vector2i(3, 5)
## Minimum spacing of squad centres, px, for a horde of `route_radius_px`; it grows with the square root of the radius.
@export var squad_spacing_px: float = 72.0
## Members stand around their squad centre within this radius, px.
@export var squad_radius_px: float = 28.0
## Minimum distance between two members, px.
@export var member_spacing_px: float = 18.0
## Two homes closer than this many tiles keep only the stronger horde.
@export var min_home_gap_tiles: int = 18

@export_group("Behaviour")
## A dormant member wakes when the hero is this close with a clear line, px.
@export var wake_radius: float = 300.0
## A waking member alerts the members of its horde within this distance, px.
@export var alert_radius: float = 96.0
## An awake member farther than this from its home returns, px.
@export var leash_radius: float = 600.0
## Seconds without sight of the hero before an awake member gives up.
@export var lose_sight_time: float = 6.0
## Speed multiplier while returning home.
@export var return_speed_mult: float = 1.5
## Seconds between the wake checks of one member.
@export var check_interval: float = 0.2

@export_group("Streaming")
## A horde materialises when the hero is closer than this, px.
@export var materialise_radius: float = 800.0
## A dormant horde dematerialises when the hero is farther than this, px.
@export var dematerialise_radius: float = 1200.0
## Hordes materialised per frame at most.
@export var materialise_per_frame: int = 1
## Live enemies at most.
@export var max_alive: int = 120


## The weights table of a horde kind for a zone (`route`, `route_big`, `trail`, `guard` or `den`); the last row serves zones
## past the end of the table, an empty Dictionary when the table is empty.
func weights_for(kind: StringName, zone: int) -> Dictionary:
	var table: Array[Dictionary]
	match kind:
		&"route":
			table = route_weights
		&"route_big":
			table = route_big_weights
		&"trail":
			table = trail_weights
		&"guard":
			table = guard_weights
		&"den":
			table = den_weights
	if table.is_empty():
		return {}
	return table[clampi(zone, 0, table.size() - 1)]
