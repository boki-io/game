class_name PropSetMember
extends Resource
## One line of a PropSet: which prop(s), where, and how many (test-props). Offsets are in the set's own space: x to the
## right, y down (the set's origin is its centre; a wall nook reads x as "along the wall" and y as "away from it").

## Specific props to pick from, one per copy (random). Empty means use `group`.
@export var props: Array[StringName] = []
## A catalog group to pick from when `props` is empty.
@export var group: StringName = &""
## Base position of the first copy, relative to the set origin.
@export var offset := Vector2.ZERO
## Added to the position of each further copy (a row).
@export var step := Vector2.ZERO
## How many copies (a random count between the two).
@export var count_min := 1
@export var count_max := 1
## Each copy lands within this radius of its spot (0 = exact). A scatter is one line with a big `spread`.
@export var spread := 0.0
## Chance that the line is used at all, 0..1.
@export_range(0.0, 1.0) var chance := 1.0
