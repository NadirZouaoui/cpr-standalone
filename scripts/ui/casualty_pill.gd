extends Node
## "Interact with casualty" - a clickable pill on the body.
##
## Client, 23 Sep 2026: "add a pill to interact with casualty." The way into the
## treatment labels used to be aiming at the body and reading a prompt under the
## dot, which a trainee who has never played a game does not know to try. Once
## he stood up to use the radio, fetch the AED or look around, nothing on screen
## said how to get back down to the casualty.
##
## Same furniture as the extraction pills: a pinned glass pill on the body, and
## a screen-edge arrow to it while it is out of view. A click is handed to the
## casualty's own Interactable, so it does exactly what clicking the body does.
##
## Offered only while the trainee is standing (not at a CPR anchor),
## no treatment label is drawn, and the spine is at a beat where kneeling at the
## casualty is the way on. Never during the AED fetch and placement, the shock,
## the airway roll or the handover: in those beats the casualty is not what the
## trainee should be clicking, and at the shock it would be an invitation to the
## fatal mistake.

const CasualtyPointersScript := preload("res://scripts/ui/casualty_pointers.gd")

const PILL_ID := &"interact_casualty"
const LABEL := "Interact with casualty"
const EDGE_GROUP := &"edge_target"
## Above the hips, like the drag pill: a pill exactly on the hips reads as
## pointing at the floor.
const BODY_LIFT := 0.35
const REFRESH_SECONDS := 0.15

const OFFERED_STATES := [
	CprStation.STATE_PRIMARY_SURVEY,
	CprStation.STATE_BREATHING_CHECK,
	CprStation.STATE_PULSE_CHECK,
	CprStation.STATE_COMPRESSIONS_1,
	CprStation.STATE_EXPOSE_CHEST,
	CprStation.STATE_COMPRESSIONS_2,
	CprStation.STATE_RECOVERY_ROLL,
	CprStation.STATE_INJURY_SURVEY,
]

var _pointers: CanvasLayer = null
var _anchor: Marker3D = null
var _casualty: Casualty = null
var _shown: bool = false
var _wait: float = 0.0


func _ready() -> void:
	_pointers = CasualtyPointersScript.new()
	_pointers.name = "CasualtyPillLayer"
	_pointers.interactive = true
	_pointers.pin_to_anchor = true
	_pointers.activated.connect(_on_activated)
	add_child(_pointers)
	_pointers.owner = null

	_anchor = Marker3D.new()
	_anchor.name = "CasualtyPillAnchor"
	add_child(_anchor)
	_anchor.owner = null
	_anchor.set_meta(&"edge_label", LABEL)


func _process(delta: float) -> void:
	var body := _body()
	if body != null:
		_anchor.global_position = body.hips_position() + Vector3.UP * BODY_LIFT

	_wait -= delta
	if _wait > 0.0:
		return
	_wait = REFRESH_SECONDS

	var want := _wanted(body)
	if want == _shown:
		return
	_shown = want
	if want:
		_pointers.set_callouts([{"id": PILL_ID, "node": _anchor, "label": LABEL}])
		_anchor.add_to_group(EDGE_GROUP)
	else:
		_pointers.clear()
		if _anchor.is_in_group(EDGE_GROUP):
			_anchor.remove_from_group(EDGE_GROUP)


func _wanted(body: Casualty) -> bool:
	if body == null:
		return false
	var phase := int(SimState.phase)
	if phase < int(SimState.Phase.PRIMARY_SURVEY) or phase > int(SimState.Phase.RECOVERY):
		return false
	if Events.is_ui_blocking():
		return false

	# Standing. CprStation.trainee_at_anchor() is the project's one answer to
	# "is the trainee down at the casualty" - the CPR camera rig borrows the
	# player's own Camera3D, so which camera is current says nothing.
	var station := CprStation.get_current()
	if station != null and station.trainee_at_anchor():
		return false

	var menu: Node = get_parent().get_node_or_null(^"CasualtyActions") if get_parent() != null else null
	if menu != null:
		if menu.get("choice_hold") == true:
			return false
		if menu.has_method("has_visible_pointer") and menu.has_visible_pointer():
			return false

	var state := CprStation.STATE_PRIMARY_SURVEY
	if station != null and station.is_phase_entered():
		state = int(station.get("current_state"))
		if station.get("compressions_armed") == true:
			return false
	if not OFFERED_STATES.has(state):
		return false

	var target := _interactable(body)
	return target != null and target.can_interact() and target.prompt_text() != ""


func _on_activated(id: StringName) -> void:
	if id != PILL_ID:
		return
	var target := _interactable(_body())
	if target == null:
		return
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	target.interact(player.global_position if player != null else Vector3.ZERO)


func _interactable(body: Casualty) -> CasualtyInteractable:
	if body == null:
		return null
	for child in body.find_children("*", "", true, false):
		if child is CasualtyInteractable:
			return child
	return null


func _body() -> Casualty:
	if _casualty != null and is_instance_valid(_casualty):
		return _casualty
	_casualty = get_tree().get_first_node_in_group(&"casualty") as Casualty
	return _casualty