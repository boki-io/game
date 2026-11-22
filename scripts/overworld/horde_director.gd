class_name HordeDirector
extends SpawnDirector
## Runs the overworld's enemy hordes (spec 1.8 sections 5 and 7). It is a SpawnDirector so `Enemy` finds the director fields
## it reads (`teleport_distance`, `ring_position`, `release`, `on_stuck`), with the arena's timed spawning switched off.
##
## The plan (`HordePlan`) sits in a 512 px grid. Each physics frame hordes near a hero are materialised (their enemies
## pulled from a pool per (type, zone) and stood DORMANT at their posts), and dormant hordes far from every hero are
## dematerialised. A staggered loop (every `rules.check_interval` per enemy) wakes dormant and returning enemies that see a
## hero, alerts the rest of their horde, and sends awake enemies home that have lost the hero (leash, sight, rest point).
## Rewards on a kill are the arena's `Pickups` calls; the last kill of a den marks it cleared in the journey.

## The last member of a den died: `kind` is the marker's kind (`camp` or `cache`), `marker` its index in the world's markers.
signal den_cleared(kind: String, marker: int)

## Enemies instantiated per physics frame while the pools prewarm.
const PREWARM_PER_FRAME := 3
## A stuck returning member is put back at its post only if that is this far from every hero (off screen), px.
const OFFSCREEN_MARGIN := 420.0

## World px of the start camp, the checkpoints and the gates: a rest point's radius is `OverworldRules.SAFE_RADIUS_TILES`.
var safe_points := PackedVector2Array()
## Enemies killed since `setup`.
var kills := 0

var world: WorldData
var rules: HordeRules
var journey: Journey
var _rewards: Node
var _types := {}  # type id (StringName) -> EnemyData
var _zone_pools := {}  # "type|zone" -> Array[Enemy]
var _grid := {}  # Vector2i cell -> Array[HordePlan.Horde]
var _live := {}  # horde id -> Live
var _of_enemy := {}  # Enemy -> Live
var _blind := {}  # Enemy -> seconds without sight of the hero
var _positions := {}  # horde id -> PackedVector2Array (member spots, kept: they never change)
var _prewarm: Array[Dictionary] = []
var _slots := 12


## A materialised horde: its enemies (the dead and dropped are removed) and the plan entry.
class Live extends RefCounted:
	var horde: HordePlan.Horde
	var members: Array[Enemy] = []


func _ready() -> void:
	teleport_distance = INF


## `plan` is `HordePlan.build(...)`, `obstacle_map` the world's `WorldObstacles`, `pickup_node` a `Pickups` (or anything with
## `spawn_gem`, `spawn_coin`, `roll_magnet` and `roll_item_drop`), `journey_state` the saved game that holds the cleared dens.
func setup(world_data: WorldData, plan: Array, horde_rules: HordeRules, obstacle_map: Node, enemies: Node2D,
		pickup_node: Node, journey_state: Journey) -> void:
	world = world_data
	rules = horde_rules
	obstacles = obstacle_map as ObstacleMap
	enemies_root = enemies
	_rewards = pickup_node
	journey = journey_state
	teleport_distance = INF
	if enemy_scene == null:
		enemy_scene = load("res://scenes/enemy.tscn")
	if enemy_types.is_empty():
		for id in ["grunt", "ranged", "dasher"]:
			enemy_types.append(load("res://content/enemies/%s.tres" % id))
	for type in enemy_types:
		_types[type.id] = type
		alive_by_type[type.id] = 0
	_slots = maxi(1, roundi(rules.check_interval * Engine.physics_ticks_per_second))
	safe_points = PackedVector2Array()
	for m in world.markers:
		if m.kind in HordePlan.SAFE_KINDS:
			safe_points.append(WorldData.marker_world(m))
	_grid.clear()
	for h in plan:
		var cell := _cell(h.home)
		if not _grid.has(cell):
			_grid[cell] = []
		_grid[cell].append(h)
	kills = 0


static func _cell(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / 512.0), floori(pos.y / 512.0))


## Queues `count_per_type` enemies of every type for the pool of `zone`; they are instantiated a few per frame.
func prewarm(count_per_type: int, zone := 0) -> void:
	for id in _types:
		for i in count_per_type:
			_prewarm.append({"type": _types[id], "zone": zone})


## Enemies still waiting to be instantiated by `prewarm`.
func prewarm_pending() -> int:
	return _prewarm.size()


func live_count() -> int:
	return alive


## The plan entry an enemy belongs to, or null.
func horde_of(enemy: Enemy) -> HordePlan.Horde:
	var live: Live = _of_enemy.get(enemy)
	return live.horde if live != null else null


## Ids of the hordes with a materialised (or spent, not yet far enough away to regrow) entry.
func live_horde_ids() -> Array:
	return _live.keys()


