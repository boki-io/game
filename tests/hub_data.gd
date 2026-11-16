extends SceneTree
## The hub's trait text is typed into the data files, so check it still matches the trait script's constants,
## and that every character has what the info panel shows.
## Run: godot --headless --path . --script tests/hub_data.gd

var _failed := false


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed = true
		print("FAIL: ", what)


func _init() -> void:
	await process_frame
	for c in CharacterRegistry.all():
		_check(not c.display_name.is_empty() and not c.description.is_empty(), "%s has a name and description" % c.id)
		_check(c.ability_auto != null and c.ability_q != null and c.ability_e != null and c.ability_r != null,
			"%s has all four abilities" % c.id)
		_check(c.trait_name.is_empty() == (c.trait_script == null), "%s: trait text and trait script agree" % c.id)
		if c.trait_script == null:
			continue
		var bonus_percent := roundi((c.trait_script.BONUS - 1.0) * 100.0)
		_check(("+%d%%" % bonus_percent) in c.trait_description, "%s trait text shows +%d%%" % [c.id, bonus_percent])
		if not c.trait_script.get_script_constant_map().has("DELAY"):
			continue
		_check(("%ss" % String.num(c.trait_script.DELAY, 2)) in c.trait_description or ("%ds" % int(c.trait_script.DELAY)) in c.trait_description,
			"%s trait text shows the %ss delay" % [c.id, c.trait_script.DELAY])
	for c in CharacterRegistry.all():
		if c.id == &"archer":
			_check("+30%" in c.trait_description and "160" in c.trait_description, "Steady Aim text shows +30% and 160")
			_check(c.trait_script.FULL_DISTANCE == 160.0 and c.trait_script.BONUS == 1.30, "Steady Aim constants match the text")
	print("FAIL" if _failed else "PASS")
	quit(1 if _failed else 0)
