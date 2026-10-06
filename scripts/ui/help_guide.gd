extends CanvasLayer
## [H] Help - how to do the thing in front of you, and a yellow arrow to where.
##
## Client feedback, 23 Sep 2026: a non-technical tester dragged the casualty
## clear and then had no idea what came next. The one job left, isolating at
## the breaker, had its label on the handle behind him.
##
##   1. A standing "[H] Help" chip, top right, for the whole run.
##   2. [H] opens a card - what the screen is currently asking for and how to
##      work the controls to do it - and an arrow at the object: on it when it
##      is on screen, on the screen edge pointing towards it when it is not.
##   3. If nothing has moved on for NUDGE seconds the chip lights up and the
##      feedback pill says so; after AUTO seconds the card opens by itself.
##      Pure navigation beats use the shorter "fast" timings.
##
## HOW, NEVER WHAT. Client, same day: "do not give the answer to the exercise -
## for example 'don correct PPE', they should know what the PPE is; we only
## tell them how to interact." So the card never names an item to pick up, a
## tool to use, a hazard, a place, or the order of two jobs. It only ever names
## a step the HUD is already naming, and for a step the HUD keeps quiet
## (suppress_prompt - the gotchas) it says nothing about the step at all, only
## how the labels and objects in front of the trainee are used.
##
## Asking for help is written to the transcript (category "help"), once per
## objective, and never scored. Owns no state the run depends on.

const TutorialScript := preload("res://scripts/ui/controls_tutorial.gd")
const EdgeScript := preload("res://scripts/ui/edge_indicators.gd")

## Above the HUD (5) and the body pointers (6), below the centre card (8) and
## every blocking screen.
const LAYER := 7

## Idle timings, in seconds without progress. "Progress" is any fact on the bus
## that the run moved on. Clicking at things that refuse does not count: that
## is what being stuck looks like.
const NUDGE_SECONDS := 30.0
const AUTO_SECONDS := 60.0
const NUDGE_SECONDS_FAST := 12.0
const AUTO_SECONDS_FAST := 25.0

## How long the card and the arrow stay up once opened. [H] closes both early.
const CARD_SECONDS := 18.0
const ARROW_SECONDS := 45.0

## Narrow and short on purpose: the controls are the tutorial's job, and a
## tall card covered the objective pill, the held-item chip and the edge arrow.
const CARD_WIDTH := 330.0
const TOP_MARGIN := 24.0
const RIGHT_MARGIN := 24.0

const NUDGE_TEXT := "Not sure what to do next? Press H for help."

const PICKUP := "To take something from the bench, aim the dot at it and left-click. Press G to put a tool back down."
const CASUALTY_FIRST := "If no labels are showing on the casualty, left-click 'Interact with casualty' on him. "
const COMPRESS := "During compressions, press the left mouse button to push down and release it to let the chest come back up, in time with the beat you hear."
const LABELS_HOW := "Labels on the casualty show what you can do: aim the dot at one and left-click it. "
const HOLD_HOW := "When a check is running, keep the dot where the text under it says and HOLD the left mouse button until it finishes. Let go too early and it starts again."
const PERFORM := "Perform CPR"

## Every casualty step from the primary survey on, one card. Client, 23 Sep:
## "don't mention the micro-steps, only guide the student to the interaction,
## and don't tell them what to do next in the correct order. Lump it all under
## 'treat casualty'." The labels on the body are the options; the card says
## how labels, objects and C work, and nothing about which comes first.
const TREAT := {
	"title": "Treat the casualty",
	"how": LABELS_HOW + CASUALTY_FIRST + "To use anything else, walk to it, aim the dot at it and left-click. C stands you up or kneels you down.",
	"target": "casualty", "where": "The casualty",
}

