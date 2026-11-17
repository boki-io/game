extends SceneTree
## Spec 1.1 section 7: the 14 new Archer upgrade files (data only) and the four reused general ones.
## Run: godot --headless --path . --script tests/archer_upgrades.gd

const Index := preload("res://tests/upgrade_index.gd")
const NEW_IDS := [
	&"arrow_twin", &"arrow_pierce", &"arrow_rapid", &"dashshot_range", &"dashshot_spray", &"dashshot_chain",
	&"ricochet_count", &"ricochet_bounce", &"ricochet_hits", &"rain_radius", &"rain_zones", &"rain_linger",
	&"archer_haste", &"archer_eagle"]
const REUSED_IDS := [&"damage", &"max_hp", &"move_speed", &"pickup_radius"]
const TAGS := ["Arrow", "Dash Shot", "Ricochet Volley", "Arrow Rain", "Passive"]
const KEYS := [
	"arrow.extra", "arrow.pierce", "arrow.cooldown", "arrow.range", "dashshot.range", "dashshot.arrows",
	"dashshot.chain", "ricochet.extra", "ricochet.bounces", "ricochet.hits", "arrow_rain.radius",
	"arrow_rain.extra", "arrow_rain.ticks", "cooldown", "steady.full"]
## id -> [key, "adds" or "mults", per-level value, max_level]
const EXPECT := {
	&"arrow_twin": ["arrow.extra", "adds", 1.0, 3], &"arrow_pierce": ["arrow.pierce", "adds", 1.0, 3],
	&"arrow_rapid": ["arrow.cooldown", "mults", 0.85, 3], &"dashshot_range": ["dashshot.range", "mults", 1.3, 3],
	&"dashshot_spray": ["dashshot.arrows", "adds", 2.0, 3], &"dashshot_chain": ["dashshot.chain", "adds", 1.0, 2],
	&"ricochet_count": ["ricochet.extra", "adds", 1.0, 3], &"ricochet_bounce": ["ricochet.bounces", "adds", 1.0, 3],
	&"ricochet_hits": ["ricochet.hits", "adds", 1.0, 3], &"rain_radius": ["arrow_rain.radius", "mults", 1.25, 3],
	&"rain_zones": ["arrow_rain.extra", "adds", 1.0, 2], &"rain_linger": ["arrow_rain.ticks", "adds", 2.0, 3],
	&"archer_haste": ["cooldown", "mults", 0.92, 3], &"archer_eagle": ["arrow.range", "mults", 1.1, 3]}

var _failed := false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _init() -> void:
	var seen: Dictionary = {}
	for id: StringName in NEW_IDS + REUSED_IDS:
		var data: UpgradeData = load(Index.path_of(id))
		_check(data != null, "%s loads" % id)
		if data == null:
			continue
		_check(data.id == id and not seen.has(data.id), "%s has its own unique id" % id)
		seen[data.id] = true
		_check(data.max_level >= 1 and data.max_level <= 3, "%s max_level %d is valid" % [id, data.max_level])
		_check(data.display_name != "" and data.description != "" and data.tag != "", "%s has name, description and tag" % id)
		if id in NEW_IDS:
			_check(data.tag in TAGS, "%s tag %s" % [id, data.tag])
			for key: String in data.adds.keys() + data.mults.keys():
				_check(key in KEYS, "%s uses a known stat key: %s" % [id, key])
			_check(data.adds.size() + data.mults.size() >= 1, "%s changes something" % id)

		# Applying one level to a Stats node changes the key as the spec table says.
		var stats := Stats.new()
		for key: String in data.adds:
			stats.add(StringName(key), data.adds[key])
		for key: String in data.mults:
			stats.multiply(StringName(key), data.mults[key])
		if EXPECT.has(id):
			var e: Array = EXPECT[id]
			_check(data.max_level == e[3], "%s max_level is %d" % [id, e[3]])
			var base := 10.0
			var got: float = stats.value(StringName(e[0]), base)
			var want: float = base + e[2] if e[1] == "adds" else base * e[2]
			_check(is_equal_approx(got, want), "%s: %s is %s, expected %s" % [id, e[0], got, want])
		stats.free()

	# Eagle Eye's second key: the full Steady Aim distance drops 20 px per level.
	var eagle: UpgradeData = load(Index.path_of("archer_eagle"))
	var s := Stats.new()
	for i in eagle.max_level:
		for key: String in eagle.adds:
			s.add(StringName(key), eagle.adds[key])
		for key: String in eagle.mults:
			s.multiply(StringName(key), eagle.mults[key])
	_check(is_equal_approx(s.value(&"steady.full", 160.0), 100.0), "Eagle Eye level 3: steady.full 160 -> 100")
	_check(is_equal_approx(s.value(&"arrow.range", 100.0), 100.0 * pow(1.1, 3)), "Eagle Eye level 3: arrow range x1.331")
	s.free()

	# Exact text from the spec for the two general ones.
	var haste: UpgradeData = load(Index.path_of("archer_haste"))
	_check(haste.display_name == "Fast Hands" and haste.description == "Q, E and R cooldowns -8%", "Fast Hands text")
	_check(eagle.display_name == "Eagle Eye", "Eagle Eye name")

	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)
