class_name DamageZones
extends Node2D
## Delayed or repeating damage areas that outlive the ability that made them
## (Blade Trail, Shockwave). Zones tick on a timer and hit whatever is inside.

var _zones: Array[Dictionary] = []


static func get_for(node: Node) -> DamageZones:
	return node.get_tree().get_first_node_in_group(&"zones") as DamageZones


func _ready() -> void:
	add_to_group(&"zones")
	z_index = 5


## Capsule along a..b. Hits every `interval` seconds, `ticks` times, starting after `delay`.
func add_line(a: Vector2, b: Vector2, width: float, damage: float, interval: float, ticks: int) -> void:
	_zones.append({kind = &"line", a = a, b = b, radius = width, damage = damage, interval = interval,
		cd = 0.0, ticks = ticks, total = ticks, ring = false, knockback = 0.0})


## Circle at pos that fires once after `delay`, with an optional ring effect and knockback.
func add_burst(pos: Vector2, radius: float, damage: float, delay: float, knockback: float) -> void:
	_zones.append({kind = &"circle", a = pos, b = pos, radius = radius, damage = damage, interval = 0.0,
		cd = delay, ticks = 1, total = 1, ring = true, knockback = knockback})


func _physics_process(delta: float) -> void:
	if _zones.is_empty():
		return
	for z in _zones:
		z.cd -= delta
		if z.cd <= 0.0 and z.ticks > 0:
			z.ticks -= 1
			z.cd += z.interval
			_fire(z)
	_zones = _zones.filter(func(z: Dictionary) -> bool: return z.ticks > 0)
	queue_redraw()


func _fire(z: Dictionary) -> void:
	var mid: Vector2 = (z.a + z.b) / 2.0
	var reach: float = z.radius + 6.0 + (z.a as Vector2).distance_to(z.b) / 2.0
	for e in EnemyGrid.query(mid, reach):
		if z.kind == &"line":
			var closest := Geometry2D.get_closest_point_to_segment(e.global_position, z.a, z.b)
			if closest.distance_to(e.global_position) > z.radius + 6.0:
				continue
		e.take_damage(z.damage)
		if z.knockback > 0.0:
			var away: Vector2 = e.global_position - z.a
			e.apply_knockback(away.normalized() * z.knockback)
	if z.ring:
		var fx := Effects.get_for(self)
		if fx:
			fx.ring(z.a, z.radius)


func _draw() -> void:
	for z in _zones:
		if z.kind == &"line":
			var alpha := 0.15 + 0.3 * float(z.ticks) / float(z.total)
			draw_line(z.a, z.b, Color(0.5, 0.8, 1.0, alpha), z.radius * 2.0)
