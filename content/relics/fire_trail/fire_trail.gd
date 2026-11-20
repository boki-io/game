class_name FireTrail
extends RelicBehavior
## Fire Trail (spec 1.0, section 4.5). Always on while moving: a flame every STEP px walked, at the feet. Flames
## are data in one array, drawn by one node. One global tick queries every flame and hits each enemy at most
## once per tick, so overlapping flames do not stack. Level 3 also ignites what a flame touches.

const STEP := 12.0
const MAX_PER_STEP := 8
const JUMP := 120.0  # a bigger move in one frame is a teleport: no flames
const MAX_FLAMES := 80
const TICK := 0.5

## Each flame: {pos: Vector2, left: float, life: float}.
var flames: Array[Dictionary] = []

var _last_pos := Vector2.ZERO
var _carry := 0.0  # distance walked since the last flame
var _tick_left := TICK
var _started := false
var _drawer: Node2D


## Draws the flames in world space; the data lives in the behavior.
class Drawer extends Node2D:
	var trail: FireTrail

	func _draw() -> void:
		for f: Dictionary in trail.flames:
			var t: float = clampf(f.left / f.life, 0.0, 1.0)
			var r: float = trail.params().radius * (0.55 + 0.45 * t)
			draw_circle(f.pos, r, Color(1.0, 0.45, 0.1, 0.35 * t + 0.1))
			draw_circle(f.pos, r * 0.6, Color(1.0, 0.8, 0.3, 0.4 * t + 0.1))


func _ready() -> void:
	_drawer = Drawer.new()
	_drawer.trail = self
	_drawer.top_level = true
	_drawer.z_index = 5
	add_child(_drawer)


func _physics_process(delta: float) -> void:
	_walk(player.global_position)
	for i in range(flames.size() - 1, -1, -1):
		flames[i].left -= delta
		if flames[i].left <= 0.0:
			flames.remove_at(i)
	_tick_left -= delta
	if _tick_left <= 0.0:
		_tick_left += TICK
		_burn()
	_drawer.queue_redraw()


## Hidden while the behavior is disabled (the player is dead).
func _notification(what: int) -> void:
	if what == NOTIFICATION_DISABLED and _drawer:
		_drawer.visible = false
	elif what == NOTIFICATION_ENABLED and _drawer:
		_drawer.visible = true


## Drops flames along the move from the last position to `pos`.
func _walk(pos: Vector2) -> void:
	if not _started:
		_started = true
		_last_pos = pos
		return
	var step := pos - _last_pos
	var length := step.length()
	var from := _last_pos
	_last_pos = pos
	if length > JUMP:
		_carry = 0.0
		return
	var total := _carry + length
	var n := int(total / STEP)
	for k in mini(n, MAX_PER_STEP):
		drop_flame(from + step * ((STEP * (k + 1) - _carry) / length))
	_carry = total - STEP * n


## Puts one flame at `pos` (the oldest goes when there are MAX_FLAMES).
func drop_flame(pos: Vector2) -> void:
	if flames.size() >= MAX_FLAMES:
		flames.remove_at(0)
	var life: float = params().life
	flames.append({pos = pos, left = life, life = life})


func _burn() -> void:
	var p := params()
	var hit: Dictionary = {}
	for f: Dictionary in flames:
		for e in EnemyGrid.query(f.pos, p.radius):
			if hit.has(e):
				continue
			hit[e] = true
			e.take_damage(dmg(p.tick))
			if p.ignite_dps > 0.0:
				e.ignite(dmg(p.ignite_dps), p.ignite_seconds)
