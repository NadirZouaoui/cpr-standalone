class_name BreakerPanel
extends Node
## Binds the breaker-panel sequence onto the imported room, points the
## trainee at it, and holds the incident back until it is finished.
##
## Same reason ToolRack exists: the room is an imported .blend, so its node
## tree is rebuilt wholesale on every reimport. Anything wired in the editor
## would be lost and any exported NodePath into it would go stale, so the
## binding is done in code at startup, keyed on Blender object names.
##
## The sequence runs across three objects now. The door owns "examine" and
## "open"; the busbars own the reassessment that opening the board makes
## possible.
## The sign is hung on IsolationSignAnchor's ghost - the translucent box
## sitting exactly where the sign belongs - rather than on the breaker mesh:
## a two-metre cabinet answering to "Hang the Isolation Sign" anywhere along
## its face tells the trainee nothing about where the notice actually goes,
## and the door it was on before swings clear the moment it is opened.
##
## What this gates, and why. The worker used to be electrocuted the moment
## the kit check closed, because both Casualty and ShockCue armed themselves
## off the preamble boundary. That left no room for anything the trainee is
## supposed to do *before* the incident. Now the pre-incident work - name the
## hazard, open the board, sign the point of isolation - is a real sequence
## with real checklist steps, and the worker is not put in the room until it
## is done. Casualty.autostart and ShockCue.armed_externally are the two
## switches that hand that decision here; if this node is disabled or fails
## to bind, nothing starts, so the failure is loud rather than silent.

## Loaded by path rather than by class_name: hazard_panel_3d.gd is a plain
## Node3D script with no class_name, exactly like kit_identify_panel.gd, and
## kit_check.gd reaches for that one the same way.
const HazardPanelScript := preload("res://scripts/ui/hazard_panel_3d.gd")

@export_group("Binding")
## Turn off to leave the panel inert and start the incident on the old
## timing - useful when testing the rescue itself.
@export var enabled: bool = true

## The imported room. NodePath rather than a Node export, because a
## hand-written .tscn needs `node_paths=PackedStringArray(...)` for Node
## references and silently drops them otherwise.
@export var room_path: NodePath = ^"../ControlRoom"

## The swinging panel. Blender "Breaker.002-col"; the importer eats the
## "-col" suffix and sanitises the dot, leaving "Breaker_002".
@export var door_node: String = "Breaker_002"

@export var display_name: String = "Breaker Panel"

@export_group("Handle")
## The ON/OFF lever on the breaker. Blender "Breaker_handle", a child of
## "Breaker" rather than of the room root, so it is looked up recursively.
@export var handle_node: String = "Breaker_handle"
@export var handle_display_name: String = "Breaker Handle"
## Local translation from the imported ON pose to the OFF pose.
@export var handle_off_offset: Vector3 = Vector3(0.0, 0.0, 0.074)
## Degrees added to the imported ON rotation to reach OFF.
@export var handle_off_rotation_deg: Vector3 = Vector3(23.0, 0.0, 0.0)
@export var handle_throw_seconds: float = 0.35

@export_group("Hazards")
## The busbars inside the board - what opening the door exposes, and where the
## reassessment prompt hangs. Deliberately NOT the door: the door goes inert
## the moment it opens and swings 154 degrees clear of the board, so a prompt
## on it would point at a slab of steel that is no longer part of what is
## being looked at.
@export var busbars_node: String = "Breaker busbars"
@export var busbars_display_name: String = "Open Board"

## Where hazard pass 1 hangs, in the *closed* door's local space, measured
## from the centre of the door's own mesh rather than from its origin - the
## origin sits on the hinge edge, so an offset measured from it lands half a
## metre off to one side. Same anchoring as the beacon, and for the same
## reason.
@export var hazard_panel_offset: Vector3 = Vector3(0.0, -0.15, 0.5)

## Where hazard pass 2 hangs, relative to the busbars' mesh centre, in world
## axes.
@export var hazard_reassess_offset: Vector3 = Vector3(0.0, -0.2, 0.0)

@export_group("Sign")
## The hand-placed marker, and the ghost the trainee clicks. Without it
## there is nothing to hang the sign on and the sequence cannot finish.
@export var sign_anchor_path: NodePath = ^"../SignAnchor"
@export var sign_item_id: StringName = &"isolation_sign"
## Correction for the sign mesh's own baked orientation. The anchor decides
## placement and facing; this only fixes a mesh modelled back-to-front.
@export var sign_rotation_deg: Vector3 = Vector3.ZERO

