extends Node
## [F8] Reports the actual RENDER triangle under the crosshair.
##
## Written to pin down a dark patch on the casualty's chest that survived every
## theory tried against it: blend-shape mode, a permanently-active shape weight,
## splitting the normal-mapped surfaces onto their own mesh, repairing 24 broken
## vertex normals, and removing 4 duplicate coincident faces. Each of those was
## a real defect and none of them was this one.
##
## InteractionRay's own F9 probe reports COLLIDERS, which is no use here: the
## casualty's collider is a single convex hull, so it answers "the casualty" no
## matter which polygon is at fault. This walks the visible geometry itself and
## names the exact surface, material and triangle the crosshair is pointing at.
##
## The last section is the point of the whole thing: it lists every other
## triangle within 5 mm behind the front-most hit. Two surfaces that close are
## z-fighting, which is what a mottled dark blotch usually is — and it reports
## which meshes they belong to, so the answer is "these two things overlap here"
## rather than another guess.
##
## Debug builds only, spawned by main.gd next to PauseMenu and DevMenu. Prints
## to the console and appends to user://mesh_probe.txt, following the same
## append-don't-overwrite convention InteractionRay._probe() uses so several
## presses from several angles build one picture.

const PROBE_KEY := KEY_F8
const REACH_METRES := 4.0
## Ray-triangle testing runs in GDScript, one triangle at a time. The control
## room's own mesh is tens of thousands of triangles and its AABB contains the
## camera, so it passed the broad-phase test and the probe walked all of it —
## which read as the game hanging. Anything above this is skipped and named in
## the report, so a skip is never silent.
const MAX_TRIANGLES_PER_MESH := 12000
## Total budget across all meshes, as a backstop for a scene full of
## medium-sized meshes that individually pass the cap above.
const MAX_TRIANGLES_TOTAL := 60000
## Two triangles closer than this along the view ray cannot resolve reliably in
## the depth buffer at this range — the definition of a z-fight.
const COINCIDENT_METRES := 0.005
const REPORT_PATH := "user://mesh_probe.txt"

## Remaining triangle budget for the probe currently running.
var _budget: int = MAX_TRIANGLES_TOTAL


func _ready() -> void:
	if not OS.is_debug_build():
		set_process_unhandled_input(false)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == PROBE_KEY:
		_probe()


func _probe() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		push_warning("MeshProbe: no current Camera3D.")
		return

	var from := camera.global_position
	var direction := -camera.global_transform.basis.z

	var hits: Array = []
	var skipped: PackedStringArray = []
	_budget = MAX_TRIANGLES_TOTAL
	_gather(get_tree().current_scene, from, direction, hits, skipped)
	hits.sort_custom(func(x, y): return float(x["distance"]) < float(y["distance"]))

	var out: PackedStringArray = []
	out.append("===== mesh probe %.1fs =====" % (Time.get_ticks_msec() / 1000.0))
	out.append("eye     (%.3f, %.3f, %.3f)" % [from.x, from.y, from.z])
	out.append("forward (%.3f, %.3f, %.3f)" % [direction.x, direction.y, direction.z])
	for line in skipped:
		out.append("  skipped (too many triangles to test in script): %s" % line)

	if hits.is_empty():
		out.append("  nothing rendered within %.1f m along the crosshair" % REACH_METRES)
		_write(out)
		return

	out.append("hits along the ray, nearest first:")
	for i in mini(hits.size(), 8):
		var h: Dictionary = hits[i]
		out.append("  [%d] %.4f m  %s" % [i, h["distance"], h["node"]])
		out.append("       surface %d '%s'  tri %d" % [h["surface"], h["material"], h["triangle"]])
		out.append("       point (%.4f, %.4f, %.4f)  local (%.4f, %.4f, %.4f)"
			% [h["point"].x, h["point"].y, h["point"].z,
			h["local"].x, h["local"].y, h["local"].z])
		out.append("       face normal (%.2f, %.2f, %.2f)"
			% [h["normal"].x, h["normal"].y, h["normal"].z])

	# The reason this file exists.
	var front: Dictionary = hits[0]
	var coincident: Array = []
	for i in range(1, hits.size()):
		var h: Dictionary = hits[i]
		if float(h["distance"]) - float(front["distance"]) <= COINCIDENT_METRES:
			coincident.append(h)
		else:
			break

	out.append("")
	if coincident.is_empty():
		out.append("VERDICT: nothing within %.0f mm behind the front face — not a z-fight here."
			% (COINCIDENT_METRES * 1000.0))
		out.append("         the artefact is in the front face's own shading or texture:")
		out.append("         %s surface %d '%s' tri %d"
			% [front["node"], front["surface"], front["material"], front["triangle"]])
	else:
		out.append("VERDICT: Z-FIGHT. %d face(s) within %.0f mm behind the front face."
			% [coincident.size(), COINCIDENT_METRES * 1000.0])
		out.append("  front: %s surf %d '%s' tri %d"
			% [front["node"], front["surface"], front["material"], front["triangle"]])
		for h in coincident:
			out.append("  also:  %s surf %d '%s' tri %d  (+%.4f m)"
				% [h["node"], h["surface"], h["material"], h["triangle"],
				float(h["distance"]) - float(front["distance"])])

	_write(out)


