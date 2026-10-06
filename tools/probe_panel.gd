extends SceneTree
## Headless: stand where the trainee stands and see what the interaction ray
## actually hits.
##
## The AABB dump could not settle this - every box is axis-aligned in the
## door's space, so a rotated cabinet reports as far larger than it is. This
## builds the real colliders, closes the door, adds the hitbox exactly as
## BreakerPanelInteract does, and casts from eye height at several ranges and
## offsets. Whatever comes back is what the player would be aiming at.

var _room: Node3D = null
var _door: MeshInstance3D = null
var _frames: int = 0
var _lines: PackedStringArray = []


func _initialize() -> void:
	var packed: PackedScene = load("res://LVR CPR.blend")
	_room = packed.instantiate()
	root.add_child(_room)

	_door = _room.get_node_or_null("Breaker_002") as MeshInstance3D
	if _door == null:
		_lines.append("NO Breaker_002")
		return

	_door.rotation.y = _door.rotation.y + deg_to_rad(154.3)

	# Same hitbox the runtime builds.
	var own := _door.mesh.get_aabb()
	var shape := BoxShape3D.new()
	shape.size = own.size + Vector3(0.05, 0.05, 0.18)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = own.get_center()
	var body := StaticBody3D.new()
	body.name = "PanelHitbox"
	body.collision_layer = 2
	body.collision_mask = 0
	body.add_child(cs)
	_door.add_child(body)

	for b in _bodies(_door):
		b.collision_layer |= 2

	_lines.append("door centre world: %s" % (_door.global_transform * own.get_center()))
	_lines.append("hitbox size: %s" % shape.size)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 5:
		return false
	if _door != null:
		_probe()
	_write()
	quit()
	return true


func _probe() -> void:
	var own := _door.mesh.get_aabb()
	var target: Vector3 = _door.global_transform * own.get_center()
	var space := root.get_world_3d().direct_space_state

	# Eye height 1.7, standing out in the room (+Z of the board), at a
	# spread of ranges and lateral offsets.
	for dz: float in [0.6, 1.0, 1.5, 2.0]:
		for dx: float in [0.0, 0.4, -0.4]:
			var eye := Vector3(target.x + dx, 1.7, target.z + dz)
			var params := PhysicsRayQueryParameters3D.create(eye, target)
			params.collision_mask = 7
			var hit := space.intersect_ray(params)
			var who: String = "NOTHING"
			if not hit.is_empty():
				var c: Node = hit["collider"]
				who = "%s  (parent %s)  at %.3fm" % [
					c.name,
					c.get_parent().name if c.get_parent() != null else "-",
					eye.distance_to(hit["position"])
				]
			_lines.append("eye dz=%.1f dx=%+.1f -> %s" % [dz, dx, who])


func _bodies(root_node: Node) -> Array[CollisionObject3D]:
	var out: Array[CollisionObject3D] = []
	if root_node is CollisionObject3D:
		out.append(root_node)
	for child in root_node.get_children():
		out.append_array(_bodies(child))
	return out


func _write() -> void:
	var f := FileAccess.open("user://probe_panel.txt", FileAccess.WRITE)
	f.store_string("\n".join(_lines))
	f.close()
