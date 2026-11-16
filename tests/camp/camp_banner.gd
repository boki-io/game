extends SceneTree
## Spec 0.7, 7.4: returning to the hub after a run shows the banked reward as a banner, once, and the counter ends at
## the banked total. Without a reward there is no banner. Works with the last-character early return.

var failures := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _make_hub() -> Node:
	var hub: Node = load("res://scenes/hub.tscn").instantiate()
	root.add_child(hub)
	await process_frame
	return hub


func _initialize() -> void:
	await process_frame
	var gs := root.get_node("GameSession")
	gs.gold = 100
	gs.last_reward = 0
	gs.last_character = null
	var hub: Node = await _make_hub()
	check(hub.reward_banner == null, "no banner without a reward")
	check(hub.gold_counter != null and hub.gold_counter.shown == 100, "counter shows the banked gold (%s, gold %s)" % [hub.gold_counter.shown if hub.gold_counter else -1, gs.gold])
	hub.queue_free()
	await process_frame

	gs.gold = 130
	gs.last_reward = 30
	gs.last_character = load("res://scripts/characters/character_registry.gd").all()[0]
	hub = await _make_hub()  # starts in walk mode: the early return must not skip the banner
	check(hub.reward_banner != null and hub.reward_banner.text == "+30 gold", "banner shows the reward")
	check(gs.last_reward == 0, "the reward is taken once")
	check(hub.gold_counter.shown == 100, "the counter starts at the old total")
	await create_timer(1.6).timeout
	check(hub.gold_counter.shown == 130, "the counter ends at the banked total")
	hub.queue_free()
	await process_frame

	print("PASS" if failures == 0 else "FAIL")
	quit(failures)
