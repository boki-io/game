extends SceneTree
## Knight's Double Dash upgrade: after the first dash the follow-up is free, the cooldown is frozen while the
## chain is open, it starts when the chain ends, and an unused chain expires after its window.
## Run: godot --headless --path . --script tests/double_dash.gd

var _failed := false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _init() -> void:
	await process_frame
	await process_frame
	var F: GDScript = load("res://tests/fixture.gd")
	var main: Node = F.start_run(self, &"knight")
	await F.frames(self, 3)
	var p = F.player()
	F.upgrade(p, "dash_chain")
	var caster = p.caster
	var cooldown = caster.cooldown_of(caster.ability_q)

	var mana_before = p.mana.current
	F.cast(p, &"q")
	await F.seconds(self, 0.4)
	_check(not caster.is_busy(), "the dash has finished")
	_check(caster.chain_open(&"q"), "a follow-up is available after the first dash")
	_check(caster.chain_remaining(&"q") == 1, "one follow-up left")
	_check(mana_before - p.mana.current > caster.mana_cost_of(caster.ability_q) * 0.5, "the first dash costs mana (less a little regen)")
	_check(is_equal_approx(caster.cooldowns[&"q"], cooldown), "cooldown is frozen while the chain is open")

	var mana_open = p.mana.current
	F.cast(p, &"q", Vector2.LEFT)
	await F.seconds(self, 0.4)
	_check(p.mana.current >= mana_open, "the follow-up is free")
	_check(not caster.chain_open(&"q"), "the chain closes after the last follow-up")
	_check(caster.cooldowns[&"q"] < cooldown, "the cooldown starts when the chain ends")

	# An unused chain expires after CHAIN_WINDOW and then the cooldown runs.
	await F.seconds(self, cooldown + 0.2)
	_check(caster.cooldowns[&"q"] == 0.0, "cooldown finished")
	F.cast(p, &"q")
	await F.seconds(self, 0.4)
	_check(caster.chain_open(&"q"), "chain open again")
	await F.seconds(self, caster.CHAIN_WINDOW + 0.2)
	_check(not caster.chain_open(&"q"), "an unused chain expires")
	_check(caster.cooldowns[&"q"] < cooldown, "the cooldown runs after the window expires")

	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)
