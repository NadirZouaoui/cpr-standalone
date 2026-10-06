extends Node
## Asserts that the two assets Task 2 authors in LVR CPR.blend are present in
## the imported scene, and that they survive the mesh rebuild the game runs at
## startup. Fails if the .blend work is reverted.
##
##     godot --headless --path <project> res://tools/check_blender_assets.tscn
##
## WHAT IS BEING GUARDED
##
## 1. `Compression` on the clothed skinned mesh Boots1_002. COMPRESSIONS_1 runs
##    with the shirt on, so the shape has to exist on the clothed body as well
##    as on the bare Casualty_CPR_Posed overlay. Matching is BY NAME - glTF
##    blend shape ordering is not stable across reimports (ARCHITECTURE.md
##    section 1) - so the assertion is on the name and the index is only ever
##    looked up from it.
##
## 2. That it survives CasualtyMeshRepair.repair(), which rebuilds the worker's
##    mesh surface by surface at startup and re-adds the shapes by name. A shape
##    dropped there would stay invisible until someone ran a compression in game.
##
## 3. `Casualty_Recovery_Posed`, the static posed mesh the AIRWAY_INSPECT and
##    RECOVERY_ROLL beats cold-switch to: carrying `Mouth open`, and sharing
##    Casualty_CPR_Posed's origin so the body does not jump across the floor on
##    the switch.
##
## 4. `LVR_Recovery` on the AnimationPlayer - Task 2c, and the implementation
##    Nadir chose on 3 Sep in place of the mesh swap: the same recovery pose,
##    driven through the clothed body's own armature. Two gates have to be
##    passed for a clip to get this far and BOTH fail silently, which is why
##    this is asserted rather than trusted:
##
##      a. In Blender the action has to be stashed on an NLA strip on the
##         Armature OBJECT. The glTF exporter runs in ACTIONS mode and writes
##         the active action plus NLA-strip actions and nothing else, so an
##         action that merely exists in the .blend never leaves it.
##      b. In Godot the clip has to be named in trim_animations.gd's CLIPS
##         allowlist, or the post-import script deletes it again.
##
##    The assertion below is not "the name is present". It plays the clip and
##    measures the skeleton it produces, against the supine pose LVR_Fall ends
##    on and against the approved mesh's own bounding box - so a clip that
##    arrives empty, or arrives holding the wrong pose, fails here.
##
## The recovery-pose assertions were reported but NOT fatal while
## RECOVERY_REQUIRED was false, because the tracks that consume the mesh are
## specified to degrade gracefully when it is absent. Task 2b landed on
## 3 Sep 2026 (commit ff40529) and the flag is now true: these are real
## assertions and they fail the check if the pose is reverted.

## The clothed, skinned body. Compressions in set 1 are read off this one.
const WORKER_MESH := "Boots1_002"
## The bare posed overlay. Geometric authority - colliders, pad sites, ear and
## hand anchors all hang off it. Used here only as the reference the other two
## are measured against.
const CPR_MESH := "Casualty_CPR_Posed"
## The static recovery pose. Task 2b.
const RECOVERY_MESH := "Casualty_Recovery_Posed"

const COMPRESSION_SHAPE := "Compression"
const MOUTH_SHAPE := "Mouth open"

## Task 2c. Kept in step with trim_animations.gd::CLIPS and with Casualty's
## anim_recovery export - a rename in Blender has to land in all three.
const RECOVERY_CLIP := "LVR_Recovery"
## The clip that leaves the casualty supine on the floor. Used as the reference
## the recovery pose is measured AGAINST, so that neither figure is a magic
## number: both are read out of the same import in the same run.
const SUPINE_CLIP := "LVR_Fall"

## True since Task 2b landed. See the header.
const RECOVERY_REQUIRED := true

## The recovery mesh has to sit on Casualty_CPR_Posed's origin or the body
## slides across the floor on the cold switch. Float noise through the glTF
## round trip is fine; a centimetre is not.
const ORIGIN_TOLERANCE_M := 0.001

