class_name CharacterData
extends Resource
## A playable character: look, base stats, abilities and upgrade pool.

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var body_color: Color = Color("4a7bd0")
@export_group("Sprite")
## Optional animation set. Animation names used: idle, walk, attack1, attack2, hurt, death
## (any that are missing are skipped). Without it the placeholder rectangle is drawn.
@export var sprite_frames: SpriteFrames
## Moves the frames so the character's feet sit on the origin (the point it stands on).
@export var sprite_offset: Vector2 = Vector2.ZERO
@export var sprite_scale: float = 1.0
## Tick if the art is drawn facing left (it is mirrored when the player faces right).
@export var sprite_faces_left: bool = false

@export_group("Stats")
@export var max_hp: float = 100.0
@export var move_speed: float = 90.0
@export var max_mana: float = 100.0
@export var mana_regen: float = 8.0  # per second
## Optional trait: a Node script the player adds as a child (e.g. Arcane Focus).
@export var trait_script: Script
@export_group("Abilities")
@export var ability_auto: AbilityData
@export var ability_q: AbilityData
@export var ability_e: AbilityData
@export var ability_r: AbilityData
@export var upgrade_pool: Array[UpgradeData] = []
