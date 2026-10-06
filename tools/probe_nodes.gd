extends SceneTree
func _init() -> void:
	var packed: PackedScene = load("res://LVR CPR.blend")
	var room: Node = packed.instantiate()
	var names: PackedStringArray = []
	_walk(room, names)
	names.sort()
	print("\n".join(names))
	room.free()
	quit()

func _walk(n: Node, out: PackedStringArray) -> void:
	if n is MeshInstance3D:
		out.append(n.name)
	for c in n.get_children(): _walk(c, out)