## How deep the sternum goes at full compression, in metres. Measured off the
## Compression shape on Casualty_CPR_Posed; the clothed shape was authored to
## match it. A shape that exists but barely moves anything is caught here
## rather than in game.
const EXPECTED_PEAK_M := 0.034
const PEAK_TOLERANCE_M := 0.008

## The clip has to actually move the skeleton somewhere. A roll onto the side
## displaces the average bone by a good deal more than this; a clip that
## imported as a name with no usable tracks displaces it by nothing.
const MIN_MEAN_BONE_TRAVEL_M := 0.05
## Bones sit inside the body, so the skeleton is shorter than the skin. The
## supine skeleton is flat on the floor and the side-lying one is not, and that
## gap is what is asserted - not an absolute height.
const MIN_SKELETON_RISE_M := 0.08
## The posed skeleton must lie inside the approved mesh's own bounding box.
## Bones can sit at the surface (fingers, toes), so the box is grown a little
## rather than taken exactly.
const SKELETON_INSIDE_MARGIN_M := 0.06

## A body on its side is thicker top to bottom than a supine one: the supine
## mesh stands 0.358 m tall, the recovery pose 0.568 m. Asserted so that
## re-pointing RECOVERY_MESH at a duplicate of the supine body - or losing the
## pose in a rebuild - fails here rather than in front of a trainee.
const MIN_SIDE_LYING_HEIGHT_M := 0.45
## Both bodies rest on the same floor, so their lowest vertex is at the same
## height. This is the assertion that actually guards risk 1b: matching object
## origins say nothing about where the geometry inside them sits.
const FLOOR_TOLERANCE_M := 0.005

var _failures: PackedStringArray = []


func _ready() -> void:
	var root := (load("res://LVR CPR.blend") as PackedScene).instantiate()
	add_child(root)

	var worker := CprGhost.find_node(root, WORKER_MESH) as MeshInstance3D
	var posed := CprGhost.find_node(root, CPR_MESH) as MeshInstance3D
	var recovery := CprGhost.find_node(root, RECOVERY_MESH) as MeshInstance3D

	_check_worker_compression(worker, posed)
	_check_recovery(recovery, posed)
	_check_recovery_clip(root, recovery)

	if _failures.is_empty():
		print("check_blender_assets: all assertions passed.")
		get_tree().quit()
		return
	for line in _failures:
		print("FAIL: %s" % line)
	get_tree().quit(1)


## 2a. The Compression shape on the clothed mesh, before and after the startup
## repair, with its displacement measured rather than assumed.
func _check_worker_compression(worker: MeshInstance3D, posed: MeshInstance3D) -> void:
	if worker == null:
		_fail("no MeshInstance3D named '%s' in the .blend" % WORKER_MESH)
		return

	print("  %s: shapes %s" % [CPR_MESH, _shape_names(posed)])
	print("  %s.%s: peak %.4f m (the reference the clothed shape matches)" % [
		CPR_MESH, COMPRESSION_SHAPE, _peak_delta(posed, COMPRESSION_SHAPE)])
	print("  %s: shapes %s" % [WORKER_MESH, _shape_names(worker)])

	if _shape_index(worker, COMPRESSION_SHAPE) < 0:
		_fail("'%s' carries no blend shape named '%s' - Task 2a reverted, or the .blend has not been reimported" % [
			WORKER_MESH, COMPRESSION_SHAPE])
		return

	var peak := _peak_delta(worker, COMPRESSION_SHAPE)
	print("  %s.%s: peak %.4f m" % [WORKER_MESH, COMPRESSION_SHAPE, peak])
	if absf(peak - EXPECTED_PEAK_M) > PEAK_TOLERANCE_M:
		_fail("'%s.%s' displaces %.4f m; expected %.3f +/- %.3f so it reads at the same depth as the bare chest" % [
			WORKER_MESH, COMPRESSION_SHAPE, peak, EXPECTED_PEAK_M, PEAK_TOLERANCE_M])

	# The rebuild main.gd runs at startup re-adds shapes by name. Confirm it
	# rather than assume it - a dropped shape only shows up mid-run.
	CasualtyMeshRepair.repair(worker)
	print("  %s after CasualtyMeshRepair.repair(): shapes %s" % [
		WORKER_MESH, _shape_names(worker)])
	if _shape_index(worker, COMPRESSION_SHAPE) < 0:
		_fail("CasualtyMeshRepair.repair() drops '%s' from '%s'" % [
			COMPRESSION_SHAPE, WORKER_MESH])
		return
	var after := _peak_delta(worker, COMPRESSION_SHAPE)
	if absf(after - peak) > 1e-4:
		_fail("CasualtyMeshRepair.repair() changed '%s' on '%s' from %.4f m to %.4f m" % [
			COMPRESSION_SHAPE, WORKER_MESH, peak, after])