@export_group("Incident")
@export var casualty_path: NodePath = ^"../Casualty"
## The casualty's click capsule. Armed with the rest of the incident.
@export var casualty_rig_path: NodePath = ^"../Casualty/Rig"
@export var shock_cue_path: NodePath = ^"../ShockCue"

## Beat between the sign going up and the worker appearing at the board, so
## the two do not read as one event. Long enough for the success message on
## the sign to land and the ghost to disappear before anything else moves.
@export var incident_delay: float = 2.0

@export_group("Door")
## Degrees added to the door's imported Y rotation to shut it.
@export var closed_offset_deg: float = 154.3
@export var swing_seconds: float = 0.9
@export var start_closed: bool = true

@export_group("Beacon")
## A floating marker over the objective while the sequence is outstanding.
## The breaker is one grey cabinet among several and the trainee has no
## reason to know which one matters yet. It moves to the sign ghost once
## the board is open, because that is where the next action is.
@export var show_beacon: bool = true

## Set the first time the board is opened. See _refresh_beacon().
var _touched: bool = false

## Offset from the *centre of the door's own mesh*, in the door's local
## space, taken at the closed pose. Anchored on the mesh rather than on the
## node origin: the origin sits on the hinge edge, so an offset measured
## from it lands half a metre off to one side.
@export var beacon_offset: Vector3 = Vector3(0.0, 0.65, 0.3)

## Offset from the sign anchor, in world axes, for the second half.
@export var beacon_sign_offset: Vector3 = Vector3(0.0, 0.35, 0.0)

@export var beacon_color: Color = Tokens.ATTENTION
@export var beacon_bob: float = 0.06
@export var beacon_spin_speed: float = 1.1

var _door: Node3D = null
var _anchor: IsolationSignAnchor = null
var _rig: CasualtyRig = null
var _interact: BreakerPanelInteract = null
var _mount: IsolationSignMount = null
var _handle: BreakerHandle = null
var _hazards: HazardAssessment = null
var _hazard_panel: CanvasLayer = null
var _busbars: HazardReassessInteract = null
var _beacon: ObjectiveBeacon = null


func _ready() -> void:
	if not enabled:
		return

	var room := get_node_or_null(room_path)
	if room == null:
		push_error("BreakerPanel: no room at '%s'." % room_path)
		return

	_door = _find(room, door_node)
	if _door == null:
		push_error(
			"BreakerPanel: no door named '%s' in the room - renamed in Blender? "
			% door_node
			+ "The incident will never start."
		)
		return

	_anchor = get_node_or_null(sign_anchor_path) as IsolationSignAnchor
	if _anchor == null:
		push_error(
			"BreakerPanel: no IsolationSignAnchor at '%s'; the sign cannot be "
			% sign_anchor_path
			+ "hung and the incident will never start."
		)
		return

	_rig = get_node_or_null(casualty_rig_path) as CasualtyRig
	if _rig != null:
		# Enforced here, not left to the exported flag - see CasualtyRig.hold().
		_rig.hold()
	if _rig == null:
		push_warning(
			"BreakerPanel: no CasualtyRig at '%s'; its capsule may block the "
			% casualty_rig_path
			+ "panel until the incident starts."
		)

	_build_door_interact()
	_build_handle_interact()
	_build_hazard_assessment(room)
	_build_sign_mount()
	_build_beacon()
	_refresh_beacon()
	Events.phase_changed.connect(_on_phase_changed)
	Events.step_completed.connect(_on_step_completed)
	Events.step_failed.connect(func(id, _reason): _on_step_completed(id, 0.0))


## Exact name first, then a prefix match. The importer appends a numeric
## suffix when two Blender objects sanitise to the same node name, so an
## innocuous rename upstream should degrade to a warning rather than to a
## sequence that never binds.
func _find(room: Node, wanted: String) -> Node3D:
	var exact := room.get_node_or_null(NodePath(wanted)) as Node3D
	if exact != null:
		return exact
	for child in room.get_children():
		if child is Node3D and String(child.name).begins_with(wanted):
			push_warning("BreakerPanel: '%s' not found, using '%s'." % [wanted, child.name])
			return child as Node3D
	return null


