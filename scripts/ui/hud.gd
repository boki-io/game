class_name Hud
extends Control
## HUD, drawn from one canvas item: HP and mana bars, four ability icons with a
## cooldown sweep (dimmed when mana is short), XP bar with level, countdown timer, kills.
## Without a RunManager (the hub) only the mana bar and the ability icons are drawn.

const BAR_SIZE := Vector2(90, 8)
const ICON_RADIUS := 11.0
const ICON_GAP := 6.0
const FLASH_TIME := 0.3
## The red edge pulse when the player takes a hit: bands stepping in from every screen edge, fading over HURT_PULSE_TIME.
const HURT_PULSE_TIME := 0.35
const HURT_BANDS := 8
const HURT_BAND_WIDTH := 6.0
const HURT_ALPHA := 0.3
## Relic slots (spec 1.0): a column on the right edge under Kills and gold.
const RELIC_SLOT_SIZE := 22.0
const RELIC_SLOT_GAP := 4.0
const RELIC_COLUMN_TOP := 36.0
const RELIC_MARGIN := 28.0
const SLOTS := [
	{slot = &"auto", key = "", color = Color("e8e8e8")},
	{slot = &"q", key = "Q", color = Color("6cb4ff")},
	{slot = &"e", key = "E", color = Color("7be08a")},
	{slot = &"r", key = "R", color = Color("ff9a4a")},
]

var player: Player
var run_manager: RunManager

var _stage_text := ""
var _flash: Dictionary = {}  # slot -> seconds left (failed cast feedback)
var _mana_flash := 0.0
var _hurt_pulse := 0.0  # seconds of the red edge pulse left
var _relic_flash: Dictionary = {}  # relic slot index -> seconds left (gained or raised)


func bind(p: Player, rm: RunManager = null) -> void:
	player = p
	run_manager = rm
	_stage_text = ""
	var stage := GameSession.current_stage
	if rm != null and stage != null and GameSession.path != null:
		_stage_text = "Stage %d/%d - %s" % [GameSession.current_column + 1, GameSession.path.column_count(), stage.name]
	_hurt_pulse = 0.0
	player.caster.cast_failed.connect(_on_cast_failed)
	player.hurtbox.hit_taken.connect(_on_hit_taken)
	_relic_flash.clear()
	player.relics.flashed.connect(_on_relic_flashed)
	player.tree_exiting.connect(_on_player_exiting.bind(p))


func _on_player_exiting(p: Player) -> void:
	if player == p:
		player = null


func _on_relic_flashed(slot: int) -> void:
	_relic_flash[slot] = FLASH_TIME


## Whether the MP bar (and its no-mana flash) is shown for `character`.
static func shows_mana(character: CharacterData) -> bool:
	return character == null or character.uses_mana


func _on_hit_taken(_amount: float) -> void:
	_hurt_pulse = HURT_PULSE_TIME


func _on_cast_failed(slot: StringName, reason: StringName) -> void:
	if reason == &"cooldown":
		return
	_flash[slot] = FLASH_TIME
	Audio.play(&"no_mana")
	if reason == &"mana" and shows_mana(player.character):
		_mana_flash = FLASH_TIME


func _process(delta: float) -> void:
	for slot: StringName in _flash.keys():
		_flash[slot] -= delta
		if _flash[slot] <= 0.0:
			_flash.erase(slot)
	for slot: int in _relic_flash.keys():
		_relic_flash[slot] -= delta
		if _relic_flash[slot] <= 0.0:
			_relic_flash.erase(slot)
	_mana_flash = maxf(_mana_flash - delta, 0.0)
	_hurt_pulse = maxf(_hurt_pulse - delta, 0.0)
	queue_redraw()