## 2b. The static recovery pose: present, mouth-driveable, and sharing the CPR
## mesh's origin.
func _check_recovery(recovery: MeshInstance3D, posed: MeshInstance3D) -> void:
	if recovery == null:
		_soft("no MeshInstance3D named '%s' in the .blend (Task 2b)" % RECOVERY_MESH)
		return
	print("  %s: shapes %s" % [RECOVERY_MESH, _shape_names(recovery)])
	print("  %s.%s: peak %.5f m" % [
		RECOVERY_MESH, MOUTH_SHAPE, _peak_delta(recovery, MOUTH_SHAPE)])

	if _shape_index(recovery, MOUTH_SHAPE) < 0:
		_soft("'%s' carries no '%s' shape; casualty.gd::_set_mouth_open() would have nothing to write and the head reads as closed after the swap" % [
			RECOVERY_MESH, MOUTH_SHAPE])

	if posed == null:
		_soft("'%s' is missing, so the recovery pose's origin cannot be checked against it" % CPR_MESH)
		return
	var offset := recovery.transform.origin - posed.transform.origin
	print("  %s origin offset from %s: %.4f m" % [
		RECOVERY_MESH, CPR_MESH, offset.length()])
	if offset.length() > ORIGIN_TOLERANCE_M:
		_soft("'%s' sits %.4f m from '%s'; the body will jump across the floor on the cold switch" % [
			RECOVERY_MESH, offset.length(), CPR_MESH])

	# Where the geometry sits inside the object, which is what the trainee sees.
	var box := (recovery.mesh as ArrayMesh).get_aabb()
	var reference := (posed.mesh as ArrayMesh).get_aabb()
	print("  %s aabb: pos %s size %s" % [RECOVERY_MESH, box.position, box.size])
	print("  %s aabb: pos %s size %s" % [CPR_MESH, reference.position, reference.size])
	if box.size.y < MIN_SIDE_LYING_HEIGHT_M:
		_soft("'%s' is only %.3f m tall; a body in the recovery position stands at least %.2f m, so this is not a side-lying pose" % [
			RECOVERY_MESH, box.size.y, MIN_SIDE_LYING_HEIGHT_M])
	var floor_drift := absf(box.position.y - reference.position.y)
	print("  %s floor line vs %s: %.4f m" % [RECOVERY_MESH, CPR_MESH, floor_drift])
	if floor_drift > FLOOR_TOLERANCE_M:
		_soft("'%s' rests %.4f m off '%s's floor line; the body sinks or floats on the cold switch" % [
			RECOVERY_MESH, floor_drift, CPR_MESH])

	# Both posed meshes import VISIBLE - Casualty_CPR_Posed does too - because
	# their Blender visibility is collection-level and does not survive the glTF
	# conversion. The project's convention is therefore to hide them in code:
	# casualty.gd::_ready() sets chest_mesh.visible = false with a comment saying
	# why it is not done in the .blend ("authored state in an imported subtree
	# does not survive a reimport"). So the assertion that matters is not how the
	# mesh imports, but whether the code hides it - which is what is exercised
	# here, by binding it exactly the way _ready() does.
	print("  %s imported visible = %s (expected - hidden in code, not the .blend)"
		% [RECOVERY_MESH, recovery.visible])
	_check_code_hides_recovery(recovery)

	# main.gd does not repair this mesh today, but the rebuild copies shapes by
	# name and a future caller would. Confirmed rather than assumed.
	var before := _peak_delta(recovery, MOUTH_SHAPE)
	CasualtyMeshRepair.repair(recovery)
	print("  %s after CasualtyMeshRepair.repair(): shapes %s" % [
		RECOVERY_MESH, _shape_names(recovery)])
	if _shape_index(recovery, MOUTH_SHAPE) < 0:
		_soft("CasualtyMeshRepair.repair() drops '%s' from '%s'" % [MOUTH_SHAPE, RECOVERY_MESH])
	elif absf(_peak_delta(recovery, MOUTH_SHAPE) - before) > 1e-4:
		_soft("CasualtyMeshRepair.repair() changed '%s' on '%s' from %.5f m to %.5f m" % [
			MOUTH_SHAPE, RECOVERY_MESH, before, _peak_delta(recovery, MOUTH_SHAPE)])


