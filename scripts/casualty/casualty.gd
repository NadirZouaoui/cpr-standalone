class_name Casualty
extends Node3D
## The shocked worker.
##
## Holds the clinical state - responsive, breathing, in contact - and drives
## the rig's animations. Deliberately knows nothing about scoring: it reports
## what happened through Events and Assessment decides what that was worth.
##
## The important invariant is that unsafe contact while IN_CONTACT is fatal to
## the rescuer. That rule lives here rather than in the grader because it is
## a property of the casualty's situation, not of the checklist.
##
## SINGLE OWNER OF THE ANIMATIONPLAYER. This is the only script that calls
## play() on the imported AnimationPlayer. ShockCue used to drive the same
## clips on the same player from its own timer, which meant two nodes racing
## to start the shock a quarter of a second apart and the second one
## restarting the lead-in the first had already begun. ShockCue now owns the
## presentation - the rig's visibility and the arc at the breaker - and
## listens for the state changes emitted here. If a third thing ever needs to
## move the worker, it asks this node; it does not reach for the player.
##
## Node references are NodePath exports rather than typed Node exports on
## purpose: a hand-written .tscn silently drops typed Node references unless
## the node line also carries `node_paths=PackedStringArray(...)`, and this
## scene is edited by hand.

enum State {
	IN_CONTACT,    ## Locked to the conductor, shock animation looping.
	COLLAPSING,    ## Contact broken, falling. Not yet touchable.
	DOWN,          ## Unresponsive, not breathing, still in the hazard zone.
	BEING_DRAGGED, ## Mid-extraction.
	SAFE,          ## In the safe area, ready for the primary survey.
	COMPRESSIONS,  ## CPR underway.
	ROSC,          ## Spontaneous breathing has returned.
	RECOVERY,      ## On their side, airway protected.
	FIDDLING,      ## Working at the panel; the shock has not happened yet.
	WAITING,       ## Not in the room yet. The kit check is still up.
}

@export_group("Rig")
## The AnimationPlayer that came in with the .blend.
@export var animation_player_path: NodePath = ^"../ControlRoom/AnimationPlayer"

## The imported armature's root. The skinned mesh lives inside the .blend
## subtree rather than under this node, so an extraction has to move *that*
## and not this node's origin - tweening `self` looked correct in the
## remote tree and moved nothing on screen.
@export var rig_root_path: NodePath = ^"../ControlRoom/Armature"

## The closed-shirt skinned body - the one the trainee sees for the whole
## exercise up to this point. Hidden the moment the chest overlay is shown,
## so the two stop overlapping; not hidden any earlier, because it is the
## skinned mesh doing the actual falling/dragging animation.
@export var closed_shirt_mesh_path: NodePath = ^"../ControlRoom/Armature/Skeleton3D/Boots1_002"

## The chest-exposed overlay mesh - the shirt-open body baked from the same
## fall pose as the skinned casualty, sitting in the same spot but not
## parented under the armature (it is a plain static MeshInstance3D, not a
## skinned one). Hidden until expose_chest() reveals it, and moved by hand in
## drag_to_safety() rather than by reparenting, for the same reason `self` is
## tweened alongside `mover` below: it is not in the armature's subtree, so
## nothing else moves it.
@export var chest_mesh_path: NodePath = ^"../ControlRoom/Casualty_CPR_Posed"

## Clip names as they arrive from Blender. The four LVR_* actions are the
## authored sequence; the rest are placeholders that do not exist yet, and
## `_play` degrades to "hold the last pose" when a name is missing.
@export var anim_fiddle: StringName = &"LVR_Fiddle"
@export var anim_shock_enter: StringName = &"LVR_ShockEnter"
@export var anim_shock_loop: StringName = &"LVR_ShockHold"
@export var anim_collapse: StringName = &"LVR_Fall"
@export var anim_down: StringName = &""
@export var anim_drag: StringName = &""
@export var anim_compressions: StringName = &""
@export var anim_breathing: StringName = &""
@export var anim_recovery: StringName = &"LVR_Recovery"

@export_group("Opening")
## Run the fiddle-then-shock opening by itself. Off leaves the worker in
## WAITING until something calls `begin_opening()` or `begin_shock()`.
@export var autostart: bool = true

## Hold the opening until the exercise proper begins. The kit check runs
## first and is untimed, so without this the worker is electrocuted while
## the trainee is still reading a quiz - and the contact clock, which is the
## number the debrief is built around, starts against a trainee who has not
## been let into the room yet.
@export var wait_for_exercise_start: bool = true

## How long the worker fiddles at the breaker before the shock. The idle is
## 1.75 s, so this runs just under three cycles - long enough for the
## trainee to look around and read the scene before the incident.
@export var fiddle_duration: float = 5.25

## Skip the opening and start already energised. For testing the rescue
## without sitting through the fiddle; not for the shipping build.
@export var start_energised: bool = false

@export_group("Extraction")
## Where the casualty ends up after a successful drag. Position only - the
## marker's rotation is ignored, because the body is turned by measuring the
## rig's own bones rather than by copying a transform onto a mirrored basis.
@export var safe_area_marker_path: NodePath
@export var drag_duration: float = 3.5

## Keep the body at the height it fell at. The anchor is placed on the floor
## plane by eye and its Y is not meant to be authoritative.
@export var preserve_drag_height: bool = true

## Finish the drag with the body lying along world X. The compression pose,
## the kneeling position beside the chest and the camera framing all assume
## that axis, so the trainee has to lay him out, not merely move him.
@export var align_to_x_axis: bool = true

