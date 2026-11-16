class_name CampSite
extends Node2D
## The camp in the hub: a tent, a chest, a campfire, a camper and a "CAMP" sign, drawn as placeholder shapes (real
## art is later). Pure decoration: no collider and no click area. Drawn relative to its own position (the centre).


func _draw() -> void:
	var font := ThemeDB.fallback_font
	# Sign post on the left, above the tent's front.
	draw_rect(Rect2(-2, -8, 4, 24), Color("4a3320"))
	draw_rect(Rect2(-24, -28, 48, 18), Color("6b4a2b"))
	draw_rect(Rect2(-24, -28, 48, 18), Color("3a2716"), false, 1.5)
	draw_string(font, Vector2(-24, -15), "CAMP", HORIZONTAL_ALIGNMENT_CENTER, 48.0, 11, Color("ffd866"))
	# Tent: a triangle of cloth with a dark doorway, left of centre.
	var t := Vector2(-24, 24)
	draw_colored_polygon(PackedVector2Array([t + Vector2(-26, 0), t + Vector2(26, 0), t + Vector2(0, -34)]), Color("b8654a"))
	draw_colored_polygon(PackedVector2Array([t + Vector2(-7, 0), t + Vector2(7, 0), t + Vector2(0, -16)]), Color("2e1a14"))
	draw_polyline(PackedVector2Array([t + Vector2(-26, 0), t + Vector2(0, -34), t + Vector2(26, 0), t + Vector2(-26, 0)]),
		Color("5a2e22"), 1.5)
	# Chest: a box with a lid and a gold clasp, right of the tent.
	var c := Vector2(26, 22)
	draw_rect(Rect2(c + Vector2(-11, -8), Vector2(22, 14)), Color("7a5230"))
	draw_rect(Rect2(c + Vector2(-11, -14), Vector2(22, 7)), Color("94683c"))
	draw_rect(Rect2(c + Vector2(-11, -14), Vector2(22, 20)), Color("3a2716"), false, 1.5)
	draw_rect(Rect2(c + Vector2(-2, -9), Vector2(4, 5)), Color("ffd866"))
	# Campfire: stones, logs and a flame, below the tent and chest.
	var f := Vector2(-2, 32)
	for i in 6:
		var a := TAU * i / 6.0
		draw_circle(f + Vector2(cos(a) * 9.0, sin(a) * 4.5), 2.5, Color("6e6e78"))
	draw_line(f + Vector2(-6, 2), f + Vector2(6, -2), Color("4a3320"), 3.0)
	draw_line(f + Vector2(-6, -2), f + Vector2(6, 2), Color("4a3320"), 3.0)
	draw_colored_polygon(PackedVector2Array([f + Vector2(-5, 0), f + Vector2(5, 0), f + Vector2(0, -15)]), Color("ff8a2b"))
	draw_colored_polygon(PackedVector2Array([f + Vector2(-2.5, 0), f + Vector2(2.5, 0), f + Vector2(0, -8)]), Color("ffe27a"))
	# Camper: a small figure standing by the chest.
	var p := Vector2(42, 28)
	draw_rect(Rect2(p + Vector2(-4, -12), Vector2(8, 12)), Color("4a78b8"))
	draw_circle(p + Vector2(0, -17), 4.5, Color("e8c8a0"))
	draw_rect(Rect2(p + Vector2(-5, -22), Vector2(10, 3)), Color("5a3a22"))
