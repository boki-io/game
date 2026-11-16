class_name Ambience
extends Node2D
## Ambient life (spec v0.9 section 3): a fixed number of tiny drifting motes in the world, five kinds of motion chosen per map.
## Kept apart from the Effects bits and their cap. Motes live in world space around the camera: a mote that leaves the visible
## area (plus MARGIN) or reaches the end of its life respawns inside it. Uses no autoload, so a test can preload it.
## The numbers are visual constants, not tuning data.

const MARGIN := 16.0
const FADE := 0.5  # seconds to fade in and out
const WIND := Vector2(4.0, 8.0)  # DUST: sideways drift range, px/s

var kind: int = MapTheme.AmbienceKind.DUST
var color := Color(0.8, 0.75, 0.65)
var count := 40

var _rng := RandomNumberGenerator.new()
var _motes: Array[Dictionary] = []
var _placed := false


## `theme` null keeps today's cave: 40 motes of warm dust. `map_seed` seeds every random choice, respawns included.
func setup(theme: MapTheme, map_seed: int) -> void:
	if theme != null:
		kind = theme.ambience_kind
		color = theme.ambience_color
		count = theme.ambience_count
	_rng.seed = map_seed
	_motes.clear()
	_placed = false
	for i in count:
		_motes.append({})


func _ready() -> void:
	z_index = 4  # above the y-sorted world, below the damage zones (5), projectiles (6) and effects (10)


## The motes (read by tests).
func motes() -> Array[Dictionary]:
	return _motes


## The visible world area grown by MARGIN: the canvas transform includes the camera, its offset and its shake.
func visible_rect() -> Rect2:
	return (get_canvas_transform().affine_inverse() * get_viewport_rect()).grow(MARGIN)


func _process(delta: float) -> void:
	var rect := visible_rect()
	if not _placed:
		for m in _motes:
			_respawn(m, rect, true)
		_placed = true
	for m in _motes:
		m.age += delta
		_move(m, delta)
		if m.age >= m.life or not rect.has_point(m.pos):
			_respawn(m, rect, false)
	queue_redraw()


func _respawn(m: Dictionary, rect: Rect2, initial: bool) -> void:
	m.pos = Vector2(_rng.randf_range(rect.position.x, rect.end.x), _rng.randf_range(rect.position.y, rect.end.y))
	m.phase = _rng.randf() * TAU
	m.size = 1
	m.heading = _rng.randf() * TAU
	match kind:
		MapTheme.AmbienceKind.DUST:
			m.life = _rng.randf_range(6.0, 10.0)
			m.vel = Vector2(_rng.randf_range(WIND.x, WIND.y), 0.0)
		MapTheme.AmbienceKind.EMBERS:
			m.size = 2
			m.life = _rng.randf_range(2.0, 4.0)
			m.vel = Vector2(0.0, -_rng.randf_range(14.0, 28.0))
		MapTheme.AmbienceKind.SPORES:
			m.size = 2
			m.life = _rng.randf_range(6.0, 10.0)
			m.vel = Vector2.from_angle(m.heading) * _rng.randf_range(3.0, 7.0)
		MapTheme.AmbienceKind.FROST:
			m.size = 2 if _rng.randf() < 0.25 else 1
			m.life = _rng.randf_range(5.0, 8.0)
			m.vel = Vector2(0.0, _rng.randf_range(10.0, 18.0))
		_:  # GLINT: it does not move
			m.size = 2
			m.life = _rng.randf_range(0.8, 1.6)
			m.vel = Vector2.ZERO
	m.speed = m.vel.length()
	m.age = _rng.randf() * m.life if initial else 0.0


func _move(m: Dictionary, delta: float) -> void:
	match kind:
		MapTheme.AmbienceKind.DUST:
			m.pos += m.vel * delta
			m.pos.y += sin(m.age * 1.3 + m.phase) * 2.0 * delta
		MapTheme.AmbienceKind.EMBERS:
			m.pos += m.vel * delta
			m.pos.x += cos(m.age * 2.0 + m.phase) * 12.0 * delta  # a sway of about 6 px
		MapTheme.AmbienceKind.SPORES:
			m.heading += sin(m.age * 0.9 + m.phase) * 1.2 * delta
			m.pos += Vector2.from_angle(m.heading) * m.speed * delta
			m.pos.y += sin(m.age * 2.0 + m.phase) * 2.0 * delta
		MapTheme.AmbienceKind.FROST:
			m.pos += m.vel * delta
			m.pos.x += cos(m.age * 1.5 + m.phase) * 6.0 * delta  # a sway of about 4 px
		_:
			pass


## The mote's alpha now, 0 at birth and at death. GLINT has an envelope of its own; the others fade in and out over FADE.
func alpha_of(m: Dictionary) -> float:
	if kind == MapTheme.AmbienceKind.GLINT:
		return 0.9 * sin(PI * clampf(m.age / m.life, 0.0, 1.0))
	var fade := clampf(minf(m.age / FADE, (m.life - m.age) / FADE), 0.0, 1.0)
	match kind:
		MapTheme.AmbienceKind.DUST:
			return 0.35 * fade
		MapTheme.AmbienceKind.EMBERS:
			return (0.65 + 0.25 * sin(m.age * 14.0 + m.phase)) * fade  # flickers between 0.4 and 0.9
		_:
			return 0.5 * fade


func _draw() -> void:
	if not _placed:
		return
	for m in _motes:
		var a := alpha_of(m)
		if a <= 0.0:
			continue
		var s: int = m.size
		draw_rect(Rect2(m.pos.round() - Vector2(s / 2, s / 2), Vector2(s, s)), Color(color, a))
