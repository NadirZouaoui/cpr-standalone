extends SceneTree
## Headless: measure the closed-door geometry so the interaction hitbox can
## be sized from facts rather than guesses.
##
## Reports, in the door's own local space, where the breaker face and the
## cabinet sit relative to it - which is what decides whether a ray aimed at
## the closed panel reaches the door or is stopped by something in front.

func _initialize() -> void:
	var lines: PackedStringArray = []
	var packed: PackedScene = load("res://LVR CPR.blend")
	if packed == null:
		lines.append("FAILED TO LOAD")
		_write(lines)
		quit()
		return

	var room: Node3D = packed.instantiate()
	var door := room.get_node_or_null("Breaker_002") as MeshInstance3D
	if door == null:
		lines.append("NO Breaker_002")
		_write(lines)
		room.free()
		quit()
		return

	# Shut it, exactly as BreakerPanelInteract does at runtime.
	var open_y := door.rotation.y
	door.rotation.y = open_y + deg_to_rad(154.3)
	lines.append("door open_y=%.4f closed_y=%.4f" % [open_y, door.rotation.y])

	var own := door.mesh.get_aabb() if door.mesh != null else AABB()
	lines.append("door own AABB pos=%s size=%s" % [own.position, own.size])
	lines.append("door children: " + str(door.get_children().map(
		func(c: Node) -> String: return "%s[%s]" % [c.name, c.get_class()]
	)))

	# Everything else in the room, expressed in the door's local space.
	var to_local := door.global_transform.affine_inverse()
	for child in room.get_children():
		var mesh := child as MeshInstance3D
		if mesh == null or mesh.mesh == null or mesh == door:
			continue
		var box: AABB = (to_local * mesh.global_transform) * mesh.mesh.get_aabb()
		# Only things overlapping the door's footprint can block a ray at it.
		if box.position.x > own.end.x or box.end.x < own.position.x:
			continue
		if box.position.y > own.end.y or box.end.y < own.position.y:
			continue
		lines.append("  %-24s local z: %.4f .. %.4f" % [
			child.name, box.position.z, box.end.z
		])

	room.free()
	_write(lines)
	quit()


func _write(lines: PackedStringArray) -> void:
	var f := FileAccess.open("user://panel_dump.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
