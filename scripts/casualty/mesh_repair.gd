class_name CasualtyMeshRepair
extends RefCounted
## Geometry repairs the two casualty models need before they are lit.
##
## Both bodies come out of the same .blend and carry the same two defect
## classes, neither of which Blender shows you:
##
##   * Coincident duplicate faces. Two copies of one triangle z-fight, which
##     reads as a dark mottled blotch. Blender does not care - it draws them on
##     top of each other and you never know - but the depth test does. Measured:
##     4 on the CPR body, 13 on its pants, 1 on its teeth, 2 on the worker's.
##   * Vertex normals that point away from the faces meeting at them. A normal
##     more than 90 degrees out is facing into the mesh, so the surface takes no
##     light from in front of it and goes dark. Measured: 15 of these on the
##     worker's shirt, 22 on the CPR body.
##
## NOT the dark patches in the armpits - those are the clothing's shading, fixed
## at import in scripts/import/casualty_clothing_shading.gd, which is also where
## the reasoning for that one lives.
##
## The repairs live in code rather than in the .blend because a reimport
## rebuilds the node tree wholesale and would throw away anything fixed there
## (CPR_CONTRACT.md section 3). If the model is ever revisited, merging the
## doubled faces and recalculating the outside normals in Blender is the tidier
## home for both, and this file can then go.
##
## No owner in the CPR agent split: casualty_cpr.gd (Agent C) and main.gd both
## call in here, and neither should be reaching into the other's file for it.

## 0.1 mm buckets - tight enough that genuinely distinct geometry never
## collides, loose enough to catch a duplicate that differs only in float noise.
const GRID := 10000.0
## Beyond this a vertex normal is not a smooth-shading choice, it is pointing
## into the mesh. Hard edges on the clothing legitimately sit 45-60 degrees off
## the average of their faces, so the threshold has to be well clear of that.
const INVERTED_DEG := 90.0
## Below this, a vertex's adjacent faces have no usable area to solve from.
const DEGENERATE_EPSILON := 1e-18


## Rebuilds `mesh_node`'s mesh with the duplicate faces dropped and the
## inverted normals turned back outwards, keeping every surface, material,
## blend shape and skinning weight exactly as it was.
##
## For the meshes that are NOT split by casualty_cpr.gd - the clothed worker
## the trainee watches, collapses and drags. Idempotent in effect: a second
## call finds nothing to repair and returns without touching the mesh.
static func repair(mesh_node: MeshInstance3D) -> void:
	var src := mesh_node.mesh as ArrayMesh
	if src == null:
		return

	var repaired := ArrayMesh.new()
	for i in src.get_blend_shape_count():
		repaired.add_blend_shape(src.get_blend_shape_name(i))
	repaired.blend_shape_mode = src.blend_shape_mode

	var changed := false
	for i in src.get_surface_count():
		var original: Array = src.surface_get_arrays(i)
		var arrays: Array = fix_inverted_normals(strip_duplicate_faces(original), null)
		if arrays[Mesh.ARRAY_INDEX] != original[Mesh.ARRAY_INDEX] \
				or arrays[Mesh.ARRAY_NORMAL] != original[Mesh.ARRAY_NORMAL]:
			changed = true

		var shapes: Array = []
		for shape_arrays in src.surface_get_blend_shape_arrays(i):
			shapes.append(fix_inverted_normals(shape_arrays, arrays[Mesh.ARRAY_INDEX]))
		repaired.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, shapes)
		repaired.surface_set_material(i, src.surface_get_material(i))

	if changed:
		mesh_node.mesh = repaired


## Drops triangles that occupy exactly the same three positions as one already
## kept.
##
## Keyed on quantised POSITIONS, not vertex indices: the importer splits
## vertices at every UV and material seam, so the two copies of a face come in
## as separate vertices and an index-based comparison misses them entirely.
##
## Winding-independent - a reversed duplicate is still a duplicate.
##
## Only the index array changes; the orphaned vertices are left in place, which
## costs a little memory and nothing visually.
static func strip_duplicate_faces(arrays: Array) -> Array:
	if arrays[Mesh.ARRAY_INDEX] == null:
		return arrays
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]

	var seen := {}
	var kept := PackedInt32Array()
	var t := 0
	while t + 2 < indices.size():
		var corners := [
			face_key(verts[indices[t]]),
			face_key(verts[indices[t + 1]]),
			face_key(verts[indices[t + 2]]),
		]
		corners.sort()
		var key: String = "|".join(corners)
		if not seen.has(key):
			seen[key] = true
			kept.append(indices[t])
			kept.append(indices[t + 1])
			kept.append(indices[t + 2])
		t += 3

	if kept.size() == indices.size():
		return arrays
	var out := arrays.duplicate()
	out[Mesh.ARRAY_INDEX] = kept
	return out


## Turns back the vertex normals that face into the mesh, and leaves every
## other normal alone.
##
## The conservative half of recompute_normals(): accumulation is keyed on
## vertex INDEX, not position, so a vertex on one side of a hard edge is solved
## only from the faces on that side. That keeps the clothing's authored creases
## - which is why this, and not the wholesale solve, is what the normal-mapped
## surfaces get.
##
## Godot's winding makes cross(v1 - v0, v2 - v0) point AWAY from the shading
## normal, hence the negation. Face normals are left unnormalised while
## accumulating, so their length carries twice the triangle area and larger
## faces weigh more.
##
## `indices` is the surface's index array. Blend shape arrays do not carry one
## of their own, so the base surface's is passed in for them; null means "take
## the one in `arrays`".
static func fix_inverted_normals(arrays: Array, indices: Variant = null) -> Array:
	if indices == null:
		indices = arrays[Mesh.ARRAY_INDEX]
	if indices == null:
		return arrays
	var idx: PackedInt32Array = indices
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	if verts.is_empty() or normals.size() != verts.size() or idx.is_empty():
		return arrays

	var accumulated := PackedVector3Array()
	accumulated.resize(verts.size())
	var t := 0
	while t + 2 < idx.size():
		var i0 := idx[t]
		var i1 := idx[t + 1]
		var i2 := idx[t + 2]
		var face := -((verts[i1] - verts[i0]).cross(verts[i2] - verts[i0]))
		accumulated[i0] += face
		accumulated[i1] += face
		accumulated[i2] += face
		t += 3

	var fixed := 0
	for v in verts.size():
		var summed: Vector3 = accumulated[v]
		if summed.length_squared() < DEGENERATE_EPSILON:
			continue
		var solved := summed.normalized()
		if rad_to_deg(normals[v].angle_to(solved)) > INVERTED_DEG:
			normals[v] = solved
			fixed += 1
	if fixed == 0:
		return arrays

	var out := arrays.duplicate()
	out[Mesh.ARRAY_NORMAL] = normals
	return out


## 0.1 mm buckets. See GRID.
static func face_key(p: Vector3) -> String:
	return "%d_%d_%d" % [roundi(p.x * GRID), roundi(p.y * GRID), roundi(p.z * GRID)]
