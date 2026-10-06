class_name BreakerPanelInteract
extends Interactable
## The breaker panel door: recognise the hazard, then open the board.
##
## Two beats, in order:
##
##   IDENTIFY  Raise hazard assessment pass 1. HazardAssessment grades the
##             ticked set and completes `identify_step`; this node only asks
##             for the panel and waits for the step to land.
##   OPEN      Swing the panel. Completes `open_step`, then goes inert.
##
## **This node no longer tells the trainee what the hazard is.** It used to
## complete `identify_step` on a single click and then print "Live 400 V
## supply. This board feeds the panel the worker is about to open..." on
## screen - which is the answer to the assessment, given away for free, in
## exchange for a critical weight-6 step and one mouse button. The assessment
## replaced both halves of that (docs/OVERNIGHT_PLAN.md section 5, Task 4).
##
## They share one node because they are two uses of the same physical thing,
## and because the reticle prompt is the tutorial: the trainee reads
## "Examine", then "Open", off the same object.
##
## Hanging the sign is deliberately *not* here - see IsolationSignMount. By
## the time the sign is due this door has swung 154 degrees out of the way,
## so a prompt on it would point at a panel that is no longer part of the
## board being looked at.
##
## The .blend ships this door modelled open. `start_closed` shuts it on the
## first frame, so opening it is something the trainee does rather than
## something they walk in on.
##
## Built in code by BreakerPanel, which owns the tunables. The room is an
## imported .blend and its node tree is rebuilt wholesale on every reimport,
## so nothing wired into it by hand would survive.

signal stage_changed(stage: int)
## The board is open. BreakerPanel uses this to arm the sign mount.
signal panel_opened()

enum Stage {
	IDENTIFY, ## The panel has not been recognised as the hazard yet.
	OPEN,     ## Recognised, still shut.
	DONE,     ## Open. Inert from here on.
}

@export_group("Door")
## The mesh that swings. Defaults to this node's parent, which is how
## BreakerPanel attaches it.
@export var door_path: NodePath = ^".."

## Degrees added to the door's *imported* Y rotation to shut it. Read off
## the Blender file: the panel is authored at -154.3 degrees about Z and
## closed is zero, so this is the swing it travels backwards on startup.
@export var closed_offset_deg: float = 154.3

@export var swing_seconds: float = 0.9

## Shut the door on startup.
@export var start_closed: bool = true

@export_group("Steps")
@export var identify_step: StringName = &"hazard_identified"
@export var open_step: StringName = &"panel_opened"

@export_group("Copy")
## Deliberately absent: the identify beat has no message. It used to carry
## `identify_message`, naming the live source and its voltage the moment the
## board was clicked - i.e. reading out most of hazard pass 1 before the
## trainee had answered it. The teaching text now lives on the hazard entries
## themselves and reaches the trainee in the debrief, with everything else.
@export_multiline var open_message: String = "Panel open. Mark the point of isolation before any work starts."

var _door: Node3D = null
var _stage: Stage = Stage.IDENTIFY
var _open_y: float = 0.0
var _closed_y: float = 0.0
var _is_open: bool = true
## True while the door is mid-swing. Stops a second activation restarting
## the tween half way through.
var _busy: bool = false
## Generous stand-in collider, see _build_hitbox().
var _hitbox: StaticBody3D = null


func _ready_impl() -> void:
	_door = get_node_or_null(door_path) as Node3D
	if _door == null:
		push_error("BreakerPanelInteract: no door at '%s'" % door_path)
		return

	# The imported pose is the open one, so it is the reference. Closed is
	# derived from it rather than assumed to be zero, which keeps this
	# working if the .blend's world rotation changes or the importer adds a
	# correction of its own.
	_open_y = _door.rotation.y
	_closed_y = _open_y + deg_to_rad(closed_offset_deg)

	if start_closed:
		_door.rotation.y = _closed_y
		_is_open = false

	_build_hitbox()

	# Something else may already have graded the hazard - a briefing card, a
	# future observer NPC. Do not make the trainee identify it twice.
	if Assessment.is_resolved(identify_step):
		_stage = Stage.OPEN
	Events.step_completed.connect(_on_step_completed)