## Which way the head points once aligned.
@export var head_toward_positive_x: bool = true

## Extra turn applied on top of the measured alignment, in degrees. Nudge
## this if the finished pose reads a few degrees off.
@export var align_yaw_deg: float = 0.0

## Bones the alignment measures between, matched by name suffix.
@export var align_from_bone: String = "Hips"
@export var align_to_bone: String = "Head"

@export_group("Clinical")
## Seconds of compressions after the shock before spontaneous breathing
## returns. Matches the reference video's pacing rather than any real
## physiology - it exists so the trainee experiences resuming CPR.
@export var rosc_delay: float = 20.0

var state: State = State.WAITING:
	set = _set_state

var responsive: bool = false
var breathing: bool = false
var chest_exposed: bool = false
var pads_attached: bool = false
var airway_open: bool = false

var animation_player: AnimationPlayer
var rig_root: Node3D
var closed_shirt_mesh: Node3D
var chest_mesh: Node3D
var safe_area_marker: Node3D

var _shock_delivered: bool = false
var _compression_time: float = 0.0
var _opened: bool = false


func _ready() -> void:
	add_to_group(&"casualty")
	animation_player = get_node_or_null(animation_player_path) as AnimationPlayer
	if animation_player == null:
		push_error("Casualty: no AnimationPlayer at '%s'" % animation_player_path)
	rig_root = get_node_or_null(rig_root_path) as Node3D
	if rig_root == null:
		push_warning("Casualty: no rig root at '%s'; extraction will not move the body"
			% rig_root_path)
	closed_shirt_mesh = get_node_or_null(closed_shirt_mesh_path) as Node3D
	if closed_shirt_mesh == null:
		push_warning("Casualty: no closed-shirt mesh at '%s'; expose_chest() will not hide it"
			% closed_shirt_mesh_path)
	chest_mesh = get_node_or_null(chest_mesh_path) as Node3D
	if chest_mesh == null:
		push_warning("Casualty: no chest overlay mesh at '%s'; expose_chest() will not change the model"
			% chest_mesh_path)
	else:
		# Starts hidden - the trainee has not exposed the chest yet. Set here
		# rather than as a scene default so the overlay's default visibility
		# never has to be hand-edited in the imported .blend subtree.
		chest_mesh.visible = false
		# The overlay comes out of the .blend with its "Mouth open" shape
		# already driven, so a chest exposed before the airway was opened
		# swapped in a head that was tilted back with no one having tilted it.
		# Zeroed here for the same reason the visibility is: authored state in
		# an imported subtree does not survive a reimport.
		_set_mouth_open(chest_mesh, 0.0)
	# Bind the recovery pose eagerly, for the same reason chest_mesh is hidden
	# just above: it imports visible, and a lazy bind would leave a second body
	# lying on the floor until the first roll beat resolved it. _recovery_mesh()
	# hides it on bind and warns once if the .blend never got the mesh.
	_recovery_mesh()
	if not safe_area_marker_path.is_empty():
		safe_area_marker = get_node_or_null(safe_area_marker_path) as Node3D

	# The other half of the extraction gate. The drag asks _try_leave_extraction()
	# directly because it runs here; the isolation is BreakerHandle's and reaches
	# this the only way it can - through the step it completes.
	Events.step_completed.connect(_on_step_completed_for_extraction)

	# The .blend may carry an autoplay of its own, and the imported player
	# starts on whatever that is. Stop rather than merely declining to play.
	if animation_player != null:
		animation_player.stop()

	if start_energised:
		begin_shock()
		return
	if not autostart:
		return

	if wait_for_exercise_start and SimState.is_preamble():
		Events.phase_changed.connect(_on_phase_changed)
		return

	begin_opening()


func _on_phase_changed(_previous: int, _current: int) -> void:
	if SimState.is_preamble():
		return
	Events.phase_changed.disconnect(_on_phase_changed)
	begin_opening()


func _process(delta: float) -> void:
	if state != State.COMPRESSIONS:
		return
	_compression_time += delta
	# Return of spontaneous circulation only after a shock plus sustained
	# compressions. Without the shock, compressions alone never convert.
	if _shock_delivered and _compression_time >= rosc_delay:
		_achieve_rosc()


func _set_state(next: State) -> void:
	if next == state:
		return
	state = next
	Events.casualty_state_changed.emit(next)


## Missing clips are a warning, not an error: an unimplemented state simply
## holds whatever pose the previous clip ended on.
##
## `loop` restates what trim_animations.gd already set at import. That is
## deliberate belt-and-braces: a .blend that has not been reimported since
## the trim step was added would otherwise play the idle once and freeze.
func _play(anim: StringName, loop: bool = false) -> void:
	if animation_player == null or anim == &"":
		return
	if not animation_player.has_animation(anim):
		push_warning("Casualty: missing animation '%s'" % anim)
		return
	var a := animation_player.get_animation(anim)
	a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	animation_player.play(anim)


## Blocks until the named clip finishes. `animation_finished` fires for
## whatever ended, not for what was asked about, so a clip cut short by the
## rescue landing mid-sequence would otherwise release the wrong await.
func _await_clip(anim: StringName) -> void:
	if animation_player == null or not animation_player.has_animation(anim):
		await get_tree().create_timer(1.5).timeout
		return
	while true:
		var finished: StringName = await animation_player.animation_finished
		if finished == anim or not animation_player.is_playing():
			return


# =============================================================================
# Opening: fiddle -> shock
# =============================================================================
## Puts the worker at the panel and starts the countdown to the incident.
## Idempotent, so a phase that fires twice cannot restart the idle.
func begin_opening() -> void:
	if _opened:
		return
	_opened = true
	self.state = State.FIDDLING
	_play(anim_fiddle, true)
	_run_opening()