## 2c. The recovery pose as an armature clip.
##
## This is the assertion that catches a clip which was authored in Blender but
## never made it to the AnimationPlayer - the failure mode the whole task was
## written around, because it is completely silent at runtime: casualty.gd's
## _has_recovery_clip() simply returns false and the game falls back to the
## static mesh without a word.
##
## Nothing here is a hardcoded pose. The supine pose LVR_Fall ends on is read
## out of the same import and used as the reference, so the two figures drift
## together if the rig is ever rebuilt.
func _check_recovery_clip(root: Node, recovery: MeshInstance3D) -> void:
	var player := _find_player(root)
	if player == null:
		_fail("no AnimationPlayer in the .blend; nothing can play '%s'" % RECOVERY_CLIP)
		return
	var names := player.get_animation_list()
	print("  AnimationPlayer '%s': clips %s" % [player.name, names])

	if not player.has_animation(RECOVERY_CLIP):
		_fail(("the AnimationPlayer carries no clip named '%s'. Either the action is not "
			+ "stashed on an NLA strip on the Armature object (Blender's glTF exporter "
			+ "runs in ACTIONS mode and writes nothing else), or '%s' is missing from "
			+ "trim_animations.gd::CLIPS, which deletes every clip it does not name.")
			% [RECOVERY_CLIP, RECOVERY_CLIP])
		return

	var clip := player.get_animation(RECOVERY_CLIP)
	print("  %s: %d track(s), %.4f s, loop_mode %d" % [
		RECOVERY_CLIP, clip.get_track_count(), clip.length, clip.loop_mode])
	if clip.get_track_count() == 0:
		_fail("'%s' imported with no tracks at all - the name arrived, the pose did not" % RECOVERY_CLIP)
		return
	if clip.length <= 0.0:
		_fail(("'%s' is %.4f s long. A single-keyframe action exports as a zero-length "
			+ "glTF animation; the clip needs at least two frames so AnimationPlayer has "
			+ "something to hold.") % [RECOVERY_CLIP, clip.length])

	var skeleton := _find_skeleton(root)
	if skeleton == null:
		_fail("no Skeleton3D in the .blend, so '%s' has nothing to pose" % RECOVERY_CLIP)
		return
	# Track paths arrive from glTF as "Armature/Skeleton3D:mixamorig:Hips" -
	# relative to the player's root node, not to the skeleton - so they are
	# resolved rather than string-matched.
	var anim_root := player.get_node_or_null(player.root_node)
	var bone_tracks := 0
	for t in clip.get_track_count():
		var whole := String(clip.track_get_path(t))
		var node_part := whole.split(":")[0]
		if anim_root != null and anim_root.get_node_or_null(NodePath(node_part)) == skeleton:
			bone_tracks += 1
	print("  %s: %d of %d track(s) address '%s' (first: %s)" % [
		RECOVERY_CLIP, bone_tracks, clip.get_track_count(), skeleton.name,
		clip.track_get_path(0)])
	if bone_tracks == 0:
		_fail(("'%s' has %d track(s) but none of them addresses '%s'. The clip would play "
			+ "and pose nothing.") % [RECOVERY_CLIP, clip.get_track_count(), skeleton.name])
		return

	# What the two clips actually do to the skeleton, measured the same way.
	var supine := _bone_positions(player, skeleton, SUPINE_CLIP, -1.0)
	var rolled := _bone_positions(player, skeleton, RECOVERY_CLIP, 0.0)
	if rolled.is_empty():
		_fail("'%s' left the skeleton unposed" % RECOVERY_CLIP)
		return

	var rolled_box := _box_of(rolled)
	print("  skeleton under %s: aabb pos %s size %s" % [RECOVERY_CLIP, rolled_box.position, rolled_box.size])
	if not supine.is_empty():
		var supine_box := _box_of(supine)
		print("  skeleton under %s: aabb pos %s size %s" % [SUPINE_CLIP, supine_box.position, supine_box.size])
		var travel := 0.0
		for i in mini(supine.size(), rolled.size()):
			travel += supine[i].distance_to(rolled[i])
		travel /= float(mini(supine.size(), rolled.size()))
		print("  mean bone travel %s -> %s: %.4f m" % [SUPINE_CLIP, RECOVERY_CLIP, travel])
		if travel < MIN_MEAN_BONE_TRAVEL_M:
			_fail(("'%s' moves the average bone %.4f m off the supine pose. It is playing, but "
				+ "it is not a roll - expected at least %.2f m.") % [
				RECOVERY_CLIP, travel, MIN_MEAN_BONE_TRAVEL_M])
		var rise := rolled_box.size.y - supine_box.size.y
		print("  skeleton stands %.4f m taller on its side than supine" % rise)
		if rise < MIN_SKELETON_RISE_M:
			_fail(("the skeleton under '%s' is only %.4f m taller than under '%s'. A body on "
				+ "its side is markedly thicker floor-to-top than a flat one, so this pose is "
				+ "not side-lying.") % [RECOVERY_CLIP, rise, SUPINE_CLIP])

	# And it has to be THIS recovery pose, not some other one: the approved mesh
	# is still in the .blend, so the skeleton is measured against its box.
	if recovery == null or recovery.mesh == null:
		print("  (no %s to measure the posed skeleton against)" % RECOVERY_MESH)
		return
	var approved := (recovery.mesh as ArrayMesh).get_aabb()
	approved.position += recovery.global_transform.origin
	var grown := approved.grow(SKELETON_INSIDE_MARGIN_M)
	var outside := 0
	var worst := 0.0
	for p in rolled:
		if not grown.has_point(p):
			outside += 1
			worst = maxf(worst, _distance_outside(grown, p))
	print("  %d of %d posed bone(s) outside %s's box (+%.2f m): worst %.4f m" % [
		outside, rolled.size(), RECOVERY_MESH, SKELETON_INSIDE_MARGIN_M, worst])
	if outside > 0:
		_fail(("%d bone(s) posed by '%s' land outside '%s's own bounding box by up to %.4f m. "
			+ "The clip poses the body somewhere other than the approved recovery position - "
			+ "on the switch the casualty would sink, float or slide.") % [
			outside, RECOVERY_CLIP, RECOVERY_MESH, worst])


