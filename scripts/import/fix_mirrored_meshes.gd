@tool
extends RefCounted
## Reverses triangle winding on meshes that Godot rasterises with a flipped
## front-face convention, so they light correctly.
##
## Several objects in LVR CPR.blend sit under a negative-determinant transform -
## the character's Armature is (0.01, 0.01, -0.01), the switchboard cabinets are
## (-1.2247, -1, -1). Blender compensates for mirrored transforms when it
## renders; Godot does not, and the symptom is inverted lighting: the lit side
## goes dark and the shadowed side glows.
##
## WHAT IS ACTUALLY WRONG. It is worth being precise, because the obvious
## diagnosis is wrong and the obvious fix makes things worse.
##
##   Normals are fine. Godot transforms them with the inverse transpose of the
##   basis, which yields correct outward normals even under a mirror. Probing
##   the geometric normal in view space returns "towards the camera" on every
##   visible fragment.
##
##   Facing is not fine. Every visible fragment on these meshes reports
##   FRONT_FACING == false. The imported materials are double-sided (Blender's
##   backface culling is off, so glTF marks them doubleSided and Godot sets
##   cull_mode = CULL_DISABLED), and Godot negates NORMAL on back faces. That
##   negation is the entire bug.
##
## So the correction is to reverse the winding and leave normals alone. An
## earlier version of this script also negated normals, which fixed the facing
## and broke the normals - still inverted, just for the opposite reason.
##
## This also explains why overriding the material in Godot appears to fix it and
## editing the material in Blender does not. An override drops cull_mode back to
## CULL_BACK, which stops the negation - but it also culls the real front faces,
## so what you are looking at is the inside of the far surface. It reads as
## correct and is not.
##
## The test that settles it: put an OmniLight3D at the camera position. Every
## visible surface should light up. tools/check_shading.tscn automates this.
##
## NOTE: rebuilding a surface discards generated LODs and shadow meshes for the
## affected meshes. That is a handful of objects in a small interior, so the
## cost is negligible - but it is why this is not applied blindly to everything.

static func apply(scene: Node) -> void:
	var xforms: Dictionary = {}
	_collect(scene, Transform3D.IDENTITY, xforms)

	var cache: Dictionary = {}
	var fixed: PackedStringArray = []

	for node in xforms:
		if not (node is MeshInstance3D):
			continue
		var mi: MeshInstance3D = node
		if mi.mesh == null:
			continue
		if (xforms[mi] as Transform3D).basis.determinant() >= 0.0:
			continue

		var key: int = mi.mesh.get_instance_id()
		if not cache.has(key):
			cache[key] = _rewound_copy(mi.mesh)
		mi.mesh = cache[key]
		fixed.append(String(mi.name))

	if fixed.size() > 0:
		print("fix_mirrored_meshes: rewound %d instance(s): %s"
			% [fixed.size(), ", ".join(fixed)])


## The scene is not inside a SceneTree during post-import, so global_transform
## is unavailable and transforms must be accumulated by hand.
static func _collect(node: Node, parent_xform: Transform3D, xforms: Dictionary) -> void:
	var xform: Transform3D = parent_xform
	if node is Node3D:
		xform = parent_xform * (node as Node3D).transform
	xforms[node] = xform
	for child in node.get_children():
		_collect(child, xform, xforms)


static func _rewound_copy(source: Mesh) -> ArrayMesh:
	var out := ArrayMesh.new()
	out.resource_name = source.resource_name

	var src_array_mesh: ArrayMesh = source as ArrayMesh

	# Blend shapes must be declared before any surface is added.
	if src_array_mesh != null:
		out.blend_shape_mode = src_array_mesh.blend_shape_mode
		for i in src_array_mesh.get_blend_shape_count():
			out.add_blend_shape(src_array_mesh.get_blend_shape_name(i))

	for s in source.get_surface_count():
		var arrays: Array = source.surface_get_arrays(s)
		var blends: Array = []
		if src_array_mesh != null:
			blends = src_array_mesh.surface_get_blend_shape_arrays(s)

		_reverse_winding(arrays, source.resource_name)

		# Carry across only the flags that affect array layout. Compression
		# flags are left to Godot to recalculate.
		var flags: int = 0
		if src_array_mesh != null:
			var fmt: int = src_array_mesh.surface_get_format(s)
			if fmt & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS:
				flags |= Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS

		out.add_surface_from_arrays(source.surface_get_primitive_type(s), arrays, blends, {}, flags)
		out.surface_set_material(s, source.surface_get_material(s))
		if src_array_mesh != null:
			out.surface_set_name(s, src_array_mesh.surface_get_name(s))

	return out


## Normals and tangents are deliberately left untouched - see the header.
static func _reverse_winding(arrays: Array, label: String) -> void:
	if arrays[Mesh.ARRAY_INDEX] == null:
		push_warning("fix_mirrored_meshes: '%s' has a non-indexed surface; winding left unchanged" % label)
		return
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var t: int = 0
	while t + 2 < indices.size():
		var swap: int = indices[t + 1]
		indices[t + 1] = indices[t + 2]
		indices[t + 2] = swap
		t += 3
	arrays[Mesh.ARRAY_INDEX] = indices
