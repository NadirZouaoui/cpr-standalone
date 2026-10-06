extends SceneTree
## One-off probe for the client-feedback planning pass. Dumps:
##  - blend shape names on both casualty meshes (can we compress with the shirt on?)
##  - every Light3D in the room (what goes dark when the supply is isolated?)
##  - the animation clips the .blend actually exports (is there a recovery roll?)

func _init() -> void:
	var packed: PackedScene = load("res://LVR CPR.blend")
	if packed == null:
		print("FAILED to load the .blend"); quit(); return
	var room: Node = packed.instantiate()

	print("=== BLEND SHAPES ===")
	_shapes(room)
	print("\n=== LIGHTS ===")
	_lights(room, "")
	print("\n=== ANIMATIONS ===")
	_anims(room)

	room.free()
	quit()

func _shapes(n: Node) -> void:
	var mi := n as MeshInstance3D
	if mi != null and mi.mesh != null and mi.mesh.get_blend_shape_count() > 0:
		var names: PackedStringArray = []
		for i in mi.mesh.get_blend_shape_count():
			names.append(mi.mesh.get_blend_shape_name(i))
		print("  %s (%d surf) : %s" % [n.name, mi.mesh.get_surface_count(), ", ".join(names)])
	for c in n.get_children(): _shapes(c)

func _lights(n: Node, indent: String) -> void:
	var l := n as Light3D
	if l != null:
		print("  %s (%s) energy=%.2f" % [n.name, n.get_class(), l.light_energy])
	for c in n.get_children(): _lights(c, indent)

func _anims(n: Node) -> void:
	var ap := n as AnimationPlayer
	if ap != null:
		for lib in ap.get_animation_library_list():
			for a in ap.get_animation_library(lib).get_animation_list():
				print("  %s : %.2fs" % [a, ap.get_animation_library(lib).get_animation(a).length])
	for c in n.get_children(): _anims(c)