## Per procedure step, for the steps the HUD names. `target` is resolved every
## frame (see _target_point):
##   "casualty"      the casualty's hips
##   "kit"           the middle of the bench
##   "id:<id>"       the Interactable with that id
##   "node:<name>"   a node in the room, by name
## `held_item` / `target_held` / `where_held` / `how_held`: once that item is in
## the hand, point at the second target and say the second half instead.
## `near_hide`: metres; the arrow stands down once the trainee is that close.
## Casualty targets default to 1.8. `fast` uses the short idle timings. `wait`
## means there is nothing to do, so the idle clock does not run.
const STEP_HELP := {
	&"kit_identified": {
		"how": "Walk to the bench. To name an item as rescue kit, aim the dot at it, left-click, and pick its name from the list. Click it again to take it back. Press Enter when you are done to check your list.",
		"target": "kit", "where": "The bench", "near_hide": 2.5,
	},
	&"ppe_donned": {"how": PICKUP, "target": "kit", "where": "The bench", "near_hide": 2.5},
	&"torch_taken": {"how": PICKUP, "target": "kit", "where": "The bench", "near_hide": 2.5},
	&"hazard_identified": {
		"how": "Aim the dot at the breaker board and left-click. A list opens: click the lines to tick them, then confirm.",
		"target": "id:breaker_panel", "where": "Breaker board",
	},
	&"panel_opened": {
		"how": "Aim the dot at the breaker board door and left-click to open it.",
		"target": "id:breaker_panel", "where": "Breaker board",
	},
	&"hazards_reassessed": {
		"how": "Aim the dot inside the open board and left-click. A list opens: click the lines to tick them, then confirm.",
		"target": "id:breaker_busbars", "where": "Inside the board",
	},
	&"isolation_point_signed": {
		"how": PICKUP + " Then aim the dot at the place on the board where it goes and left-click.",
		"target": "kit", "where": "The bench", "near_hide": 2.5,
		"held_item": &"isolation_sign", "target_held": "id:breaker_sign_mount", "where_held": "The board",
		"how_held": "Aim the dot at the place on the board where it goes and left-click.",
	},
	&"crook_retrieved": {
		"title": "Break contact with the live hazard",
		"how": "Hurry. " + PICKUP + " To act on the worker, aim the dot at him and left-click.",
		"target": "casualty", "where": "The worker", "fast": true,
	},
	&"contact_broken": {
		"how": "Hurry. " + PICKUP + " To act on the worker, aim the dot at him and left-click.",
		"target": "casualty", "where": "The worker", "fast": true,
	},
}
## Per CPR spine state, asked BEFORE the checklist: `cpr_performed` and
## `aed_used` are graded at the end of the phase, so next_step() names the
## compression set for every beat after the pulse check. Each line here is the
## game's own instruction for that beat (CprStation.STATE_MESSAGES and the
## breathing check's prompts) plus the controls to carry it out - nothing more.
## COMPRESSIONS_2 is worded neutrally: its post-shock pills are the run's second
## decision. SHOCK does not say to stand up: C is described, the choice is not.
const CPR_STATE_HELP := {
	CprStation.STATE_BREATHING_CHECK: {"title": PERFORM, "how": HOLD_HOW},
	CprStation.STATE_AIRWAY_INSPECT: {
		"title": PERFORM,
		"how": "Watch for a moment. If a label appears, aim the dot at it and left-click.",
	},
	CprStation.STATE_PULSE_CHECK: {"title": PERFORM, "how": HOLD_HOW},
	CprStation.STATE_COMPRESSIONS_1: {"title": PERFORM, "how": LABELS_HOW + COMPRESS},
	CprStation.STATE_EXPOSE_CHEST: {"title": PERFORM, "how": LABELS_HOW},
	# The bench, never the AED itself (client, 23 Sep).
	CprStation.STATE_AED_FETCH: {
		"title": PERFORM,
		"how": "If you are kneeling, press C to stand up. Walk to the bench, aim the dot at what you need and left-click to pick it up.",
		"target": "kit", "where": "The bench", "fast": true,
	},
	CprStation.STATE_AED_DEPLOY: {
		"title": PERFORM,
		"how": "Walk back to the casualty. Aim the dot at the see-through outline beside him and left-click to set down what you are carrying.",
		"target": "casualty", "where": "The casualty", "fast": true,
	},
	CprStation.STATE_PAD_PLACEMENT: {
		"title": PERFORM,
		"how": "Aim the dot at a place on his bare chest and left-click to put a pad there.",
	},
	CprStation.STATE_SHOCK: {
		"title": PERFORM,
		"how": "Follow what the AED says. Its button is used like everything else: aim the dot at it and left-click. C stands you up or kneels you down.",
	},
	CprStation.STATE_COMPRESSIONS_2: {"title": PERFORM, "how": LABELS_HOW + COMPRESS},
	CprStation.STATE_RECOVERY_ROLL: TREAT,
	CprStation.STATE_INJURY_SURVEY: TREAT,
	CprStation.STATE_HANDOVER: {
		"title": "Hand over to the crew",
		"how": "The ambulance is on its way. There is nothing more to do - wait for the crew to take over.",
		"wait": true,
	},
}
## The handover when nobody called 000: CprStation stalls the ambulance and
## says so itself ("Nobody called 000 ... call it now"), so there is something
## to do and the card must not say the crew is on the way. How, not what: the
## game's own line already says what.
const AWAIT_CALL := {
	"title": "Treat the casualty",
	"how": "If you are kneeling, press C to stand up. Walk to the bench, aim the dot at what you need and left-click.",
	"target": "kit", "where": "The bench",
}

