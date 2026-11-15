class_name LightningBehavior
extends AbilityBehavior
## Chain Lightning: instant. Strikes the nearest enemy inside a cone around the aim, then jumps
## to the nearest unhit enemy near the last one. Damage falls off with each jump.
## Upgrades: Extra Jumps (lightning.jumps), Static Shock (lightning.stun), Wide Arc
## (lightning.radius and lightning.cone_degrees).

const BASE_JUMPS := 4
const FALLOFF := 0.85  # damage multiplier per jump
const STUN_PER_LEVEL := 0.5
const CHEST := Vector2(0, -8)  # bolts run between body centres, not feet


func can_cast(c: AbilityCaster, aim: Vector2, d: AbilityData) -> bool:
	if _chain(c, aim, d).is_empty():
		fail_reason = &"no_target"
		return false
	return true


func cast(c: AbilityCaster, aim: Vector2, d: AbilityData) -> void:
	caster = c
	data = d
	var chain := _chain(c, aim, d)
	if chain.is_empty():
		return
	var damage := c.damage_of(d)
	var stun := STUN_PER_LEVEL * int(c.value(d, &"stun", 0.0))
	var points := PackedVector2Array([c.player.global_position + CHEST])
	for e: Enemy in chain:
		points.append(e.global_position + CHEST)
	for e: Enemy in chain:
		e.take_damage(damage)
		if stun > 0.0:
			e.stun(stun)
		damage *= FALLOFF
	var fx := Effects.get_for(c)
	if fx:
		fx.lightning(points)
	c.play_sfx(d)


## The enemies the bolt would strike, in order. Empty when nothing is inside the cone.
func _chain(c: AbilityCaster, aim: Vector2, d: AbilityData) -> Array[Enemy]:
	var chain: Array[Enemy] = []
	var origin := c.player.global_position
	var reach := c.value(d, &"range", d.range)
	var half_cone := deg_to_rad(c.value(d, &"cone_degrees", d.cone_degrees))
	var first: Enemy
	var best := INF
	for e in EnemyGrid.query(origin, reach):
		var to_enemy := e.global_position - origin
		if to_enemy.length_squared() > 1.0 and absf(aim.angle_to(to_enemy)) > half_cone:
			continue
		var dist := to_enemy.length_squared()
		if dist < best:
			best = dist
			first = e
	if first == null:
		return chain
	chain.append(first)
	var jump_radius := c.value(d, &"radius", d.radius)
	var jumps := BASE_JUMPS + int(c.value(d, &"jumps", 0.0))
	for i in jumps:
		var last := chain[chain.size() - 1]
		var next: Enemy
		best = INF
		for e in EnemyGrid.query(last.global_position, jump_radius):
			if chain.has(e):
				continue
			var dist := e.global_position.distance_squared_to(last.global_position)
			if dist < best:
				best = dist
				next = e
		if next == null:
			break
		chain.append(next)
	return chain