func _run_opening() -> void:
	if fiddle_duration > 0.0:
		await get_tree().create_timer(fiddle_duration).timeout
	# A reset, an early failure, or a scene teardown can move us on while
	# the timer runs.
	if not is_inside_tree() or state != State.FIDDLING:
		return
	begin_shock()


## Skip-into point for ShockEnter, in seconds. The first ~0.55 s of the bake
## is just more fiddling - the jolt does not start until after it - so played
## from zero the incident reads as the worker carrying on before shocking.
## Nudge this in the inspector if the clip is re-baked from Blender.
@export var shock_enter_start: float = 0.55


## Enters the shock and holds it. Idempotent, so a clue or a debug key that
## fires twice cannot restart the convulsion mid-way.
func begin_shock() -> void:
	if state == State.IN_CONTACT:
		return
	_opened = true
	self.state = State.IN_CONTACT

	# Opens the contact clock. Nothing else moved the phase to BREAK_CONTACT,
	# so `SimState.contact_seconds` - the one number the debrief is built
	# around - was reading zero on every run. Guarded rather than assigned
	# outright so a late call cannot rewind the exercise to before the fall.
	if SimState.phase < SimState.Phase.BREAK_CONTACT:
		SimState.phase = SimState.Phase.BREAK_CONTACT

	_play(anim_shock_enter)
	# Cut past the clip's baked-in fiddle lead-in (see shock_enter_start).
	# Without this the worker keeps fiddling for half a second after the arc
	# starts burning, and the incident reads as two beats instead of one.
	if animation_player != null and shock_enter_start > 0.0:
		animation_player.seek(shock_enter_start, true)

	# ShockEnter is a one-shot lead-in; ShockHold is the loop the trainee
	# actually interrupts. Awaiting is safer than queue() because the rescue
	# can land during the lead-in, and the state check below stops the hold
	# from stomping the fall.
	await _await_clip(anim_shock_enter)
	if state != State.IN_CONTACT:
		return
	_play(anim_shock_loop, true)


## World position of the hips, for anything that needs to aim at the body
## rather than at the camera's hit point. Falls back to the node origin if
## the rig has not built yet.
func hips_position() -> Vector3:
	var rig := get_node_or_null(^"Rig") as CasualtyRig
	if rig == null:
		return global_position
	var p := rig.bone_position()
	return global_position if p == Vector3.ZERO else p


# =============================================================================
# Break contact
# =============================================================================
## The rescuer reached the casualty without the insulated hook and gloves.
## This is the failure the whole exercise exists to prevent.
func touch_unsafely(what: String = "") -> void:
	if state == State.IN_CONTACT:
		var detail := " " + what if what != "" else ""
		Events.fatal_violation.emit(
			"You contacted a casualty still connected to a live conductor%s. " % detail
			+ "The current passed through you and there are now two casualties."
		)
	elif state == State.COLLAPSING:
		Assessment.record_violation(&"contact_broken", "Reached in before the casualty was clear of the conductor.")


## Kept for callers that predate the PPE rule.
func touch_bare_handed() -> void:
	touch_unsafely("bare-handed")


## Called by the rescue hook, once Rescuer has confirmed hook + gloves.
func break_contact_with_crook() -> void:
	if state != State.IN_CONTACT:
		return
	SimState.mark_contact_broken()
	Assessment.complete(&"contact_broken")
	# COLLAPSING is what stops the arc: ShockCue is watching this signal, so
	# the sparks die on the frame the hook lands rather than whenever some
	# other script remembers to call release().
	self.state = State.COLLAPSING
	_play(anim_collapse)

	await _await_clip(anim_collapse)
	if not is_inside_tree() or state != State.COLLAPSING:
		return

	self.state = State.DOWN
	# anim_down is empty until a floor idle exists; the fall's last frame
	# stays on screen, which is the correct pose anyway.
	_play(anim_down, true)
	SimState.phase = SimState.Phase.EXTRACTION


# =============================================================================
# Extraction
# =============================================================================
func can_drag() -> bool:
	return state == State.DOWN