func _build_door_interact() -> void:
	_interact = BreakerPanelInteract.new()
	_interact.name = "PanelInteract"
	_interact.id = &"breaker_panel"
	_interact.display_name = display_name
	_interact.closed_offset_deg = closed_offset_deg
	_interact.swing_seconds = swing_seconds
	_interact.start_closed = start_closed
	_door.add_child(_interact)

	# Mark the collider as interactable without taking it out of the world
	# layer, so the panel still behaves like a solid object.
	for body in _bodies(_door):
		body.collision_layer |= 2

	_interact.panel_opened.connect(_on_panel_opened)


## The mount goes on the ghost's wrapper, alongside the ghost's own collider
## - the interaction ray walks up from a body and checks that node's direct
## children, so mount and body have to be siblings.
func _build_sign_mount() -> void:
	var target := _anchor.target()
	if target == null:
		push_error("BreakerPanel: sign anchor built no target.")
		return

	_mount = IsolationSignMount.new()
	_mount.name = "SignMount"
	_mount.id = &"breaker_sign_mount"
	_mount.display_name = "Isolation Point"
	_mount.sign_item_id = sign_item_id
	_mount.sign_rotation_deg = sign_rotation_deg
	_mount.anchor = _anchor
	target.add_child(_mount)

	_mount.sign_hung.connect(_on_sign_hung)


# =============================================================================
# Hazard assessment
# =============================================================================
## The two-pass hazard assessment, bound onto the room the same way everything
## else on this node is. Three pieces:
##
##   - HazardAssessment, the controller. Owns the lists, the `panel_opened`
##     gate on pass 2, and the grading.
##   - HazardPanel3D, the full-screen tick list. Added to this node's own
##     parent rather than under it - see the note at the add_child below.
##   - HazardReassessInteract on the busbars, the way into pass 2.
##
## Pass 1 is reached through the door's existing "Examine" prompt, so there is
## no second interactable for it.
##
## A missing busbar mesh is a warning, not an error: pass 1, the incident and
## the whole rescue still run without it, and only `hazards_reassessed` goes
## uncompletable. Better reported than fatal.
func _build_hazard_assessment(room: Node) -> void:
	_hazards = HazardAssessment.new()
	_hazards.name = "HazardAssessment"
	add_child(_hazards)

	_hazard_panel = HazardPanelScript.new()
	_hazard_panel.name = "HazardPanel"
	# This node's own parent, not get_tree().current_scene: the headless
	# checks instantiate main.tscn under a tool scene, where current_scene is
	# the *tool*, and a panel parented there would outlive every reboot and
	# keep answering the bus. check_hazard_assessment finds it by name from
	# Main, so it has to stay there now that it is a CanvasLayer and could
	# technically live anywhere.
	var host: Node = get_parent()
	if host == null:
		host = get_tree().current_scene
	if host == null:
		host = get_tree().root
	# Deferred, because this runs from BreakerPanel's own `_ready` - i.e. while
	# main.tscn is still adding its children - and a plain `add_child` on a
	# parent that is mid-setup is refused outright ("Parent node is busy
	# setting up children"). The panel silently never existed. Anything that
	# needs it must wait a frame; both callers already do.
	host.add_child.call_deferred(_hazard_panel)

	# Pass 1 hangs off the closed door, on a marker parented to the room -
	# not to the door, which swings 154 degrees and would carry an anchor
	# parented to it round to face a wall.
	if _door != null:
		var box := BreakerPanelInteract.own_bounds(_door)
		var centre: Vector3 = box.get_center() if box.size != Vector3.ZERO else Vector3.ZERO
		var marker := Marker3D.new()
		marker.name = "HazardAnchorPass1"
		var parent := _door.get_parent()
		if parent != null:
			parent.add_child(marker)
			marker.global_position = _door.global_transform * (centre + hazard_panel_offset)
			_hazards.anchors[&"hazard_identified"] = marker

	_build_busbars_interact(room)


func _build_busbars_interact(room: Node) -> void:
	var busbars := _find_deep(room, busbars_node)
	if busbars == null:
		push_warning(
			"BreakerPanel: no busbars named '%s' in the room - renamed in "
			% busbars_node
			+ "Blender? The board can never be reassessed and "
			+ "'hazards_reassessed' will never complete."
		)
		return

	_busbars = HazardReassessInteract.new()
	_busbars.name = "ReassessInteract"
	_busbars.id = &"breaker_busbars"
	_busbars.display_name = busbars_display_name
	busbars.add_child(_busbars)

	# Mark whatever colliders the mesh already carries as interactable, on top
	# of the padded hitbox the interactable builds for itself.
	for body in _bodies(busbars):
		body.collision_layer |= 2

	var marker := Marker3D.new()
	marker.name = "HazardAnchorPass2"
	busbars.add_child(marker)
	var box: AABB = BreakerPanelInteract.own_bounds(busbars)
	var centre: Vector3 = box.get_center() if box.size != Vector3.ZERO else Vector3.ZERO
	marker.global_position = busbars.global_transform * centre + hazard_reassess_offset
	if _hazards != null:
		_hazards.anchors[&"hazards_reassessed"] = marker


