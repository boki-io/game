class_name EnemyProjectile
extends Area2D
## Pooled shot fired by Ranged enemies. Hurts the player, vanishes on walls and props.
## Dodge only: no player ability destroys it. It passes through a player who is invulnerable.

var active := false
var damage := 0.0
var pool: Projectiles

var _velocity := Vector2.ZERO
var _life := 0.0


func _ready() -> void:
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)


func launch(pos: Vector2, dir: Vector2, speed: float, dmg: float, lifetime: float) -> void:
	global_position = pos
	_velocity = dir * speed
	damage = dmg
	_life = lifetime
	rotation = dir.angle()
	active = true
	visible = true
	set_physics_process(true)
	set_deferred("monitoring", true)


func retire() -> void:
	if not active:
		return
	active = false
	visible = false
	set_physics_process(false)  # not process_mode: it can't change inside a physics callback
	set_deferred("monitoring", false)
	pool.release(self)


func _physics_process(delta: float) -> void:
	global_position += _velocity * delta
	_life -= delta
	if _life <= 0.0:
		retire()


func _on_area_entered(area: Area2D) -> void:
	if active and area is Hurtbox and area.receive_hit(damage):
		Audio.play(&"projectile_hit")
		retire()


func _on_body_entered(_body: Node2D) -> void:
	retire()


func _draw() -> void:
	draw_line(Vector2(-9, 0), Vector2(0, 0), Color(1.0, 0.55, 0.15, 0.35), 3.0)
	draw_line(Vector2(-5, 0), Vector2(0, 0), Color(1.0, 0.7, 0.25, 0.6), 2.0)
	draw_circle(Vector2.ZERO, 3.5, Color(1.0, 0.45, 0.1))
	draw_circle(Vector2.ZERO, 2.0, Color(1.0, 0.95, 0.7))
