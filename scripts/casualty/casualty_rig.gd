class_name CasualtyRig
extends Node
## Builds the casualty's click target and keeps it on the animated body.
##
## Why this exists rather than a `-convcol` suffix in Blender: the importer's
## generated collider is baked from the mesh at rest and parented under the
## MeshInstance3D. Skinning happens on the GPU, so that shape never moves -
## by the time the worker has fallen, the collider is still standing at the
## panel. Adding `-convcol` to a skinned mesh gives you a body-shaped hole in
## the air, not a hit target.
##
## So: one capsule, driven each frame from a bone. Two details make that work.
##
## 1. The armature carries a negative Z scale from the FBX import, so
##    anything parented into the skeleton inherits a negative-determinant
##    basis. Godot refuses to scale collision shapes and will spam errors.
##    The capsule therefore lives outside the rig and only copies the bone's
##    *position* plus an orthonormalised, determinant-corrected basis.
## 2. Skeleton-local units are centimetres (the armature is scaled 0.01), so
##    the sampler reads the bone in world space rather than local space.
##
## Bound in code like ToolRack, because the .blend subtree is rebuilt on
## every reimport and anything wired in the editor would be lost.

## The imported Skeleton3D.
@export var skeleton_path: NodePath = ^"../../ControlRoom/Armature/Skeleton3D"

## Bone the capsule rides. Matched by suffix, so it survives whatever the
## glTF importer does to "mixamorig:Hips".
@export var bone_hint: String = "Hips"

@export_group("Shape")
## Radius and full height in metres, sized to the standing worker.
@export var capsule_radius: float = 0.34
@export var capsule_height: float = 1.5
## Lifts the capsule from the hip bone to the middle of the body. The hips
## bone sits at about y=1.0 when he is standing, so this is small.
@export var capsule_offset: float = 0.2

@export_group("Interaction")
@export var interactable_id: StringName = &"casualty"
@export var display_name: String = "Casualty"

## The hit target is top-level, so hiding the rig during the pre-exercise
## phases does not hide this. Without the gate the trainee could interact
## with a casualty who is not in the room yet: invisible, but clickable.
@export var wait_for_exercise_start: bool = true

## Hand the arming to someone else entirely, the way ShockCue does. With
## this set the capsule stays off layer 2 and no phase is watched, until
## another node calls arm().
##
## The preamble boundary is not late enough any more. The trainee now works
## at the breaker before the incident, and the capsule sits directly between
## them and the panel - invisible, on the interaction layer, and swallowing
## every ray aimed at the middle of the door. The panel was only reachable
## by aiming past the worker's shoulder.
##
## Takes precedence over `wait_for_exercise_start`.
@export var armed_externally: bool = false

var skeleton: Skeleton3D
var body: StaticBody3D
var interactable: CasualtyInteractable

var _bone: int = -1
var _casualty: Casualty


func _ready() -> void:
	# Nothing to follow until the capsule exists, and nothing worth following
	# while the room is empty. Re-enabled in _build_hit_target and, if the
	# preamble is holding it, in _on_phase_changed.
	set_process(false)

	_casualty = get_parent() as Casualty
	if _casualty == null:
		push_error("CasualtyRig must be a child of a Casualty node.")
		return

	skeleton = get_node_or_null(skeleton_path) as Skeleton3D
	if skeleton == null:
		push_error("CasualtyRig: no Skeleton3D at '%s'" % skeleton_path)
		return

	_bone = _find_bone(bone_hint)
	if _bone < 0:
		push_error("CasualtyRig: no bone ending in '%s'" % bone_hint)
		return

	# Children are ready before their parent, so at this point Casualty is
	# still mid-instantiation and add_child() on it is refused. Deferring
	# puts the build at the end of the frame, once the tree has settled.
	_build_hit_target.call_deferred()


## Bone names arrive as "mixamorig:Hips" or "mixamorig_Hips" depending on the
## importer's sanitiser, so match on the tail rather than the whole string.
func _find_bone(hint: String) -> int:
	var needle := hint.to_lower()
	for i in skeleton.get_bone_count():
		if skeleton.get_bone_name(i).to_lower().ends_with(needle):
			return i
	return -1


