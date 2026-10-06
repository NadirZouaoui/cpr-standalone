extends SceneTree

var out_lines: PackedStringArray = []

func _init() -> void:
	var packed: PackedScene = load("res://LVR CPR.blend")
	if packed == null:
		print("FAILED to load LVR CPR.blend")
		quit()
		return
	var room: Node = packed.instantiate()
	_find_and_print(room, "")
	var global_path := ProjectSettings.globalize_path("res://tools/out.txt")
	var f := FileAccess.open(global_path, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(out_lines))
		f.close()
	else:
		push_error("Could not open " + global_path)
	room.free()
	quit()

func _find_and_print(n: Node, indent: String) -> void:
	if "Casualty" in n.name or "Armature" in n.name or "Boots" in n.name or "Character" in n.name or "Posed" in n.name:
		var extra := ""
		if n is Node3D:
			extra += " pos=%s rot=%s scale=%s basis_det=%f" % [n.position, n.rotation_degrees, n.scale, n.basis.determinant()]
		if n is MeshInstance3D:
			extra += " mesh=%s skin=%s skel=%s" % [n.mesh.resource_name if n.mesh else "none", n.skin != null, n.skeleton]
			if n.mesh != null:
				for s in n.mesh.get_surface_count():
					var mat: Material = n.get_active_material(s)
					extra += " [s%d: mat=%s cull=%s]" % [s, mat.resource_name if mat else "none", (mat as BaseMaterial3D).cull_mode if (mat is BaseMaterial3D) else "?"]
		out_lines.append(indent + n.name + " (" + n.get_class() + ")" + extra)
	for c in n.get_children():
		_find_and_print(c, indent + "  ")




