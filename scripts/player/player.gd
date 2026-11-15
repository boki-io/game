class_name Player
extends CharacterBody2D

signal died

@export var move_speed: float = 90.0
@export var max_hp: float = 100.0

## Set before adding to the tree. Supplies abilities, base stats, color and upgrade pool.
var character: CharacterData

var facing := Vector2.RIGHT
var dead := false
## Set by abilities that take over movement (dash). Walls still apply.
var override_active := false
var velocity_override := Vector2.ZERO
## Multiplier on walking speed (spin slows the player).
var speed_scale := 1.0

var _face_dir := Vector2.RIGHT
var _was_blinking := false
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
	move_speed = character.move_speed
	sprite.body_color = character.body_color
	caster.ability_auto = character.ability_auto
	caster.ability_q = character.ability_q
	caster.ability_e = character.ability_e
	caster.ability_r = character.ability_r
	upgrades.pool = character.upgrade_pool


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
	create_tween().tween_property(sprite, "modulate", Color.WHITE, 0.15)


func _on_died() -> void:
	dead = true
	Audio.play(&"player_death")
	caster.cancel()
	_anim_busy = true
	_play(&"death", DEATH_ANIM_TIME)
	velocity = Vector2.ZERO
	sprite.modulate = Color(0.4, 0.4, 0.4)
	hurtbox.set_deferred("monitorable", false)
	died.emit()