func drag_to_safety() -> void:
	if not can_drag():
		if state == State.IN_CONTACT or state == State.COLLAPSING:
			touch_unsafely()
		return

	self.state = State.BEING_DRAGGED
	_play(anim_drag, true)

	if safe_area_marker != null:
		# The rig root, not this node. The skinned mesh lives inside the
		# .blend subtree, so tweening `self` looks correct in the remote tree
		# and moves nothing on screen.
		var mover: Node3D = rig_root if rig_root != null else self
		var start_basis := mover.global_transform.basis
		var start_pos := mover.global_position
		var end_pos := safe_area_marker.global_position
		if preserve_drag_height:
			end_pos.y = start_pos.y
		var yaw := _alignment_yaw()

		# The chest-exposed overlay is not parented under the armature (it is
		# a plain static mesh, not a skinned one), so it has to be carried by
		# hand exactly like `self` below. Captured as a transform relative to
		# `mover` at the start of the drag, rather than as a fixed offset, so
		# it keeps whatever alignment it was baked with even if the overlay
		# and the armature do not start out perfectly coincident.
		var chest_rel: Transform3D
		if chest_mesh != null:
			chest_rel = mover.global_transform.affine_inverse() * chest_mesh.global_transform

		# Assigned to a local before handing it to tween_method rather than
		# written inline: the lambda's body is now more than one statement
		# (it also carries the chest overlay along), and a multi-statement
		# lambda written directly as a call argument is a trap here - the
		# trailing comma that used to separate it from tween_method's other
		# arguments has to sit outside the lambda's own indented block, not
		# on the last line of an `if`.
		var step := func(t: float) -> void:
			var mover_xform := Transform3D(
				Basis(Vector3.UP, yaw * t) * start_basis,
				start_pos.lerp(end_pos, t)
			)
			mover.global_transform = mover_xform
			if chest_mesh != null:
				chest_mesh.global_transform = mover_xform * chest_rel

		var tween := create_tween()
		tween.set_ease(Tween.EASE_IN_OUT)
		# Position and turn are driven together through one method tweener
		# rather than through tween_property on `global_position` and
		# `global_rotation`. The armature carries a negative Z scale from the
		# FBX import, so its basis has a negative determinant; Euler angles
		# taken off it do not round-trip and the body arrives inside-out.
		# Pre-multiplying by a world-Y rotation leaves the scale and the
		# handedness exactly as the importer left them.
		tween.tween_method(step, 0.0, 1.0, drag_duration)
		if mover != self:
			# Keep the logical node with the body so hips_position()'s
			# fallback and anything parented here stay in the right place.
			var self_end := end_pos
			if preserve_drag_height:
				self_end.y = global_position.y
			tween.parallel().tween_property(self, "global_position", self_end, drag_duration)
		await tween.finished
	else:
		push_warning("Casualty: no safe_area_marker set; drag is cosmetic only")
		await get_tree().create_timer(drag_duration).timeout

	if not is_inside_tree() or state != State.BEING_DRAGGED:
		return

	self.state = State.SAFE
	_play(anim_down, true)
	Assessment.complete(&"drag_to_safe_area")
	_try_leave_extraction()


## EXTRACTION has two jobs in it, not one: drag the casualty clear, and isolate
## the board. The phase used to end on the drag alone, which meant a trainee who
## dragged and then walked away was carried into the primary survey with a live
## board at their back and only a checklist row to say so.
##
## Either job can finish last - the taught order is drag then isolate, and
## isolating first is permitted (BreakerHandle._finish records it rather than
## penalising it) - so the gate is asked from both, and moves the phase only
## when nothing is outstanding.
##
## `is_resolved`, not `is_complete`. A step closed as a failure is never coming
## back, and waiting on it would strand the run in EXTRACTION for good.
const EXTRACTION_STEPS: Array[StringName] = [&"drag_to_safe_area", &"supply_isolated"]


func _on_step_completed_for_extraction(step_id: StringName, _at: float) -> void:
	if EXTRACTION_STEPS.has(step_id):
		_try_leave_extraction()


func _try_leave_extraction() -> void:
	if SimState.phase > SimState.Phase.EXTRACTION:
		return
	for step in EXTRACTION_STEPS:
		if not Assessment.is_resolved(step):
			return
	SimState.phase = SimState.Phase.PRIMARY_SURVEY


## How far to turn the body about world Y so it finishes lying along the X
## axis, head toward +X.
##
## Measured from the rig's own bones rather than hard-coded from the fall
## clip. The clip is re-authored in Blender independently of this project,
## and a constant here would silently leave the casualty lying across the
## room's axis the first time the fall was re-baked from a different
## direction. Bones cannot go stale.
##
## Returns a delta, not an absolute heading, so it composes with whatever
## the importer did to the armature's basis instead of fighting it.
func _alignment_yaw() -> float:
	var manual := deg_to_rad(align_yaw_deg)
	if not align_to_x_axis:
		return manual

	var rig := get_node_or_null(^"Rig") as CasualtyRig
	if rig == null:
		return manual

	var from := rig.bone_position_for(align_from_bone)
	var to := rig.bone_position_for(align_to_bone)
	var axis := to - from
	axis.y = 0.0
	if axis.length() < 0.05:
		# He is still upright, or the bones did not resolve. Turning him on a
		# measurement this short would be a guess dressed up as a calculation.
		push_warning("Casualty: body axis too short to align; using align_yaw_deg only")
		return manual

	# Counter-clockwise in the XZ plane seen from above, which is the
	# convention Basis(Vector3.UP, a) rotates in.
	var current := atan2(-axis.z, axis.x)
	var target := 0.0 if head_toward_positive_x else PI
	return wrapf(target - current + manual, -PI, PI)


# =============================================================================
# The posed recovery mesh
# =============================================================================
## The clothed body lying on its side, authored in Blender for the overnight
## run of 3 Sep 2026. ONE POSE, USED TWICE: the airway inspection rolls to it and
## back, the recovery position rolls to it and stays. They are the same physical
## position; only the dwell differs.
##
## Bound by a runtime name search rather than a NodePath export, and re-searched
## on demand, because it may not exist at all: the Blender work runs in parallel
## with the code and may not land. Everything here degrades to a warning and a
## skipped visual — never a crash, never a blocked beat. That absent path is the
## one this was tested against, because the mesh was absent when it was written.
const RECOVERY_MESH_NAME := "Casualty_Recovery_Posed"

var recovery_mesh: Node3D = null
var _recovery_warned: bool = false
## True while the posed mesh is the visible body, so the swap back knows to run.
var _in_recovery_pose: bool = false
## Which meshes were on screen before the swap, restored when it reverses.
var _pre_pose_closed_visible: bool = false
var _pre_pose_chest_visible: bool = false


