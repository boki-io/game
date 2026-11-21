class_name Journey
extends RefCounted
## One character's saved game in the overworld (spec 1.6): where they stand, the progress they carry (a RunProgress snapshot),
## the checkpoints they lit, the caves and dungeons they cleared and the map they discovered. One file per character
## (JourneySave). Gold, camp attributes and the inventory are not part of it. Marker names are Strings (the JSON's).

const FOG_CELLS := 250
const FOG_BYTES := FOG_CELLS * FOG_CELLS  # 62,500: a byte per 8 x 8 tiles

var character_id: StringName = &""
## World px.
var position := Vector2.ZERO
## The name of the last checkpoint lit (the start camp at first): where the player respawns.
var respawn := ""
var checkpoints: Array[String] = []
## Names of the cleared caves, dungeons and the final vault.
var cleared: Array[String] = []
## Gates opened by a later spec's flag (spec 1.6 has none: every gate is open).
var opened_gates: Array[String] = []
var fog := PackedByteArray()
## A RunProgress snapshot: level, xp, upgrades (StringName -> int), relics (StringName -> int). Never null.
var progress: Dictionary = default_progress()
var playtime := 0.0
var markers_version := 0


static func default_progress() -> Dictionary:
	return {level = 1, xp = 0, upgrades = {}, relics = {}}


## A new journey: at the start camp, which is lit.
static func new_for(id: StringName, world: WorldData) -> Journey:
	var j := Journey.new()
	j.character_id = id
	var start := world.start_marker()
	j.position = WorldData.marker_world(start)
	j.respawn = start.name
	j.checkpoints = [start.name]
	j.fog.resize(FOG_BYTES)
	j.markers_version = world.markers_version
	return j


## Lights a checkpoint (or the start camp) and makes it the respawn. False when it was already lit (the respawn still moves).
func activate_checkpoint(checkpoint_name: String) -> bool:
	respawn = checkpoint_name
	if checkpoint_name in checkpoints:
		return false
	checkpoints.append(checkpoint_name)
	return true


func is_cleared(marker_name: String) -> bool:
	return marker_name in cleared


func mark_cleared(marker_name: String) -> void:
	if not marker_name in cleared:
		cleared.append(marker_name)


## False when a lock is on and no flag has opened the gate. Always true in spec 1.6 (OverworldRules.gate_locked is false).
func gate_open(gate_name: String) -> bool:
	return not OverworldRules.gate_locked(gate_name) or gate_name in opened_gates
