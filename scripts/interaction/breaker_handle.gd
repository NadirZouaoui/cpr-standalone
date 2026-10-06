class_name BreakerHandle
extends Interactable
## The breaker's ON/OFF handle - the point of isolation, thrown after the
## casualty is clear.
##
## Why this comes last. The casualty is slumped against this breaker and in
## contact with the busbars it feeds, so the handle is physically
## unreachable while he is on it. Isolation is therefore *deferred*, not
## skipped: break contact with the crook, drag him clear, then throw the
## handle before anyone kneels down beside an open board and works for
## several minutes. Skipping it is how you get a second casualty when the
## paramedics arrive into the same space.
##
## Drag-then-isolate is the taught order, but it is not the only defensible
## one and the grading no longer treats it as though it were. Once the crook
## has cleared the casualty the handle is reachable, and a trainee who kills
## the supply right then - before walking back into the hazard zone to take
## hold of him - has made a reasoned call. That earns the coaching line in
## `early_message` and a transcript entry, and costs nothing. What still
## fails the exercise is never isolating at all: `supply_isolated` is
## critical, and an open board beside a resuscitation is the second-casualty
## case the whole beat exists to teach.
##
## The obstruction is the teaching beat, so it is loud. Between the incident
## starting and the casualty being dragged clear the prompt still appears
## and activating it refuses out loud, rather than doing nothing and reading
## as a bug. `blocked_message` is the whole lesson.
##
## Three states:
##
##   INERT    Pre-incident. No prompt - the worker is not at the board yet
##            and there is nothing to isolate for.
##   BLOCKED  Incident running, casualty still on the breaker. Prompt shows,
##            activation refuses.
##   ARMED    Casualty dragged clear. Throwing it completes `isolate_step`.
##
## Poses. The handle is authored ON in the .blend and the OFF pose was read
## off the inspector, so only the delta is stored here:
##
##   ON   position (0.005, 0.229, -0.012)  rotation x -8.9
##   OFF  position (0.005, 0.229,  0.062)  rotation x  14.1
##
## The imported pose is captured at runtime as ON and OFF is derived from it,
## the same way BreakerPanelInteract derives the door's closed angle. Storing
## the absolutes instead would snap the handle to a stale spot the first time
## the breaker moves in Blender.
##
## Built in code by BreakerPanel, which owns the tunables. The room is an
## imported .blend rebuilt wholesale on every reimport, so nothing wired into
## it by hand would survive.

signal supply_isolated()

enum Stage {
	INERT,   ## Before the incident. Not a target.
	BLOCKED, ## Casualty is on the breaker; the handle cannot be reached.
	ARMED,   ## Casualty is clear; the handle can be thrown.
	DONE,    ## Thrown. Inert from here on.
}

@export_group("Handle")
## The mesh that moves. Defaults to this node's parent, which is how
## BreakerPanel attaches it.
@export var handle_path: NodePath = ^".."

## Local translation from the ON pose to the OFF pose, in the handle's own
## parent space. Measured: z +0.074.
@export var off_offset: Vector3 = Vector3(0.0, 0.0, 0.074)

## Degrees added to the ON rotation to reach OFF. Measured: x +23.0
## (-8.9 -> 14.1).
@export var off_rotation_deg: Vector3 = Vector3(23.0, 0.0, 0.0)

## Deliberately quick and firm. A switching action is a snap, not a swing.
@export var throw_seconds: float = 0.35

@export_group("Gating")
## Completing this arms the handle. The casualty is lying against the
## breaker until he has been dragged clear, so this is the drag - not the
## crook. Exported so the gate moves in one place if the scenario is later
## rebuilt with the worker downstream of the board.
@export var gate_step: StringName = &"contact_broken"

## The step that makes throwing the handle match the taught order. Not a
## prerequisite of `isolate_step` any more - Assessment would score it as an
## out-of-order violation on a critical step, which fails the run outright,
## and an early throw is not worth a fail. Read here only, to choose between
## the two coaching messages and to write the recorded-not-penalised line.
@export var order_step: StringName = &"drag_to_safe_area"

