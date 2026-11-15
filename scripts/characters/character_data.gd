class_name CharacterData
extends Resource
## A playable character: look, base stats, abilities and upgrade pool.

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var body_color: Color = Color("4a7bd0")
@export var max_hp: float = 100.0
@export var move_speed: float = 90.0
@export var ability_auto: AbilityData
@export var ability_q: AbilityData
@export var ability_e: AbilityData
@export var ability_r: AbilityData
@export var upgrade_pool: Array[UpgradeData] = []
