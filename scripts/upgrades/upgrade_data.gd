class_name UpgradeData
extends Resource
## One pick from the level-up menu. Each level applies the same modifiers again.
## adds/mults map Stats keys (e.g. "slash.cooldown", "max_hp") to a per-level value.

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var tag: String  # shown on the card: ability name or "Passive"
@export var max_level: int = 3
@export var adds: Dictionary = {}
@export var mults: Dictionary = {}
