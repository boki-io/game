class_name Hud
extends Control
## In-run HUD, drawn from one canvas item: HP and mana bars, four ability icons with a
## cooldown sweep (dimmed when mana is short), XP bar with level, countdown timer, kills.

const BAR_SIZE := Vector2(90, 8)
const ICON_RADIUS := 11.0
const ICON_GAP := 6.0
const FLASH_TIME := 0.3
const SLOTS := [
	{slot = &"auto", key = "", color = Color("e8e8e8")},
	{slot = &"q", key = "Q", color = Color("6cb4ff")},
	{slot = &"e", key = "E", color = Color("7be08a")},
	{slot = &"r", key = "R", color = Color("ff9a4a")},
]

var player: Player
var run_manager: RunManager

var _flash: Dictionary = {}  # slot -> seconds left (failed cast feedback)
var _mana_flash := 0.0


func bind(p: Player, rm: RunManager) -> void:
	player = p
	run_manager = rm
	player.caster.cast_failed.connect(_on_cast_failed)


func _on_cast_failed(slot: StringName, reason: StringName) -> void:
	if reason == &"mana":
		_flash[slot] = FLASH_TIME
		_mana_flash = FLASH_TIME
		Audio.play(&"no_mana")


func _process(delta: float) -> void:
	for slot: StringName in _flash.keys():
		_flash[slot] -= delta
		if _flash[slot] <= 0.0:
			_flash.erase(slot)
	_mana_flash = maxf(_mana_flash - delta, 0.0)
	queue_redraw()


func _draw() -> void:
	if player == null or run_manager == null:
		return
	var font := ThemeDB.fallback_font
	_draw_bar(Vector2(6, 6), player.health.current, player.health.max_health, Color("d84040"), "HP", font)
	_draw_bar(Vector2(6, 17), player.mana.current, player.mana.max_mana(), Color("3f7fe0"), "MP", font,
		_mana_flash > 0.0)

	var remaining := maxf(RunManager.RUN_DURATION - run_manager.elapsed, 0.0)
	_text(font, Vector2(240, 14), UiKit.format_time(remaining), 12, HORIZONTAL_ALIGNMENT_CENTER, 0)
	_text(font, Vector2(474, 12), "Kills %d" % run_manager.kills, 8, HORIZONTAL_ALIGNMENT_RIGHT, 0)

	_draw_xp(font)
	_draw_icons(font)


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
		origin.x -= 40.0
		w = 80.0
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		origin.x -= 80.0
		w = 80.0
	draw_string(font, origin + Vector2(1, 1), text, align, w, size, Color(0, 0, 0, 0.9))
	draw_string(font, origin, text, align, w, size, Color.WHITE)