## Dematerialises everything at once (the hero respawned or was moved far). Cleared dens stay cleared.
func reset() -> void:
	for live: Live in _live.values():
		for e in live.members.duplicate():
			_drop(e)
	_live.clear()
	_of_enemy.clear()
	_blind.clear()


func ring_position(_around: Vector2) -> Variant:
	return null


func _physics_process(delta: float) -> void:
	if rules == null or world == null:
		return  # not set up (a scene that runs without hordes)
	for i in mini(PREWARM_PER_FRAME, _prewarm.size()):
		var job: Dictionary = _prewarm.pop_back()
		_pool(job.type, job.zone).append(_make(job.type, job.zone))
	_stream()
	_behave(delta)


# --- streaming ---------------------------------------------------------------------------------

func _stream() -> void:
	var heroes: Array[Player] = []
	for p in PlayerRegistry.players:
		if not p.dead:
			heroes.append(p)
	# Dematerialise: only hordes that are all dormant (a spent horde counts), beyond the radius from every hero.
	for id in _live.keys():
		var live: Live = _live[id]
		var near := false
		for p in heroes:
			if p.global_position.distance_to(live.horde.home) <= rules.dematerialise_radius:
				near = true
				break
		if near:
			continue
		var asleep := true
		for e in live.members:
			if e.state != Enemy.State.DORMANT:
				asleep = false
				break
		if asleep:
			_remove(live)
	if heroes.is_empty():
		return
	var cands: Array = []
	var seen := {}
	for p in heroes:
		var lo := _cell(p.global_position - Vector2.ONE * rules.materialise_radius)
		var hi := _cell(p.global_position + Vector2.ONE * rules.materialise_radius)
		for cy in range(lo.y, hi.y + 1):
			for cx in range(lo.x, hi.x + 1):
				for h: HordePlan.Horde in _grid.get(Vector2i(cx, cy), []):
					if seen.has(h.id) or _live.has(h.id):
						continue
					var d := p.global_position.distance_to(h.home)
					if d > rules.materialise_radius:
						continue
					seen[h.id] = true
					cands.append([d, h])
	if cands.is_empty():
		return
	cands.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var made := 0
	for c in cands:
		if made >= rules.materialise_per_frame:
			break
		var h: HordePlan.Horde = c[1]
		if h.kind == HordePlan.KIND_DEN and journey != null and journey.is_den_cleared(_marker_kind(h), h.marker):
			continue
		if alive + h.members.size() > rules.max_alive:
			break  # the nearest waits, so nothing farther jumps the queue
		_materialise(h)
		made += 1


func _marker_kind(h: HordePlan.Horde) -> String:
	return String(world.markers[h.marker].kind)


func _materialise(h: HordePlan.Horde) -> void:
	if not _positions.has(h.id):
		_positions[h.id] = HordePlan.member_positions(world, h)
	var spots: PackedVector2Array = _positions[h.id]
	var live := Live.new()
	live.horde = h
	_live[h.id] = live
	for i in spots.size():
		var type: EnemyData = _types.get(h.members[i])
		if type == null:
			continue
		var e := _acquire_for(type, h.zone)
		e.activate(spots[i], h.hp_mult)
		e.state = Enemy.State.DORMANT
		e.home = spots[i]
		e.return_speed_mult = rules.return_speed_mult
		live.members.append(e)
		_of_enemy[e] = live
		alive += 1
		alive_by_type[type.id] += 1


## Releases every member and forgets the horde.
func _remove(live: Live) -> void:
	for e in live.members.duplicate():
		_drop(e)
	_live.erase(live.horde.id)


## Takes one member out of play without a kill: back to its pool, off its horde.
func _drop(e: Enemy) -> void:
	var live: Live = _of_enemy.get(e)
	if live != null:
		live.members.erase(e)
	release(e)


# --- pools -------------------------------------------------------------------------------------

func _pool(type: EnemyData, zone: int) -> Array:
	var key := "%s|%d" % [type.id, zone]
	if not _zone_pools.has(key):
		_zone_pools[key] = []
	return _zone_pools[key]


func _acquire(type: EnemyData) -> Enemy:
	return _acquire_for(type, 0)


## An enemy of `type` dressed in `zone`'s monster variant, from the pool of that (type, zone) or new.
func _acquire_for(type: EnemyData, zone: int) -> Enemy:
	var pool := _pool(type, zone)
	if not pool.is_empty():
		return pool.pop_back()
	return _make(type, zone)


func _make(type: EnemyData, zone: int) -> Enemy:
	var enemy: Enemy = enemy_scene.instantiate()
	enemy.data = type
	enemy.director = self
	enemy.obstacles = obstacles
	enemy.return_speed_mult = rules.return_speed_mult
	enemy.set_meta(&"zone", zone)
	enemy.died.connect(_on_enemy_died)
	enemy.woken.connect(_on_woken)
	enemy.arrived_home.connect(_on_arrived_home)
	enemies_root.add_child(enemy)
	var zone_id: String = world.zones[clampi(zone, 0, world.zones.size() - 1)].id
	var theme: MapTheme = MapRegistry.by_id(StringName(zone_id))
	if theme == null:
		theme = MapRegistry.default()
	enemy.apply_variant(theme.variant_for(type.id))
	enemy.deactivate()
	return enemy


