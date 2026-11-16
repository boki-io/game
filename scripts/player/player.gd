class_name Player
extends CharacterBody2D

signal died

@export var move_speed: float = 90.0
@export var max_hp: float = 100.0

## Set before adding to the tree. Supplies abilities, base stats, color and upgrade pool.
var character: CharacterData
## Set before adding to the tree. The hub: infinite mana, no damage to take, no progression.
var hub_mode := false
## Set before adding to the tree: camp attribute levels (id -> level). Written to `stats` once, in
## `_apply_character`, before max HP and mana are read. Empty means no bonuses.
var attribute_levels: Dictionary = {}

var facing := Vector2.RIGHT
var dead := false
## Set by abilities that take over movement (dash). Walls still apply.
var override_active := false
var velocity_override := Vector2.ZERO
## Multiplier on walking speed (spin slows the player).
var speed_scale := 1.0

var _face_dir := Vector2.RIGHT
var _was_blinking := false

# Phase Shift: a timed ghost state (invulnerable, faster, optional touch damage).
const PHASE_TINT := Color(0.55, 0.8, 1.0, 0.5)
const PHASE_TOUCH_RADIUS := 16.0
const PHASE_TOUCH_INTERVAL := 0.25
var phase_left := 0.0
var _hit_tint_tween: Tween
var _phase_touch_damage := 0.0
var _phase_touch_cd := 0.0
var _phase_grace := 0.0
var _phase_trail_cd := 0.0
var _phase_belt: Dictionary = {}  # params for the orb belt that follows the phase (empty = none)
var _belt: Node2D  # an OrbBelt, created on first use
var _anim: AnimatedSprite2D  # only when the character has sprite_frames
var _anim_busy := false  # an attack, hurt or death animation is playing
var _attack_toggle := false

const ATTACK_ANIM_TIME := 0.25  # attack and hurt animations are sped up to fit this
const HURT_ANIM_TIME := 0.2
const DEATH_ANIM_TIME := 0.7
const ONE_SHOT_ANIMS: Array[StringName] = [&"attack1", &"attack2", &"hurt", &"death"]
var _face_time := 0.0

@onready var player_input: PlayerInput = $PlayerInput
@onready var sprite: Node2D = $Sprite
@onready var health: Health = $Health
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var stats: Stats = $Stats
@onready var mana: Mana = $Mana
@onready var caster: AbilityCaster = $AbilityCaster
@onready var xp: PlayerXP = $XP
@onready var upgrades: PlayerUpgrades = $Upgrades
@onready var collector: XPCollector = $XPCollector


func _ready() -> void:
	if character:
		_apply_character()
	PlayerRegistry.register(self)
	if character and character.sprite_frames:
		_setup_animation()
	caster.cast_started.connect(_on_cast_started)
	health.setup(stats.value(&"max_hp", max_hp))
	health.died.connect(_on_died)
	hurtbox.hit_taken.connect(_on_hit_taken)


func _apply_character() -> void:
	max_hp = character.max_hp
	CampAttributes.apply(stats, attribute_levels)
	mana.configure(character.max_mana, character.mana_regen)
	mana.infinite = hub_mode
	move_speed = character.move_speed
	sprite.body_color = character.body_color
	caster.ability_auto = character.ability_auto
	caster.ability_q = character.ability_q
	caster.ability_e = character.ability_e
	caster.ability_r = character.ability_r
	upgrades.pool = character.upgrade_pool
	if character.trait_script:
		var trait_node: Node = character.trait_script.new()
		trait_node.name = "Trait"
		add_child(trait_node)


func _exit_tree() -> void:
	PlayerRegistry.unregister(self)


func _physics_process(delta: float) -> void:
	if dead:
		return
	var move := player_input.move_vector
	if override_active:
		velocity = velocity_override
	else:
		velocity = move * stats.value(&"move_speed", move_speed) * speed_scale
	move_and_slide()
	if move != Vector2.ZERO:
		facing = move.normalized()
	_tick_phase(delta)
	var regen := stats.value(&"hp_regen", 0.0)
	if regen > 0.0 and health.current < health.max_health:
		health.heal(regen * delta)
	_update_grace_blink()
	_face_time -= delta
	var look := _face_dir if _face_time > 0.0 else facing
	sprite.facing = look
	_update_animation(look, move)
	sprite.aim = player_input.aim_vector


## Briefly turn the sprite toward a cast direction (it otherwise faces movement).
func face_towards(dir: Vector2, duration: float) -> void:
	_face_dir = dir
	_face_time = duration


## Starts Phase Shift: unhittable and `speed_mult` times faster for `duration` seconds.
func start_phase(duration: float, speed_mult: float, touch_damage: float, grace_after: float,
		belt: Dictionary = {}) -> void:
	phase_left = duration
	_phase_belt = belt
	speed_scale = speed_mult
	hurtbox.invulnerable = true
	_phase_touch_damage = touch_damage
	_phase_touch_cd = 0.0
	_phase_grace = grace_after
	if _hit_tint_tween:
		_hit_tint_tween.kill()  # a pending hit-tint fade would overwrite the ghost tint
	sprite.modulate = PHASE_TINT


