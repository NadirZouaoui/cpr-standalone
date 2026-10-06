class_name ExtractionPointers
extends Node
## The two signposts of the extraction beat: the casualty, and the breaker.
##
## Once contact has been broken there are two jobs outstanding and no order
## forced on the trainee. Before this existed the screen only ever named one of
## them - Assessment.next_step() returns the first available step in list order,
## so the checklist said "Drag the casualty to the safe area" and the isolation
## stayed invisible until the drag was done. The trainee could not choose an
## order they could not see.
##
## So both are drawn at once, each on the thing it is about: one pill riding the
## casualty's hips, one on the breaker handle across the room.
##
## THEY ARE BUTTONS NOW. They were signposts - draw the label, make the trainee
## walk to the object and use it - and the argument for that was that clicking
## "isolate" from the far side of the switchroom teaches the opposite of what
## the beat is about. Nadir, in playtest: "just make the pills clickable
## drag/isolate." So they are; the choice being made is still which one you take
## first, and the beat still shows both.
##
## What is left of the old argument is the pinning (see
## CasualtyPointers.pin_to_anchor): a pill is drawn ON its object and is culled
## the moment that object leaves the frame, so taking either one means being
## turned towards the thing it names. Turning to the board to throw it is not
## walking to the board, and that is a real loss - flagged rather than argued.
##
## Neither pill implements anything. Both call interact() on the object's own
## Interactable, so the refusals, the ordering judgement and the transcript
## entries are the ones that were always there (BreakerHandle._refuse, and
## Casualty.drag_to_safety through CasualtyInteractable).
##
## Only one order is correct. Dragging first is the taught one, and
## BreakerHandle already owns that judgement: throwing the handle early is
## allowed, said out loud, and written to the transcript as a deviation at no
## cost to the score (see BreakerHandle._finish). Nothing here re-grades it;
## this only makes the choice visible.
##
## Both have to be done to leave EXTRACTION. That gate lives in
## Casualty._try_leave_extraction(), not here - a UI layer must not be load
## bearing for the phase machine.

const CasualtyPointersScript := preload("res://scripts/ui/casualty_pointers.gd")

## The step each pill retires on.
const DRAG_STEP := &"drag_to_safe_area"
const ISOLATE_STEP := &"supply_isolated"

## edge_indicators.gd draws a screen-edge arrow to anything in this group.
const EDGE_GROUP := &"edge_target"

## The BreakerHandle interactable, as BreakerPanel._build_handle_interact()
## names it. Resolved by name at runtime for the same reason everything else
## here is: the room is an imported .blend and its subtree is rebuilt on every
## reimport (ARCHITECTURE.md §1).
const HANDLE_NODE_NAME := "HandleInteract"

## How far above the hips the body pill sits, in metres. The hips are the
## casualty's own anchor (Casualty.hips_position()) and a pill drawn exactly
## there reads as pointing at the floor.
const BODY_LIFT := 0.35

var _pointers: CanvasLayer = null
## Re-posed every frame onto the casualty's hips, so the pill rides the body
## through the drag rather than staying where he fell.
var _body_anchor: Marker3D = null
var _casualty: Casualty = null
var _handle: Node3D = null


func _ready() -> void:
	_pointers = CasualtyPointersScript.new()
	_pointers.name = "ExtractionPointerLayer"
	_pointers.interactive = true
	_pointers.activated.connect(_on_pill_activated)
	# Labels on the two objects, not callouts beside a body. See
	# CasualtyPointers.pin_to_anchor - the breaker is across the room and the
	# casualty is on the floor, and a pill dragged into frame off either of
	# them stops saying where the job is.
	_pointers.pin_to_anchor = true
	add_child(_pointers)
	_pointers.owner = null

	_body_anchor = Marker3D.new()
	_body_anchor.name = "ExtractionBodyAnchor"
	add_child(_body_anchor)
	_body_anchor.owner = null

	Events.phase_changed.connect(_on_phase_changed)
	Events.step_completed.connect(_on_step_completed)
	set_process(false)
	_refresh()


func _on_phase_changed(_previous: int, _current: int) -> void:
	_refresh()


func _on_step_completed(_step_id: StringName, _at: float) -> void:
	_refresh()


## The hips move every frame while the drag tween runs, so the anchor is
## re-posed in _process rather than on the signals above. Only runs while the
## pills are up.
func _process(_delta: float) -> void:
	var body := _body()
	if body == null:
		return
	_body_anchor.global_position = body.hips_position() + Vector3.UP * BODY_LIFT


