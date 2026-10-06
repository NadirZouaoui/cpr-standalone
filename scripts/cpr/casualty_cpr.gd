class_name CasualtyCpr
extends Node

## Owns the `Compress` and `Shock` blend shapes on `Casualty_CPR_Posed` —
## CPR_CONTRACT.md section 3/4.2/4.3.
##
## Resolves the mesh and both blend shape indices once, by name, from
## call_deferred("_build") rather than straight out of _ready() — the
## ControlRoom .blend instance may still be settling on the frame this node
## enters the tree (CPR_CONTRACT.md section 3/8). glTF blend shape ordering is
## not guaranteed across reimports either, so nothing here is looked up by
## literal index.
##
## `depth` is the single source of truth for how far the chest is currently
## pressed. compression_driver.gd writes it every frame while a compression is
## in progress. `trigger_shock()` is the one-shot Shock tween — Agent H's
## shock_button.gd calls it directly and must not edit this file.
## Nothing else should touch either blend shape — CPR_CONTRACT.md section 8:
## "compressions and shock are blend shapes, driven through casualty_cpr.gd only."
##
## `depth` is also public and static-shared on purpose ("the future arms rig
## will share it" — CPR_AGENTS.md, Agent C brief): scripts/cpr/fps_arms.gd
## reads CasualtyCpr.current_depth() to pose the rescuer's forearms without
## needing a node reference of its own.
##
## OWNED BY AGENT C · COMPRESSIONS — see CPR_CONTRACT.md section 7.

const CASUALTY_CPR_MESH := "Casualty_CPR_Posed"
## The clothed skinned body — the one on screen for the whole exercise up to the
## point the shirt comes off.
##
## The client's reordered spine (docs/OVERNIGHT_PLAN.md §2) puts the first
## compression set BEFORE `chest_exposed`, so the first thirty compressions are
## delivered through the shirt and the chest that has to move is this one. The
## `Compression` shape is authored onto it in Blender; if that work has not
## landed, the shape is absent, this warns once and set 1 reads as no
## depression at all — the beat still completes and still scores.
##
## Both meshes are written every frame rather than the visible one being picked,
## following casualty.gd::_tween_mouth_open(): the expose-chest swap can land
## mid-set, and a mesh that was not being driven arrives with a flat chest.
const CASUALTY_CLOTHED_MESH := "Boots1_002"
const SHAPE_COMPRESS := "Compression"
const SHAPE_SHOCK := "Shock"
const SHOCK_TWEEN_S := 0.25

## Child node holding the surfaces no blend shape touches — see
## repair_mesh().
const CLOTHING_NODE_NAME := "CasualtyStaticSurfaces"
## A surface counts as moved if any shape shifts a vertex further than 0.1 mm.
## Comfortably above the ~1e-4 float noise measured on the untouched surfaces
## and far below the 3.4 cm the chest actually travels.
const SPLIT_EPSILON_SQ := 0.0001 * 0.0001
## Below this, a vertex's adjacent faces have no usable area to solve from.
const DEGENERATE_EPSILON := 1e-18

## MEASURED, do not re-investigate from theory: the whole-casualty re-lighting
## when `Compression` is driven is NOT in the mesh data. Read straight off the
## running ArrayMesh, of six surfaces only surface 0 (Human.body) has any
## deltas — 138 of 1757 vertices move, max 3.4 cm. On Head4/Shirt1/Pants1/
## Boots1/Gloves1 the shape arrays are identical to the base in POSITION
## (max delta 0.0), NORMAL (max ~7e-5) and TANGENT (max ~2e-4), so the blend
## is arithmetically the identity there and cannot change how they light.
##
## Tried and reverted: forcing BLEND_SHAPE_MODE_RELATIVE (translates the whole
## body — the importer stores absolute positions, so NORMALIZED is correct),
## and pinning the shape a hair above zero to keep the mesh permanently on the
## blend-shape vertex path (no effect, so it is not a path switch either).

## Current compression depth, 0.0-1.0. Setting it immediately pushes the value
## onto the Compress blend shape (once resolved); read it directly if you hold
## a reference, or via the static current_depth() if you don't.
var depth: float = 0.0:
	set(value):
		depth = clampf(value, 0.0, 1.0)
		_apply_depth()