func end_phase(grace: bool = true) -> void:
	if phase_left <= 0.0 and not hurtbox.invulnerable:
		return
	phase_left = 0.0
	speed_scale = 1.0
	hurtbox.invulnerable = false
	if grace:
		hurtbox.grant_grace(_phase_grace)
	sprite.modulate = Color.WHITE
	if grace and not _phase_belt.is_empty():
		_start_belt()
	elif _belt:
		_belt.stop()


func _start_belt() -> void:
	if _belt == null:
		_belt = load("res://scripts/player/orb_belt.gd").new()
		_belt.name = "OrbBelt"
		add_child(_belt)
	_belt.start(_phase_belt.count, _phase_belt.radius, _phase_belt.turns, _phase_belt.damage, _phase_belt.duration)


func trait_active() -> bool:
	var t := get_node_or_null("Trait")
	return t != null and t.get("active") == true


func _tick_phase(delta: float) -> void:
	if phase_left <= 0.0:
		return
	phase_left -= delta
	_phase_trail_cd -= delta
	if _phase_trail_cd <= 0.0:
		_phase_trail_cd = 0.07
		var fx := Effects.get_for(self)
		if fx:
			fx.puff(global_position + Vector2(0, -8), Color(0.6, 0.8, 1.0))
	if _phase_touch_damage > 0.0:
		_phase_touch_cd -= delta
		if _phase_touch_cd <= 0.0:
			_phase_touch_cd = PHASE_TOUCH_INTERVAL
			for e in EnemyGrid.query(global_position, PHASE_TOUCH_RADIUS):
				e.take_damage(_phase_touch_damage)
	if phase_left <= 0.0:
		end_phase()


## Flickers the sprite while post-dash immunity is active so the player can see it.
func _update_grace_blink() -> void:
	var blinking := hurtbox.grace_left > 0.0
	if blinking:
		sprite.modulate.a = 0.45 if int(Time.get_ticks_msec() / 60) % 2 == 0 else 0.85
	elif _was_blinking:
		sprite.modulate.a = 1.0
	_was_blinking = blinking


## Re-read stats that other components cache (call after an upgrade).
func refresh_stats() -> void:
	health.set_max(stats.value(&"max_hp", max_hp))
	mana.refresh()
	collector.refresh()


func _setup_animation() -> void:
	var frames := character.sprite_frames
	for anim in frames.get_animation_names():
		frames.set_animation_loop(anim, not ONE_SHOT_ANIMS.has(anim))
	_anim = AnimatedSprite2D.new()
	_anim.sprite_frames = frames
	_anim.scale = Vector2(character.sprite_scale, character.sprite_scale)
	_anim.position = character.sprite_offset
	_anim.animation_finished.connect(func() -> void: _anim_busy = false)
	sprite.add_child(_anim)  # a child of the sprite so hit tint and the dash blink apply to it
	sprite.body_visible = false  # keep the shadow, hide the rectangle
	_play(&"idle")


## Plays `anim`; one-shot animations are sped up (or slowed) to last about `fit_time` seconds.
func _play(anim: StringName, fit_time: float = 0.0) -> void:
	if _anim == null or not _anim.sprite_frames.has_animation(anim):
		return
	var frames := _anim.sprite_frames
	var natural := frames.get_frame_count(anim) / maxf(frames.get_animation_speed(anim), 0.01)
	_anim.speed_scale = natural / fit_time if fit_time > 0.0 else 1.0
	_anim.play(anim)


func _update_animation(look: Vector2, move: Vector2) -> void:
	if _anim == null:
		return
	if absf(look.x) > 0.1:
		var mirror := look.x > 0.0 if character.sprite_faces_left else look.x < 0.0
		_anim.flip_h = mirror
		_anim.position.x = -character.sprite_offset.x if mirror else character.sprite_offset.x
	if _anim_busy:
		return
	var want: StringName = &"walk" if (move != Vector2.ZERO or override_active) else &"idle"
	if _anim.animation != want or not _anim.is_playing():
		_play(want)


func _on_cast_started(_slot: StringName, _data: AbilityData) -> void:
	if _anim == null:
		return
	_attack_toggle = not _attack_toggle
	var anim: StringName = &"attack1" if _attack_toggle else &"attack2"
	if _anim.sprite_frames.has_animation(anim):
		_anim_busy = true
		_play(anim, ATTACK_ANIM_TIME)


func _on_hit_taken(_amount: float) -> void:
	if _anim and _anim.sprite_frames.has_animation(&"hurt"):
		_anim_busy = true
		_play(&"hurt", HURT_ANIM_TIME)
	Audio.play(&"player_hurt")
	CameraFollow.shake(self, 1.5, 0.12)
	sprite.modulate = Color(1, 0.35, 0.35)
	if _hit_tint_tween:
		_hit_tint_tween.kill()
	_hit_tint_tween = create_tween()
	_hit_tint_tween.tween_property(sprite, "modulate", Color.WHITE, 0.15)


func _on_died() -> void:
	dead = true
	end_phase(false)
	if _belt:
		_belt.stop()
	Audio.play(&"player_death")
	caster.cancel()
	_anim_busy = true
	_play(&"death", DEATH_ANIM_TIME)
	velocity = Vector2.ZERO
	sprite.modulate = Color(0.4, 0.4, 0.4)
	hurtbox.set_deferred("monitorable", false)
	died.emit()
