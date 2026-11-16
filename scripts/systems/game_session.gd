extends Node
## Autoload. Remembers the selected character, owns scene changes between the Hub, the stage select screen and
## the arena, holds the path of the current run (in memory only) and the camp state (banked gold and attribute
## levels), which is loaded from and saved to disk through SaveGame.

const HUB := "res://scenes/hub.tscn"
const SELECT := "res://scenes/select.tscn"
const RUN := "res://scenes/main.tscn"

## The character of the current or next run.
var character: CharacterData
## The character last taken into a run this session. Null at boot: the hub then starts in browse mode.
var last_character: CharacterData

## The generated graph of the current run. Null outside a run.
var path: StagePath
var path_seed := 0
## 0-based column the player is about to play or is playing.
var current_column := 0
## The row (top to bottom) taken in each column cleared so far.
var beaten: Array[int] = []
## The stage being played. Null outside a run.
var current_stage: StageData
## Row of `current_stage` in its column. -1 when none.
var current_row := -1
## Kills over the cleared stages of this run.
var run_kills := 0
## What the victory screen shows, written by finish_run().
var run_summary: Dictionary = {}
## The Player's carried level, XP and upgrades (see RunProgress). Null at the start of a run and outside a run.
var run_progress: Variant = null
## Banked gold, spendable at the camp. Saved (SaveGame); only bank_run() and the camp raise it.
var gold := 0
## Coins collected in the current run (the run purse). Not saved; banked when the run ends.
var run_gold := 0
## Gold banked since the hub last read it with take_reward().
var last_reward := 0
## Camp attribute levels (spec 0.7): attribute id -> level, shared by all characters. Saved (SaveGame).
var attribute_levels: Dictionary = {}

## Emitted after any attribute level or the gold spent on it changes.
signal attributes_changed

## Test seam: when valid, scene changes call it with the scene path instead of fading to the scene.
var scene_hook: Callable


func _ready() -> void:
	# Default so the run scene also runs directly from the editor.
	character = CharacterRegistry.all()[0]
	var saved := SaveGame.load_data()
	gold = saved.gold
	attribute_levels = saved.levels


## The camp level of attribute `id` (0 if never bought).
func level_of(id: StringName) -> int:
	var attr := AttributeRegistry.find(id)
	return 0 if attr == null else CampShop.level_of(_shop_state(), attr)


## Buys the next level of attribute `id` with `gold`. False if unknown, maxed or too poor.
func buy_attribute(id: StringName) -> bool:
	var attr := AttributeRegistry.find(id)
	if attr == null:
		return false
	var state := _shop_state()
	var ok := CampShop.buy(state, attr)
	if ok:
		_commit_shop(state)
	return ok


## Undoes one level of attribute `id` and refunds its cost. False at level 0.
func undo_attribute(id: StringName) -> bool:
	var attr := AttributeRegistry.find(id)
	if attr == null:
		return false
	var state := _shop_state()
	var ok := CampShop.undo(state, attr)
	if ok:
		_commit_shop(state)
	return ok


## Undoes every level and refunds the total spent.
func reset_attributes() -> void:
	var state := _shop_state()
	CampShop.reset_all(state)
	_commit_shop(state)


## Gold sunk into the current attribute levels.
func spent_total() -> int:
	return CampShop.spent(_shop_state())


func _shop_state() -> Dictionary:
	return CampShop.make_state(gold, attribute_levels.duplicate())


func _commit_shop(state: Dictionary) -> void:
	gold = state.gold
	attribute_levels = state.levels
	SaveGame.save(gold, attribute_levels)
	attributes_changed.emit()


## The seed of the map being played (spec 0.6, 6.1): a string hash of the path seed and the theme id, so each map
## is stable for a given path and differs between runs. 0 with no stage or no theme (an editor run).
func map_seed() -> int:
	if current_stage == null or current_stage.theme == null:
		return 0
	return hash("%d:%s" % [path_seed, current_stage.theme.id])