func _on_step_completed(step_id: StringName, _at: float) -> void:
	if step_id == identify_step and _stage == Stage.IDENTIFY:
		_set_stage(Stage.OPEN)


func stage() -> Stage:
	return _stage


func is_open() -> bool:
	return _is_open


# =============================================================================
# Prompt
# =============================================================================
func prompt_text() -> String:
	match _stage:
		Stage.IDENTIFY:
			return "Examine %s" % label()
		Stage.OPEN:
			return "Open %s" % label()
		_:
			return ""


## Inert once open: the worker is about to be at this board, and the trainee
## closing the door on him helps nobody.
func can_interact() -> bool:
	return enabled and not _busy and _stage != Stage.DONE and not SimState.is_preamble()


# =============================================================================
# Activation
# =============================================================================
func _on_interact(_from_position: Vector3) -> void:
	match _stage:
		Stage.IDENTIFY:
			_do_identify()
		Stage.OPEN:
			_do_open()


## Ask for the assessment; do not grade it and do not advance. The stage moves
## to OPEN off `step_completed(identify_step)` in `_on_step_completed`, which
## fires when HazardAssessment closes the pass - so the board cannot be opened
## until the trainee has actually made an assessment, however poor.
##
## Safe to hit repeatedly: HazardAssessment ignores a request for a pass that
## is already up, so re-aiming at the door mid-assessment does not wipe the
## ticks.
func _do_identify() -> void:
	Events.hazard_assessment_requested.emit(identify_step)


func _do_open() -> void:
	if _door == null or _is_open:
		_finish_open()
		return

	_busy = true
	unhighlight()

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(_door, "rotation:y", _open_y, swing_seconds)
	await tween.finished

	if not is_inside_tree():
		return

	_busy = false
	_is_open = true
	_finish_open()


func _finish_open() -> void:
	# The panel is done being a target, and a proud box swinging out into the
	# room would sit between the trainee and everything behind it.
	if _hitbox != null:
		_hitbox.collision_layer = 0
	Assessment.complete(open_step)
	Events.center_message_requested.emit(open_message, Tokens.SCENE_TEXT, 3.5)
	_set_stage(Stage.DONE)
	unhighlight()
	panel_opened.emit()


func _set_stage(next: Stage) -> void:
	if next == _stage:
		return
	_stage = next
	stage_changed.emit(next)


## A box that swallows the door and stands proud of both its faces.
##
## The door's own imported collider is flush with the cabinet, and the
## breaker face in front of it is proud of that - so a ray aimed square at
## the closed panel hits the cabinet first, finds no Interactable on it, and
## reports nothing. That is why the prompt only appeared from off to one
## side or with the reticle almost touching the steel.
##
## Padding the volume outward fixes it without touching the room's geometry:
## the hitbox becomes the nearest thing along the ray, so it wins. It is on
## the interactable layer only and masks nothing, so it stays invisible to
## movement and physics.
func _build_hitbox() -> void:
	var box := own_bounds(_door)
	if box.size == Vector3.ZERO:
		return

	var shape := BoxShape3D.new()
	# Symmetric on Z rather than pushed toward the room: which local face is
	# the outward one depends on the .blend, and a box that covers both is
	# right either way.
	shape.size = box.size + Vector3(0.10, 0.10, 0.30)

	var collider := CollisionShape3D.new()
	collider.name = "Shape"
	collider.shape = shape
	collider.position = box.get_center()

	_hitbox = StaticBody3D.new()
	_hitbox.name = "PanelHitbox"
	_hitbox.collision_layer = 2
	_hitbox.collision_mask = 0
	_hitbox.add_child(collider)
	_door.add_child(_hitbox)


## Bounds of a node's *own* mesh, in its own local space - children are left
## out on purpose. The cabinet carries the neighbouring cabinets' front
## panels as children, so a merged AABB would span half the room.
static func own_bounds(node: Node3D) -> AABB:
	var mesh := node as MeshInstance3D
	if mesh == null or mesh.mesh == null:
		return AABB()
	return mesh.mesh.get_aabb()
