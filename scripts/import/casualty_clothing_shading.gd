@tool
extends RefCounted
## Makes the casualty's clothing shade like cloth instead of like sheet metal
## with black creases. Import-time, so the editor viewport shows exactly what
## the build does - the imported materials cannot be edited by hand.
##
## THE BLACK PATCH IN THE ARMPITS. Diagnosed by elimination, in the editor, with
## a white Surface Material Override on the shirt:
##
##   * Unshaded -> flat white. So it is not the albedo texture or the UVs.
##   * Shaded white, non-metal, cull disabled -> patch still there. So it is not
##     metalness, not the normal map, and not the mirrored-winding problem
##     fix_mirrored_meshes.gd handles.
##   * A NORMAL-as-colour shader -> smooth gradient swinging to a different hue
##     across the armpit. The normals are continuous and geometrically correct;
##     they simply rotate to face INTO the fold.
##   * It appears ~1.9 s into LVR_Fall, as the arm comes up. It is the skinning
##     pinching the fabric, not anything wrong in the mesh data. Recomputing the
##     normals from the geometry changes nothing, because they were already the
##     geometry's own normals.
##
## Blender does not show it because EEVEE/Cycles fill that fold with indirect
## light. The Compatibility renderer (WebGL2/SCORM, not negotiable) has no GI
## and no reflection probes - one omni and sky ambient - so a fold facing away
## from the light crushes to black. Raising ambient lifts the whole scene by the
## same amount and does not help the contrast; Backlight lifts the whole
## material. Both were tried and rejected for that reason.
##
## So the fix is to stop the fold's normals pointing into itself:
##
##   1. SMOOTHED NORMALS. Each vertex normal is pulled toward the average of its
##      neighbourhood, a few passes wide. On flat fabric this is a no-op - the
##      neighbourhood already agrees - so the garment is unchanged where it was
##      already fine. In a concave pinch the neighbourhood disagrees strongly
##      and the normal swings back outwards, which is exactly and only where the
##      problem is. The mesh keeps its shape; only shading changes. Normals are
##      skinned along with the vertices, so this holds through the animation.
##   2. LAMBERT WRAP diffuse, which softens the terminator so what is left of
##      the crease falls off gently instead of cliff-edging to black.
##   3. METALLIC 0. Separate defect, found on the way: every clothing material
##      imports with metallic = 1.0 and its metallic_texture pointing at the
##      *_rough.png map. glTF carries metalness in that texture's blue channel;
##      these are plain greyscale roughness maps, so the blue channel is the
##      roughness value and the shirt renders as a metal of about 0.79. The
##      character pack's real metalness maps are black (measured means 0.007 to
##      0.02), so nothing on the outfit is metal.
##
## STRENGTH is the one number worth touching. 0.0 disables the smoothing
## entirely, 1.0 replaces the normals with the smoothed set. Raise it if the
## fold is still dark, lower it if the fabric starts to look inflated and
## plasticky. PASSES widens the neighbourhood the average is taken over.
##
## Only the casualty bodies are touched. The same metalness defect is on the
## room's Iron, Fabric Rough 01 and Material.0xx materials, deliberately left
## alone - the room's look is signed off.

## How far each normal moves toward its smoothed neighbourhood average.
const STRENGTH := 1
## Laplacian passes. Each one widens the neighbourhood by a ring of faces.
const PASSES := 3

## The two bodies: the clothed worker who collapses and is dragged, and the
## posed body used for the CPR phase.
const MESH_NAMES: PackedStringArray = ["Boots1_002", "Casualty_CPR_Posed"]
## Surfaces to treat, matched against the material name's prefix. Skin, hair,
## mouth and eyes are left alone: they are not the problem and smoothing a face
## is a good way to lose its features.
const CLOTHING_PREFIXES: PackedStringArray = ["Shirt1", "Pants1", "Boots1", "Gloves1"]

## Below this, a vertex's neighbourhood has no usable direction to solve from.
const DEGENERATE_EPSILON := 1e-18


static func apply(scene: Node) -> void:
	var touched: PackedStringArray = []
	for name in MESH_NAMES:
		var mesh_instance := _find(scene, name) as MeshInstance3D
		if mesh_instance == null:
			push_warning("casualty_clothing_shading: no MeshInstance3D named '%s'" % name)
			continue
		if _apply_to(mesh_instance):
			touched.append(name)
	if touched.size() > 0:
		print("casualty_clothing_shading: reshaded %s" % ", ".join(touched))


