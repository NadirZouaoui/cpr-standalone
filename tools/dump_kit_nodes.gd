extends SceneTree

## Temp diagnostic 4: world positions of the kit items, for camera framing.

func _init() -> void:
	var packed: PackedScene = load("res://LVR CPR.blend")
	var room: Node = packed.instantiate()
	root.add_child(room)
	var names := ["Rescue kit bag", "Fire blanket", "Burns_dressings", "Hook", "Flashlight",
		"Gloves", "Isolate here", "AED Defibrilator Cabinet", "Wrench",
		"Hammer", "Pliers1", "SD1", "SD2", "Level1", "Roulette1", "Pen1",
		"Electric_hammerdrill1", "Radio1"]
	for nm in names:
		var n := _find(room, nm) as Node3D
		if n == null:
			print("%s: NOT FOUND" % nm)
			continue
		var aabb := (n as MeshInstance3D).mesh.get_aabb() if n is MeshInstance3D else AABB()
		var world_aabb := n.global_transform * aabb if n is MeshInstance3D else AABB(n.position, Vector3.ONE)
		print("%-28s pos=%s  world_aabb P=%s S=%s" % [nm, n.global_position, world_aabb.position, world_aabb.size])
	quit()

func _find(n: Node, target: String) -> Node:
	if String(n.name) == target:
		return n
	for c in n.get_children():
		var r := _find(c, target)
		if r != null:
			return r
	return null