## Play `clip`, seek, and read every bone's global origin. `at` < 0 means "the
## last frame" - that is where _restore_supine_pose() parks LVR_Fall.
func _bone_positions(player: AnimationPlayer, skeleton: Skeleton3D, clip: String, at: float) -> PackedVector3Array:
	var out: PackedVector3Array = []
	if not player.has_animation(clip):
		return out
	player.play(clip)
	player.seek(player.get_animation(clip).length if at < 0.0 else at, true)
	player.advance(0.0)
	for b in skeleton.get_bone_count():
		out.append((skeleton.global_transform * skeleton.get_bone_global_pose(b)).origin)
	return out


func _box_of(points: PackedVector3Array) -> AABB:
	var box := AABB(points[0], Vector3.ZERO)
	for p in points:
		box = box.expand(p)
	return box


func _distance_outside(box: AABB, p: Vector3) -> float:
	var e := box.position + box.size
	var d := Vector3(
		maxf(maxf(box.position.x - p.x, p.x - e.x), 0.0),
		maxf(maxf(box.position.y - p.y, p.y - e.y), 0.0),
		maxf(maxf(box.position.z - p.z, p.z - e.z), 0.0))
	return d.length()


func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for c in node.get_children():
		var found := _find_player(c)
		if found != null:
			return found
	return null


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for c in node.get_children():
		var found := _find_skeleton(c)
		if found != null:
			return found
	return null


