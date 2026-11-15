class_name DummyReadout
extends Node2D
## The numbers above a training dummy: "Last 22  Total 340  DPS 45".
## A burst is a run of hits where each lands within BURST_GAP of the previous one. Total is the damage in the
## current burst; DPS is Total over the time from the burst's first hit to its last (at least MIN_DURATION).
## The numbers clear KEEP_TIME after the last hit. Damage is counted per hit, not per merged on-screen number.

const BURST_GAP := 3.0
const KEEP_TIME := 3.0
const MIN_DURATION := 1.0

var last := 0.0
var total := 0.0

var _clock := 0.0  # game time, so it stops while the tree is paused
var _burst_start := 0.0
var _last_hit := 0.0
var _has_hits := false


func track(health: Health) -> void:
	health.damaged.connect(_on_damaged)
	set_process(false)


func dps() -> float:
	return total / maxf(_last_hit - _burst_start, MIN_DURATION)


func readout_text() -> String:
	if not _has_hits:
		return ""
	return "Last %d  Total %d  DPS %d" % [roundi(last), roundi(total), roundi(dps())]


func _on_damaged(amount: float) -> void:
	if not _has_hits or _clock - _last_hit > BURST_GAP:
		total = 0.0
		_burst_start = _clock
	last = amount
	total += amount
	_last_hit = _clock
	_has_hits = true
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_clock += delta
	if _clock - _last_hit > KEEP_TIME:
		_has_hits = false
		last = 0.0
		total = 0.0
		set_process(false)
		queue_redraw()


func _draw() -> void:
	var text := readout_text()
	if text.is_empty():
		return
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-60, 0) + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_CENTER, 120.0, 8, Color(0, 0, 0, 0.9))
	draw_string(font, Vector2(-60, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 120.0, 8, Color("ffd866"))