func _draw() -> void:
	if not is_instance_valid(player):
		return
	if _hurt_pulse > 0.0:
		_draw_hurt_pulse()
	var font := ThemeDB.fallback_font
	if run_manager == null:
		if shows_mana(player.character):
			_draw_bar(Vector2(6, 6), player.mana.current, player.mana.max_mana(), Color("3f7fe0"), "MP", font,
				_mana_flash > 0.0)
		_draw_icons(font)
		return
	_draw_bar(Vector2(6, 6), player.health.current, player.health.max_health, Color("d84040"), "HP", font)
	if shows_mana(player.character):
		_draw_bar(Vector2(6, 17), player.mana.current, player.mana.max_mana(), Color("3f7fe0"), "MP", font,
			_mana_flash > 0.0)

	if player.trait_active():
		_text(font, Vector2(28, 36), "FOCUS", 8, HORIZONTAL_ALIGNMENT_CENTER, 0)
	var remaining := maxf(RunManager.RUN_DURATION - run_manager.elapsed, 0.0)
	var view := get_viewport_rect().size
	_text(font, Vector2(view.x / 2.0, 14), UiKit.format_time(remaining), 12, HORIZONTAL_ALIGNMENT_CENTER, 0)
	if _stage_text != "":
		_text(font, Vector2(view.x / 2.0, 25), _stage_text, 8, HORIZONTAL_ALIGNMENT_CENTER, 200.0)
	_text(font, Vector2(view.x - 6.0, 12), "Kills %d" % run_manager.kills, 8, HORIZONTAL_ALIGNMENT_RIGHT, 0)
	_draw_gold(font, view)

	_draw_xp(font)
	_draw_icons(font)
	_draw_relics(font, view)


## Red bands along the four screen edges, strongest at the edge and fading inward and over time.
func _draw_hurt_pulse() -> void:
	var view := get_viewport_rect().size
	var fade := _hurt_pulse / HURT_PULSE_TIME
	for i in HURT_BANDS:
		var color := Color(0.9, 0.1, 0.1, HURT_ALPHA * (1.0 - i / float(HURT_BANDS)) * fade)
		var off := i * HURT_BAND_WIDTH
		draw_rect(Rect2(0, off, view.x, HURT_BAND_WIDTH), color)  # top
		draw_rect(Rect2(0, view.y - off - HURT_BAND_WIDTH, view.x, HURT_BAND_WIDTH), color)  # bottom
		draw_rect(Rect2(off, 0, HURT_BAND_WIDTH, view.y), color)  # left
		draw_rect(Rect2(view.x - off - HURT_BAND_WIDTH, 0, HURT_BAND_WIDTH, view.y), color)  # right


## A drawn coin and the gold number, right-aligned under the kills counter.
func _draw_gold(font: Font, view: Vector2) -> void:
	var text := str(GameSession.run_gold)
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	var right := view.x - 6.0
	_text(font, Vector2(right, 24), text, 8, HORIZONTAL_ALIGNMENT_RIGHT, 0)
	var centre := Vector2(right - width - 7.0, 21.5)
	draw_circle(centre, 3.5, Color("c89a1c"))
	draw_circle(centre, 2.5, Color("ffd23f"))


## The rect of relic slot `i` (0 to 3) for a viewport of size `view`.
static func relic_slot_rect(i: int, view: Vector2) -> Rect2:
	return Rect2(view.x - RELIC_MARGIN, RELIC_COLUMN_TOP + i * (RELIC_SLOT_SIZE + RELIC_SLOT_GAP),
		RELIC_SLOT_SIZE, RELIC_SLOT_SIZE)


## Seconds of flash left on relic slot `i` (0 when not flashing).
func relic_flash_left(i: int) -> float:
	return _relic_flash.get(i, 0.0)


## Four relic slots: a dim outline when empty; owned = tinted square, glyph, level pips and, for timed
## relics, a cooldown sweep (cooldown_fraction() is 0 for always-on ones, so nothing is drawn for them).
func _draw_relics(font: Font, view: Vector2) -> void:
	var relics: PlayerRelics = player.relics
	var ids := relics.levels.keys()
	for i in PlayerRelics.MAX_SLOTS:
		var rect := relic_slot_rect(i, view)
		draw_rect(rect, Color(0, 0, 0, 0.6))
		if i >= ids.size():
			draw_rect(rect, Color(1, 1, 1, 0.2), false, 1.0)
			continue
		var data := RelicRegistry.find(ids[i])
		var color: Color = data.color
		draw_rect(rect, Color(color, 0.35))
		var behavior := relics.behavior_of(ids[i])
		var cd := behavior.cooldown_fraction() if behavior != null else 0.0
		if cd > 0.0:
			_draw_square_sweep(rect.get_center(), rect.size / 2.0, cd)
		_text(font, rect.get_center() + Vector2(0, 1), data.glyph, 8, HORIZONTAL_ALIGNMENT_CENTER, 0)
		var level: int = relics.levels[ids[i]]
		for k in PlayerRelics.MAX_LEVEL:
			var pip := Rect2(rect.position.x + 5.0 + k * 5.0, rect.end.y - 5.0, 3.0, 2.0)
			draw_rect(pip, Color.WHITE if k < level else Color(1, 1, 1, 0.25))
		var ring := Color(color, 0.9)
		if _relic_flash.has(i):
			draw_rect(rect, Color(1, 1, 1, 0.6 * _relic_flash[i] / FLASH_TIME))
			ring = Color.WHITE
		draw_rect(rect, ring, false, 1.0)