## Every visible MeshInstance3D the ray could reach, tested triangle by
## triangle. The AABB test first keeps this to a single frame's work — without
## it this walks every triangle in the room.
func _gather(node: Node, from: Vector3, direction: Vector3, hits: Array, skipped: PackedStringArray) -> void:
	if node == null:
		return
	var mesh_instance := node as MeshInstance3D
	if mesh_instance != null and mesh_instance.is_visible_in_tree() and mesh_instance.mesh != null:
		var world_aabb := mesh_instance.global_transform * mesh_instance.get_aabb()
		if world_aabb.grow(0.01).intersects_ray(from, direction * REACH_METRES) != null:
			var triangles := _triangle_count(mesh_instance.mesh)
			if triangles > MAX_TRIANGLES_PER_MESH:
				skipped.append("%s (%d tris)" % [mesh_instance.get_path(), triangles])
			elif triangles > _budget:
				skipped.append("%s (%d tris, over the total budget)" % [mesh_instance.get_path(), triangles])
			else:
				_budget -= triangles
				_test_mesh(mesh_instance, from, direction, hits)
	for child in node.get_children():
		_gather(child, from, direction, hits, skipped)


func _triangle_count(mesh: Mesh) -> int:
	var total := 0
	for surface in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
			continue
		if arrays[Mesh.ARRAY_INDEX] != null:
			total += int(arrays[Mesh.ARRAY_INDEX].size() / 3)
		else:
			total += int(arrays[Mesh.ARRAY_VERTEX].size() / 3)
	return total


func _test_mesh(mesh_instance: MeshInstance3D, from: Vector3, direction: Vector3, hits: Array) -> void:
	var mesh := mesh_instance.mesh
	var to_world := mesh_instance.global_transform
	for surface in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var material := mesh.surface_get_material(surface)
		var material_name := str(material.resource_name) if material != null else "-"

		var count := indices.size() if not indices.is_empty() else verts.size()
		var t := 0
		while t + 2 < count:
			var i0 := indices[t] if not indices.is_empty() else t
			var i1 := indices[t + 1] if not indices.is_empty() else t + 1
			var i2 := indices[t + 2] if not indices.is_empty() else t + 2
			var a := to_world * verts[i0]
			var b := to_world * verts[i1]
			var c := to_world * verts[i2]
			var point: Variant = Geometry3D.ray_intersects_triangle(from, direction, a, b, c)
			if point != null:
				var world_point: Vector3 = point
				var distance := from.distance_to(world_point)
				if distance <= REACH_METRES:
					# Godot's winding makes the raw cross point away from the
					# shading normal — negated so this reads as the surface does.
					var normal := -((b - a).cross(c - a))
					if normal.length_squared() > 0.0:
						normal = normal.normalized()
					hits.append({
						"node": str(mesh_instance.get_path()),
						"surface": surface,
						"material": material_name,
						"triangle": t / 3,
						"distance": distance,
						"point": world_point,
						"local": to_world.affine_inverse() * world_point,
						"normal": normal,
					})
			t += 3


func _write(lines: PackedStringArray) -> void:
	var text := "\n".join(lines) + "\n\n"
	print(text)
	var file := FileAccess.open(REPORT_PATH, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	else:
		file.seek_end()
	if file != null:
		file.store_string(text)
		file.close()
	Events.center_message_requested.emit("Mesh probe written", Tokens.WARNING, 1.5)