const WAIT_WATCH := {
	"title": "Keep watching",
	"how": "Nothing needs doing yet. Keep an eye on the worker.",
	"wait": true,
}

const CHOICE := {
	"title": "Answer the question",
	"how": "Aim the dot at your answer on the card in front of you and left-click it.",
}

## The extraction's two jobs are a silent choice of order, and both carry
## suppress_prompt. So the card names neither and orders nothing: it says how
## the labels work and that an arrow at the edge shows where one is.
const EXTRACTION_BOTH := {
	"title": "Two things to do",
	"how": "Labels show what needs doing now. Choose which to do first, aim the dot at its label and left-click. If a label is out of view, a yellow arrow at the edge of the screen shows which way to turn.",
	"fast": true,
}
const EXTRACTION_ONE := {
	"title": "One thing left",
	"how": "One label is left. If it is out of view, turn the way the yellow arrow at the edge of the screen points, then aim the dot at the label and left-click.",
	"fast": true,
}


const EXTRACTION_STEPS: Array[StringName] = [&"drag_to_safe_area", &"supply_isolated"]

var _root: Control
var _chip: PanelContainer
var _chip_label: Label
var _card: PanelContainer
var _title: Label
var _how: Label
var _where: Label
var _arrow: Control

var _current: Dictionary = {}
var _recheck: float = 0.0
var _card_left: float = 0.0
var _card_key: String = ""
var _arrow_left: float = 0.0

var _idle: float = 0.0
var _nudged: bool = false
var _auto_done: bool = false
var _chip_tween: Tween
var _logged: Dictionary = {}
var _headless: bool = false
var _docked_left: bool = false


func _ready() -> void:
	layer = LAYER
	_headless = DisplayServer.get_name() == "headless"
	_build()

	# [signal, argument count] - unbind() drops the payload; only the fact that
	# something happened matters here.
	var progress := [
		[Events.step_completed, 2], [Events.step_failed, 2],
		[Events.phase_changed, 2], [Events.cpr_state_changed, 2],
		[Events.compression_delivered, 3], [Events.kit_answer_recorded, 1],
		[Events.kit_stage_changed, 1], [Events.hazard_answer_recorded, 3],
		[Events.review_answered, 2], [Events.aed_picked_up, 0],
		[Events.aed_placed, 0], [Events.aed_pad_placed, 3],
		[Events.breathing_checked, 1], [Events.casualty_actions_requested, 1],
	]
	for entry in progress:
		var sig: Signal = entry[0]
		var argc: int = entry[1]
		sig.connect(_on_progress if argc == 0 else _on_progress.unbind(argc))

	_connect_hand.call_deferred()


func _connect_hand() -> void:
	var slot := get_tree().get_first_node_in_group(HandSlot.GROUP) as HandSlot
	if slot != null:
		slot.held_changed.connect(func(_id): _on_progress())

