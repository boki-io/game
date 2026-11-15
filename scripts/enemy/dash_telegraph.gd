class_name DashTelegraph
extends Node2D
## The ground lane a Dasher projects before lunging. Yellow while it is still aiming,
## red and filling toward the tip once locked. Drawn in world space, above the ground
## and below characters.

const AIM_COLOR := Color("ffd23f")
const LOCK_COLOR := Color("ff2a2a")

var from := Vector2.ZERO
var dir := Vector2.RIGHT
var length := 140.0
var width := 26.0
var locked := false
var lock_progress := 0.0  # 0..1 over the lock time


func _ready() -> void:
	top_level = true
	global_position = Vector2.ZERO
	z_index = -4
	visible = false
	set_process(false)


func show_lane() -> void:
	visible = true
	set_process(true)


func hide_lane() -> void:
	visible = false
	set_process(false)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var side := dir.orthogonal() * width / 2.0
	var end := from + dir * length
	var base := LOCK_COLOR if locked else AIM_COLOR
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * (30.0 if locked else 8.0))
	var quad := PackedVector2Array([from + side, end + side, end - side, from - side])
	draw_colored_polygon(quad, Color(base, 0.18 + 0.14 * pulse))
	if locked and lock_progress > 0.0:
		var tip := from + dir * length * lock_progress
		draw_colored_polygon(PackedVector2Array([from + side, tip + side, tip - side, from - side]),
			Color(base, 0.45))
	draw_polyline(PackedVector2Array([from + side, end + side, end - side, from - side, from + side]),
		Color(base, 0.9), 1.0)
	draw_colored_polygon(PackedVector2Array([end + side * 1.1, end + dir * 12.0, end - side * 1.1]),
		Color(base, 0.55 + 0.4 * pulse))
