class_name PropSet
extends Resource
## A group of props placed as one unit (test-props): a graveyard, a camp, a nook along a wall. One file per set in
## content/props/sets/, listed in the catalog and named in a map's `prop_sets` (set id -> how many).

## Where the set goes: in open floor, along the rock band, or against a freestanding wall (x runs along it).
enum Place { OPEN, BAND, WALL }

@export var id: StringName = &""
@export var display_name := ""
@export var place := Place.OPEN
## OPEN and BAND sets are mirrored left to right half of the time.
@export var mirror := true
@export var members: Array[PropSetMember] = []