# =============================================================================
# Frame
# =============================================================================
func _process(delta: float) -> void:
	var blocked := Events.is_ui_blocking()
	_root.visible = not blocked
	if blocked:
		return

	_recheck -= delta
	if _recheck <= 0.0:
		_recheck = 0.5
		_current = _objective()

	var live := not _current.is_empty()
	# The tutorial hides the rest of the UI; the chip comes back only on the
	# card that teaches it.
	var tutorial_hides := TutorialScript.running and TutorialScript.current_try != &"help"
	_chip.visible = _card.visible or (live and not tutorial_hides)
	if _card.visible:
		_dock_card()

	# The card follows the trainee: if the objective moves on while it is up,
	# it says the new one rather than the one they asked about.
	if _card.visible:
		_card_left -= delta
		if _card_left <= 0.0:
			_card.visible = false
		elif String(_current.get("key", "")) != _card_key:
			_fill_card(_current)

	if _arrow_left > 0.0:
		_arrow_left -= delta
		var spec: String = _current.get("target", "")
		var point: Variant = _target_point(spec) if _arrow_left > 0.0 else null
		var near: float = _current.get("near_hide", 1.8 if spec == "casualty" else 0.0)
		if point is Vector3 and near > 0.0 and _player_within(point, near):
			point = null
		_arrow.set("target", point)
		_arrow.set("where", String(_current.get("where", "")))
	else:
		_arrow.set("target", null)
	# Only promise an arrow when there is somewhere to point.
	if _card.visible:
		_where.visible = _arrow.get("target") != null

	if _headless or TutorialScript.running or not live or _current.get("wait", false) or _card.visible:
		return
	_idle += delta
	var fast: bool = _current.get("fast", false)
	if not _nudged and _idle >= (NUDGE_SECONDS_FAST if fast else NUDGE_SECONDS):
		_nudged = true
		_set_nudge(true)
		Events.center_message_requested.emit(NUDGE_TEXT, Tokens.ATTENTION, 4.5)
	if not _auto_done and _idle >= (AUTO_SECONDS_FAST if fast else AUTO_SECONDS):
		_auto_done = true
		_open(true)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != KEY_H:
		return
	if Events.is_ui_blocking():
		return
	get_viewport().set_input_as_handled()
	if _card.visible:
		_close()
	else:
		_open(false)


func _on_progress() -> void:
	_idle = 0.0
	_nudged = false
	_auto_done = false
	_recheck = 0.0
	_set_nudge(false)


# =============================================================================
# Open / close
# =============================================================================
func _open(automatic: bool) -> void:
	_current = _objective()
	_fill_card(_current)
	_card.visible = true
	_card_left = CARD_SECONDS
	_arrow_left = ARROW_SECONDS
	_set_nudge(false)

	# The tutorial's own "try it now" is not the trainee asking for help.
	if _current.is_empty() or TutorialScript.running:
		return
	var title := String(_current.get("title", ""))
	if not _logged.has(title):
		_logged[title] = true
		Events.log_action(&"help", "Help: %s" % title, &"info",
			"Opened automatically after a pause." if automatic else "Asked for help.")


func _close() -> void:
	_card.visible = false
	_card_left = 0.0
	_arrow_left = 0.0
	_arrow.set("target", null)


func _fill_card(obj: Dictionary) -> void:
	_card_key = String(obj.get("key", ""))
	if obj.is_empty():
		_title.text = "Nothing to do right now"
		_how.text = "Keep watching. The next step will show on screen."
		_where.visible = false
		return
	_title.text = String(obj.get("title", ""))
	_how.text = String(obj.get("how", ""))
	_where.visible = String(obj.get("target", "")) != ""
	_where.text = "Follow the yellow arrow."


## Right-hand side by default, under the chip. While pills are drawn - on the
## body, or on the extraction targets - it moves to the left under the
## checklist: pills are laid out to the right of what they point at, and a card
## that says "click the label" must not be what covers it.
func _dock_card() -> void:
	var left := _pills_drawn()
	if left:
		_card.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_card.grow_horizontal = Control.GROW_DIRECTION_END
		_card.offset_left = RIGHT_MARGIN
		_card.offset_right = RIGHT_MARGIN
		_card.offset_top = _checklist_bottom() + 12.0
		_card.offset_bottom = _card.offset_top
	elif _docked_left:
		_card.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_card.offset_right = -RIGHT_MARGIN
		_card.offset_left = -RIGHT_MARGIN
		_card.offset_top = TOP_MARGIN + 48.0
		_card.offset_bottom = TOP_MARGIN + 48.0
	_docked_left = left


