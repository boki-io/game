extends Node
## Autoload. Remembers the selected character, owns scene changes between the Hub, the stage select screen and
## the arena, and holds the path of the current run (in memory only; nothing is saved to disk).

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
## Gold when the run started, so gold earned = gold - run_start_gold.
var run_start_gold := 0
## What the victory screen shows, written by finish_run().
var run_summary: Dictionary = {}
## The Player's carried level, XP and upgrades (see RunProgress). Null at the start of a run and outside a run.
var run_progress: Variant = null
## Coins collected. Unlike the path it is not reset when a run ends: it waits for the future trade system.
var gold := 0


## Test seam: when valid, scene changes call it with the scene path instead of fading to the scene.
var scene_hook: Callable


func _ready() -> void:
	# Default so the run scene also runs directly from the editor.
	character = CharacterRegistry.all()[0]


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
	run_start_gold = gold
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


func is_last_stage() -> bool:
	return path != null and current_column >= path.column_count() - 1


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
		gold_earned = gold - run_start_gold,
		level = player.xp.level if player else 1,
	}
	_clear_run()


## Death: the run is over, back to the hub.
func fail_run() -> void:
	_clear_run()
	go_to_hub()


## The player gave up: same as death.
func abandon_run() -> void:
	_clear_run()
	go_to_hub()


func go_to_hub() -> void:
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