func _draw_bar(pos: Vector2, value: float, maximum: float, color: Color, label: String, font: Font,
		flash: bool = false) -> void:
	draw_rect(Rect2(pos, BAR_SIZE), Color(0, 0, 0, 0.6))
	var frac := clampf(value / maxf(maximum, 1.0), 0.0, 1.0)
	draw_rect(Rect2(pos, Vector2(BAR_SIZE.x * frac, BAR_SIZE.y)), color)
	draw_rect(Rect2(pos, BAR_SIZE), Color(1, 0.3, 0.3) if flash else Color(1, 1, 1, 0.5), false)
	_text(font, pos + Vector2(3, 7), "%s %d/%d" % [label, ceili(value), roundi(maximum)], 8,
		HORIZONTAL_ALIGNMENT_LEFT, 0)


func _draw_xp(font: Font) -> void:
	var size := get_viewport_rect().size
	var rect := Rect2(0, size.y - 5, size.x, 5)
	draw_rect(rect, Color(0, 0, 0, 0.6))
	var frac := float(player.xp.xp) / float(player.xp.needed())
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * frac, rect.size.y)), Color("b06cff"))
	_text(font, Vector2(6, size.y - 8), "Lv %d" % player.xp.level, 8, HORIZONTAL_ALIGNMENT_LEFT, 0)


func _draw_icons(font: Font) -> void:
	var size := get_viewport_rect().size
	var textured := _any_icon_textures()
	var step := (32.0 if textured else ICON_RADIUS * 2.0) + ICON_GAP
	var x0 := size.x / 2.0 - step * (SLOTS.size() - 1) / 2.0
	var y := size.y - (28.0 if textured else 24.0)
	for i in SLOTS.size():
		var info: Dictionary = SLOTS[i]
		var slot: StringName = info.slot
		var data := player.caster.slot_data(slot)
		var c := Vector2(x0 + step * i, y)
		if data != null and data.icon != null:
			_draw_textured_icon(font, c, info, data)
			continue
		draw_circle(c, ICON_RADIUS + 1.0, Color(0, 0, 0, 0.7))
		if data == null:
			draw_arc(c, ICON_RADIUS, 0.0, TAU, 20, Color(1, 1, 1, 0.2), 1.0)
			continue
		var affordable := player.mana.can_afford(player.caster.mana_cost_of(data))
		var color: Color = info.color
		draw_circle(c, ICON_RADIUS - 3.0, color if affordable else color.darkened(0.7))
		var chaining := player.caster.chain_open(slot)
		var cd: float = player.caster.cooldowns[slot]
		if cd > 0.0 and not chaining:
			_draw_sweep(c, ICON_RADIUS, cd / maxf(player.caster.cooldown_of(data), 0.01))
			_text(font, c + Vector2(0, 3), "%.1f" % cd, 8, HORIZONTAL_ALIGNMENT_CENTER, 0)
		var ring := Color(1, 1, 1, 0.5)
		if not affordable and not chaining:
			ring = Color(0.3, 0.5, 1.0, 0.9)
		if _flash.has(slot):
			ring = Color(1, 0.2, 0.2)
		draw_arc(c, ICON_RADIUS, 0.0, TAU, 20, ring, 1.0)
		if chaining:
			_draw_chain_hint(font, c, slot, ICON_RADIUS)
		if info.key != "":
			_text(font, c + Vector2(0, ICON_RADIUS + 9), info.key, 8, HORIZONTAL_ALIGNMENT_CENTER, 0)