func _pills_drawn() -> bool:
	var root: Node = get_parent()
	if root == null:
		return false
	for path in [^"CasualtyActions", ^"CasualtyPill", ^"ExtractionPointers", ^"ControlsTutorial"]:
		var owner_node: Node = root.get_node_or_null(path)
		if owner_node == null:
			continue
		if owner_node.has_method("has_visible_pointer") and owner_node.has_visible_pointer():
			return true
		var layer_obj: Object = owner_node.get("_pointers")
		if layer_obj != null and layer_obj.has_method("drawn_count") and int(layer_obj.call("drawn_count")) > 0:
			return true
	return false


## The checklist is faded out during the tutorial; faded counts as absent.
func _checklist_bottom() -> float:
	var hud: Node = get_parent().get_node_or_null(^"Hud") if get_parent() != null else null
	var panel: Object = hud.get("_checklist_panel") if hud != null else null
	if panel is Control and (panel as Control).is_visible_in_tree() and (panel as Control).modulate.a > 0.01:
		return (panel as Control).get_global_rect().end.y
	return TOP_MARGIN


func _set_nudge(on: bool) -> void:
	if _chip_tween != null and _chip_tween.is_valid():
		_chip_tween.kill()
	_chip.modulate = Color.WHITE
	var sb := Tokens.glass_chip()
	if on:
		sb.bg_color = Tokens.ATTENTION
		_chip_label.text = "[H]  Need help?"
		_chip_tween = create_tween().set_loops()
		_chip_tween.tween_property(_chip, "modulate:a", 0.45, 0.6)
		_chip_tween.tween_property(_chip, "modulate:a", 1.0, 0.6)
	else:
		_chip_label.text = "[H]  Help"
	_chip.add_theme_stylebox_override("panel", sb)

# =============================================================================
# What is the trainee on
# =============================================================================
func _objective() -> Dictionary:
	if SimState.phase == SimState.Phase.DEBRIEF:
		return {}
	if SimState.is_preamble():
		return _from_step(&"kit_identified")

	# The choice card owns the screen while it is up; help says how to answer,
	# never what.
	var menu: Node = get_parent().get_node_or_null(^"CasualtyActions") if get_parent() != null else null
	if menu != null and menu.get("choice_hold") == true:
		return _keyed(CHOICE, "choice")

	var station := CprStation.get_current()
	if station != null and station.is_phase_entered():
		var state := int(station.get("current_state"))
		if state == CprStation.STATE_HANDOVER and station.get("_awaiting_help_call") == true:
			return _keyed(AWAIT_CALL, "cpr:handover:call")
		if CPR_STATE_HELP.has(state):
			return _keyed(CPR_STATE_HELP[state], "cpr:%d" % state)

	if int(SimState.phase) == int(SimState.Phase.EXTRACTION):
		var left := 0
		for id in EXTRACTION_STEPS:
			if Assessment.steps.has(id) and not Assessment.is_resolved(id):
				left += 1
		if left >= 2:
			return _keyed(EXTRACTION_BOTH, "extraction:2")
		if left == 1:
			return _keyed(EXTRACTION_ONE, "extraction:1")

	var step := Assessment.next_step()
	if step == &"" or not Assessment.steps.has(step):
		return {}
	var owning: ProcedureStep = Assessment.steps[step]
	if owning.min_phase >= 0 and int(SimState.phase) < owning.min_phase:
		return _keyed(WAIT_WATCH, "wait")
	# From the primary survey on it is all one card, whatever the step.
	if int(SimState.phase) >= int(SimState.Phase.PRIMARY_SURVEY):
		# While the call for help is outstanding the arrow goes to the bench,
		# never to the AED (client, 23 Sep).
		if step == &"send_for_help" or step == &"call_for_aed":
			var calling := TREAT.duplicate()
			calling["target"] = "kit"
			calling["where"] = "The bench"
			calling.erase("near_hide")
			return _keyed(calling, "treat:bench")
		return _keyed(TREAT, "treat")
	if owning.suppress_prompt:
		return _keyed(WAIT_WATCH, "wait")
	return _from_step(step)


func _keyed(entry: Dictionary, key: String) -> Dictionary:
	var out := entry.duplicate()
	out["key"] = key
	return out