var _mesh: MeshInstance3D = null
var _compress_idx: int = -1
var _shock_idx: int = -1
var _resolved: bool = false
var _shock_tween: Tween = null

## The clothed body and its own Compression shape. Both may legitimately be
## absent — see CASUALTY_CLOTHED_MESH.
var _clothed_mesh: MeshInstance3D = null
var _clothed_compress_idx: int = -1

## First instance to reach _build() wins. There is exactly one of these alive
## in the running scene — compression_driver.gd owns creating it.
static var _active: CasualtyCpr = null


func _ready() -> void:
	_active = self
	call_deferred("_build")


func _exit_tree() -> void:
	if _active == self:
		_active = null


func _build() -> void:
	var root: Node = null
	if get_tree() != null:
		root = get_tree().current_scene
		if root == null:
			root = get_tree().root
	if root == null:
		push_error("CasualtyCpr: no scene tree to search.")
		return

	_mesh = CprGhost.find_node(root, CASUALTY_CPR_MESH) as MeshInstance3D
	if _mesh == null:
		push_error("CasualtyCpr: no MeshInstance3D named '%s' found." % CASUALTY_CPR_MESH)
		return

	var mesh_resource: Mesh = _mesh.mesh
	if mesh_resource == null:
		push_error("CasualtyCpr: '%s' has no Mesh resource." % CASUALTY_CPR_MESH)
		return

	# THE WHOLE-MODEL SHADING BUG, and why the fix is a mesh split.
	#
	# Driving `Compression` visibly re-lit the entire casualty — most obviously
	# the reflective band on the shirt — even though the mesh data says it
	# cannot. Read off the running ArrayMesh: of six surfaces only surface 0
	# (Human.body) has deltas at all (138 of 1757 vertices, max 3.4 cm). On
	# Head4/Shirt1/Pants1/Boots1/Gloves1 the shape arrays are identical to the
	# base in POSITION (0.0), NORMAL (~7e-5) and TANGENT (~2e-4), the mesh is
	# not skinned, and the blend is arithmetically the identity there.
	#
	# What correlates is the material: surfaces 2-5 are normal-mapped, 0 and 1
	# are not, and 2-5 are exactly the ones that change. Blend shapes are a
	# whole-mesh property, so a non-zero weight puts EVERY surface through the
	# Compatibility renderer's blend-shape vertex path, which does not carry
	# the same tangents through — and a normal-mapped surface with different
	# tangents re-lights. Compatibility is not optional here (WebGL2/SCORM), so
	# the renderer cannot be changed.
	#
	# Fix: keep the normal-mapped surfaces off that path altogether. The
	# surfaces no blend shape actually touches are moved to a sibling mesh with
	# no blend shapes on it, so they render from a plain static buffer no matter
	# what the compression weight is. Done at runtime, not in Blender, because a
	# .blend reimport rebuilds this node tree wholesale (CPR_CONTRACT.md §3).
	#
	# Tried and rejected first: BLEND_SHAPE_MODE_RELATIVE (translates the whole
	# body — the importer stores absolute positions, so NORMALIZED is correct),
	# and pinning the weight a hair above zero to stay permanently on the
	# blend-shape path (no effect).
	repair_mesh(_mesh)
	mesh_resource = _mesh.mesh

	_compress_idx = _find_shape(mesh_resource, SHAPE_COMPRESS)
	if _compress_idx < 0:
		push_error("CasualtyCpr: no blend shape named '%s' on '%s'." % [SHAPE_COMPRESS, CASUALTY_CPR_MESH])
		return

	_shock_idx = _find_shape(mesh_resource, SHAPE_SHOCK)
	if _shock_idx < 0:
		push_error("CasualtyCpr: no blend shape named '%s' on '%s'." % [SHAPE_SHOCK, CASUALTY_CPR_MESH])
		# Compress still works without Shock; do not bail out of the whole build.

	_bind_clothed_mesh(root)

	_resolved = true
	_apply_depth()


