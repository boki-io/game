class_name MonsterVariant
extends Resource
## How one enemy type looks on one map (spec 0.6 section 7). Appearance only: there is deliberately no gameplay
## field here (health, speed, damage, hitbox, brain all stay in the type's EnemyData). One file per map and type at
## content/maps/<map id>/monsters/<enemy_id>.tres. This script keeps its path: .tres files name it.

enum Mark { NONE, STRIPE, SPOTS, CREST }

## The EnemyData.id this dresses (grunt, ranged, dasher). Equals the file name.
@export var enemy_id: StringName = &""
## The body colour: the type's base colour moved toward the map's colours.
@export var body_color := Color.WHITE
## Today the outline is the body darkened by half, and the eye is white.
@export var outline_color := Color.BLACK
@export var eye_color := Color.WHITE
## One small detail drawn on the body.
@export var mark := Mark.NONE
@export var mark_color := Color.WHITE