## Completing this brings the handle out of INERT - it is what starts the
## incident, so before it there is no worker and nothing to isolate.
@export var incident_step: StringName = &"isolation_point_signed"

@export_group("Steps")
@export var isolate_step: StringName = &"supply_isolated"
## Passed on the Events.supply_isolated signal so downstream listeners can
## tell which board went dead.
@export var source_id: StringName = &"control_room_board"

@export_group("Copy")
## While the casualty is still in contact, on the breaker.
@export_multiline var blocked_contact_message: String = "You cannot reach the handle - the casualty is slumped against the breaker and still in contact with the busbars. Break contact with the crook first."

## After the hook, before the drag. He is off the breaker but still down in
## the hazard zone, at the foot of an open board.
@export_multiline var blocked_drag_message: String = "Not yet. The casualty is still lying in the hazard zone at the open board. Drag him clear, then come back and isolate."
@export_multiline var isolated_message: String = "Supply isolated. The busbars are dead - the board is safe to work beside."

## Shown when the handle is thrown before the casualty has been dragged
## clear. The action happened - the supply really is off - but it was taken
## standing over a casualty still lying in the hazard zone.
@export_multiline var early_message: String = "Supply isolated - but you did that standing over a casualty still in the hazard zone. Drag him clear first, then isolate. Recorded."

var _handle: Node3D = null
var _stage: Stage = Stage.INERT
var _on_position: Vector3 = Vector3.ZERO
var _on_rotation: Vector3 = Vector3.ZERO
var _off_position: Vector3 = Vector3.ZERO
var _off_rotation: Vector3 = Vector3.ZERO
## True while the handle is mid-throw, so a second click cannot restart it.
var _busy: bool = false
## Generous stand-in collider, see _build_hitbox().
var _hitbox: StaticBody3D = null


func _ready_impl() -> void:
	_handle = get_node_or_null(handle_path) as Node3D
	if _handle == null:
		push_error("BreakerHandle: no handle at '%s'" % handle_path)
		return

	# The imported pose is ON, so it is the reference. OFF is derived rather
	# than hard-coded, which keeps this working if the breaker is moved in
	# Blender.
	_on_position = _handle.position
	_on_rotation = _handle.rotation
	_off_position = _on_position + off_offset
	_off_rotation = _on_rotation + Vector3(
		deg_to_rad(off_rotation_deg.x),
		deg_to_rad(off_rotation_deg.y),
		deg_to_rad(off_rotation_deg.z)
	)

	_build_hitbox()
	_refresh_stage()
	Events.step_completed.connect(_on_step_completed)


func _on_step_completed(_step_id: StringName, _at: float) -> void:
	_refresh_stage()


func stage() -> Stage:
	return _stage


func is_isolated() -> bool:
	return _stage == Stage.DONE


func _refresh_stage() -> void:
	if _stage == Stage.DONE:
		return
	var next := Stage.INERT
	if Assessment.is_complete(gate_step):
		next = Stage.ARMED
	elif Assessment.is_resolved(incident_step):
		next = Stage.BLOCKED
	if next == _stage:
		return
	_stage = next
	if _stage == Stage.INERT:
		unhighlight()


# =============================================================================
# Prompt
# =============================================================================
func prompt_text() -> String:
	match _stage:
		Stage.BLOCKED, Stage.ARMED:
			return "Isolate at %s" % label()
		_:
			return ""


## BLOCKED is interactable on purpose: the refusal is the lesson, and a
## prompt that silently does nothing reads as a broken object.
func can_interact() -> bool:
	return (
		enabled
		and not _busy
		and not SimState.is_preamble()
		and (_stage == Stage.BLOCKED or _stage == Stage.ARMED)
	)