# =============================================================================
# Sequence
# =============================================================================
func _on_panel_opened() -> void:
	# Playtest: "remove yellow arrows once trainee interacts with kit/panel."
	# The arrow's job was to bring the trainee to this board; the door swinging
	# is proof it is done. What comes next at the same board - reassess, then
	# sign - is carried by the prompts and the ghost, both of which are on the
	# thing itself rather than floating over it.
	_touched = true
	_refresh_beacon()
	_arm_sign_if_ready()
	# NOT straight to the sign. The mount refuses the sign until the
	# reassessment is done (IsolationSignMount.accepts_sign), so an arrow that
	# jumps to the ghost the instant the door swings is pointing the trainee at
	# something that will turn them away - and it is what made the old
	# skip-the-reassessment trap so easy to walk into. It moves when the
	# reassessment resolves, in _on_step_completed.
	_refresh_beacon_target()


func _on_sign_hung() -> void:
	if _anchor != null:
		_anchor.activate(false)
	_refresh_beacon()

	if incident_delay > 0.0:
		await get_tree().create_timer(incident_delay).timeout
	if not is_inside_tree():
		return

	# Order matters: the rig has to be in the room before it is asked to
	# play anything, or the first frames of the idle happen off screen.
	var cue := get_node_or_null(shock_cue_path) as ShockCue
	if cue != null:
		cue.arm()

	# The click capsule is armed separately from the rig's visibility. It is
	# top-level and sits between the trainee and the breaker, so leaving it
	# live during the pre-incident work made the middle of the panel
	# unclickable - the ray hit an invisible worker instead.
	if _rig != null:
		_rig.arm()

	var casualty := get_node_or_null(casualty_path) as Casualty
	if casualty == null:
		casualty = get_tree().get_first_node_in_group(&"casualty") as Casualty
	if casualty == null:
		push_error("BreakerPanel: no Casualty to start; the incident will never happen.")
		return
	casualty.begin_opening()


# =============================================================================
# Beacon
# =============================================================================
func _build_beacon() -> void:
	if not show_beacon or _door == null:
		return

	# Parented to the room rather than to the door: the door swings 154
	# degrees and a marker that swings with it ends up over a wall.
	var parent := _door.get_parent()
	if parent == null:
		return

	# The cone, the bob and the spin all live on ObjectiveBeacon now, so the
	# kit bench can put up the same arrow rather than a near-copy of it. What
	# stays here is everything specific to this sequence: where the arrow
	# belongs, and the two times it moves while it is up.
	_beacon = ObjectiveBeacon.build(parent, "PanelBeacon", "Breaker board")
	if _beacon == null:
		return
	_beacon.color = beacon_color
	_beacon.bob = beacon_bob
	_beacon.spin_speed = beacon_spin_speed

	# Read the door's closed pose *now* - _ready_impl has already shut it,
	# because the interactable was added as a child above.
	var box := BreakerPanelInteract.own_bounds(_door)
	var origin: Vector3 = box.get_center() if box.size != Vector3.ZERO else Vector3.ZERO
	_beacon.global_position = _door.global_transform * (origin + beacon_offset)


## Once the board is open the objective is the ghost, so the arrow follows
## it rather than hovering over a door nobody needs to touch again.
func _move_beacon_to_sign() -> void:
	if _beacon == null or _anchor == null:
		return
	_beacon.global_position = _anchor.global_position + beacon_sign_offset


## Where the arrow belongs right now. With the board open there are two
## objectives in sequence at the same board - reassess what opening it exposed,
## then sign the point of isolation - and only the second one is at the ghost.
## Pointing at the ghost during the first is pointing at a mount that will
## refuse.
##
## `is_resolved`, not `is_complete`, and for the same reason the mount uses it:
## a reassessment that is off the trainee's plate either way is one the arrow
## should have moved on from.
func _refresh_beacon_target() -> void:
	if _beacon == null:
		return
	if Assessment.is_resolved(&"hazards_reassessed"):
		_move_beacon_to_sign()
		return
	var marker := _hazards.anchors.get(&"hazards_reassessed") as Node3D 		if _hazards != null else null
	if marker != null:
		_beacon.global_position = marker.global_position + beacon_sign_offset