## Double Dash: a gold ring that drains with the follow-up window, and "xN" follow-ups left.
func _draw_chain_hint(font: Font, c: Vector2, slot: StringName, radius: float) -> void:
	var fraction := player.caster.chain_window_fraction()
	draw_arc(c, radius + 3.0, -PI / 2.0, -PI / 2.0 + TAU * fraction, 32, Color("ffd23f"), 2.0)
	_text(font, c + Vector2(0, -radius - 6.0), "x%d" % player.caster.chain_remaining(slot), 8,
		HORIZONTAL_ALIGNMENT_CENTER, 0)


func _any_icon_textures() -> bool:
	for info: Dictionary in SLOTS:
		var data := player.caster.slot_data(info.slot)
		if data != null and data.icon != null:
			return true
	return false


## Native-size icon from AbilityData.icon with a square cooldown sweep.
func _draw_textured_icon(font: Font, c: Vector2, info: Dictionary, data: AbilityData) -> void:
	var slot: StringName = info.slot
	var half := data.icon.get_size() / 2.0
	var affordable := player.mana.can_afford(player.caster.mana_cost_of(data))
	draw_rect(Rect2(c - half - Vector2(1, 1), half * 2.0 + Vector2(2, 2)), Color(0, 0, 0, 0.7))
	draw_texture(data.icon, c - half, Color.WHITE if affordable else Color(0.35, 0.4, 0.65))
	var chaining := player.caster.chain_open(slot)
	var cd: float = player.caster.cooldowns[slot]
	if cd > 0.0 and not chaining:
		_draw_square_sweep(c, half, cd / maxf(player.caster.cooldown_of(data), 0.01))
		_text(font, c + Vector2(0, 3), "%.1f" % cd, 8, HORIZONTAL_ALIGNMENT_CENTER, 0)
	var ring := Color(1, 1, 1, 0.5)
	if not affordable and not chaining:
		ring = Color(0.3, 0.5, 1.0, 0.9)
	if _flash.has(slot):
		ring = Color(1, 0.2, 0.2)
	draw_rect(Rect2(c - half, half * 2.0), ring, false, 1.0)
	if chaining:
		_draw_chain_hint(font, c, slot, half.y)
	if info.key != "":
		_text(font, c + Vector2(half.x - 4.0, half.y - 1.0), info.key, 8, HORIZONTAL_ALIGNMENT_CENTER, 0)


## Square version of the cooldown sweep: shades `fraction` of the icon, shrinking clockwise from 12 o'clock.
func _draw_square_sweep(c: Vector2, half: Vector2, fraction: float) -> void:
	var start := -PI / 2.0 + TAU * (1.0 - clampf(fraction, 0.0, 1.0))
	var pts := PackedVector2Array([c])
	var steps := 48
	for i in steps + 1:
		var a := start + (-PI / 2.0 + TAU - start) * i / steps
		var p := Vector2.from_angle(a) * half.length() * 1.5
		pts.append(c + Vector2(clampf(p.x, -half.x, half.x), clampf(p.y, -half.y, half.y)))
	draw_colored_polygon(pts, Color(0, 0, 0, 0.65))


## Shades `fraction` of the circle, shrinking clockwise from 12 o'clock.
func _draw_sweep(c: Vector2, radius: float, fraction: float) -> void:
	var start := -PI / 2.0 + TAU * (1.0 - clampf(fraction, 0.0, 1.0))
	var pts := PackedVector2Array([c])
	var steps := 16
	for i in steps + 1:
		pts.append(c + Vector2.from_angle(start + (-PI / 2.0 + TAU - start) * i / steps) * radius)
	draw_colored_polygon(pts, Color(0, 0, 0, 0.65))


func _text(font: Font, pos: Vector2, text: String, size: int, align: HorizontalAlignment, width: float) -> void:
	var w := width if width > 0.0 else -1.0
	var origin := pos
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		w = width if width > 0.0 else 80.0
		origin.x -= w / 2.0
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		origin.x -= 80.0
		w = 80.0
	draw_string(font, origin + Vector2(1, 1), text, align, w, size, Color(0, 0, 0, 0.9))
	draw_string(font, origin, text, align, w, size, Color.WHITE)
