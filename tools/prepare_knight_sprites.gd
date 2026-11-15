extends SceneTree
## Turns the raw Knight animation sheets (large opaque frames on a black background) into clean game
## sprites: transparent background, pixel-art downscale, fixed 48x48 cells, feet on a common baseline.
## Writes assets/sprites/knight/*.png and data/characters/knight_frames.tres.
##
## Run:  godot --headless --script tools/prepare_knight_sprites.gd
## Tune: TARGET_HEIGHT (how tall the knight is in game pixels) and the sheet grid below.

const OUT_DIR := "res://assets/sprites/knight/"
const FRAMES_PATH := "res://data/characters/knight_frames.tres"
const CELL := 48  # output frame size in px
const FEET_Y := 44  # row where the feet sit inside the output cell
const TARGET_HEIGHT := 30.0  # knight height in game px (the whole figure including the plume)
const BG_MAX_CHANNEL := 0.09  # a pixel with every channel below this counts as background

const SHEETS := [
	{name = "idle", path = "res://assets/sprites/Pixel Knight Idle Animation Sheet.png", cols = 3, rows = 2, fps = 6.0},
	{name = "walk", path = "res://assets/sprites/walk.png", cols = 4, rows = 2, fps = 10.0},
]


func _initialize() -> void:
	var animations: Array[Dictionary] = []
	for sheet in SHEETS:
		var frames := _process_sheet(sheet)
		var out_path: String = OUT_DIR + "knight_%s.png" % sheet.name
		frames.save_png(ProjectSettings.globalize_path(out_path))
		animations.append({name = sheet.name, path = out_path, count = sheet.cols * sheet.rows, fps = sheet.fps})
		print("wrote ", out_path, " ", frames.get_size())
	_write_sprite_frames(animations)
	print("wrote ", FRAMES_PATH)
	quit()


## Returns a horizontal strip of CELL x CELL frames.
func _process_sheet(sheet: Dictionary) -> Image:
	var img := Image.load_from_file(ProjectSettings.globalize_path(sheet.path))
	img.convert(Image.FORMAT_RGBA8)
	var cells: Array[Image] = []
	for i in sheet.cols * sheet.rows:
		var cx: int = i % sheet.cols
		var cy: int = i / sheet.cols
		var x0 := roundi(float(cx) * img.get_width() / sheet.cols)
		var x1 := roundi(float(cx + 1) * img.get_width() / sheet.cols)
		var y0 := roundi(float(cy) * img.get_height() / sheet.rows)
		var y1 := roundi(float(cy + 1) * img.get_height() / sheet.rows)
		var cell := img.get_region(Rect2i(x0, y0, x1 - x0, y1 - y0))
		_remove_background(cell)
		_remove_flat_dark_blobs(cell)
		cells.append(cell)

	# One crop rectangle for the whole animation keeps frames registered (no jitter between them).
	var union := Rect2i()
	for i in cells.size():
		var used := cells[i].get_used_rect()
		union = used if i == 0 else union.merge(used)
	var scale_factor := TARGET_HEIGHT / float(union.size.y)
	var out_w := maxi(1, roundi(union.size.x * scale_factor))
	var out_h := maxi(1, roundi(union.size.y * scale_factor))
	print(sheet.name, ": figure ", union.size, " px -> ", Vector2i(out_w, out_h), " (scale ", snappedf(scale_factor, 0.0001), ")")

	var strip := Image.create(CELL * cells.size(), CELL, false, Image.FORMAT_RGBA8)
	for i in cells.size():
		var small := _downscale(cells[i].get_region(union), out_w, out_h)
		var dest := Vector2i(i * CELL + (CELL - out_w) / 2, FEET_Y - out_h)
		strip.blit_rect(small, Rect2i(0, 0, out_w, out_h), dest)
	return strip


## Flood-fills near-black pixels connected to the cell border to transparent. Black pixels inside the
## figure (visor slits, outlines) are not reachable from the border, so they stay.
func _remove_background(cell: Image) -> void:
	var w := cell.get_width()
	var h := cell.get_height()
	var seen := PackedByteArray()
	seen.resize(w * h)
	var queue: Array[Vector2i] = []
	for x in w:
		queue.append(Vector2i(x, 0))
		queue.append(Vector2i(x, h - 1))
	for y in h:
		queue.append(Vector2i(0, y))
		queue.append(Vector2i(w - 1, y))
	var head := 0
	while head < queue.size():
		var p := queue[head]
		head += 1
		if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h or seen[p.y * w + p.x] == 1:
			continue
		var c := cell.get_pixelv(p)
		if c.r > BG_MAX_CHANNEL or c.g > BG_MAX_CHANNEL or c.b > BG_MAX_CHANNEL:
			continue
		seen[p.y * w + p.x] = 1
		cell.set_pixelv(p, Color(0, 0, 0, 0))
		queue.append(p + Vector2i.RIGHT)
		queue.append(p + Vector2i.LEFT)
		queue.append(p + Vector2i.DOWN)
		queue.append(p + Vector2i.UP)


