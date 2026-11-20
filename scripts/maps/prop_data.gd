class_name PropData
extends Resource
## One sprite prop cut from the props sheet (test-props): where it is on the sheet, where its base is, and whether it
## blocks. Listed in content/props/catalog.tres, which tools/props/build_catalog.py writes.

@export var id: StringName = &""
## storage, grave, furniture, monument or rock: what a map's `prop_weights` picks by.
@export var group: StringName = &""
## The prop's rectangle on the sheet (shadow included).
@export var region := Rect2i()
## The base point inside `region`, in px from its top-left corner: the bottom centre of the opaque body. The
## node's origin sits here, so the prop Y-sorts with characters by its base.
@export var anchor := Vector2.ZERO
## Footprint (width, depth) in px, centred on the base and running up from it. ZERO means walk-through.
@export var block_size := Vector2.ZERO


func blocks() -> bool:
	return block_size != Vector2.ZERO


## The footprint in world coordinates for a prop whose base is at `base`.
func footprint(base: Vector2) -> Rect2:
	return Rect2(base + Vector2(-block_size.x / 2.0, -block_size.y), block_size)