# =============================================================================
# The set
# =============================================================================
## Live only during EXTRACTION, and only for the jobs still outstanding.
##
## `is_resolved`, not `is_complete`: a step closed as a failure is done with,
## and a signpost still pointing at it would be telling the trainee to do
## something they can no longer do.
func _refresh() -> void:
	if _pointers == null:
		return
	if int(SimState.phase) != int(SimState.Phase.EXTRACTION):
		_stop()
		return

	var body := _body()
	var handle := _handle_node()
	var live: Array = []

	if body != null and not Assessment.is_resolved(DRAG_STEP):
		_body_anchor.global_position = body.hips_position() + Vector3.UP * BODY_LIFT
		live.append({
			"id": DRAG_STEP,
			"node": _body_anchor,
			"label": _title(DRAG_STEP, "Drag the casualty to the safe area"),
		})

	if handle != null and not Assessment.is_resolved(ISOLATE_STEP):
		live.append({
			"id": ISOLATE_STEP,
			"node": handle,
			"label": _title(ISOLATE_STEP, "Isolate the circuit at the breaker"),
		})

	_mark_edge(_body_anchor, body != null and not Assessment.is_resolved(DRAG_STEP), DRAG_STEP)
	_mark_edge(handle, handle != null and not Assessment.is_resolved(ISOLATE_STEP), ISOLATE_STEP)

	if live.is_empty():
		_stop()
		return

	_pointers.set_callouts(live)
	set_process(true)


## A pill was clicked: hand the click to the object the pill is sitting on.
##
## Through Interactable.interact() rather than the behaviour underneath it, so a
## pill press and a crosshair press on the object itself are the same event -
## including the refusals. Throwing the handle before the drag is allowed, said
## out loud and written to the transcript (BreakerHandle._refuse / _throw), and
## routing round interact() would have quietly dropped all of that.
func _on_pill_activated(id: StringName) -> void:
	var target: Node = null
	match id:
		DRAG_STEP:
			target = _casualty_interactable()
		ISOLATE_STEP:
			target = _handle_node()
	if target == null or not target.has_method("interact"):
		return
	target.call("interact", _player_position())


## The click target on the body, which is a descendant of the Casualty rather
## than the Casualty itself. Found by class instead of by name: main.tscn is
## frozen and the node has been renamed once already.
func _casualty_interactable() -> Node:
	var body := _body()
	if body == null:
		return null
	for child in body.find_children("*", "", true, false):
		if child is CasualtyInteractable:
			return child
	return null


## Where the click is considered to come from. Interactables that measure a
## distance measure it from here, so a pill press is judged at the place the
## trainee is actually standing and not at the pill.
func _player_position() -> Vector3:
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	return player.global_position if player != null else Vector3.ZERO


func _stop() -> void:
	_pointers.clear()
	set_process(false)
	_mark_edge(_body_anchor, false, DRAG_STEP)
	_mark_edge(_handle, false, ISOLATE_STEP)


## A pinned pill is culled with its object, so off-screen it says nothing.
## Client, 23 Sep: the trainee has just dragged the casualty and is facing him,
## with "Isolate the circuit at the breaker" behind them. While a pill is live
## its anchor sits in the edge group and edge_indicators.gd points at it from
## the side of the screen, with the pill's own words.
func _mark_edge(node: Node, on: bool, step_id: StringName) -> void:
	if node == null or not is_instance_valid(node):
		return
	if on:
		node.add_to_group(EDGE_GROUP)
		node.set_meta(&"edge_label", _title(step_id, ""))
	elif node.is_in_group(EDGE_GROUP):
		node.remove_from_group(EDGE_GROUP)


## The procedure resource is the one place these are named, so the pill and the
## checklist row cannot drift apart. The fallback is only for a run with a
## step missing from the resource, which _validate_prerequisites would already
## have shouted about.
func _title(step_id: StringName, fallback: String) -> String:
	if Assessment.steps.has(step_id):
		return String(Assessment.steps[step_id].title)
	return fallback


func _body() -> Casualty:
	if _casualty != null and is_instance_valid(_casualty):
		return _casualty
	_casualty = get_tree().get_first_node_in_group(&"casualty") as Casualty
	return _casualty


func _handle_node() -> Node3D:
	if _handle != null and is_instance_valid(_handle):
		return _handle
	var scene := get_tree().current_scene
	if scene == null:
		return null
	_handle = CprGhost.find_node(scene, HANDLE_NODE_NAME) as Node3D
	return _handle
