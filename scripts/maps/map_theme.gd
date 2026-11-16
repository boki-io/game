class_name MapTheme
extends Resource
## One map (spec 0.6 section 4): its identity, palette, light, obstacle layout rules, decor mix and monster looks.
## One file per map at content/maps/<id>/map.tres, listed in MapRegistry. This script keeps its path: .tres files
## name it. Colours are Color, counts are ints.

enum Style { SCATTER, LANES, CLUSTERS }

@export_group("Identity")
## Unique, equal to the folder name.
@export var id: StringName = &""
## Becomes StageData.name; unique.
@export var display_name := ""
## The folder's thumbnail.png (64x40).
@export var thumbnail: Texture2D

@export_group("Monsters")
## One MonsterVariant per enemy type (empty on the default theme).
@export var monsters: Array[MonsterVariant] = []

@export_group("Floor")
## The four plain tile shades.
@export var floor_plain: Array[Color] = []
## The dark patch shade.
@export var floor_dark := Color.BLACK
## The worn-path shade.
@export var floor_light := Color.BLACK
## Fraction of tiles that are pebbled or cracked.
@export_range(0.0, 1.0) var floor_flecks := 0.12

@export_group("Rock")
## The rock band (CaveWalls).
@export var rock := Color.BLACK
@export var rock_dark := Color.BLACK
@export var rock_light := Color.BLACK
## Freestanding walls (CaveWall).
@export var wall_top := Color.BLACK
@export var wall_top_light := Color.BLACK
@export var wall_side := Color.BLACK
@export var wall_outline := Color.BLACK
## The pillar's stone colour.
@export var pillar := Color.BLACK

@export_group("Light")
## Flame colour of the torches.
@export var torch_color := Color.WHITE
## Halo colour (drawn additively).
@export var glow_color := Color.WHITE
## Torches along the walls, 4..12.
@export_range(4, 12) var torch_count := 12
## Multiplied over the world; stays near white (each channel at least 0.8).
@export var ambient := Color.WHITE
## Edge darkness, 0.4..0.8.
@export_range(0.4, 0.8) var vignette := 0.62

@export_group("Layout")
## True only on the default theme: MapLayout then calls the existing layout code and fixed seeds (today's arena).
@export var legacy_layout := false
@export var style := Style.SCATTER
## Freestanding walls.
@export var wall_count := 6
## Allowed lengths in px, a subset of CaveWall.LENGTHS.
@export var wall_lengths: Array[float] = []
## Chance that a wall runs left-right, 0..1.
@export_range(0.0, 1.0) var horizontal_bias := 0.5
@export var pillar_count := 8

@export_group("Decor")
## Pieces of decor, at most 140.
@export_range(0, 140) var decor_count := 110
## CaveDecor.Kind -> weight (float).
@export var decor_weights: Dictionary = {}


## The variant that dresses `enemy_id` on this map, or null when there is none (the enemy keeps its own look).
func variant_for(enemy_id: StringName) -> MonsterVariant:
	for variant in monsters:
		if variant != null and variant.enemy_id == enemy_id:
			return variant
	return null