## Resolves the posed mesh, searching once per call so a Blender reimport that
## lands mid-session is picked up. Null (with one warning, not one per frame) if
## the asset was never authored.
func _recovery_mesh() -> Node3D:
	if recovery_mesh != null and is_instance_valid(recovery_mesh):
		return recovery_mesh
	var root: Node = get_tree().current_scene if get_tree() != null else null
	if root == null:
		root = get_parent()
	recovery_mesh = CprGhost.find_node(root, RECOVERY_MESH_NAME) as Node3D
	if recovery_mesh != null and not _in_recovery_pose:
		# The .blend imports it visible, so without this the posed body lies on
		# the floor from the first frame, through the whole exercise. Hidden here
		# at bind time rather than in the .blend: Blender's hide_render risks
		# dropping it from the glTF conversion altogether, and the engine side is
		# where the other posed mesh is governed too. Guarded on _in_recovery_pose
		# so a reimport that re-resolves mid-pose does not hide a body that should
		# be on screen.
		recovery_mesh.visible = false
	if recovery_mesh == null and not _recovery_warned:
		_recovery_warned = true
		push_warning(
			("Casualty: no mesh named '%s'; the airway inspection and the recovery "
			+ "position run as messages with no visual. Author it in the .blend at "
			+ "the same origin and world transform as Casualty_CPR_Posed, carrying "
			+ "a '%s' blend shape.") % [RECOVERY_MESH_NAME, SHAPE_MOUTH_OPEN]
		)
	return recovery_mesh


## True when a real recovery clip is on the AnimationPlayer. That is the better
## of the two implementations and the one Nadir chose on 3 Sep: pose the skinned
## clothed body through its own 65-bone armature, rather than cold-switching to
## a static 7101-vert duplicate of it.
##
## It does not violate CPR_CONTRACT.md §8. That rule reads "never touch the
## casualty's AnimationPlayer - Casualty is its single owner", which binds OTHER
## scripts; this file is the owner and already calls play(). The casualty is
## lying supine in the first place because LVR_Fall put it there, so posing this
## body by clip is the established mechanism rather than an exception to it.
func _has_recovery_clip() -> bool:
	return (
		anim_recovery != &""
		and animation_player != null
		and animation_player.has_animation(anim_recovery)
	)


## Back to the supine pose the fall left on screen. `anim_down` is empty - there
## is no floor idle - so the pose to return to is LVR_Fall's last frame, the same
## frame _collapse() leaves up. Seeked to the end rather than replayed, or the
## body would fall over a second time in front of the trainee.
func _restore_supine_pose() -> void:
	if animation_player == null:
		return
	if anim_down != &"" and animation_player.has_animation(anim_down):
		_play(anim_down, true)
		return
	if anim_collapse == &"" or not animation_player.has_animation(anim_collapse):
		return
	var clip := animation_player.get_animation(anim_collapse)
	animation_player.play(anim_collapse)
	animation_player.seek(clip.length, true)
	animation_player.pause()


## Pose the skinned body, or return it to supine. Preferred over the mesh swap
## below whenever the clip exists.
##
## The static bare overlay is hidden on the way in: it carries no armature, so
## it cannot follow the pose and would lie supine underneath a body that had
## rolled. The pad sites are its children (docs/OVERNIGHT_PLAN.md §3), so they
## go with it rather than floating at the old position - the same pad fix the
## mesh path gets, by the same mechanism.
##
## AIRWAY_INSPECT costs no swap at all here: it runs before compressions with
## the shirt still on, so the skinned body is already what is on screen and only
## the pose changes. That is the saving that made this the better design.
func _show_recovery_pose_by_clip(on: bool) -> bool:
	if on:
		_pre_pose_closed_visible = closed_shirt_mesh != null and closed_shirt_mesh.visible
		_pre_pose_chest_visible = chest_mesh != null and chest_mesh.visible
		if chest_mesh != null:
			chest_mesh.visible = false
		if closed_shirt_mesh != null:
			closed_shirt_mesh.visible = true
			# The airway is open by the time either roll beat runs, and each mesh
			# holds the shape independently - same reason expose_chest() re-syncs
			# it across its own swap.
			_set_mouth_open(closed_shirt_mesh, _pose_mouth_value())
		# loop = false, so the clip holds its last frame: a static pose, which is
		# what "just pose well cold switch" asked for.
		_play(anim_recovery)
	else:
		if closed_shirt_mesh != null:
			closed_shirt_mesh.visible = _pre_pose_closed_visible
		if chest_mesh != null:
			chest_mesh.visible = _pre_pose_chest_visible
		_restore_supine_pose()
		# AFTER the pose restore, not before. _restore_supine_pose() seeks
		# LVR_Fall's last frame, and that clip drives the head's blend shapes
		# along with its bones - so it puts the jaw back where the fall left
		# it, which is shut. Coming out of the pose with the airway open used
		# to land a supine body with a closed mouth, undoing on screen a step
		# the trainee had performed and been graded on.
		_sync_mouth_shape()
	_in_recovery_pose = on
	return true