func _on_step_completed(step_id: StringName, _elapsed: float) -> void:
	if step_id == &"hazards_reassessed":
		_arm_sign_if_ready()
		_refresh_beacon_target()
	if PREP_STEPS.has(step_id):
		_refresh_beacon()


## The ghost and the "Hang the Isolation Sign" prompt stay down until the open
## board has been reassessed. Client, 23 Sep: "hide the hang isolation sign
## ghost/prompt until second risk assessment." They used to come up the moment
## the door swung, which put the next job on screen before the one in front of
## it was done. The mount still refuses a sign before the reassessment
## (IsolationSignMount.accepts_sign) as a second lock.
##
## `is_resolved`, not `is_complete`: a failed pass must not keep the sign, and
## with it the whole rescue, shut for good.
func _arm_sign_if_ready() -> void:
	if not _touched or _mount == null or _mount.is_hung():
		return
	if Assessment.steps.has(&"hazards_reassessed") and not Assessment.is_resolved(&"hazards_reassessed"):
		return
	_mount.arm()
	if _anchor != null:
		_anchor.activate(true)


func _on_phase_changed(_previous: int, _current: int) -> void:
	_refresh_beacon()


## Gloves and torch come first. Client, 23 Sep: "the breaker board arrow should
## show after donning PPE/torch." Until both are resolved the arrow stays down,
## so the first thing pointed at in the room is not the board. Resolved, not
## completed: a skipped torch is failed once the incident starts, but that is
## after the board, so a trainee who never takes it is not shown the board by
## the arrow - the checklist and [H] still carry them.
const PREP_STEPS: Array[StringName] = [&"ppe_donned", &"torch_taken"]


func _prep_done() -> bool:
	for id in PREP_STEPS:
		if Assessment.steps.has(id) and not Assessment.is_resolved(id):
			return false
	return true


## Up only until the board has been opened: while the sequence is outstanding,
## the trainee is actually in the room - not over the kit check - and the door
## has not been touched yet.
func _refresh_beacon() -> void:
	if _beacon == null:
		return
	var wanted := (
		not SimState.is_preamble()
		and _prep_done()
		and not _touched
		and _mount != null
		and not _mount.is_hung()
	)
	_beacon.show_beacon(wanted)


# =============================================================================
# Handle
# =============================================================================
## The point of isolation. Bound here rather than in the .tscn for the same
## reason as everything else on this node: the room is rebuilt on reimport.
##
## Missing handle is a warning, not an error. The pre-incident sequence and
## the rescue both still run without it; only the isolation step goes
## uncompletable, and that is better reported than fatal.
func _build_handle_interact() -> void:
	var room := get_node_or_null(room_path)
	if room == null:
		return

	var handle := _find_deep(room, handle_node)
	if handle == null:
		push_warning(
			"BreakerPanel: no handle named '%s' in the room - renamed in "
			% handle_node
			+ "Blender? The supply can never be isolated."
		)
		return

	_handle = BreakerHandle.new()
	_handle.name = "HandleInteract"
	_handle.id = &"breaker_handle"
	_handle.display_name = handle_display_name
	_handle.off_offset = handle_off_offset
	_handle.off_rotation_deg = handle_off_rotation_deg
	_handle.throw_seconds = handle_throw_seconds
	handle.add_child(_handle)

	for body in _bodies(handle):
		body.collision_layer |= 2


# =============================================================================
# Helpers
# =============================================================================
## Depth-first name lookup. `_find` only walks the room's direct children,
## which is enough for the cabinets but not for parts hanging off them.
func _find_deep(root: Node, wanted: String) -> Node3D:
	for child in root.get_children():
		if child is Node3D and String(child.name).begins_with(wanted):
			return child as Node3D
	for child in root.get_children():
		var hit := _find_deep(child, wanted)
		if hit != null:
			return hit
	return null


func _bodies(root: Node) -> Array[CollisionObject3D]:
	var out: Array[CollisionObject3D] = []
	if root is CollisionObject3D:
		out.append(root)
	for child in root.get_children():
		out.append_array(_bodies(child))
	return out
