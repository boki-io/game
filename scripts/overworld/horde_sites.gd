class_name HordeSites
extends RefCounted
## Where hordes can be (spec 1.8): the route sites and the side trail sites of `horde_sites.json`, built offline by
## `tools/overworld/build_horde_sites.py`. Loaded once and shared (`HordeSites.shared()`). Tiles are converted to world px
## (tile centres) with `WorldData.world_of`. A grid with 512 px cells answers `near`.

const SITES := "res://content/overworld/data/horde_sites.json"
const CELL_PX := 512.0

static var _shared: HordeSites

## One per route site: `tile` (Vector2i), `x` and `y` (the same in tile coordinates, the shape `HordePlan` reads), `pos` (world px), `zone`, `t` (route_t, 0 to 1 along the zone).
var routes: Array[Dictionary] = []
## One per trail: `marker` (index into `WorldData.markers`), `kind`, `points`: `tile`, `pos`, `t` (trail_t, 0 at the road, 1 at the end).
var trails: Array[Dictionary] = []
var _grid := {}  # Vector2i cell -> Array of {kind, index, point_index, pos}


static func shared() -> HordeSites:
	if _shared == null:
		_shared = HordeSites.new()
	return _shared


func _init() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SITES))
	for r in data.route:
		var tile := Vector2i(int(r.x), int(r.y))
		routes.append({"tile": tile, "x": tile.x, "y": tile.y, "pos": WorldData.world_of(tile), "zone": int(r.zone), "t": float(r.t)})
	for t in data.trails:
		var points: Array[Dictionary] = []
		for p in t.points:
			var tile := Vector2i(int(p.x), int(p.y))
			points.append({"tile": tile, "x": tile.x, "y": tile.y, "pos": WorldData.world_of(tile), "t": float(p.t)})
		trails.append({"marker": int(t.marker), "kind": String(t.kind), "points": points})
	for i in routes.size():
		_add(&"route", i, -1, routes[i])
	for i in trails.size():
		var points: Array = trails[i].points
		for j in points.size():
			_add(&"trail", i, j, points[j])


func _add(kind: StringName, index: int, point_index: int, point: Dictionary) -> void:
	var cell := _cell(point.pos)
	if not _grid.has(cell):
		_grid[cell] = []
	_grid[cell].append({"kind": kind, "index": index, "point_index": point_index, "point": point})


static func _cell(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / CELL_PX), floori(pos.y / CELL_PX))


## The sites within `radius_px` of a world position: dictionaries of `kind` (`&"route"` or `&"trail"`), `index` (into
## `routes` or `trails`), `point_index` (into the trail's points, -1 for a route site) and `point` (the site's dictionary).
func near(pos_px: Vector2, radius_px: float) -> Array:
	var out := []
	var lo := _cell(pos_px - Vector2(radius_px, radius_px))
	var hi := _cell(pos_px + Vector2(radius_px, radius_px))
	var r2 := radius_px * radius_px
	for cy in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			var bucket: Array = _grid.get(Vector2i(cx, cy), [])
			for e in bucket:
				if e.point.pos.distance_squared_to(pos_px) <= r2:
					out.append(e)
	return out
