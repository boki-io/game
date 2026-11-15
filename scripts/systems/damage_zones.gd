class_name DamageZones
extends Node2D
## Delayed or repeating damage areas that outlive the ability that made them
## (Blade Trail, Shockwave, Rift, Scorched Earth, Meteor Strike). Zones tick on a timer and hit
## whatever is inside. They belong to the Game scene, so they pause with the tree and vanish on restart.

var _zones: Array[Dictionary] = []


static func get_for(node: Node) -> DamageZones:
	return node.get_tree().get_first_node_in_group(&"zones") as DamageZones


func _ready() -> void:
	add_to_group(&"zones")
	z_index = 5


## Drops every pending burst and field (used when the hub changes character).
func clear() -> void:
	_zones.clear()
	queue_redraw()


## Capsule along a..b. Hits every `interval` seconds, `ticks` times, the first one at once.
func add_line(a: Vector2, b: Vector2, width: float, damage: float, interval: float, ticks: int) -> void:
	_zones.append({kind = &"line", a = a, b = b, radius = width, damage = damage, interval = interval,
		cd = 0.0, ticks = ticks, total = ticks, ring = false, knockback = 0.0, extras = {}, color = Color.WHITE})


## Circle at pos that fires once after `delay`, with a ring effect and knockback.
## extras (all optional): sfx (AudioStream played at impact), shake (Vector2: strength, seconds),
## visual (&"meteor"), stun (seconds applied to every enemy hit).
func add_burst(pos: Vector2, radius: float, damage: float, delay: float, knockback: float,
		extras: Dictionary = {}) -> void:
	_zones.append({kind = &"circle", a = pos, b = pos, radius = radius, damage = damage, interval = 0.0,
		cd = delay, ticks = 1, total = 1, ring = true, knockback = knockback, extras = extras,
		color = Color.WHITE})


## Circle that damages everything inside every `interval` seconds, `ticks` times. The first tick lands
## after `delay` (0 = at once). Drawn as a faint ground circle that fades as ticks run out.
func add_field(pos: Vector2, radius: float, damage: float, interval: float, ticks: int,
		color: Color, delay: float = 0.0) -> void:
	_zones.append({kind = &"field", a = pos, b = pos, radius = radius, damage = damage, interval = interval,
		cd = delay, ticks = ticks, total = ticks, ring = false, knockback = 0.0, extras = {}, color = color})


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
	var stun: float = z.extras.get("stun", 0.0)
	for e in EnemyGrid.query(mid, reach):
		if z.kind == &"line":
			var closest := Geometry2D.get_closest_point_to_segment(e.global_position, z.a, z.b)
			if closest.distance_to(e.global_position) > z.radius + 6.0:
				continue
		e.take_damage(z.damage)
		if z.knockback > 0.0:
			var away: Vector2 = e.global_position - z.a
			e.apply_knockback(away.normalized() * z.knockback)
		if stun > 0.0:
			e.stun(stun)
	var fx := Effects.get_for(self)
	if z.ring and fx:
		fx.ring(z.a, z.radius)
	if z.extras.get("visual") == &"meteor" and fx:
		fx.meteor_fall(z.a)
	if z.extras.has("sfx"):
		Audio.play_stream(z.extras.sfx)
	if z.extras.has("shake"):
		var shake: Vector2 = z.extras.shake
		CameraFollow.shake(self, shake.x, shake.y)


func _draw() -> void:
	for z in _zones:
		var frac := float(z.ticks) / float(z.total)
		if z.kind == &"line":
			draw_line(z.a, z.b, Color(0.5, 0.8, 1.0, 0.15 + 0.3 * frac), z.radius * 2.0)
		elif z.kind == &"field" and (z.cd <= 0.0 or z.ticks < z.total):
			var c: Color = z.color
			draw_circle(z.a, z.radius, Color(c, 0.08 + 0.14 * frac))
			draw_arc(z.a, z.radius, 0.0, TAU, 32, Color(c, 0.25 + 0.4 * frac), 1.0)
