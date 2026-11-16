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
@export var target_range: float = 0.0  # px, auto-cast targeting range; 0 = caster default (90)
@export var cone_degrees: float = 0.0  # half-angle for aimed target selection
@export var windup: float = 0.0  # seconds before the hit lands
@export var duration: float = 0.0  # seconds the cast lasts (dash time, spin time)
@export var immunity_after: float = 0.0  # seconds the player stays unhittable after the cast
@export var speed_multiplier: float = 1.0  # walking speed while the cast lasts (Phase: 1.5 = +50%)
@export var knockback: float = 0.0  # px/s shove on nearby enemies when the cast ends
@export var behavior: Script  # e.g. DashSlashBehavior
@export var sfx: AudioStream
## Optional second sound played together with `sfx` (Slam's boom), unvaried.
@export var sfx_layer: AudioStream

@export_group("Cast effect")
## Optional animation played when the ability lands. Draw it facing right; it is rotated to the aim.
## When empty, the built-in placeholder shapes are used instead.
@export var effect: SpriteFrames
@export var effect_scale: float = 1.0
@export var effect_offset: float = 0.0  # px from the player along the aim (slash)