## Removes baked-in ground shadows: wide, flat, near-black blobs that survive the background fill because
## a gap separates them from the border. Small dark details (visor slits) are not wide and flat, so stay.
func _remove_flat_dark_blobs(cell: Image) -> void:
	var w := cell.get_width()
	var h := cell.get_height()
	var seen := PackedByteArray()
	seen.resize(w * h)
	for y in h:
		for x in w:
			if seen[y * w + x] == 1 or not _is_dark_opaque(cell.get_pixel(x, y)):
				continue
			var blob: Array[Vector2i] = []
			var stack: Array[Vector2i] = [Vector2i(x, y)]
			seen[y * w + x] = 1
			var lo := Vector2i(x, y)
			var hi := Vector2i(x, y)
			while not stack.is_empty():
				var p: Vector2i = stack.pop_back()
				blob.append(p)
				lo = Vector2i(mini(lo.x, p.x), mini(lo.y, p.y))
				hi = Vector2i(maxi(hi.x, p.x), maxi(hi.y, p.y))
				for d in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
					var n: Vector2i = p + d
					if n.x >= 0 and n.y >= 0 and n.x < w and n.y < h and seen[n.y * w + n.x] == 0 \
							and _is_dark_opaque(cell.get_pixelv(n)):
						seen[n.y * w + n.x] = 1
						stack.append(n)
			var bw := hi.x - lo.x + 1
			var bh := hi.y - lo.y + 1
			if bw >= 30 and bw >= 3 * bh:
				for p in blob:
					cell.set_pixelv(p, Color(0, 0, 0, 0))


func _is_dark_opaque(c: Color) -> bool:
	return c.a > 0.5 and c.r <= BG_MAX_CHANNEL * 2.0 and c.g <= BG_MAX_CHANNEL * 2.0 and c.b <= BG_MAX_CHANNEL * 2.0


## Pixel-art downscale: each output pixel takes the most common colour in its source block, so edges
## stay crisp instead of blurring. A block that is mostly transparent stays transparent.
func _downscale(src: Image, out_w: int, out_h: int) -> Image:
	var out := Image.create(out_w, out_h, false, Image.FORMAT_RGBA8)
	var bw := float(src.get_width()) / out_w
	var bh := float(src.get_height()) / out_h
	for y in out_h:
		for x in out_w:
			var counts: Dictionary = {}
			var opaque := 0
			var total := 0
			for sy in 3:
				for sx in 3:
					var px := clampi(int((x + (sx + 0.5) / 3.0) * bw), 0, src.get_width() - 1)
					var py := clampi(int((y + (sy + 0.5) / 3.0) * bh), 0, src.get_height() - 1)
					var c := src.get_pixel(px, py)
					total += 1
					if c.a < 0.5:
						continue
					opaque += 1
					var key := c.to_rgba32() & 0xF0F0F0FF  # quantise so near-equal colours vote together
					if not counts.has(key):
						counts[key] = {n = 0, color = c}
					counts[key].n += 1
			if opaque * 2 <= total:
				continue
			var best: Dictionary = {}
			for k in counts:
				if best.is_empty() or counts[k].n > best.n:
					best = counts[k]
			out.set_pixel(x, y, best.color)
	return out


func _write_sprite_frames(animations: Array[Dictionary]) -> void:
	var text := "[gd_resource type=\"SpriteFrames\" format=3]\n\n"
	for i in animations.size():
		text += "[ext_resource type=\"Texture2D\" path=\"%s\" id=\"t%d\"]\n" % [animations[i].path, i]
	text += "\n"
	for i in animations.size():
		for f in animations[i].count:
			text += "[sub_resource type=\"AtlasTexture\" id=\"a%d_%d\"]\natlas = ExtResource(\"t%d\")\nregion = Rect2(%d, 0, %d, %d)\n\n" % [i, f, i, f * CELL, CELL, CELL]
	text += "[resource]\nanimations = [\n"
	var parts: PackedStringArray = []
	for i in animations.size():
		var frames: PackedStringArray = []
		for f in animations[i].count:
			frames.append("{\n\"duration\": 1.0,\n\"texture\": SubResource(\"a%d_%d\")\n}" % [i, f])
		parts.append("{\n\"frames\": [%s],\n\"loop\": true,\n\"name\": &\"%s\",\n\"speed\": %s\n}" % [", ".join(frames), animations[i].name, animations[i].fps])
	text += ", ".join(parts) + "\n]\n"
	var file := FileAccess.open(ProjectSettings.globalize_path(FRAMES_PATH), FileAccess.WRITE)
	file.store_string(text)
	file.close()
