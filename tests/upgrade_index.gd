extends RefCounted
## Finds an upgrade file by its id (the file name is the id). Scans every `upgrades/` folder under data/ (before
## spec 1.2's move) and content/ (after), so a test does not name where an upgrade lives. Not a test: run_all skips it.

static var _paths: Dictionary = {}


static func path_of(id: String) -> String:
	if _paths.is_empty():
		for root: String in ["res://data/upgrades", "res://content"]:
			_scan(root, false)
	return _paths.get(id, "")


static func _scan(dir: String, inside: bool) -> void:
	for f in DirAccess.get_files_at(dir):
		if (inside or dir.ends_with("data/upgrades")) and f.ends_with(".tres"):
			_paths[f.get_basename()] = dir + "/" + f
	for d in DirAccess.get_directories_at(dir):
		if d != "maps" and not d.begins_with("."):
			_scan(dir + "/" + d, inside or d == "upgrades")