## The largest vertex displacement the named shape applies, in metres. Zero if
## the mesh or the shape is missing.
func _peak_delta(mi: MeshInstance3D, shape: String) -> float:
	var index := _shape_index(mi, shape)
	if index < 0:
		return 0.0
	var mesh := mi.mesh as ArrayMesh
	var peak := 0.0
	for s in mesh.get_surface_count():
		var base: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		var shapes: Array = mesh.surface_get_blend_shape_arrays(s)
		if index >= shapes.size():
			continue
		var moved: PackedVector3Array = (shapes[index] as Array)[Mesh.ARRAY_VERTEX]
		if moved.size() != base.size():
			continue
		for v in base.size():
			peak = maxf(peak, (moved[v] - base[v]).length())
	return peak


## Blend shapes are matched BY NAME, never by index - glTF ordering is not
## stable across reimports (ARCHITECTURE.md section 1).
func _shape_index(mi: MeshInstance3D, shape: String) -> int:
	if mi == null or mi.mesh == null:
		return -1
	var mesh := mi.mesh as ArrayMesh
	if mesh == null:
		return -1
	for i in mesh.get_blend_shape_count():
		if String(mesh.get_blend_shape_name(i)) == shape:
			return i
	return -1


func _shape_names(mi: MeshInstance3D) -> String:
	if mi == null or mi.mesh == null:
		return "<absent>"
	var mesh := mi.mesh as ArrayMesh
	if mesh == null:
		return "<not an ArrayMesh>"
	var names: PackedStringArray = []
	for i in mesh.get_blend_shape_count():
		names.append(String(mesh.get_blend_shape_name(i)))
	return "[%s]" % ", ".join(names)


func _fail(message: String) -> void:
	_failures.append(message)


## Reported and non-fatal while RECOVERY_REQUIRED is false. See the header.
func _soft(message: String) -> void:
	if RECOVERY_REQUIRED:
		_failures.append(message)
	else:
		print("  PENDING (Task 2b unfinished, not fatal): %s" % message)


## The real guard on "a second body is on screen from frame one": Casualty binds
## the posed mesh in _ready() and _recovery_mesh() hides it on bind. Exercised
## rather than assumed, because the import-time visibility above is expected to
## be true and so proves nothing on its own.
##
## A bare Casualty is used rather than the one in main.tscn: its exported
## NodePaths are empty here, so _ready() pushes a few warnings about meshes it
## cannot find and carries on. That is the point - the recovery bind has to
## survive a casualty whose other meshes are missing, which is exactly the
## degraded state Task 2b was written against.
func _check_code_hides_recovery(recovery: MeshInstance3D) -> void:
	if recovery == null:
		return
	recovery.visible = true  # worst case: whatever the import gave us
	var casualty: Node = (load("res://scripts/casualty/casualty.gd") as GDScript).new()
	add_child(casualty)
	var hidden: bool = not recovery.visible
	print("  %s hidden by Casualty._ready(): %s" % [RECOVERY_MESH, hidden])
	if not hidden:
		_fail(("Casualty._ready() left '%s' visible. Nothing hides the posed body, so it "
			+ "lies on the floor from the first frame through the whole exercise. "
			+ "_ready() must bind it (_recovery_mesh() hides on bind).") % RECOVERY_MESH)
	casualty.queue_free()
