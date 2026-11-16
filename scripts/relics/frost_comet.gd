class_name FrostComet
extends RelicBehavior
## Frost Comet (spec 1.0, section 4.2): every `cooldown` seconds `comets` distinct random enemies within RANGE px are marked;
## 0.5 s later a comet lands where each one stood, hurting and freezing everything in `radius`. The damage lands before
## the freeze, so the comet's own hit never gets the vulnerable multiplier. The random pick uses the relic's own `rng`.

const RANGE := 200.0
const DELAY := 0.5
const RETRY := 0.25

## Owned by the relic, so a test can seed it.
var rng := RandomNumberGenerator.new()

var _cooldown_left := 0.0
var _retry_left := 0.0
var _impact_sound: AudioStream


func _ready() -> void:
	if ResourceLoader.exists("res://assets/audio/relic_comet.wav"):
		_impact_sound = load("res://assets/audio/relic_comet.wav")


func cooldown_fraction() -> float:
	return clampf(_cooldown_left / float(params().cooldown), 0.0, 1.0)


func set_level(new_level: int) -> void:
	super(new_level)
	_cooldown_left = minf(_cooldown_left, float(params().cooldown))


func _physics_process(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	_retry_left -= delta
	if _cooldown_left > 0.0 or _retry_left > 0.0:
		return
	if _cast():
		_cooldown_left = float(params().cooldown)
	else:
		_retry_left = RETRY


func _cast() -> bool:
	var zones := DamageZones.get_for(self)
	if zones == null:
		return false
	var found: Array = EnemyGrid.query(player.global_position, RANGE)
	if found.is_empty():
		return false
	# A stable order, so the same seed picks the same enemies however the grid happens to list them.
	found.sort_custom(func(a: Enemy, b: Enemy) -> bool: return a.get_instance_id() < b.get_instance_id())
	var p := params()
	var fx := Effects.get_for(self)
	var extras := {freeze = {seconds = float(p.freeze), vulnerable = float(p.vulnerable)}}
	if _impact_sound:
		extras.sfx = _impact_sound
	var picks := mini(int(p.comets), found.size())
	for i in picks:
		var j := rng.randi_range(i, found.size() - 1)
		var e: Enemy = found[j]
		found[j] = found[i]
		found[i] = e
		var pos := e.global_position
		if fx:
			fx.telegraph(pos, float(p.radius), DELAY)
		zones.add_burst(pos, float(p.radius), dmg(float(p.damage)), DELAY, 0.0, extras)
	return true