## Pose the body, or take it back off the pose. Two implementations: the clip
## above when one is authored, and the static-mesh cold switch below when it is
## not. No tween in either - Nadir, 3 Sep: "we dont need roll animation just
## pose well cold switch."
##
## Returns true if the visual actually happened, so a caller can tell a silent
## skip from a real roll. Nothing depends on it being true.
func show_recovery_pose(on: bool) -> bool:
	if on == _in_recovery_pose:
		return true
	if _has_recovery_clip():
		return _show_recovery_pose_by_clip(on)

	# Fallback: the static duplicate mesh. Kept because it is verified working
	# and is the only path if the clip is ever lost in a reimport.
	var mesh := _recovery_mesh()
	if mesh == null:
		return false

	if on:
		_pre_pose_closed_visible = closed_shirt_mesh != null and closed_shirt_mesh.visible
		_pre_pose_chest_visible = chest_mesh != null and chest_mesh.visible
		if closed_shirt_mesh != null:
			closed_shirt_mesh.visible = false
		if chest_mesh != null:
			chest_mesh.visible = false
		# The airway is open by the time either roll beat runs, and the meshes
		# hold the shape independently — same reason expose_chest() re-syncs it
		# across its own swap.
		_set_mouth_open(mesh, _pose_mouth_value())
		mesh.visible = true
	else:
		mesh.visible = false
		if closed_shirt_mesh != null:
			closed_shirt_mesh.visible = _pre_pose_closed_visible
		if chest_mesh != null:
			chest_mesh.visible = _pre_pose_chest_visible
		# Same re-sync as the clip path above. This one is belt and braces -
		# the static swap never touched the skinned meshes' shapes - but the
		# two paths have to leave the body in the same state or which of them
		# ran becomes visible to the trainee.
		_sync_mouth_shape()

	_in_recovery_pose = on
	return true


## True while the posed body is what is on screen.
func in_recovery_pose() -> bool:
	return _in_recovery_pose


# =============================================================================
# Primary survey
# =============================================================================
## Client item 4: check the casualty is not on fire. One observation beat, and
## the outcome is always clear — Nadir confirmed it, and there is no fire
## simulation behind it. The fire blanket stays in the kit as the answer to a
## question this run does not ask.
func check_for_fire() -> bool:
	Assessment.complete(&"fire_checked")
	Events.center_message_requested.emit(
		"No burning clothing, no arcing. The casualty is not alight.",
		Tokens.SUCCESS, 3.5
	)
	return false


## Client item 6, first half: roll the casualty and look in the mouth for a
## blockage. Rolls and reports; CprStation owns the dwell and calls
## end_airway_inspection() to roll back.
##
## The finding is always "clear". Like the fire check, this is an observation
## the trainee has to actually make rather than a puzzle with an answer.
##
## The finding line says the roll back is coming. The beat is a roll onto the
## side, a look, and a roll back onto the back - that is the procedure, and
## compressions cannot be done on a body lying on its side. But the trainee sees
## it as one click that tips the casualty over and stands them up again, and in
## playtest it read as the game undoing itself rather than as the second half of
## the check. Nothing about the beat changes; it just stops being a surprise.
func inspect_airway() -> void:
	show_recovery_pose(true)
	Events.center_message_requested.emit(
		"Airway clear — no obstruction. Rolling them back onto their back.",
		Tokens.SUCCESS, 3.0
	)
	Assessment.complete(&"airway_inspected")


## Rolls the casualty back off the airway inspection. Safe to call when the
## pose never happened.
func end_airway_inspection() -> void:
	show_recovery_pose(false)


func check_response() -> bool:
	Assessment.complete(&"check_response")
	Events.center_message_requested.emit(
		"No response. The casualty does not react to voice or touch.",
		Tokens.DANGER, 3.5
	)
	return responsive


func check_breathing() -> bool:
	Assessment.complete(&"check_breathing")
	if breathing:
		Events.center_message_requested.emit("The casualty is breathing normally.", Tokens.SUCCESS, 3.0)
	else:
		Events.center_message_requested.emit(
			"Not breathing. Send for help and start compressions.",
			Tokens.DANGER, 3.5
		)
	return breathing


## Name of the mouth-open blend shape as authored in Blender. Present on both
## the closed-shirt skinned mesh and the chest-exposed overlay, since the
## trainee can open the airway before or after exposing the chest and
## whichever mesh is visible at that moment needs the shape driven.
const SHAPE_MOUTH_OPEN := "Mouth open"

## Seconds for the head tilt. Long enough to read as a hand moving the head,
## short enough that the trainee is not waiting on it before the next step.
const AIRWAY_TILT_SECONDS := 0.55

## True while the head tilt is animating. Only expose_chest() cares: it must
## not stamp a fixed value over a tween that is mid-flight.
var _airway_tilting: bool = false


## The head tilt is a movement, not a state change: snapping the blend shape to
## 1.0 read as the jaw teleporting. Tweened instead, over a beat that matches a
## hand actually tilting the head back.
##
## The step is graded on the instant the action is taken, not when the tween
## lands — the trainee did the thing; the animation is only how it is shown.
func open_airway() -> void:
	if airway_open:
		return
	airway_open = true
	_tween_mouth_open()
	Assessment.complete(&"airway_opened")


func _tween_mouth_open() -> void:
	_airway_tilting = true
	var tween := create_tween()
	tween.finished.connect(func() -> void: _airway_tilting = false)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(
		func(v: float) -> void:
			# Both meshes, every frame: the chest overlay may be swapped in
			# part-way through and would otherwise arrive with a closed mouth.
			_set_mouth_open(closed_shirt_mesh, v)
			_set_mouth_open(chest_mesh, v),
		0.0, 1.0, AIRWAY_TILT_SECONDS
	)


## How far open the jaw sits once the body is in the recovery position.
##
## Not the full tilt. The head-tilt-chin-lift that holds an unconscious supine
## airway open is a thing the rescuer does with their hands and stops doing the
## moment they let go; on his side the airway is held open by the position
## itself, and the jaw falls most of the way back. Leaving it gaping read as
## the rescuer still holding a tilt on a casualty they had just rolled and let
## go of.
##
## Applies to the recovery position only. The airway inspection rolls the body
## too, but that beat is a look INTO the mouth - see _pose_mouth_value().
const RECOVERY_MOUTH_OPEN := 0.5


