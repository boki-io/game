extends Node
## Autoload. Plays sound effects from a small player pool. Missing files are skipped,
## so the game runs without audio assets.

const POOL_SIZE := 12
const MIN_INTERVAL_MS := 40  # per-sound throttle so mass hits don't stack into noise
const SOUNDS := [
	&"slash", &"dash", &"spin", &"slam", &"enemy_hit", &"enemy_death", &"xp_pickup",
	&"level_up", &"player_hurt", &"player_death", &"no_mana", &"menu_click",
	&"dasher_charge", &"dasher_dash", &"ranged_windup", &"ranged_shot", &"projectile_hit",
	&"bolt_fire", &"bolt_hit",
]

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
	play_stream(stream, volume_db)


func play_stream(stream: AudioStream, volume_db: float = 0.0) -> void:
	if stream == null:
		return
	for i in POOL_SIZE:
		var p := _players[(_next + i) % POOL_SIZE]
		if not p.playing:
			_next = (_next + i + 1) % POOL_SIZE
			p.stream = stream
			p.volume_db = volume_db
			p.play()
			return
	# Pool exhausted: steal the next slot.
	var victim := _players[_next]
	_next = (_next + 1) % POOL_SIZE
	victim.stream = stream
	victim.volume_db = volume_db
	victim.play()
