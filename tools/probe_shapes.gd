extends SceneTree
func _init() -> void:
	var packed: PackedScene = load("res://LVR CPR.blend")
	var room: Node = packed.instantiate()
	_walk(room)
	print("--- ANIMATIONS ---")
	_anims(room)
	room.free()
	quit()

func _walk(n: Node) -> void:
	if n is MeshInstance3D and n.mesh != null:
		var m: MeshInstance3D = n
		if m.mesh.get_blend_shape_count() > 0:
			var s: PackedStringArray = []
			for i in m.mesh.get_blend_shape_count():
				s.append(m.mesh.get_blend_shape_name(i))
			print("%s  [%d surf]  shapes: %s" % [m.name, m.mesh.get_surface_count(), ", ".join(s)])
	for c in n.get_children(): _walk(c)

func _anims(n: Node) -> void:
	if n is AnimationPlayer:
		print("AnimationPlayer '%s': %s" % [n.name, ", ".join(n.get_animation_list())])
	for c in n.get_children(): _anims(c)
