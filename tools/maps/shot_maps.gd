extends SceneTree
## Renders every map for review (spec 0.6, section 13). It builds each map with the preview scene (MapBuilder, a fixed
## seed) inside off-screen SubViewports and saves PNGs into a folder:
##   <id>.png          the map at normal zoom (640x360 around the middle, with the three monsters)
##   <id>_full.png     the whole arena (Arena.RUN_SIZE, scaled to fit 1600x896)
##   <id>_monsters.png the monster row, 4x
##   contact_sheet.png all eight whole arenas in a 4x2 grid; monsters_sheet.png the eight monster rows
## Needs a real renderer, so do not pass --headless:
##   godot --path . --script tools/maps/shot_maps.gd -- <folder>
## <folder> defaults to user://map_shots. Optional: --seed=N (default 7; map i uses N + i).

const PREVIEW := "res://scenes/dev/map_preview.tscn"  # loaded at run time: the scene needs the autoloads, which exist from the first frame
const NORMAL := Vector2i(640, 360)
const FULL := Vector2i(1600, 896)
const SHEET_CELL := Vector2i(480, 269)
const MONSTER_CROP := Vector2i(160, 64)
const MONSTER_SCALE := 4

var _folder := "user://map_shots"
var _seed := 7


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			_seed = int(arg.substr(7))
		elif not arg.begins_with("--"):
			_folder = arg
	_run()


func _run() -> void:
	await process_frame
	# Rendering has stalled once on a busy machine; do not hang a script that is waiting on frames.
	create_timer(90.0).timeout.connect(func() -> void:
		push_error("shot_maps: timed out")
		quit(1))
	DirAccess.make_dir_recursive_absolute(_folder)
	var viewport := SubViewport.new()
	viewport.size = FULL
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var preview: Node2D = load(PREVIEW).instantiate()
	preview.show_info = false
	viewport.add_child(preview)
	await _frames(3)
	var maps := MapRegistry.all()
	var fulls: Array[Image] = []
	var rows: Array[Image] = []
	for i in maps.size():
		var theme: MapTheme = maps[i]
		preview.show_map(theme, _seed + i)  # a different seed per map, so the floors differ too
		viewport.size = NORMAL
		preview.zoomed_out = false
		preview._update_camera()
		await _frames(4)
		_save(viewport, "%s.png" % theme.id)
		var centre: Vector2 = preview.monster_centre()
		preview._camera.position = centre
		await _frames(3)
		var row := _crop(viewport, Rect2i((Vector2i(NORMAL) - MONSTER_CROP) / 2 - Vector2i(0, 18), MONSTER_CROP), MONSTER_SCALE)
		_write(row, "%s_monsters.png" % theme.id)
		rows.append(row)
		viewport.size = FULL
		preview.zoomed_out = true
		preview._update_camera()
		await _frames(4)
		var full := viewport.get_texture().get_image()
		_write(full, "%s_full.png" % theme.id)
		fulls.append(full)
	_sheet(fulls, SHEET_CELL, "contact_sheet.png")
	_sheet(rows, MONSTER_CROP * MONSTER_SCALE / 2, "monsters_sheet.png")
	print("Saved %d maps to %s" % [maps.size(), ProjectSettings.globalize_path(_folder)])
	quit(0)


func _frames(n: int) -> void:
	for i in n:
		await process_frame
	RenderingServer.force_draw(false)  # not `await frame_post_draw`: that never fires while the window is hidden


func _save(viewport: SubViewport, file: String) -> void:
	_write(viewport.get_texture().get_image(), file)


func _write(img: Image, file: String) -> void:
	var err := img.save_png("%s/%s" % [_folder, file])
	if err != OK:
		push_error("could not save %s: %d" % [file, err])


func _crop(viewport: SubViewport, rect: Rect2i, scale: int) -> Image:
	var img := viewport.get_texture().get_image().get_region(rect)
	img.resize(rect.size.x * scale, rect.size.y * scale, Image.INTERPOLATE_NEAREST)
	return img


## A 4x2 grid of `images`, each scaled to `cell`.
func _sheet(images: Array[Image], cell: Vector2i, file: String) -> void:
	var sheet := Image.create(cell.x * 4, cell.y * 2, false, Image.FORMAT_RGBA8)
	for i in images.size():
		var img := images[i].duplicate() as Image
		img.resize(cell.x, cell.y, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(img, Rect2i(Vector2i.ZERO, cell), Vector2i(i % 4, i / 4) * cell)
	_write(sheet, file)
