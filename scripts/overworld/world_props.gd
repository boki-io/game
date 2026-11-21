class_name WorldProps
extends Node2D
## The overworld's nature props (spec 1.7 section 5): the sprites and trunk colliders `NatureLayout` places, built when the
## terrain builds a chunk and freed when it frees it. This node (`World/Props`) is y-sorted with the players and the markers,
## so the hero draws behind a tree's canopy when standing north of its foot and in front when south. The sprites are direct
## children (not of the terrain's chunk nodes, which are not y-sorted). Uses no autoload.

const WALL_LAYER := 1
## Cached layout cells farther than this many chunks from the last built chunk are dropped.
const CACHE_RADIUS := OverworldRules.UNLOAD_RADIUS + 2
const KIND_NAMES := {&"tree": "trees", &"rock": "rocks", &"shrub": "shrubs"}

var world: WorldData
var rules: NatureRules
## The sprite catalog the layout reads: `NatureSprites` (a class with static functions) or a stand-in with the same methods.
var sprites
var _chunks := {}  # Vector2i -> Array of the chunk's nodes (sprites and its body)
var _cache := {}
var _last_chunk := Vector2i.ZERO


## Gives the node what it needs and listens to the terrain. A node without rules builds nothing.
func setup(world_data: WorldData, nature_rules: NatureRules, terrain: WorldTerrain, sprite_catalog = NatureSprites) -> void:
	world = world_data
	rules = nature_rules
	sprites = sprite_catalog
	terrain.chunk_built.connect(build_chunk)
	terrain.chunk_freed.connect(free_chunk)


func loaded_chunks() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in _chunks.keys():
		out.append(c)
	return out


## The nodes of a built chunk: its Sprite2D children and its body (empty when the chunk is not built).
func chunk_nodes(chunk: Vector2i) -> Array:
	return _chunks.get(chunk, [])


func build_chunk(chunk: Vector2i) -> void:
	if rules == null or world == null or _chunks.has(chunk):
		return
	_last_chunk = chunk
	var nodes: Array = []
	var placements := NatureLayout.props_for_chunk(world, rules, sprites, chunk, _cache)
	var body: StaticBody2D = null
	for p in placements:
		var kind: String = KIND_NAMES[p.kind]
		var s := Sprite2D.new()
		s.texture = sprites.texture(kind)
		s.centered = false
		s.region_enabled = true
		s.region_rect = sprites.region(kind, p.sprite)
		s.offset = -sprites.anchor(kind, p.sprite)
		s.position = p.base
		if p.flip:
			s.scale.x = -1.0
		add_child(s)
		nodes.append(s)
		if p.solid_radius > 0.0:
			if body == null:
				body = StaticBody2D.new()
				body.name = "props_body_%d_%d" % [chunk.x, chunk.y]
				body.collision_layer = WALL_LAYER
				body.collision_mask = 0
			var shape := CircleShape2D.new()
			shape.radius = p.solid_radius
			var cs := CollisionShape2D.new()
			cs.shape = shape
			cs.position = p.base
			body.add_child(cs)
	if body != null:
		add_child(body)
		nodes.append(body)
	_chunks[chunk] = nodes
	NatureLayout.evict(_cache, chunk, CACHE_RADIUS)


func free_chunk(chunk: Vector2i) -> void:
	var nodes: Array = _chunks.get(chunk, [])
	_chunks.erase(chunk)
	for n in nodes:
		n.queue_free()
