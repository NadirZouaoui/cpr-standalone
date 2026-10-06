extends Node
func _ready() -> void:
	var packed := ResourceLoader.load("res://LVR CPR.blend") as PackedScene
	if packed == null:
		printerr("PROBE: could not load res://LVR CPR.blend")
		get_tree().quit(1); return
	var inst := packed.instantiate()
	var found := _walk(inst, "")
	print("PROBE: Casualty_Recovery_Posed present = %s" % ("YES" if found else "NO"))
	inst.free()
	get_tree().quit(0)

func _walk(n: Node, path: String) -> bool:
	if n.name == "Casualty_Recovery_Posed":
		print("PROBE: found at %s/%s (%s)" % [path, n.name, n.get_class()])
		var mi := n as MeshInstance3D
		if mi != null and mi.mesh != null:
			var names: Array = []
			for i in mi.mesh.get_blend_shape_count():
				names.append(str(mi.mesh.get_blend_shape_name(i)))
			print("PROBE: blend shapes = %s" % [names])
			print("PROBE: transform = %s" % [n.transform])
		return true
	for c in n.get_children():
		if _walk(c, path + "/" + str(n.name)):
			return true
	return false
