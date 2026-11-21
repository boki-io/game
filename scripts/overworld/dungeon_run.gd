class_name DungeonRun
extends RefCounted
## The expedition in progress: a cave, dungeon or final vault played as arena stages (spec 1.6, section 8). Held in
## GameSession.dungeon, which is null outside one.

## The marker's markers.json entry.
var marker: Dictionary
var stages: Array[StageData] = []
## 0-based stage being played.
var index := 0
## The journey's progress when the run began (a RunProgress snapshot).
var entry_progress: Dictionary = {}


func _init(marker_data: Dictionary = {}, stage_list: Array[StageData] = [], progress: Dictionary = {}) -> void:
	marker = marker_data
	stages = stage_list
	entry_progress = progress


func marker_name() -> String:
	return String(marker.get("name", ""))


func current_stage() -> StageData:
	return stages[index] if index < stages.size() else null


func is_last() -> bool:
	return index >= stages.size() - 1


## "<marker name> - stage n of N".
func stage_text() -> String:
	return "%s - stage %d of %d" % [marker_name(), index + 1, stages.size()]
