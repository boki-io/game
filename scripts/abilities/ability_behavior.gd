class_name AbilityBehavior
extends RefCounted
## Shape of an ability. Numbers come from AbilityData; the caster supplies modified values.
## cast() starts it; the caster then calls update() every physics frame until it returns true.

const ENEMY_RADIUS := 6.0  # added to reach so edge-touching enemies are hit
const ARENA_INSET := 8.0  # clamp_to_arena keeps points this far inside the wall margin

var caster: AbilityCaster
var data: AbilityData
## Why can_cast() last returned false: &"no_target" or &"blocked".
var fail_reason: StringName = &""


## `pos` pulled inside the arena, clear of its walls (a target point for a ground effect).
static func clamp_to_arena(pos: Vector2) -> Vector2:
	var inset := ARENA_INSET + Arena.wall_margin
	return pos.clamp(Vector2(inset, inset), Vector2(Arena.world_size) - Vector2(inset, inset))


## Checked before mana is spent or the cooldown starts. Return false to reject the cast.
func can_cast(_caster: AbilityCaster, _aim: Vector2, _data: AbilityData) -> bool:
	return true


func cast(_caster: AbilityCaster, _aim: Vector2, _data: AbilityData) -> void:
	pass


## Return true when the ability is finished (the caster is busy until then).
func update(_delta: float) -> bool:
	return true


## Cleanup. Called on normal completion and when the cast is cancelled (e.g. death).
func finish() -> void:
	pass


## Damage every enemy in an arc not already in `already`. Returns the hit count.
func hit_arc(origin: Vector2, dir: Vector2, reach: float, arc_rad: float, damage: float, already: Dictionary) -> int:
	var hits := 0
	for e in EnemyGrid.query(origin, reach + ENEMY_RADIUS):
		if already.has(e):
			continue
		if absf(dir.angle_to(e.global_position - origin)) <= arc_rad / 2.0:
			already[e] = true
			e.take_damage(damage)
			hits += 1
	return hits


## Damage every enemy within radius of center not already in `already`. Returns the hit count.
func hit_circle(center: Vector2, radius: float, damage: float, already: Dictionary) -> int:
	var hits := 0
	for e in EnemyGrid.query(center, radius + ENEMY_RADIUS):
		if already.has(e):
			continue
		already[e] = true
		e.take_damage(damage)
		hits += 1
	return hits
