class_name MapLayoutData
extends RefCounted
## The result of MapLayout.generate (spec 0.6 section 6): plain data, no nodes.

## Freestanding rock walls (world rectangles, as CaveWall footprints).
var walls: Array[Rect2] = []
## Pillar base positions (a Prop's origin). The collider is a circle of radius 6 centred 6 px above this.
var pillars: Array[Vector2] = []
## Decor pieces: {kind: CaveDecor.Kind, pos: Vector2, variant: int}.
var decor: Array[Dictionary] = []
## Torch positions along the rock band.
var torches: Array[Vector2] = []
## Sprite props: {id: StringName, pos: Vector2} (pos is the base).
var props: Array[Dictionary] = []
## Footprints of the blocking props (also added to the ObstacleMap; no node is built for them).
var prop_rects: Array[Rect2] = []


## True when both layouts hold exactly the same things in the same order.
func equals(other: MapLayoutData) -> bool:
	return walls == other.walls and pillars == other.pillars and torches == other.torches and decor == other.decor \
			and props == other.props