## The jaw for whichever roll is being entered.
##
## The two rolls want different mouths and only the casualty's state tells them
## apart: roll_to_recovery() sets State.RECOVERY before it poses the body, and
## the airway inspection never leaves the state it found.
func _pose_mouth_value() -> float:
	if not airway_open:
		return 0.0
	return RECOVERY_MOUTH_OPEN if state == State.RECOVERY else 1.0


## Puts both skinned meshes' jaws back where `airway_open` says they belong.
##
## Needed wherever something else has driven the head: an animation clip owns
## the blend-shape track as much as it owns the bones, so any play() or seek()
## overwrites the airway tilt. See _show_recovery_pose_by_clip's else branch.
func _sync_mouth_shape() -> void:
	var v: float = 1.0 if airway_open else 0.0
	_set_mouth_open(closed_shirt_mesh, v)
	_set_mouth_open(chest_mesh, v)


## Drives the named blend shape by name rather than by cached index: this runs
## for well under a second, once per exercise, so there is no per-frame cost to
## justify resolving and caching the index the way casualty_cpr.gd does for the
## every-frame Compress shape.
func _set_mouth_open(mesh_node: Node3D, value: float) -> void:
	var mi := mesh_node as MeshInstance3D
	if mi == null or mi.mesh == null:
		return
	for i in mi.mesh.get_blend_shape_count():
		if mi.mesh.get_blend_shape_name(i) == SHAPE_MOUTH_OPEN:
			mi.set_blend_shape_value(i, value)
			return


## Swaps the closed-shirt skinned body for the chest-exposed static overlay.
## One-way: nothing in the exercise re-covers the chest, so there is no
## corresponding "hide the overlay, show the skinned body" path back.
func expose_chest() -> void:
	chest_exposed = true
	if closed_shirt_mesh != null:
		closed_shirt_mesh.visible = false
	if chest_mesh != null:
		chest_mesh.visible = true
		# Carry the airway across the swap: the two meshes hold the shape
		# independently, so whichever is revealed has to be told where the head
		# currently is. Skipped mid-tilt, where the running tween is already
		# writing both meshes every frame.
		if not _airway_tilting:
			_set_mouth_open(chest_mesh, 1.0 if airway_open else 0.0)
	Assessment.complete(&"chest_exposed")


# =============================================================================
# Resuscitation
# =============================================================================
func start_compressions() -> void:
	# Still where he fell, or still moving. Compressions in the hazard zone
	# are not a scoring mistake to be written down afterwards - they are a
	# thing the trainee should not be able to start at all.
	if state == State.DOWN or state == State.BEING_DRAGGED:
		Events.center_message_requested.emit(
			"Drag the casualty clear and lay him out before starting compressions.",
			Tokens.WARNING, 3.0
		)
		return
	if not airway_open:
		Assessment.record_violation(&"airway_opened", "Compressions begun with the airway unmanaged.")
	if state == State.ROSC or state == State.RECOVERY:
		# Recorded against `cpr_performed`, the live step for the compression
		# work. It used to name `compressions_started`, an id retired from the
		# procedure resource — a violation against a step that does not exist
		# has no title for the debrief to print.
		Assessment.record_violation(&"cpr_performed", "Compressions continued on a breathing casualty.")
		return

	self.state = State.COMPRESSIONS
	_compression_time = 0.0
	_play(anim_compressions, true)

	# `compressions_started` and `compressions_resumed` were completed here.
	# Both ids were retired from lvr_cpr_procedure.tres and every call was a
	# push_warning no-op (PROJECT_STATUS.md §6.4); the compression work is
	# graded once, as `cpr_performed`, off the CPR spine's own metrics. The
	# phase move is the only thing this branch was really doing.
	if not _shock_delivered:
		SimState.phase = SimState.Phase.RESUSCITATION


func stop_compressions() -> void:
	if state != State.COMPRESSIONS:
		return
	self.state = State.SAFE
	_play(anim_down, true)


func attach_pads() -> void:
	if not chest_exposed:
		Events.center_message_requested.emit(
			"The pads will not stick through clothing. Expose the chest first.",
			Tokens.WARNING, 3.0
		)
		return
	pads_attached = true
	# `pads_placed` was completed here. Retired id, push_warning no-op — pad
	# work is graded as part of `aed_used` off the CPR spine's metrics.
	#
	# The guard above used to be theatre: the shirt came off before the pads
	# could ever be reached. The client's reordered spine puts the first
	# compression set in front of `chest_exposed`, so a trainee can now genuinely
	# arrive at the pads with the shirt closed. Keep it.


## NOTE: nothing calls this. The CPR phase delivers its shock through
## ShockButton (Events.aed_shock_delivered + CasualtyCpr.trigger_shock_static),
## and the rescuer-in-contact fatal that used to live here — unreachable, since
## this function is never invoked — now sits in shock_button.gd where the press
## actually happens, keyed off CprStation.trainee_at_anchor() rather than this
## casualty's own state. Left otherwise intact because `_shock_delivered` still
## feeds the ROSC check above; removing it is a separate cleanup.
func deliver_shock() -> void:
	if not pads_attached:
		return
	_shock_delivered = true
	_compression_time = 0.0
	# `shock_delivered` was completed here. Retired id, push_warning no-op — the
	# shock is graded as part of `aed_used`.


