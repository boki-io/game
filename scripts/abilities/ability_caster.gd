class_name AbilityCaster
extends Node
## Owns cooldowns, checks mana, runs ability behaviors. One active cast at a time;
## the auto Slash holds off while a Q/E/R cast is running.

signal cast_started(slot: StringName, data: AbilityData)
## reason is &"mana" or &"cooldown".
signal cast_failed(slot: StringName, reason: StringName)

const AUTO_TARGET_RANGE := 90.0
const INPUT_BUFFER := 0.15  # seconds a press is remembered while another cast is running

@export var ability_auto: AbilityData
@export var ability_q: AbilityData
@export var ability_e: AbilityData
@export var ability_r: AbilityData

var cooldowns: Dictionary = {&"auto": 0.0, &"q": 0.0, &"e": 0.0, &"r": 0.0}

var _active: AbilityBehavior
var _behaviors: Dictionary = {}  # slot -> AbilityBehavior
var _buffered_slot: StringName = &""
var _buffer_left := 0.0

@onready var player: Player = get_parent()
@onready var stats: Stats = player.get_node("Stats")
@onready var mana: Mana = player.get_node("Mana")


func _ready() -> void:
	var input: PlayerInput = player.get_node("PlayerInput")
	input.ability_pressed.connect(_on_ability_pressed)


func is_busy() -> bool:
	return _active != null


## Stops the active cast and runs its cleanup (used on death).
func cancel() -> void:
	if _active:
		_active.finish()
		_active = null


func slot_data(slot: StringName) -> AbilityData:
	match slot:
		&"auto":
			return ability_auto
		&"q":
			return ability_q
		&"e":
			return ability_e
		&"r":
			return ability_r
	return null


## Modified stat for an ability, e.g. value(data, &"cooldown", data.cooldown).
func value(data: AbilityData, stat: StringName, base: float) -> float:
	return stats.value(StringName("%s.%s" % [data.id, stat]), base)


func damage_of(data: AbilityData) -> float:
	return value(data, &"damage", data.damage) * stats.value(&"damage", 1.0)


func cooldown_of(data: AbilityData) -> float:
	return value(data, &"cooldown", data.cooldown)


func mana_cost_of(data: AbilityData) -> float:
	return maxf(value(data, &"mana_cost", data.mana_cost), 0.0)


func _physics_process(delta: float) -> void:
	if player.dead:
		return
	for slot: StringName in cooldowns:
		cooldowns[slot] = maxf(cooldowns[slot] - delta, 0.0)

	if _active:
		if _active.update(delta):
			_active.finish()
			_active = null

	if _active == null:
		if _buffer_left > 0.0:
			_buffer_left -= delta
			if _buffer_left > 0.0:
				var slot := _buffered_slot
				_buffered_slot = &""
				_buffer_left = 0.0
				_try_cast(slot)
		if _active == null:
			_auto_cast()


func _on_ability_pressed(slot: StringName) -> void:
	if player.dead:
		return
	if _active:
		_buffered_slot = slot
		_buffer_left = INPUT_BUFFER
		return
	_try_cast(slot)


func _try_cast(slot: StringName) -> void:
	var data := slot_data(slot)
	if data == null or data.behavior == null:
		return
	if cooldowns[slot] > 0.0:
		cast_failed.emit(slot, &"cooldown")
		return
	if not mana.can_afford(mana_cost_of(data)):
		cast_failed.emit(slot, &"mana")
		return
	_begin(slot, data, player.player_input.aim_vector)


func _auto_cast() -> void:
	if ability_auto == null or cooldowns[&"auto"] > 0.0:
		return
	var target := EnemyGrid.nearest(player.global_position, AUTO_TARGET_RANGE)
	if target == null:
		return
	var dir := (target.global_position - player.global_position).normalized()
	_begin(&"auto", ability_auto, dir)


func _begin(slot: StringName, data: AbilityData, aim: Vector2) -> void:
	var cost := mana_cost_of(data)
	if cost > 0.0:
		mana.spend(cost)
		var fx := Effects.get_for(self)
		if fx:
			fx.mana_number(player.global_position + Vector2(16, -22), cost)
	cooldowns[slot] = cooldown_of(data)
	player.face_towards(aim, 0.25)
	cast_started.emit(slot, data)
	if not _behaviors.has(slot):
		_behaviors[slot] = data.behavior.new()
	var behavior: AbilityBehavior = _behaviors[slot]
	behavior.cast(self, aim, data)
	# Instant abilities finish in their first update; the rest keep the caster busy.
	if behavior.update(0.0):
		behavior.finish()
	else:
		_active = behavior