## Door entry: a new path from a random seed, then the select screen.
func start_run(selected: CharacterData) -> void:
	new_run(selected, randi())
	_go(SELECT)


## Sets up a fresh run from `seed` without changing scene.
func new_run(selected: CharacterData, seed_value: int) -> void:
	character = selected
	last_character = selected
	path_seed = seed_value
	path = PathGenerator.generate(seed_value)
	current_column = 0
	beaten.clear()
	current_stage = null
	current_row = -1
	run_kills = 0
	run_gold = 0
	run_summary = {}
	run_progress = null


## Rows of the current column the player may pick: all of column 1, then those the last beaten stage leads to.
func available_rows() -> Array[int]:
	var rows: Array[int] = []
	if path == null:
		return rows
	if current_column == 0:
		for row in path.columns[0].size():
			rows.append(row)
		return rows
	return path.next_rows(current_column - 1, beaten.back())


func available_stages() -> Array[StageData]:
	var out: Array[StageData] = []
	for row in available_rows():
		out.append(path.stage_at(current_column, row))
	return out


## Starts the arena for `stage`, which must be one of the available stages.
func select_stage(stage: StageData) -> void:
	for row in available_rows():
		if path.stage_at(current_column, row) == stage:
			current_row = row
			current_stage = stage
			_go(RUN)
			return


## True on the final column. Without a path (main.tscn run from the editor) a won stage is also the last.
func is_last_stage() -> bool:
	return path == null or current_column >= path.column_count() - 1


## A stage of column 1 or 2 was won: records it, adds its kills, saves the Player's progress, moves on to the
## next column and loads the select screen.
func complete_stage() -> void:
	beaten.append(current_row)
	run_kills += _stage_kills()
	var player := _player()
	if player:
		run_progress = RunProgress.capture(player)
	current_column += 1
	current_stage = null
	current_row = -1
	_go(SELECT)


## The final stage was won: snapshots the summary for the victory screen and clears the path.
func finish_run() -> void:
	var player := _player()
	run_summary = {
		stages_cleared = path.column_count() if path else 0,
		kills = run_kills + _stage_kills(),
		gold_earned = run_gold,
		level = player.xp.level if player else 1,
	}
	bank_run()
	_clear_run()


## Death: the run is over, back to the hub.
func fail_run() -> void:
	_clear_run()
	go_to_hub()


## The player gave up: banks the purse, same as death.
func abandon_run() -> void:
	bank_run()
	_clear_run()
	go_to_hub()


## Moves the run purse into the banked gold and saves. Returns the reward (0 with an empty purse, when nothing
## changes). Called when a run ends (victory, death screen, abandon) and again by go_to_hub as a safety net.
func bank_run() -> int:
	var reward := run_gold
	if reward <= 0:
		run_gold = 0
		return 0
	gold += reward
	run_gold = 0
	last_reward += reward
	SaveGame.save(gold, attribute_levels)
	return reward


## What the hub shows once: the gold banked since the last call, which is cleared.
func take_reward() -> int:
	var reward := last_reward
	last_reward = 0
	return reward


func go_to_hub() -> void:
	bank_run()
	_go(HUB)


func _go(scene_path: String) -> void:
	if scene_hook.is_valid():
		scene_hook.call(scene_path)
	else:
		SceneFader.fade_to_scene(scene_path)


func _clear_run() -> void:
	path = null
	current_stage = null
	current_row = -1
	current_column = 0
	beaten.clear()
	run_progress = null


func _player() -> Player:
	return PlayerRegistry.players[0] if not PlayerRegistry.players.is_empty() else null


## Kills of the stage in play (RunManager resets per stage).
func _stage_kills() -> int:
	var scene := get_tree().current_scene
	var manager: Variant = scene.get("run_manager") if scene else null
	return manager.kills if manager else 0