## Resolves the clothed body's own Compression shape, if it has one.
##
## Deliberately does NOT call repair_mesh() on it. That splits a mesh in two and
## rebuilds it from arrays, which is right for the static posed overlay and wrong
## for a skinned one — main.gd already runs CasualtyMeshRepair.repair() over this
## mesh at startup, which keeps the skinning weights and copies the blend shapes
## across by name, so the index resolved here is the repaired mesh's.
##
## Every failure is a warning and a skipped visual. The Blender work that adds
## the shape runs in parallel with this code and may not land; a missing shape
## must cost the depression, never the beat.
func _bind_clothed_mesh(root: Node) -> void:
	_clothed_mesh = CprGhost.find_node(root, CASUALTY_CLOTHED_MESH) as MeshInstance3D
	if _clothed_mesh == null:
		push_warning(
			"CasualtyCpr: no MeshInstance3D named '%s'; the first compression set "
			% CASUALTY_CLOTHED_MESH
			+ "will not depress the shirt."
		)
		return
	if _clothed_mesh.mesh == null:
		push_warning("CasualtyCpr: '%s' has no Mesh resource." % CASUALTY_CLOTHED_MESH)
		return
	_clothed_compress_idx = _find_shape(_clothed_mesh.mesh, SHAPE_COMPRESS)
	if _clothed_compress_idx < 0:
		push_warning(
			("CasualtyCpr: no blend shape named '%s' on '%s'; compressions through "
			+ "the shirt have no visual. Author the shape in the .blend — it is "
			+ "matched by name, never by index.") % [SHAPE_COMPRESS, CASUALTY_CLOTHED_MESH]
		)


## Splits `mesh_node`'s mesh into two: the surfaces some blend shape actually moves stay
## on the original node (and keep the blend shapes), and every untouched
## surface is rehomed onto a child MeshInstance3D that has no blend shapes.
##
## The child is parented to `_mesh` with an identity transform so it inherits
## position and visibility for free — casualty.gd toggles this node's
## `visible` and must keep working without knowing the child exists. Named off
## no station's search prefix, and `owner = null` so it is never serialised
## (CPR_CONTRACT.md §6's "nodes added in code survive reimports" rule).
##
## No-op unless there is something to split, so a mesh whose shapes touch every
## surface is left exactly as it was.
##
## Static and idempotent on purpose. The repairs are not a CPR-phase concern —
## the casualty is on screen from the moment the trainee turns round, so
## main.gd runs this at startup and _build() calls it again when the
## compressions phase arrives; whichever gets there first does the work.
static func repair_mesh(mesh_node: MeshInstance3D) -> void:
	if mesh_node == null:
		return
	var src := mesh_node.mesh as ArrayMesh
	if src == null or src.get_blend_shape_count() == 0:
		return
	if mesh_node.has_node(CLOTHING_NODE_NAME):
		return  # already repaired (startup, or a second _build after a restart)

	var dynamic: Array[int] = []
	var static_surfaces: Array[int] = []
	for i in src.get_surface_count():
		if _surface_is_moved(src, i):
			dynamic.append(i)
		else:
			static_surfaces.append(i)
	if dynamic.is_empty():
		return

	var moved := ArrayMesh.new()
	for i in src.get_blend_shape_count():
		moved.add_blend_shape(src.get_blend_shape_name(i))
	moved.blend_shape_mode = src.blend_shape_mode
	for i in dynamic:
		var base: Array = _strip_duplicate_faces(src.surface_get_arrays(i))
		var indices: PackedInt32Array = base[Mesh.ARRAY_INDEX] if base[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		# Repair the base pose and every shape pose. The bad normals are in
		# the vertex data, so the compressed pose carries them too — which is
		# why the artefact tracked the chest as it moved.
		var shapes: Array = []
		for shape_arrays in src.surface_get_blend_shape_arrays(i):
			shapes.append(_recompute_normals(shape_arrays, indices))
		moved.add_surface_from_arrays(
			Mesh.PRIMITIVE_TRIANGLES, _recompute_normals(base, indices), shapes
		)
		moved.surface_set_material(moved.get_surface_count() - 1, src.surface_get_material(i))

	if not static_surfaces.is_empty():
		var still := ArrayMesh.new()
		for i in static_surfaces:
			# Deduped like the moved surfaces are: Pants1 carries 13
			# coincident faces, and two copies of a face z-fight into a dark
			# blotch wherever they are visible (measured with
			# tools/check_casualty_geometry.tscn). Normals are NOT recomputed
			# on these — see _recompute_normals() for why.
			still.add_surface_from_arrays(
				Mesh.PRIMITIVE_TRIANGLES, _strip_duplicate_faces(src.surface_get_arrays(i))
			)
			still.surface_set_material(still.get_surface_count() - 1, src.surface_get_material(i))

		var clothing := MeshInstance3D.new()
		clothing.name = CLOTHING_NODE_NAME
		clothing.mesh = still
		clothing.cast_shadow = mesh_node.cast_shadow
		mesh_node.add_child(clothing)
		clothing.owner = null
		clothing.transform = Transform3D.IDENTITY

	mesh_node.mesh = moved


## Drops triangles that occupy exactly the same three positions as one already
## kept.
##
## THIS is the dark patch over the casualty's right nipple. Measured on the
## running mesh: surface 0 has 3282 triangles but only 3278 distinct ones, and
## three of the four duplicates sit at (0.31, 0.14, 1.15) in local space —
## chest height, right side, exactly where the artefact appears. Two coincident
## coplanar faces z-fight, which reads as a mottled dark blotch, and it tracked
## the chest because both copies are driven by the same Compression shape.
##
## It looks fine in Blender because doubled faces are invisible there without
## a merge-by-distance; the depth test only cares in the engine. Removing them
## in code rather than in the .blend keeps the fix alive across reimports
## (CPR_CONTRACT.md §3) — though merging them in Blender would be the tidier
## home for it if the model is ever revisited.
##
## Keyed on quantised POSITIONS, not vertex indices: the duplicates come in as
## separate vertices, so an index-based comparison misses them entirely.
##
## Only the index array changes; the orphaned vertices are left in place, which
## costs a little memory and nothing visually.
static func _strip_duplicate_faces(arrays: Array) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if arrays[Mesh.ARRAY_INDEX] == null:
		return arrays
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]

	var seen := {}
	var kept := PackedInt32Array()
	var t := 0
	while t + 2 < indices.size():
		var corners := [
			_face_key(verts[indices[t]]),
			_face_key(verts[indices[t + 1]]),
			_face_key(verts[indices[t + 2]]),
		]
		corners.sort()  # winding-independent: a reversed duplicate is still one
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


