class_name StormOrbs
extends RelicBehavior
## Storm Orbs (spec 1.0, section 4.4). Always on: orbs circle the player and burn what they touch. It owns its
## own OrbBelt in endless mode (never Player._belt, which Phase Shift stops). Level 3: each orb also zaps the
## nearest enemy in range every `zap_interval`, staggered so a zap lands every interval / count.

var belt: OrbBelt

var _zap_timers: Array[float] = []


func _ready() -> void:
	belt = OrbBelt.new()
	belt.name = "OrbBelt"
	belt.color = data.color
	add_child(belt)
	_apply()
	belt.start(params().count, params().radius, params().turns, dmg(params().damage), 0.0)
	belt.global_position = player.global_position


func set_level(new_level: int) -> void:
	super(new_level)
	if belt:
		_apply()
	_reset_zaps()


func _physics_process(delta: float) -> void:
	belt.global_position = player.global_position
	_apply()  # the damage stat can change at any moment (Arcane Focus)
	var p := params()
	if not p.zap:
		return
	for i in _zap_timers.size():
		_zap_timers[i] -= delta
		if _zap_timers[i] <= 0.0:
			_zap_timers[i] += p.zap_interval
			_zap(i)


## Hidden while the behavior is disabled (the player is dead).
func _notification(what: int) -> void:
	if what == NOTIFICATION_DISABLED and belt:
		belt.visible = false
	elif what == NOTIFICATION_ENABLED and belt:
		belt.visible = true


func _apply() -> void:
	var p := params()
	belt.set_shape(p.count, p.radius, p.turns, dmg(p.damage))


## Orb i's first zap comes (i + 1) / count of an interval after the level is reached.
func _reset_zaps() -> void:
	_zap_timers.clear()
	var p := params()
	if not p.zap:
		return
	for i in int(p.count):
		_zap_timers.append(p.zap_interval * (i + 1) / float(p.count))


func _zap(i: int) -> void:
	var p := params()
	var from := belt.orb_position(i)
	var target := EnemyGrid.nearest(from, p.zap_range)
	if target == null:
		return
	target.take_damage(dmg(p.zap_damage))
	var fx := Effects.get_for(self)
	if fx:
		fx.lightning(PackedVector2Array([from + OrbBelt.BODY_HEIGHT, target.global_position + OrbBelt.BODY_HEIGHT]))
	Audio.play(&"relic_zap")
