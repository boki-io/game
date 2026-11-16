class_name RicochetVolley
extends Node
## The arrows of one Ricochet Volley after the first. A child of the Player (created on the first cast) so the
## caster stays free: it fires one arrow every `interval` seconds along the aim at that moment, so the player can
## sweep the volley. It stops when the player dies and after the last arrow, and pauses with the tree. A shot
## the projectile pool cannot take is skipped, not queued.

const PATTERN: Array[float] = [0.0, -3.0, 3.0, -6.0, 6.0, 0.0]  # spread in degrees, by arrow number

var _caster: AbilityCaster
var _data: AbilityData
var _total := 0
var _next := 0  # the number of the next arrow to fire
var _wait := 0.0
var _interval := 0.1
var _hits := 3
var _bounces := 3
var _reach := 140.0


func _ready() -> void:
	set_physics_process(false)


## True while arrows are still to be fired.
func active() -> bool:
	return _next < _total


## Starts a volley: arrow 1 goes at once, the rest follow every `interval` seconds.
func start(c: AbilityCaster, d: AbilityData) -> void:
	_caster = c
	_data = d
	_total = maxi(int(d.param(&"arrows", 6.0)) + int(c.value(d, &"extra", 0.0)), 1)
	_interval = maxf(d.param(&"interval", 0.1), 0.01)
	_hits = int(c.value(d, &"hits", d.param(&"hits", 3.0)))
	_bounces = int(c.value(d, &"bounces", d.param(&"bounces", 3.0)))
	_reach = d.param(&"bounce_reach", 140.0)
	_next = 0
	_wait = _interval
	_fire_next()
	set_physics_process(active())


func _physics_process(delta: float) -> void:
	if _caster.player.dead:
		_next = _total
	else:
		_wait -= delta
		while _wait <= 0.0 and active():
			_wait += _interval
			_fire_next()
	if not active():
		set_physics_process(false)


func _fire_next() -> void:
	var index := _next
	_next += 1
	var pool := PlayerProjectiles.get_for(_caster)
	if pool == null:
		return
	var dir := _caster.player.player_input.aim_vector.rotated(deg_to_rad(PATTERN[index % PATTERN.size()]))
	var opts := {&"arrow": true, &"steady": true, &"hits": _hits, &"bounces": _bounces, &"bounce_reach": _reach,
		&"steady_full": _caster.stats.value(&"steady.full", SteadyAim.FULL_DISTANCE)}
	var reach := _caster.value(_data, &"range", _data.range)
	var speed := _data.param(&"speed", 360.0)
	if pool.fire(_caster.player.global_position, dir, speed, _caster.damage_of(_data), reach, 0, opts):
		Audio.play(&"arrow_fire")