## 0.1 mm buckets — tight enough that genuinely distinct geometry never
## collides, loose enough to catch a duplicate that differs only in float noise.
static func _face_key(p: Vector3) -> String:
	return "%d_%d_%d" % [roundi(p.x * 10000.0), roundi(p.y * 10000.0), roundi(p.z * 10000.0)]


## Recomputes every vertex normal on the surface from the geometry, merging
## across coincident positions.
##
## Started as an outlier-only repair — 24 of surface 0's 1757 vertices carried a
## normal more than 70 degrees off the faces around them. Fixing only those did
## not clear the dark patch on the chest, because the patch is not made of gross
## outliers: it is a region whose normals are wrong by a moderate amount, which
## reads as a soft shadow rather than a spike and sails past any outlier test
## loose enough to be safe. So the whole surface is solved instead.
##
## Safe to do wholesale here precisely because of the mesh split above: the only
## surfaces on this mesh are Human.body and Head4_skin1, neither of which is
## normal-mapped and both of which are organic and fully smooth-shaded. The
## normal-mapped clothing keeps its authored normals untouched on the sibling
## mesh, where recomputing would have destroyed its hard edges.
##
## Accumulation is keyed on QUANTISED POSITION, not vertex index. The importer
## splits vertices at every UV and material seam, so index-keyed averaging
## leaves each side of a seam with only half its neighbouring faces and lights
## the seam as a crease — which is the artefact class being chased here, not a
## fix for it.
##
## Face normals are left unnormalised while accumulating, so their length
## carries twice the triangle area and larger faces weigh more.
##
## Godot's winding makes cross(v1 - v0, v2 - v0) point AWAY from the shading
## normal, hence the negation.
static func _recompute_normals(arrays: Array, indices: PackedInt32Array) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	if verts.is_empty() or normals.size() != verts.size() or indices.is_empty():
		return arrays

	var keys := PackedStringArray()
	keys.resize(verts.size())
	for v in verts.size():
		keys[v] = _face_key(verts[v])

	var accumulated := {}
	var t := 0
	while t + 2 < indices.size():
		var i0 := indices[t]
		var i1 := indices[t + 1]
		var i2 := indices[t + 2]
		var face := -((verts[i1] - verts[i0]).cross(verts[i2] - verts[i0]))
		for i in [i0, i1, i2]:
			var key: String = keys[i]
			accumulated[key] = accumulated.get(key, Vector3.ZERO) + face
		t += 3

	for v in verts.size():
		var summed: Vector3 = accumulated.get(keys[v], Vector3.ZERO)
		if summed.length_squared() > DEGENERATE_EPSILON:
			normals[v] = summed.normalized()

	var out := arrays.duplicate()
	out[Mesh.ARRAY_NORMAL] = normals
	return out