# =============================================================================
# Activation
# =============================================================================
func _on_interact(_from_position: Vector3) -> void:
	match _stage:
		Stage.BLOCKED:
			_refuse()
		Stage.ARMED:
			_throw()


## Two refusals, because they are two different mistakes. Before the crook
## the handle is physically unreachable; after it the handle is reachable and
## the trainee is simply doing it in the wrong order, standing over a
## casualty who is still in the hazard zone.
func _refuse() -> void:
	var reached := Assessment.is_complete(&"contact_broken")
	var text := blocked_drag_message if reached else blocked_contact_message
	Events.center_message_requested.emit(text, Tokens.WARNING, 3.5)
	# Logged rather than graded. Reaching for the isolator is the right
	# instinct at the wrong moment, and marking it against the trainee would
	# teach them not to try.
	Events.log_action(
		&"break_contact",
		"Attempted to isolate before the casualty was clear",
		&"info",
		"The casualty was still in the hazard zone at the board."
	)


func _throw() -> void:
	if _handle == null:
		_finish()
		return

	_busy = true
	unhighlight()

	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_handle, "position", _off_position, throw_seconds)
	tween.tween_property(_handle, "rotation", _off_rotation, throw_seconds)
	await tween.finished

	if not is_inside_tree():
		return

	_busy = false
	_finish()


func _finish() -> void:
	_stage = Stage.DONE
	# The handle is done being a target and the trainee is about to be
	# kneeling right beside it doing compressions; a live prompt there would
	# pull the reticle off the casualty.
	if _hitbox != null:
		_hitbox.collision_layer = 0
	# `isolate_step` requires only `contact_broken` in the procedure resource,
	# so throwing the handle before the drag is NOT an out-of-order violation
	# and does not touch the score. That is deliberate: the handle is reachable
	# the moment the crook clears the casualty, and killing the supply before
	# walking back into the hazard zone to drag him is a defensible call, not
	# an exercise-ending error. It is still a deviation from the taught order,
	# so it is said out loud here and written to the transcript for the
	# debrief - recorded, at no cost.
	var in_order := Assessment.is_complete(order_step)
	Assessment.complete(isolate_step)

	if in_order:
		Events.center_message_requested.emit(isolated_message, Tokens.SCENE_TEXT, 3.5)
	else:
		Events.center_message_requested.emit(early_message, Tokens.WARNING, 4.5)
		Events.log_action(
			&"extraction",
			"Isolated the supply before the casualty was dragged clear",
			&"warning",
			"The taught order is to drag the casualty clear of the hazard zone first, then isolate. Isolating first is defensible - it kills the supply before you re-enter the zone - but it leaves the casualty lying at the foot of an open board for longer. Recorded, not penalised."
		)
	Events.supply_isolated.emit(source_id)
	unhighlight()
	supply_isolated.emit()


## A padded box around the handle, for the same reason the panel has one:
## the handle is a small part standing proud of a large cabinet whose own
## collider is flush and much closer to the ray. Without this the prompt
## only appears from a few centimetres away.
##
## Interactable layer only, masks nothing, so it is invisible to movement
## and physics.
func _build_hitbox() -> void:
	var box := BreakerPanelInteract.own_bounds(_handle)
	if box.size == Vector3.ZERO:
		return

	var shape := BoxShape3D.new()
	# Padded to at least a comfortable click target - the handle itself is
	# only a few centimetres across.
	shape.size = Vector3(
		maxf(box.size.x + 0.08, 0.14),
		maxf(box.size.y + 0.08, 0.14),
		maxf(box.size.z + 0.14, 0.18)
	)

	var collider := CollisionShape3D.new()
	collider.name = "Shape"
	collider.shape = shape
	collider.position = box.get_center()

	_hitbox = StaticBody3D.new()
	_hitbox.name = "HandleHitbox"
	_hitbox.collision_layer = 2
	_hitbox.collision_mask = 0
	_hitbox.add_child(collider)
	_handle.add_child(_hitbox)
