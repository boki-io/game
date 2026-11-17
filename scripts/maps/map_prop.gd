class_name MapProp
extends StaticBody2D
## A sprite prop in the arena (test-props). The origin is the prop's base, so it Y-sorts with the characters. A
## blocking prop is solid for the Player (a rectangle, like the walls and pillars); enemies avoid it through the
## ObstacleMap, which the builder gives the same rectangle.


## Builds the sprite and the collider from `data`; call before the node is added.
func setup(data: PropData, sheet: Texture2D) -> void:
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(data.region)
	var sprite := Sprite2D.new()
	sprite.texture = atlas
	sprite.centered = false
	sprite.position = -data.anchor
	add_child(sprite)
	collision_layer = 1
	collision_mask = 0
	if data.blocks():
		var shape := RectangleShape2D.new()
		shape.size = data.block_size
		var cs := CollisionShape2D.new()
		cs.shape = shape
		cs.position = Vector2(0.0, -data.block_size.y / 2.0)
		add_child(cs)
