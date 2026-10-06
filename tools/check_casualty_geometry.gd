extends Node
## Regression check for the mesh defects on the casualty that only show up in
## the engine: coincident duplicate faces (they z-fight into dark blotches —
## the chest patch and the dark spot on the teeth) and vertex normals that
## disagree with the geometry around them (the dark smudging at the shoulders
## and armpits).
##
## Reports the raw .blend import FIRST, then the same mesh after
## CasualtyCpr.repair_mesh() — the repair main.gd runs at startup. The point of
## the check is the second block: it must come back clean. The first block is
## there so the defects the repair is carrying stay visible; if it ever goes
## quiet too, the .blend has been fixed at source and the repair could go.
##
##     godot --headless --path <project> res://tools/check_casualty_geometry.tscn

## 0.1 mm buckets, matching casualty_cpr.gd's own quantisation.
const GRID := 10000.0
## A vertex normal further than this from the faces meeting at it lights as a
## smudge. Well clear of the few degrees smooth shading legitimately carries.
const NORMAL_TOLERANCE_DEG := 30.0


func _ready() -> void:
	var root := (load("res://LVR CPR.blend") as PackedScene).instantiate()
	add_child(root)
	var mesh := CprGhost.find_node(root, CasualtyCpr.CASUALTY_CPR_MESH) as MeshInstance3D
	if mesh == null:
		print("FAIL: no MeshInstance3D named '%s' in the .blend" % CasualtyCpr.CASUALTY_CPR_MESH)
		get_tree().quit(1)
		return

	var worker := CprGhost.find_node(root, "Boots1_002") as MeshInstance3D
	print("=== as imported ===")
	var before := _report([mesh, worker])

	var metal := _metal_report([mesh, worker])
	CasualtyCpr.repair_mesh(mesh)
	CasualtyMeshRepair.repair(worker)
	var repaired: Array[MeshInstance3D] = [mesh]
	var still := mesh.get_node_or_null(CasualtyCpr.CLOTHING_NODE_NAME) as MeshInstance3D
	if still != null:
		repaired.append(still)
	repaired.append(worker)
	print("=== after the repairs main.gd runs at startup ===")
	var after := _report(repaired)


	print("duplicate faces: %d -> %d   suspect normals: %d -> %d   metal-clothing surfaces: %d" % [
		before["dups"], after["dups"], before["normals"], after["normals"], metal])
	if after["dups"] > 0:
		print("FAIL: coincident faces survive the repair")
		get_tree().quit(1)
		return
	if metal > 0:
		print("FAIL: clothing still reading metalness out of a roughness map (reimport the .blend?)")
		get_tree().quit(1)
		return
	print("=== ok ===")
	get_tree().quit()


## Surfaces whose metalness is being read out of their roughness map. The
## import step clears these, so a non-zero count here means
## scripts/import/casualty_clothing_shading.gd did not run.
func _metal_report(meshes: Array[MeshInstance3D]) -> int:
	var count := 0
	for mi in meshes:
		if mi == null or mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i) as BaseMaterial3D
			if m != null and m.metallic > 0.0 and m.metallic_texture != null 					and m.metallic_texture == m.roughness_texture:
				count += 1
	return count


func _report(meshes: Array[MeshInstance3D]) -> Dictionary:
	var dups := 0
	var bad_normals := 0
	for mi in meshes:
		if mi == null:
			continue
		var src := mi.mesh as ArrayMesh
		for i in src.get_surface_count():
			var mat: Material = src.surface_get_material(i)
			var arrays: Array = src.surface_get_arrays(i)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			if arrays[Mesh.ARRAY_INDEX] == null:
				continue
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]

			var keys := PackedStringArray()
			keys.resize(verts.size())
			for v in verts.size():
				keys[v] = _key(verts[v])

			var seen := {}
			var accumulated := {}
			var surface_dups := 0
			var t := 0
			while t + 2 < indices.size():
				var corners := [keys[indices[t]], keys[indices[t + 1]], keys[indices[t + 2]]]
				corners.sort()
				var face_key: String = "|".join(corners)
				if seen.has(face_key):
					surface_dups += 1
				seen[face_key] = true
				var face := -((verts[indices[t + 1]] - verts[indices[t]]).cross(
					verts[indices[t + 2]] - verts[indices[t]]))
				for j in [indices[t], indices[t + 1], indices[t + 2]]:
					accumulated[keys[j]] = accumulated.get(keys[j], Vector3.ZERO) + face
				t += 3

			var surface_bad := 0
			for v in verts.size():
				var summed: Vector3 = accumulated.get(keys[v], Vector3.ZERO)
				if summed.length_squared() < 1e-18:
					continue
				if rad_to_deg(normals[v].angle_to(summed.normalized())) > NORMAL_TOLERANCE_DEG:
					surface_bad += 1

			dups += surface_dups
			bad_normals += surface_bad
			print("  %-14s %-18s tris=%5d  duplicate faces=%d  suspect normals=%d" % [
				mi.name.substr(0, 14),
				mat.resource_name if mat != null else "?",
				indices.size() / 3, surface_dups, surface_bad])
	return {"dups": dups, "normals": bad_normals}


func _key(p: Vector3) -> String:
	return "%d_%d_%d" % [roundi(p.x * GRID), roundi(p.y * GRID), roundi(p.z * GRID)]
