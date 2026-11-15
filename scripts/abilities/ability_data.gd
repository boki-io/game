class_name AbilityData
extends Resource

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var icon: Texture2D
@export var cooldown: float = 1.5  # seconds
@export var mana_cost: float = 10.0
@export var damage: float = 20.0
@export var range: float = 48.0  # px
@export var radius: float = 32.0  # px (AoE / spin / slam)
@export var arc_degrees: float = 90.0  # arc width for slashes
@export var windup: float = 0.0  # seconds before the hit lands
@export var duration: float = 0.0  # seconds the cast lasts (dash time, spin time)
@export var behavior: Script  # e.g. DashSlashBehavior
@export var sfx: AudioStream