func _achieve_rosc() -> void:
	self.state = State.ROSC
	breathing = true
	_play(anim_breathing, true)

	# Closes `signs_of_life`, which nothing else was closing. It is a
	# prerequisite of `recovery_position`, and `recovery_position` is
	# critical - so with the step left open, rolling the casualty over was
	# always an out-of-order violation and every run failed on a step the
	# trainee had performed correctly.
	#
	# Awarded automatically because there is currently no interaction for
	# "confirm normal breathing has returned" - the physiology announces
	# itself. When that interaction exists, move this there: recognising
	# ROSC is the trainee's job, and grading it here gives it away.
	Assessment.complete(&"signs_of_life")

	Events.center_message_requested.emit(
		"The casualty is breathing on their own. Stop compressions.",
		Tokens.SUCCESS, 4.0
	)
	SimState.phase = SimState.Phase.RECOVERY


## Public door onto the ROSC beat, for CprStation to call at the end of the
## second compression set (client item 8, docs/OVERNIGHT_PLAN.md §5 Task 6).
##
## _achieve_rosc() already existed and already did the right things; the plan
## asked for it to be wired up rather than rewritten, so this is a guard and a
## delegation and nothing else. The guard matters because the spine can re-enter
## RECOVERY_ROLL through debug_jump_to_state, and announcing the return of
## circulation twice would read as a second event.
##
## The _process() route into _achieve_rosc() — shock delivered, then
## `rosc_delay` seconds of compressions — is left alone but is dead in practice:
## nothing calls start_compressions(), so `state` is never COMPRESSIONS and the
## timer never runs. The CPR spine's own second set is what the client's
## sequence actually hangs on, and that is what this serves.
func achieve_rosc() -> void:
	if state == State.ROSC or state == State.RECOVERY:
		return
	_achieve_rosc()


# =============================================================================
# Recovery
# =============================================================================
## Client item 8. Cold-switch to the posed body and leave it there — the same
## swap the airway inspection borrows, only without the roll back.
##
## The mesh swap is what the empty `anim_recovery` export always implied and
## never had. Nadir approved the clip on 3 Sep, once it was clear that "we dont
## need roll animation just pose well cold switch" ruled out a rolling MOTION
## rather than the AnimationPlayer: a single-pose clip cold-switches just as the
## mesh swap does. show_recovery_pose() prefers it and falls back to the static
## duplicate mesh when no clip is imported.
##
## THE PADS. show_recovery_pose() hides `chest_mesh`, and the pad sites are its
## children (docs/OVERNIGHT_PLAN.md §3), so they go with it rather than being
## left floating at the old supine position. That is the whole of the pad fix
## Task 2b asks for — no separate hide is needed, and adding one would be a
## second owner for the same visibility.
##
## KNOWN COMPROMISE, for the handover report: when the posed mesh does land it
## is CLOTHED, so rolling into recovery re-closes the shirt over pads that were
## just applied to a bare chest. Nadir asked for the clothed switch and there is
## no bare-chest recovery pose. Flagged, not solved.
func roll_to_recovery() -> void:
	if state != State.ROSC:
		Assessment.record_violation(
			&"recovery_position",
			"Recovery position attempted on a casualty who was not breathing."
		)
		return
	self.state = State.RECOVERY
	# No _play(anim_recovery) here: show_recovery_pose() owns the clip now, and
	# playing it here as well drove it twice in one frame.
	if not show_recovery_pose(true):
		# Degraded path, and the one that runs until Task 2b lands: the warning
		# has already been pushed by _recovery_mesh(). Say it in words so the
		# beat still reads, rather than leaving the body supine and unexplained.
		Events.center_message_requested.emit(
			"Rolled into the recovery position.", Tokens.SUCCESS, 3.0
		)
	Assessment.complete(&"recovery_position")


# =============================================================================
# Injury survey
# =============================================================================
## Client item 8's third beat: "check for any other injuries".
##
## One finding, at the hands. That is not a guess — it is where an electrical
## casualty's entry wound is, and this one was electrocuted holding a tool at a
## live board, so the burn is at the contact point. The other two sites come
## back clear, which is what makes looking at the hands mean something: three
## identical findings would be three clicks, not a survey.
##
## Deliberately NOT a hidden-object puzzle. Every site is offered at once and
## none of them is wrong to check; the assessment is that the survey was carried
## out and the injury found, not that the trainee guessed the right pill first.
const INJURY_SITES := {
	&"hands": {
		"finding": true,
		"message": "Burn to the right palm — the contact point. Note it for the crew.",
		"log": "Found the entry burn at the contact point during the injury survey.",
	},
	&"head": {
		"finding": false,
		"message": "Head and neck clear — no bleeding, no obvious deformity.",
		"log": "Checked the head and neck for injuries.",
	},
	&"legs": {
		"finding": false,
		"message": "Legs and feet clear — no exit wound found.",
		"log": "Checked the legs and feet for injuries.",
	},
}


## Reports what is at one site. Returns true if that site carried the finding,
## so the caller knows whether the survey is answered.
##
## Completing `injuries_checked` is the caller's job, not this one's: the step
## is the survey, and the survey is a sequence of looks rather than any single
## one of them.
func survey_injury(site: StringName) -> bool:
	if not INJURY_SITES.has(site):
		push_warning("Casualty.survey_injury: no injury site named '%s'" % site)
		return false
	var entry: Dictionary = INJURY_SITES[site]
	var found: bool = entry["finding"]
	Events.center_message_requested.emit(
		String(entry["message"]),
		Tokens.ATTENTION if found else Tokens.SUCCESS,
		3.5
	)
	Events.log_action(&"recovery", String(entry["log"]), &"info", "")
	return found