static func _apply_to(mesh_instance: MeshInstance3D) -> bool:
	var source := mesh_instance.mesh as ArrayMesh
	if source == null:
		return false

	var out := ArrayMesh.new()
	out.resource_name = source.resource_name
	out.blend_shape_mode = source.blend_shape_mode
	for i in source.get_blend_shape_count():
		out.add_blend_shape(source.get_blend_shape_name(i))

	var any := false
	for s in source.get_surface_count():
		var arrays: Array = source.surface_get_arrays(s)
		var blends: Array = source.surface_get_blend_shape_arrays(s)
		var material := source.surface_get_material(s) as BaseMaterial3D

		if _is_clothing(material):
			any = true
			_fix_material(material)
			var groups: Dictionary = _position_groups(arrays)
			arrays = _smooth(arrays, groups)
			# The shapes carry their own normals; leaving them raw would undo
			# the smoothing the moment a blend shape is driven.
			for i in blends.size():
				blends[i] = _smooth(blends[i], groups)

		# Only the flags that change array layout are carried across;
		# compression is left for Godot to recalculate (as in
		# fix_mirrored_meshes.gd, which this runs after).
		var flags: int = 0
		if source.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS:
			flags |= Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		out.add_surface_from_arrays(
			source.surface_get_primitive_type(s), arrays, blends, {}, flags
		)
		out.surface_set_material(s, source.surface_get_material(s))
		out.surface_set_name(s, source.surface_get_name(s))

	if any:
		mesh_instance.mesh = out
	return any


static func _is_clothing(material: BaseMaterial3D) -> bool:
	if material == null:
		return false
	for prefix in CLOTHING_PREFIXES:
		if material.resource_name.begins_with(prefix):
			return true
	return false


## Lambert Wrap and the metalness correction - see the header.
static func _fix_material(material: BaseMaterial3D) -> void:
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	if material.metallic > 0.0 and material.metallic_texture != null \
			and material.metallic_texture == material.roughness_texture:
		material.metallic = 0.0
		material.metallic_texture = null


## Vertex indices sharing a position, keyed on a 0.1 mm grid.
##
## Keyed on POSITION, not index: the importer splits vertices at every UV and
## material seam, so an index-keyed neighbourhood stops at each seam and the
## smoothing would light the seam as a crease - the artefact class this is
## meant to remove, not add.
static func _position_groups(arrays: Array) -> Dictionary:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var by_key := {}
	var keys := PackedStringArray()
	keys.resize(verts.size())
	for v in verts.size():
		var key := "%d_%d_%d" % [
			roundi(verts[v].x * 10000.0),
			roundi(verts[v].y * 10000.0),
			roundi(verts[v].z * 10000.0),
		]
		keys[v] = key
		var group: PackedInt32Array = by_key.get(key, PackedInt32Array())
		group.append(v)
		by_key[key] = group

	# Neighbours, position-merged: for every edge of every triangle, each end
	# gains every vertex sitting at the other end's position.
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var neighbours := {}
	var t := 0
	while t + 2 < indices.size():
		for pair in [[0, 1], [1, 2], [2, 0]]:
			var a: int = indices[t + pair[0]]
			var b: int = indices[t + pair[1]]
			_link(neighbours, keys[a], keys[b])
			_link(neighbours, keys[b], keys[a])
		t += 3

	return {"keys": keys, "by_key": by_key, "neighbours": neighbours}


static func _link(neighbours: Dictionary, from: String, to: String) -> void:
	var set: Dictionary = neighbours.get(from, {})
	set[to] = true
	neighbours[from] = set


## Pulls every normal STRENGTH of the way toward the average of its
## neighbourhood, PASSES rings wide. Positions are never touched.
static func _smooth(arrays: Array, groups: Dictionary) -> Array:
	if STRENGTH <= 0.0:
		return arrays
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if normals.size() != verts.size() or normals.is_empty():
		return arrays

	var keys: PackedStringArray = groups["keys"]
	var by_key: Dictionary = groups["by_key"]
	var neighbours: Dictionary = groups["neighbours"]
	if keys.size() != normals.size():
		return arrays

	# One normal per position to start with - vertices split across a seam share
	# a position and must not drift apart.
	var current := {}
	for key in by_key:
		var summed := Vector3.ZERO
		for v in (by_key[key] as PackedInt32Array):
			summed += normals[v]
		current[key] = summed.normalized() if summed.length_squared() > DEGENERATE_EPSILON \
			else normals[(by_key[key] as PackedInt32Array)[0]]

	for _pass in PASSES:
		var next := {}
		for key in current:
			var summed: Vector3 = current[key]
			for neighbour_key in (neighbours.get(key, {}) as Dictionary):
				summed += current[neighbour_key]
			next[key] = summed.normalized() if summed.length_squared() > DEGENERATE_EPSILON \
				else current[key]
		current = next

	for v in normals.size():
		var smoothed: Vector3 = current[keys[v]]
		var blended: Vector3 = normals[v].lerp(smoothed, STRENGTH)
		if blended.length_squared() > DEGENERATE_EPSILON:
			normals[v] = blended.normalized()

	var out := arrays.duplicate()
	out[Mesh.ARRAY_NORMAL] = normals
	return out


## The scene is not inside a SceneTree during post-import, so nothing here can
## use get_node().
static func _find(node: Node, name: String) -> Node:
	if node.name == name:
		return node
	for child in node.get_children():
		var found := _find(child, name)
		if found != null:
			return found
	return null
