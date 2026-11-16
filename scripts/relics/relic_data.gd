class_name RelicData
extends Resource
## One relic: an automatic power carried in a slot (spec 1.0, section 3). All numbers live in `levels`.

@export var id: StringName
@export var display_name := ""
## Colour of the slot and the card tag.
@export var color := Color.WHITE
## One letter drawn in the slot until there is real icon art.
@export var glyph := ""
## A RelicBehavior subclass; PlayerRelics creates one node from it when the relic is first taken.
@export var behavior: Script
## `levels[i]` is the dictionary of level `i + 1`: the numbers the behavior reads, plus `description`,
## the card text (at most 3 lines of about 18 characters).
@export var levels: Array[Dictionary] = []