func _build_hit_target() -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = capsule_radius
	shape.height = maxf(capsule_height, capsule_radius * 2.0)

	var col := CollisionShape3D.new()
	col.name = "Shape"
	col.shape = shape

	body = StaticBody3D.new()
	body.name = "CasualtyBody"
	# Layer 2 is what InteractionRay looks at (mask 7). Staying off layer 1
	# keeps the player from bumping into an invisible capsule.
	body.collision_layer = 2
	body.collision_mask = 0
	body.top_level = true
	body.add_child(col)

	interactable = CasualtyInteractable.new()
	interactable.name = "Interact"
	interactable.id = interactable_id
	interactable.display_name = display_name
	interactable.casualty = _casualty
	# No mesh to outline - the rig's materials come from the .blend and the
	# overlay would have to be applied per skinned surface. The reticle
	# prompt carries the affordance instead.
	interactable.mesh_to_highlight = null
	body.add_child(interactable)

	_casualty.add_child(body)
	_follow()

	# Someone else owns the arming: stay unclickable and wait to be told.
	if armed_externally:
		_set_target_active(false)
		return

	if wait_for_exercise_start and SimState.is_preamble():
		_set_target_active(false)
		Events.phase_changed.connect(_on_phase_changed)
		return

	set_process(true)


## Take the casualty back out of the room, whatever state the arming got
## into. Safe before or after the deferred capsule build, and safe to call
## twice.
##
## BreakerPanel calls this from its own _ready rather than trusting the
## exported flag in main.tscn: the scene is edited by hand and by the editor
## alternately, and a save from a stale editor copy silently dropped that
## property once already. The consequence - an invisible capsule eating
## every ray aimed at the middle of the breaker - is far too quiet a failure
## to leave resting on one line of .tscn.
func hold() -> void:
	armed_externally = true
	if Events.phase_changed.is_connected(_on_phase_changed):
		Events.phase_changed.disconnect(_on_phase_changed)
	_set_target_active(false)
	set_process(false)


## Put the casualty in the room: clickable, and following the animation.
## Safe to call before the deferred capsule build has run - _build_hit_target
## checks the flag itself.
func arm() -> void:
	armed_externally = false
	if body == null:
		return
	_set_target_active(true)
	set_process(true)


## Layer 2 is what InteractionRay looks at; layer 0 is on nobody's mask.
func _set_target_active(value: bool) -> void:
	if body != null:
		body.collision_layer = 2 if value else 0


func _on_phase_changed(_previous: int, _current: int) -> void:
	if SimState.is_preamble():
		return
	Events.phase_changed.disconnect(_on_phase_changed)
	_set_target_active(true)
	set_process(true)


## World position of the driven bone. The rescue sequence aims the hook at
## this rather than at wherever the interaction ray happened to land.
func bone_position() -> Vector3:
	if skeleton == null or _bone < 0:
		return Vector3.ZERO
	return (skeleton.global_transform * skeleton.get_bone_global_pose(_bone)).origin


## World position of any bone, matched by name suffix the same way the
## driven bone is. The extraction uses this to measure which way the body is
## lying before it decides how far to turn him, so the alignment reads the
## pose that is actually on screen rather than one assumed from the clip.
##
## Returns ZERO when the bone does not resolve; callers are expected to
## treat that as "cannot measure" rather than as the world origin.
func bone_position_for(hint: String) -> Vector3:
	if skeleton == null:
		return Vector3.ZERO
	var i := _find_bone(hint)
	if i < 0:
		push_warning("CasualtyRig: no bone ending in '%s'" % hint)
		return Vector3.ZERO
	return (skeleton.global_transform * skeleton.get_bone_global_pose(i)).origin


func _process(_delta: float) -> void:
	if body != null and body.is_inside_tree():
		_follow()


func _follow() -> void:
	var t := skeleton.global_transform * skeleton.get_bone_global_pose(_bone)

	# Strip the rig's scale and the negative-Z mirror; a collision shape must
	# sit on an orthonormal, right-handed basis or Godot will complain and
	# fall back to something unpredictable.
	var basis := t.basis.orthonormalized()
	if basis.determinant() < 0.0:
		basis.z = -basis.z

	# Offset along the bone, not world up, so the capsule lies down with the
	# body during the fall instead of standing up out of the floor.
	body.global_transform = Transform3D(basis, t.origin + basis.y * capsule_offset)
