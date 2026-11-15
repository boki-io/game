class_name BasicAttack
extends Node
## Auto Slash: targets the closest enemy within TARGET_RANGE and cuts an arc toward it.
## Folded into AbilityCaster in M4.

const TARGET_RANGE := 90.0
const ENEMY_RADIUS := 6.0  # added to the slash range so edge-touching enemies are hit
const FACE_TIME := 0.25

@export var data: AbilityData

var _cooldown := 0.0

@onready var player: Player = get_parent()


func _physics_process(delta: float) -> void:
	_cooldown -= delta
	if _cooldown > 0.0 or player.dead:
		return
	var target := EnemyGrid.nearest(player.global_position, TARGET_RANGE)
	if target == null:
		return
	var dir := (target.global_position - player.global_position).normalized()
	_cooldown = data.cooldown
	player.face_towards(dir, FACE_TIME)
	_slash(dir)


func _slash(dir: Vector2) -> void:
	var origin := player.global_position
	var half_arc := deg_to_rad(data.arc_degrees) / 2.0
	for enemy in EnemyGrid.query(origin, data.range + ENEMY_RADIUS):
		var to_enemy := enemy.global_position - origin
		if absf(dir.angle_to(to_enemy)) <= half_arc:
			enemy.take_damage(data.damage)
	var fx := Effects.get_for(self)
	if fx:
		fx.slash_arc(origin + Vector2(0, -8), dir, data.range, deg_to_rad(data.arc_degrees))