func _from_step(id: StringName) -> Dictionary:
	var out: Dictionary = (STEP_HELP.get(id, {}) as Dictionary).duplicate()
	out["key"] = String(id)
	if String(out.get("title", "")) == "":
		out["title"] = String(Assessment.steps[id].title) if Assessment.steps.has(id) \
			else String(id).capitalize()
	if String(out.get("how", "")) == "":
		out["how"] = "Aim the dot at what you want to use and left-click. The text under the dot says what the click will do."
	if out.has("held_item") and _held_item() == out["held_item"]:
		out["target"] = out.get("target_held", "")
		out["where"] = out.get("where_held", "")
		if out.has("how_held"):
			out["how"] = out["how_held"]
		# A new key, so a card that is up re-reads itself the moment the item
		# is picked up.
		out["key"] = String(id) + ":held"
	return out


func _player_within(point: Vector3, metres: float) -> bool:
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	if player == null:
		return false
	var d := player.global_position - point
	return Vector2(d.x, d.z).length() < metres


func _held_item() -> StringName:
	var slot := get_tree().get_first_node_in_group(HandSlot.GROUP) as HandSlot
	return slot.held_item_id if slot != null else &""


# =============================================================================
# Where is it
# =============================================================================
## A world point for a target spec, or null when it has none or the thing is
## gone. Resolved by id or by name at runtime rather than cached, because the
## room is an imported .blend and its subtree is rebuilt on every reimport.
func _target_point(spec: String) -> Variant:
	if spec == "":
		return null
	if spec == "casualty":
		var body := get_tree().get_first_node_in_group(&"casualty") as Casualty
		return body.hips_position() + Vector3.UP * 0.3 if body != null else null
	if spec == "kit":
		var sum := Vector3.ZERO
		var n := 0
		for node in get_tree().get_nodes_in_group(&"kit_inspect"):
			var n3 := node as Node3D
			if n3 != null and n3.is_visible_in_tree():
				sum += _world_point(n3)
				n += 1
		return sum / float(n) if n > 0 else null
	if spec.begins_with("id:"):
		var want := StringName(spec.substr(3))
		for node in get_tree().get_nodes_in_group(Interactable.GROUP):
			var n3 := node as Node3D
			if n3 != null and n3.get("id") == want and n3.is_visible_in_tree():
				return _world_point(n3)
		return null
	if spec.begins_with("node:"):
		var root: Node = get_parent() if get_parent() != null else get_tree().current_scene
		var found := CprGhost.find_node(root, spec.substr(5)) as Node3D
		return _world_point(found) if found != null and found.is_visible_in_tree() else null
	return null


## The middle of what is drawn, not the node origin.
func _world_point(node: Node3D) -> Vector3:
	var vis: VisualInstance3D = null
	var highlight: Variant = node.get("mesh_to_highlight")
	if highlight is VisualInstance3D:
		vis = highlight
	elif node is VisualInstance3D:
		vis = node
	if vis != null and is_instance_valid(vis):
		var box := vis.get_aabb()
		if box.size != Vector3.ZERO:
			return vis.global_transform * box.get_center()
	return node.global_position

# =============================================================================
# Construction
# =============================================================================
func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_chip = PanelContainer.new()
	_chip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_chip.offset_right = -RIGHT_MARGIN
	_chip.offset_left = -RIGHT_MARGIN
	_chip.offset_top = TOP_MARGIN
	_chip.offset_bottom = TOP_MARGIN
	_chip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_chip.grow_vertical = Control.GROW_DIRECTION_END
	_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_chip)
	_chip_label = Tokens.make_label("[H]  Help", Tokens.FONT_MD, Tokens.INK)
	_chip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip.add_child(_chip_label)
	_set_nudge(false)
	_chip.visible = false

	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", Tokens.glass_panel())
	_card.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_card.offset_right = -RIGHT_MARGIN
	_card.offset_left = -RIGHT_MARGIN
	_card.offset_top = TOP_MARGIN + 48.0
	_card.offset_bottom = TOP_MARGIN + 48.0
	_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_card.grow_vertical = Control.GROW_DIRECTION_END
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_card)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(column)

	column.add_child(_label("WHAT TO DO NOW", Tokens.FONT_SM, Tokens.ACCENT))
	_title = _label("", Tokens.FONT_LG, Tokens.INK)
	column.add_child(_title)
	_how = _label("", Tokens.FONT_MD, Tokens.INK_MUTED)
	column.add_child(_how)
	_where = _label("", Tokens.FONT_MD, Tokens.WARNING)
	column.add_child(_where)
	column.add_child(_label("Press H to close.", Tokens.FONT_SM, Tokens.INK_FAINT))
	_card.visible = false

	# Last, so it draws over the card: the edge arrow lands on the right-hand
	# side as often as not, which is exactly where the card sits.
	_arrow = GuideArrow.new()
	_arrow.set_anchors_preset(Control.PRESET_FULL_RECT)
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_arrow)


