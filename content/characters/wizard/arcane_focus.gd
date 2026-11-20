class_name ArcaneFocus
extends Node2D
## Wizard trait. After standing still for DELAY seconds the Wizard deals BONUS x damage until they move.
## Switches a conditional damage multiplier on Stats, so upgrades are untouched.

const DELAY := 1.0
const BONUS := 1.25
const SOURCE := &"arcane_focus"

var active := false

var _still := 0.0

@onready var player: Player = get_parent()
@onready var stats: Stats = player.get_node("Stats")


func _ready() -> void:
	set_process(false)


func _physics_process(delta: float) -> void:
	if player.dead or player.player_input.move_vector != Vector2.ZERO or player.override_active:
		_still = 0.0
		_set_active(false)
		return
	_still += delta
	if _still >= DELAY:
		_set_active(true)


func _set_active(on: bool) -> void:
	if on == active:
		return
	active = on
	set_process(on)
	if on:
		stats.set_conditional(SOURCE, &"damage", BONUS)
		Audio.play(&"focus_on", -4.0)
	else:
		stats.clear_conditional(SOURCE)
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not active:
		return
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 5.0)
	var radius := 15.0 + 3.0 * pulse
	var pts := PackedVector2Array()
	for i in 25:
		var a := TAU * i / 24.0
		pts.append(Vector2(cos(a) * radius, sin(a) * radius * 0.45))
	draw_polyline(pts, Color(1.0, 0.85, 0.3, 0.45 + 0.35 * pulse), 1.5)
