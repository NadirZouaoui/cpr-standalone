extends SceneTree
## Walks the real resource dependency graph and reports which image sources the
## build actually reaches, and which it only carries.
##
##     godot --headless --path <project> --script res://tools/probe_asset_usage.gd
##
## WHY A DEPENDENCY WALK AND NOT A GREP
##
## The worker's textures are bound inside "LVR CPR.blend", and the imported
## scene is a zstd-compressed .scn - a grep over .tscn/.tres/.gd sees none of
## them and reports the whole character as unused. ResourceLoader.get_dependencies()
## reads the same table the exporter does, so what it reaches is what ships.
##
## Blind spot, and the reason the report prints a second list: a texture pulled
## in by a runtime load("res://...") with a built-up string is in no dependency
## table. Anything listed as unreachable is checked against a text scan before
## it is deleted.

const IMAGE_EXTS := ["png", "jpg", "jpeg", "bmp", "hdr", "exr", "tga", "svg", "webp"]
const SKIP_DIRS := [".godot", "build", ".git"]

var _seen := {}
var _images := {}

func _init() -> void:
	var roots: Array[String] = ["res://main.tscn"]
	var settings := ProjectSettings.get_property_list()
	for prop in settings:
		var name: String = prop["name"]
		if name.begins_with("autoload/"):
			var value := String(ProjectSettings.get_setting(name))
			roots.append(value.trim_prefix("*"))

	_collect_images("res://")

	for root in roots:
		_walk(_resolve(root))

	var used: Array[String] = []
	var unused: Array[String] = []
	for path in _images:
		if _seen.has(path):
			used.append(path)
		else:
			unused.append(path)
	used.sort()
	unused.sort_custom(func(a, b): return _images[a] > _images[b])

	print("\n=== REACHED from main.tscn + autoloads: %d images ===" % used.size())
	for p in used:
		print("  %8.2f MB  %s" % [_images[p] / 1048576.0, p])

	var total := 0
	for p in unused:
		total += _images[p]
	print("\n=== NOT REACHED: %d images, %.2f MB of source ===" % [unused.size(), total / 1048576.0])
	for p in unused:
		print("  %8.2f MB  %s" % [_images[p] / 1048576.0, p])
	quit()


func _resolve(dep: String) -> String:
	## get_dependencies() entries are "::"-joined and the ordering of uid, type
	## and path is not stable across resource types, so the path is picked out
	## by prefix rather than by index.
	for part in dep.split("::"):
		if part.begins_with("res://"):
			return part
	for part in dep.split("::"):
		if part.begins_with("uid://"):
			var id := ResourceUID.text_to_id(part)
			if ResourceUID.has_id(id):
				return ResourceUID.get_id_path(id)
	return dep


func _walk(path: String) -> void:
	if path == "" or _seen.has(path):
		return
	_seen[path] = true
	if not ResourceLoader.exists(path):
		return
	for dep in ResourceLoader.get_dependencies(path):
		_walk(_resolve(dep))


func _collect_images(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			if not name.begins_with(".") and not SKIP_DIRS.has(name):
				_collect_images(full)
		elif IMAGE_EXTS.has(name.get_extension().to_lower()):
			_images[full] = FileAccess.get_file_as_bytes(full).size()
		name = dir.get_next()
	dir.list_dir_end()