## True if any blend shape moves any vertex of surface `index`.
static func _surface_is_moved(src: ArrayMesh, index: int) -> bool:
	var base: Array = src.surface_get_arrays(index)
	var base_verts: PackedVector3Array = base[Mesh.ARRAY_VERTEX]
	for shape_arrays in src.surface_get_blend_shape_arrays(index):
		var verts: PackedVector3Array = shape_arrays[Mesh.ARRAY_VERTEX]
		if verts.size() != base_verts.size():
			return true
		for v in verts.size():
			if verts[v].distance_squared_to(base_verts[v]) > SPLIT_EPSILON_SQ:
				return true
	return false


func _find_shape(mesh_resource: Mesh, shape_name: String) -> int:
	for i in range(mesh_resource.get_blend_shape_count()):
		if mesh_resource.get_blend_shape_name(i) == shape_name:
			return i
	return -1


## Both meshes, every frame — the same "write both, do not choose" pattern
## casualty.gd::_tween_mouth_open() uses on the mouth shape, and for the same
## reason: the expose-chest swap can happen between two compressions and the
## mesh that was not being driven would arrive flat.
func _apply_depth() -> void:
	if not _resolved:
		return
	if _mesh != null and _compress_idx >= 0:
		_mesh.set_blend_shape_value(_compress_idx, depth)
	if _clothed_mesh != null and _clothed_compress_idx >= 0:
		_clothed_mesh.set_blend_shape_value(_clothed_compress_idx, depth)


## One-shot 0 -> 1 -> 0 tween over SHOCK_TWEEN_S, per CPR_CONTRACT.md section
## 3. Public and stable — Agent H's shock_button.gd calls this on interact and
## must not need to edit this file to do it.
func trigger_shock() -> void:
	if not _resolved or _mesh == null or _shock_idx < 0:
		push_error("CasualtyCpr: trigger_shock() called before the Shock blend shape resolved.")
		return
	if _shock_tween != null and _shock_tween.is_valid():
		_shock_tween.kill()
	_mesh.set_blend_shape_value(_shock_idx, 0.0)
	_shock_tween = create_tween()
	_shock_tween.tween_method(_set_shock_value, 0.0, 1.0, SHOCK_TWEEN_S * 0.5)
	_shock_tween.tween_method(_set_shock_value, 1.0, 0.0, SHOCK_TWEEN_S * 0.5)


func _set_shock_value(value: float) -> void:
	if _mesh != null and _shock_idx >= 0:
		_mesh.set_blend_shape_value(_shock_idx, value)


## True once the mesh and the Compress blend shape have both been found.
## Shock may still be missing (see the warning in _build()) without this
## flipping false, since compressions do not depend on it.
func is_ready() -> bool:
	return _resolved


## Convenience for scripts that don't hold a CasualtyCpr reference. Returns
## 0.0 if no instance has resolved yet (e.g. called before the CPR phase has
## started).
static func current_depth() -> float:
	return _active.depth if _active != null else 0.0


## Convenience static wrapper, matching the CprStation._current accessor
## pattern used elsewhere in the CPR phase. No-ops with a push_error if no
## instance is alive yet.
static func trigger_shock_static() -> void:
	if _active != null:
		_active.trigger_shock()
	else:
		push_error("CasualtyCpr: trigger_shock_static() called with no active instance.")