func _label(text: String, size: int, colour: Color) -> Label:
	var l := Tokens.make_label(text, size, colour)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# =============================================================================
# The arrow
# =============================================================================
## Screen-space, so it works whichever camera is current. On screen: a bobbing
## arrow over the object with a pulsing ring. Off screen: an arrow on the edge
## pointing the way to turn. Stands down wherever a beacon or a live pill is
## already marking the same spot (EdgeIndicators), so there is one arrow, not two.
class GuideArrow extends Control:
	const EDGE_MARGIN := 76.0
	const TAG_SIZE := 16

	var target: Variant = null
	var where: String = ""
	var _t: float = 0.0
	var _tag_style: StyleBoxFlat

	func _ready() -> void:
		_tag_style = Tokens.glass_chip()

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		if not (target is Vector3):
			return
		var point: Vector3 = target
		if EdgeScript.is_marked_near(point):
			return
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		var vp := get_viewport_rect().size
		var centre := vp * 0.5
		var behind := cam.is_position_behind(point)
		var s := cam.unproject_position(point)
		var inside := not behind and s.x > EDGE_MARGIN and s.x < vp.x - EDGE_MARGIN \
			and s.y > EDGE_MARGIN and s.y < vp.y - EDGE_MARGIN
		var bob := sin(_t * 5.0) * 7.0

		if inside:
			var ring := fmod(_t, 1.2) / 1.2
			draw_arc(s, 14.0 + 22.0 * ring, 0.0, TAU, 40,
				Color(Tokens.ATTENTION, 1.0 - ring), 3.0, true)
			var tip := s + Vector2(0.0, -20.0 + bob)
			_draw_pointer(tip, Vector2.DOWN)
			if where != "":
				_draw_tag(tip + Vector2(0.0, -86.0), where)
			return

		var dir := s - centre
		if behind:
			dir = -dir
		if dir.length() < 0.001:
			dir = Vector2.DOWN
		dir = dir.normalized()
		var half := centre - Vector2(EDGE_MARGIN, EDGE_MARGIN)
		var kx := absf(half.x / dir.x) if absf(dir.x) > 0.0001 else INF
		var ky := absf(half.y / dir.y) if absf(dir.y) > 0.0001 else INF
		var pos := centre + dir * minf(kx, ky) + dir * bob
		_draw_pointer(pos, dir)
		var verb := "turn around" if behind else "turn this way"
		if not behind and absf(dir.y) > absf(dir.x) * 1.5:
			verb = "look up" if dir.y < 0.0 else "look down"
		var line: String = (verb.substr(0, 1).to_upper() + verb.substr(1)) if where == "" \
			else "%s - %s" % [where, verb]
		_draw_tag(pos - dir * 84.0, line)

	func _draw_pointer(tip: Vector2, dir: Vector2) -> void:
		var perp := Vector2(-dir.y, dir.x)
		var back := tip - dir * 30.0
		var tail := back - dir * 26.0
		var pts := PackedVector2Array([
			tip, back + perp * 20.0, back + perp * 8.0, tail + perp * 8.0,
			tail - perp * 8.0, back - perp * 8.0, back - perp * 20.0,
		])
		draw_colored_polygon(pts, Tokens.ATTENTION)
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, Tokens.INK, 2.5, true)

	func _draw_tag(at: Vector2, text: String) -> void:
		var font := get_theme_default_font()
		var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, TAG_SIZE)
		var box := Vector2(ts.x + 24.0, ts.y + 12.0)
		var vp := get_viewport_rect().size
		var pos := at - box * 0.5
		pos.x = clampf(pos.x, 8.0, vp.x - box.x - 8.0)
		pos.y = clampf(pos.y, 8.0, vp.y - box.y - 8.0)
		draw_style_box(_tag_style, Rect2(pos, box))
		draw_string(font, pos + Vector2(12.0, 6.0 + font.get_ascent(TAG_SIZE)), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, TAG_SIZE, Tokens.INK)