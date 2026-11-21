extends Node
## Autoload. Plays sound effects from a small player pool. Missing files are skipped,
## so the game runs without audio assets.

const POOL_SIZE := 16  # layered impacts start several voices at once
const MIN_INTERVAL_MS := 40  # per-sound throttle so mass hits don't stack into noise
const SOUNDS := [
	&"slash", &"dash", &"spin", &"slam", &"enemy_hit", &"enemy_death", &"xp_pickup",
	&"level_up", &"player_hurt", &"player_death", &"no_mana", &"menu_click",
	&"dasher_charge", &"dasher_dash", &"ranged_windup", &"ranged_shot", &"projectile_hit",
	&"bolt_fire", &"bolt_hit", &"focus_on", &"phase", &"lightning", &"meteor_fall", &"meteor_impact",
	&"hub_focus", &"hub_choose", &"door_open", &"door_enter", &"stage_clear", &"coin",
	&"impact_crack", &"impact_thud", &"kill_pop", &"impact_boom",
	&"relic_wave", &"relic_comet", &"relic_nova", &"relic_zap",
	&"arrow_fire", &"arrow_bounce", &"arrow_rain", &"vacuum_pickup",
]

## Random pitch range per sound: a sound plays at 1.0 plus or minus this much, so repeated hits do not sound identical. Sounds not
## listed (menus, the hub, level-up, stage clear, doors, no-mana, death, charges and wind-ups) always play at exactly 1.0.
const PITCH_SPREAD := {
	&"enemy_hit": 0.08, &"enemy_death": 0.08, &"bolt_hit": 0.08, &"projectile_hit": 0.07, &"xp_pickup": 0.06,
	&"slash": 0.06, &"bolt_fire": 0.06, &"coin": 0.05, &"player_hurt": 0.05, &"ranged_shot": 0.05, &"lightning": 0.05,
	&"spin": 0.04, &"dash": 0.04, &"slam": 0.04, &"dasher_dash": 0.04,
	&"relic_zap": 0.05, &"relic_wave": 0.05,
	&"arrow_fire": 0.06, &"arrow_bounce": 0.06,
}
const RECENT_MAX := 32

## The last RECENT_MAX voices started, {name, pitch, ms}, newest last. Tests read this instead of polling the voices.
var recent: Array[Dictionary] = []
var _streams: Dictionary = {}
var _last_ms: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # menus play clicks while the tree is paused
	for sound: StringName in SOUNDS:
		var path := "res://assets/audio/%s.wav" % sound
		if ResourceLoader.exists(path):
			_streams[sound] = load(path)
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func play(sound: StringName, volume_db: float = 0.0) -> void:
	var stream: AudioStream = _streams.get(sound)
	if stream == null:
		return
	var now := Time.get_ticks_msec()
	if now - _last_ms.get(sound, -1000) < MIN_INTERVAL_MS:
		return
	_last_ms[sound] = now
	play_stream(stream, volume_db, PITCH_SPREAD.get(sound, 0.0))


## An impact made of layers, `strength` 0..1. A hit that does not kill: the hit sound, a crack, and a thud once it is thick (0.4 and up,
## the damage over HEAVY_HIT in enemy.gd). A kill: the death sound, a pop, and a thud under a big body (0.5 and up). Each layer goes
## through the normal per-sound throttle; a layer whose file is missing is skipped.
func impact(kind: StringName, strength: float) -> void:
	strength = clampf(strength, 0.0, 1.0)
	match kind:
		&"hit":
			play(&"enemy_hit", -6.0)
			play(&"impact_crack", -8.0 + 4.0 * strength)
			if strength >= 0.4:
				play(&"impact_thud", -10.0 + 6.0 * strength)
		&"kill":
			play(&"enemy_death", -4.0)
			play(&"kill_pop", -6.0)
			if strength >= 0.5:
				play(&"impact_thud", -8.0 + 6.0 * strength)


## Plays `stream` on a free voice (or steals the next one) at a pitch of 1.0 plus or minus `pitch_spread`. The pitch is set on every
## play, 1.0 exactly for a spread of 0: the voices are reused, and a pitch left from an earlier sound must not stick.
func play_stream(stream: AudioStream, volume_db: float = 0.0, pitch_spread: float = 0.0) -> void:
	if stream == null:
		return
	var voice := _players[_next]
	var found := false
	for i in POOL_SIZE:
		var p := _players[(_next + i) % POOL_SIZE]
		if not p.playing:
			voice = p
			_next = (_next + i + 1) % POOL_SIZE
			found = true
			break
	if not found:
		_next = (_next + 1) % POOL_SIZE  # pool exhausted: steal the next slot
	var pitch := 1.0 + randf_range(-pitch_spread, pitch_spread) if pitch_spread > 0.0 else 1.0
	voice.stream = stream
	voice.volume_db = volume_db
	voice.pitch_scale = pitch
	voice.play()
	recent.append({name = StringName(stream.resource_path.get_file().get_basename()), pitch = pitch, ms = Time.get_ticks_msec()})
	if recent.size() > RECENT_MAX:
		recent.remove_at(0)