func release(enemy: Enemy) -> void:
	var was_active := enemy.active
	enemy.deactivate()
	_of_enemy.erase(enemy)
	_blind.erase(enemy)
	_pool(enemy.data, int(enemy.get_meta(&"zone", 0))).append(enemy)
	if was_active:
		alive -= 1
		alive_by_type[enemy.data.id] -= 1


# --- behaviour ---------------------------------------------------------------------------------

func _behave(_delta: float) -> void:
	var frame := Engine.get_physics_frames()
	var step := _slots / float(Engine.physics_ticks_per_second)
	for e: Enemy in _of_enemy.keys():
		if not e.active or (e.get_instance_id() + frame) % _slots != 0:
			continue
		_check(e, step)


## One check of one enemy: the wake test for a dormant or returning one, the leash for an awake one.
func _check(e: Enemy, step: float) -> void:
	var hero := PlayerRegistry.nearest(e.global_position)
	if e.state == Enemy.State.CHASE:
		if hero == null or _in_safe(hero.global_position) \
				or e.global_position.distance_to(hero.global_position) > rules.leash_radius:
			_send_home(e)
			return
		if _sees(e, hero):
			_blind[e] = 0.0
		else:
			_blind[e] = float(_blind.get(e, 0.0)) + step
			if _blind[e] >= rules.lose_sight_time:
				_send_home(e)
				return
		_alert(e)
		return
	if hero == null or _in_safe(hero.global_position):
		return
	if e.global_position.distance_to(hero.global_position) <= rules.wake_radius and _sees(e, hero):
		_wake(e)


func _sees(e: Enemy, hero: Player) -> bool:
	return obstacles == null or obstacles.segment_clear(e.global_position, hero.global_position, e.data.hitbox_radius)


func _in_safe(pos: Vector2) -> bool:
	var r := float(OverworldRules.SAFE_RADIUS_TILES * WorldData.TILE_PX)
	for p in safe_points:
		if pos.distance_to(p) <= r:
			return true
	return false


func _send_home(e: Enemy) -> void:
	e.send_home()
	_blind.erase(e)


## Wakes an enemy (a dormant or returning one) and its horde's dormant members close to it.
func _wake(e: Enemy) -> void:
	e.wake()
	_blind[e] = 0.0
	_alert(e)


## Wakes the dormant and returning members of `e`'s horde within `alert_radius` of it.
func _alert(e: Enemy) -> void:
	var live: Live = _of_enemy.get(e)
	if live == null:
		return
	var hero := PlayerRegistry.nearest(e.global_position)
	if hero != null and _in_safe(hero.global_position):
		return
	for o in live.members:
		if o != e and o.state != Enemy.State.CHASE \
				and o.global_position.distance_to(e.global_position) <= rules.alert_radius:
			o.wake()
			_blind[o] = 0.0


func _on_woken(e: Enemy) -> void:
	_blind[e] = 0.0
	_alert(e)


func _on_arrived_home(e: Enemy) -> void:
	_blind.erase(e)


## A chaser that cannot move goes home. A returning one that cannot is put at its post if that is off screen, else dropped.
func on_stuck(e: Enemy) -> void:
	if e.state == Enemy.State.CHASE:
		_send_home(e)
		return
	var hero := PlayerRegistry.nearest(e.global_position)
	if hero == null or hero.global_position.distance_to(e.home) > OFFSCREEN_MARGIN:
		e.global_position = e.home
	else:
		_drop(e)


# --- rewards and den clearing --------------------------------------------------------------------

func _on_enemy_died(enemy: Enemy) -> void:
	kills += 1
	var live: Live = _of_enemy.get(enemy)
	var xp_mult := live.horde.xp_mult if live != null else 1.0
	if _rewards:
		_rewards.spawn_gem(enemy.global_position, roundi(enemy.data.xp_drop * xp_mult))
		if enemy.data.xp_drop > 0 and randf() < clampf(stage.coin_chance() + coin_bonus, 0.0, 1.0):
			_rewards.spawn_coin(enemy.global_position)
		if enemy.data.xp_drop > 0:
			_rewards.roll_magnet(enemy.global_position)
		if enemy.data.item_drop_chance > 0.0:
			_rewards.roll_item_drop(enemy.global_position, enemy.data.item_drop_chance)
	if live != null:
		live.members.erase(enemy)
	release(enemy)
	if live != null and live.members.is_empty() and live.horde.kind == HordePlan.KIND_DEN:
		var kind := _marker_kind(live.horde)
		if journey != null:
			journey.mark_den_cleared(kind, live.horde.marker)
		den_cleared.emit(kind, live.horde.marker)
