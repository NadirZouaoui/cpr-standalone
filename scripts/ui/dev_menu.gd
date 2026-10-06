class_name DevMenu
extends CanvasLayer
## [F10] developer menu: jump straight to a named point in the exercise for
## testing, bypassing the normal lead-up.
##
## F9 was already taken - InteractionRay uses it to dump a probe of whatever
## the ray is looking at to user://interaction_probe.txt. This is F10 to
## stay out of its way.
##
## Built in code and spawned by main.gd, like PauseMenu and the rest of the
## runtime UI - see main.gd for why nothing here is authored into main.tscn.
##
## Debug builds only. This reaches straight into Rescuer/SimState/Casualty
## and skips every gate the real exercise enforces - exactly what a shipped
## build must never let a trainee do.

const UI_NAME := &"dev_menu"
const TOGGLE_KEY := KEY_F10
## Clean-frame curtain. See set_hud_hidden().
const HUD_KEY := KEY_F11

## A jump target. `label` is what shows on the button; `run` is called with
## no arguments and does whatever it takes to land in that state. Add more
## entries here as more stages need a quick way in - nothing else about
## this menu needs to change.
var _stages: Array[Dictionary] = []

var _root: Control
## The clean-frame entry, kept so its label can say which way it will go.
var _hud_button: Button = null


func _ready() -> void:
	set_process(false)
	if not OS.is_debug_build():
		# Still built so a debug export can use it, but inert in anything
		# that reaches a trainee.
		set_process_unhandled_input(false)
		return
	set_process(true)

	layer = 95  # Above the HUD (5), below the fail screen (100).
	process_mode = Node.PROCESS_MODE_ALWAYS

	_stages = [
		{
			"label": "Worker electrocuted (PPE + hook ready)",
			"run": _warp_to_shock,
		},
		{
			"label": "Casualty dragged clear (treatment pointers next)",
			"run": _warp_to_dragged,
		},
		{
			"label": "CPR: airway open (breathing check next)",
			"run": _warp_to_airway_open,
		},
		{
			"label": "CPR: shock delivered — final compressions (randomized run)",
			"run": _warp_to_final_compressions,
		},
		{
			"label": "Free camera (fly) — WASD, Space/Ctrl, Shift fast, wheel speed",
			"run": _toggle_free_camera,
		},
		{
			"label": "Hide all HUD (pills, prompts, objective arrow) — [F11]",
			"run": _toggle_hud,
			"id": &"hud",
		},
	]

	_build()
	_root.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return

	# The curtain is worth a key of its own: its whole use is looking at the
	# room with nothing over it, and opening a menu to lift it puts the largest
	# piece of UI in the project on the frame you were trying to see.
	if key.keycode == HUD_KEY:
		get_viewport().set_input_as_handled()
		_toggle_hud()
		return

	if key.keycode != TOGGLE_KEY:
		return

	get_viewport().set_input_as_handled()
	if is_open():
		close()
	else:
		open()


func is_open() -> bool:
	return _root != null and _root.visible


func open() -> void:
	if is_open():
		return
	_root.visible = true
	Events.open_ui(UI_NAME)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	if not is_open():
		return
	_root.visible = false
	Events.close_ui(UI_NAME)


# =============================================================================
# Stages
# =============================================================================
func _run_stage(entry: Dictionary) -> void:
	close()
	(entry["run"] as Callable).call()


## Skips PPE pickup, the breaker-panel door/sign sequence and the fiddle
## idle: gives the rescuer full PPE and the hook, reveals the casualty, and
## starts the shock loop directly.
##
## Mirrors what BreakerPanel._on_sign_hung() does to bring the worker into
## the room (arms CasualtyRig's hit capsule, arms ShockCue's reveal), then
## calls Casualty.begin_shock() instead of begin_opening() to skip straight
## past the fiddle-at-the-panel beat into the shock itself.
func _warp_to_shock() -> void:
	_force_close_blocking_screens()

	if SimState.is_preamble():
		SimState.begin_exercise()

	# Clicks the real PickupItem on each object, so PPE and the hook go
	# through the same path the player's own click would: held in the
	# HandSlot, Rescuer.equip()'d/don_ppe()'d, checklist step completed.
	# A hand-rolled shortcut here could silently drift from what picking
	# the things up actually does.
	_simulate_pickup("Gloves")
	_simulate_pickup("Hook")

	var casualty := _find_casualty()
	if casualty == null:
		push_warning("DevMenu: no Casualty in the scene; cannot warp.")
		return

	var rig := casualty.get_node_or_null(^"Rig") as CasualtyRig
	if rig != null:
		rig.arm()

	var cue := get_parent().get_node_or_null(^"ShockCue") as ShockCue
	if cue != null:
		cue.arm()

	casualty.begin_shock()
	Events.center_message_requested.emit(
		"Dev warp: worker electrocuted, PPE and hook ready.", Tokens.WARNING, 2.5
	)


## Lands at the top of the CPR phase with no waiting: PPE and hook taken,
## contact broken and the casualty in the safe area.
##
## The fall and the drag are SKIPPED, not played fast-forward through their
## clips — waiting out a 3.5 s drag tween on every test run is the whole reason
## this button exists. The state each skipped step would have left behind is set
## here instead: SimState.mark_contact_broken() so the contact clock closes and
## the debrief has a number, and both Assessment steps so the checklist agrees
## with the scene.
##
## The one thing NOT hand-rolled is the body's final pose. drag_to_safety()
## measures the turn from the rig's own bones to lay the casualty along world X,
## and the CPR camera anchors are all built against that axis — a hand-placed
## transform here put him down crossways with the anchors framing empty floor.
## So the real method still runs; `drag_duration` is just pinned to a single
## frame for the duration and put back afterwards.
## The body on the floor, laid out and ready to treat: everything
## _warp_to_airway_open() does, minus the R and A steps it hands out. This is
## where the treatment pointers start, so it is the stage to jump to when
## working on them — the airway-open warp skips straight past that sequence.
func _warp_to_dragged() -> void:
	await _warp_to_body_down()
	Events.center_message_requested.emit(
		"Dev warp: casualty dragged clear, ready to treat.", Tokens.WARNING, 2.5
	)


## Lands where the breathing check is the next thing the trainee does, skipping
## the fire check, the response check and the radio.
##
## It used to expose the chest to get here, because `chest_exposed` was what
## started the CPR spine. The 3 Sep reorder moved the shirt to between the two
## compression sets (client item 5), so exposing it now would be an out-of-order
## step that also robs EXPOSE_CHEST of its only exit — the station skips the
## state when the shirt is already open, which is correct but makes this warp
## silently miss the beat it exists to reach.
##
## What actually gates the breathing pill now is a completed response check plus
## an open airway, with the spine still at STATE_PRIMARY_SURVEY, so that is what
## this sets up. `send_for_help` goes with them: it is `airway_opened`'s
## prerequisite, and leaving it open would mark a warp-created run out of order
## on a step the trainee never saw.
func _warp_to_airway_open() -> void:
	var casualty := await _warp_to_body_down()
	if casualty == null:
		return

	casualty.check_response()
	Assessment.complete(&"fire_checked")
	Assessment.complete(&"send_for_help")
	Assessment.complete(&"call_for_aed")
	casualty.open_airway()

	Events.center_message_requested.emit(
		"Dev warp: airway open, breathing check next.", Tokens.WARNING, 2.5
	)


## Lands in COMPRESSIONS_2 — the last compression set, right after the AED
## shock — with every earlier checklist step completed in a randomized order,
## so the debrief that closes the run shows a different mix of out-of-order,
## late and missed marks each time. Deliver the final set (10 reps, or the
## debug fast-forward) and the debrief screen appears.
##
## The CPR spine is driven by emitting the same Events facts a real
## playthrough produces, in order — the same route cpr_headless_test.gd takes
## — so the station, panel, camera and voice all move exactly as they would
## have. The checklist steps, by contrast, are completed directly through
## Assessment: their order (and occasional absence) is the randomness being
## tested. compressions_armed is left off after the shock, exactly as a real
## run leaves it: the post-shock pills — "Start compressions" beside the
## signs-of-life gotcha — are the beat this warp is most often used to look at.
func _warp_to_final_compressions() -> void:
	var casualty := await _warp_to_body_down()
	if casualty == null:
		return

	var station := CprStation.get_current()
	if station == null:
		push_warning("DevMenu: no CprStation; cannot drive the CPR spine.")
		return

	await _randomize_checklist()

	station.enter_cpr_phase()  # idempotent; covers a lost phase_changed race
	# The spine's idle is STATE_PRIMARY_SURVEY now, not EXPOSE_CHEST — that
	# state moved to after the first set. Testing for the old one meant the
	# breathing check never started and the warp stalled before it began.
	if station.current_state == CprStation.STATE_PRIMARY_SURVEY:
		station.begin_breathing_check()
	Events.breathing_checked.emit(false)
	await _wait_frames(5)

	# The two new assessment beats (client items 6 and 7) sit between the
	# breathing check and the first set, and each owns a checklist step. Driven
	# here rather than left to _randomize_checklist(), so the spine walks the
	# real route and the debrief reports them as performed in order.
	station.begin_airway_inspect()
	await _wait_frames(5)
	station.finish_airway_inspect()
	station.complete_pulse_check()
	await _wait_frames(5)

	station.begin_compressions_early()
	await _emit_fake_set(30)

	# The shirt now comes off BETWEEN the sets, not before the phase. This is
	# the beat the whole reorder exists for, and it is the spine's only exit
	# from EXPOSE_CHEST: expose_chest() completes `chest_exposed`, and the
	# station moves on when the step lands.
	await _wait_frames(5)
	casualty.expose_chest()
	await _wait_frames(5)

	Events.aed_picked_up.emit()
	await _wait_frames(5)
	Events.aed_placed.emit()
	await _wait_frames(5)
	for slot in 2:
		var correct := randf() < 0.75
		var site := "PadSite_Correct_Upper" if slot == 0 else "PadSite_Correct_Lower"
		if not correct:
			site = "PadSite_Wrong_0%d" % randi_range(1, 3)
		Events.aed_pad_placed.emit(slot, correct, site)
		await _wait_frames(5)
	await _wait_frames(10)
	Events.aed_shock_delivered.emit()

	Events.center_message_requested.emit(
		"Dev warp: shock delivered — final set, then recovery, injuries, handover.",
		Tokens.WARNING, 3.5
	)


## Shuffles every still-open checklist step (the CPR spine owns four of them
## and completes them itself) and closes most of them in that random order,
## with gaps so the timestamps differ. Randomly drops the odd step entirely.
func _randomize_checklist() -> void:
	const SPINE_STEPS: Array[StringName] = [
		&"chest_exposed", &"breathing_checked", &"cpr_performed", &"aed_used",
		# The 3 Sep reorder gave the spine two more of its own: the airway
		# inspection and the pulse check are driven by the warp itself, above.
		&"airway_inspected", &"pulse_checked",
		# And Task 6 gave it four that come AFTER this warp lands. Randomly
		# completing them here would mark the recovery beats done before the
		# trainee reaches them, and pre-completing `recovery_position` in
		# particular would make a refused roll look like a successful one.
		&"signs_of_life", &"recovery_position", &"injuries_checked", &"handover",
	]
	var pending: Array[StringName] = []
	for id in Assessment.order:
		if Assessment.is_resolved(id) or SPINE_STEPS.has(id):
			continue
		pending.append(id)
	pending.shuffle()
	for id in pending:
		if randf() < 0.15:
			continue
		Assessment.complete(id)
		await get_tree().create_timer(randf_range(0.1, 0.6)).timeout


## One compression set's worth of reps at randomized quality — roughly three
## in four in spec — so the debrief's depth/rate percentages have something
## non-trivial to show. Spaced a few frames apart like real reps rather than
## dumped in one tick, so the panel's counter animates.
func _emit_fake_set(count: int) -> void:
	for i in count:
		var depth := randf_range(0.75, 0.95) if randf() < 0.75 else randf_range(0.40, 0.74)
		var rate := randf_range(100.0, 120.0) if randf() < 0.75 else randf_range(80.0, 99.0)
		Events.compression_delivered.emit(depth, rate, i)
		await _wait_frames(2)
	Events.compression_set_completed.emit(count, false)


func _wait_frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


## Shared spine of both CPR warps: electrocution, contact broken, fallen pose,
## drag, empty hands. Returns the casualty, or null if it could not be found.
func _warp_to_body_down() -> Casualty:
	_warp_to_shock()

	var casualty := _find_casualty()
	if casualty == null:
		return null  # _warp_to_shock already warned

	# What break_contact_with_crook() does, minus the wait. Setting DOWN also
	# stops begin_shock()'s own pending await from starting the shock loop —
	# its continuation bails unless the state is still IN_CONTACT.
	SimState.mark_contact_broken()
	Assessment.complete(&"contact_broken")
	_snap_to_collapse_end(casualty)
	casualty.state = Casualty.State.DOWN
	if SimState.phase < SimState.Phase.EXTRACTION:
		SimState.phase = SimState.Phase.EXTRACTION

	# EXTRACTION has two jobs in it and the phase waits for both
	# (Casualty._try_leave_extraction). A warp stands for "everything up to
	# here was done properly", so it throws the isolation as well - without it
	# every warp past this point lands in a run stuck in EXTRACTION with the
	# CPR spine never entered. Completed before the drag so the drag is the
	# step that ends the phase, which is the taught order.
	Assessment.complete(&"supply_isolated")

	var real_duration := casualty.drag_duration
	casualty.drag_duration = 0.001
	await casualty.drag_to_safety()
	if not is_instance_valid(casualty):
		return null
	casualty.drag_duration = real_duration

	# The hook did its job at break-contact and both hands are needed for
	# compressions. _warp_to_shock() picks it up so the checklist step
	# completes the way a real run's does; putting it back here leaves the
	# checklist right and the hands empty.
	_empty_hands()
	return casualty


## Applies the last frame of the fall clip in one frame, instead of playing it
## and waiting ~2 s.
##
## This is not cosmetic. drag_to_safety() measures the turn to lay the body
## along world X from the rig's own bone positions, and every CPR camera anchor
## is built against that axis — so the bones have to be in the fallen pose
## BEFORE the drag runs. Skipping the clip entirely left them in the standing
## shock pose, and the drag then solved for the wrong rotation and put the
## casualty down in the wrong place: the bug this fixes.
##
## `seek(..., update = true)` applies the pose immediately rather than on the
## next process tick, and `pause()` stops the clip advancing past it. Matches
## the real path's end state, where anim_down is empty and the fall's last
## frame is what stays on screen.
func _snap_to_collapse_end(casualty: Casualty) -> void:
	var player := casualty.animation_player
	if player == null or not player.has_animation(casualty.anim_collapse):
		push_warning("DevMenu: no '%s' clip; the casualty will not be in the fallen pose."
			% casualty.anim_collapse)
		return
	player.play(casualty.anim_collapse)
	player.seek(player.get_animation(casualty.anim_collapse).length, true)
	player.pause()


func _empty_hands() -> void:
	var player := get_tree().get_first_node_in_group(&"player") as Player
	if player == null or player.hand_slot == null:
		return
	if not player.hand_slot.is_empty():
		player.hand_slot.release()


## Not a stage jump — a view toggle that leaves the exercise's state alone.
## Sits in the same list because this menu is already the one place a tester
## reaches for, and a second keybind for one debug tool is not worth it.
##
## Re-open F10 and pick it again to come back; the camera hands the view back
## to whatever held it, including a CPR anchor.
# =============================================================================
# Clean-frame mode
# =============================================================================
## Everything the trainee is shown ON TOP of the room, off in one keystroke -
## the objective pill and timer, the interaction prompt and reticle, the body
## and extraction pointers, the CPR key hints and hands, and the yellow
## objective arrow. For screenshots, for video, and for looking at the room
## itself without the exercise drawn over it.
##
## Deliberately NOT a gameplay switch. Nothing here changes what is armed or
## what is assessed: the pointers are still solving, the prompts still fire,
## the pills a click would have landed on are still under the cursor. It is a
## curtain over the frame, so a run made behind it is still a valid run - it
## is just one where the trainee cannot see what they are being asked to do.
##
## Layer 10 and below is the whole of the overlay HUD. The blocking screens
## (kit 20, hazard 21, review 22, pause 90, this menu 95, debrief 99, fail 100)
## are above it and stay: hiding those would strand the run behind an invisible
## full-rect control that still eats every click.
const HUD_LAYER_CEILING := 10

## Rescan interval, seconds. The HUD is not one static set - pointers, key
## hints and the centre card are built the moment the beat that needs them
## starts, and several nodes recompute their own `visible` from their own
## state. So the curtain is re-applied on a timer rather than once, and
## anything that comes up while it is drawn goes straight back down.
const HUD_RESCAN := 0.25

var _hud_hidden: bool = false
var _hud_rescan_due: float = 0.0
## What we turned off, so nothing we did NOT turn off gets turned back on.
var _hud_hidden_nodes: Array[Node] = []


func _toggle_hud() -> void:
	set_hud_hidden(not _hud_hidden)


## The curtain, as a plain setter so a test or another dev tool can drive it.
func set_hud_hidden(hidden: bool) -> void:
	_hud_hidden = hidden
	if hidden:
		_hud_rescan_due = 0.0
		_apply_hud_curtain()
	else:
		for node in _hud_hidden_nodes:
			if is_instance_valid(node):
				node.set("visible", true)
		_hud_hidden_nodes.clear()
	_refresh_hud_button()


func _process(delta: float) -> void:
	if not _hud_hidden:
		return
	_hud_rescan_due -= delta
	if _hud_rescan_due <= 0.0:
		_hud_rescan_due = HUD_RESCAN
		_apply_hud_curtain()


func _apply_hud_curtain() -> void:
	var root := get_tree().root
	for node in root.find_children("*", "CanvasLayer", true, false):
		var canvas := node as CanvasLayer
		if canvas == self or canvas.layer > HUD_LAYER_CEILING:
			continue
		_hide_for_curtain(canvas)
	# The yellow arrow is world geometry, not a layer.
	for node in root.find_children("*", "ObjectiveBeacon", true, false):
		_hide_for_curtain(node)


func _hide_for_curtain(node: Node) -> void:
	if not bool(node.get("visible")):
		return
	node.set("visible", false)
	if not _hud_hidden_nodes.has(node):
		_hud_hidden_nodes.append(node)


## The menu is built once, so the entry says which way it will go next.
func _refresh_hud_button() -> void:
	if _hud_button == null:
		return
	_hud_button.text = "Show all HUD again — [F11]" if _hud_hidden 		else "Hide all HUD (pills, prompts, objective arrow) — [F11]"


func _toggle_free_camera() -> void:
	var cam := get_parent().get_node_or_null(^"FreeCamera")
	if cam == null:
		push_warning("DevMenu: no FreeCamera node in the scene.")
		return
	cam.toggle()


func _simulate_pickup(node_name: String) -> void:
	var room := get_parent().get_node_or_null(^"ControlRoom")
	if room == null:
		push_warning("DevMenu: no ControlRoom in the scene.")
		return
	var mesh := room.get_node_or_null(NodePath(node_name))
	if mesh == null:
		push_warning("DevMenu: no '%s' in the room to pick up." % node_name)
		return
	var interact := mesh.get_node_or_null(^"Interact") as PickupItem
	if interact == null:
		push_warning("DevMenu: '%s' has no PickupItem bound." % node_name)
		return
	# interact() itself no-ops once the item is already taken, so this is
	# safe to call on a warp that runs twice.
	interact.interact(Vector3.ZERO)


func _find_casualty() -> Casualty:
	return get_tree().get_first_node_in_group(&"casualty") as Casualty


## KitCheck and CasualtyActions manage their own child screens' visibility
## internally and do not listen for Events.close_ui, so closing the UI
## bookkeeping alone would leave a stale panel on screen. Each one's own
## CanvasLayer.visible is the single switch that overrides all of that at
## once, the same way _ready() and _show()/_hide() already use it.
func _force_close_blocking_screens() -> void:
	for ui_name in Events.open_uis.keys():
		Events.close_ui(ui_name)
	# HazardPanel and ReviewPanel are full-screen overlays that hold the
	# blocking-UI register themselves, so clearing open_uis above is not enough
	# on its own - the layer would still be drawn over the warped-into run.
	# Both answer close(), which puts the register back where they found it.
	for node_name in [^"HazardPanel", ^"ReviewPanel"]:
		var panel := get_parent().get_node_or_null(node_name)
		if panel != null and panel.has_method("close"):
			panel.call("close")

	for node_name in [^"KitCheck", ^"CasualtyActions"]:
		var n := get_parent().get_node_or_null(node_name) as CanvasLayer
		if n == null:
			continue
		# KitCheck rebuilds its own `visible` from the screens underneath it,
		# so hiding the layer alone leaves the brief armed and it comes back on
		# the next refresh. Ask it to close them properly first - see
		# kit_check.gd::force_close_screens().
		if n.has_method("force_close_screens"):
			n.force_close_screens()
		n.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# =============================================================================
# Construction
# =============================================================================
func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Tokens.OVERLAY_DIM
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(centre)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 0)
	panel.add_theme_stylebox_override("panel", Tokens.glass_panel())
	centre.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	var title := Label.new()
	title.text = "DEV: JUMP TO STAGE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", Tokens.FONT_LG)
	title.add_theme_color_override("font_color", Tokens.INK)
	column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Debug build only. Skips the normal lead-up - do not use this to grade a run."
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", Tokens.FONT_SM)
	subtitle.add_theme_color_override("font_color", Tokens.WARNING)
	column.add_child(subtitle)

	column.add_child(HSeparator.new())

	for entry in _stages:
		var b := Button.new()
		b.text = entry["label"]
		b.custom_minimum_size = Vector2(0, 40)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", Tokens.FONT_MD)
		Tokens.style_button(b, &"neutral")
		b.pressed.connect(_run_stage.bind(entry))
		column.add_child(b)
		if entry.get("id", &"") == &"hud":
			_hud_button = b

	column.add_child(HSeparator.new())

	var close_button := Button.new()
	close_button.text = "Close"
	close_button.custom_minimum_size = Vector2(0, 40)
	close_button.add_theme_font_size_override("font_size", Tokens.FONT_MD)
	Tokens.style_button(close_button, &"dark")
	close_button.pressed.connect(close)
	column.add_child(close_button)

	var hint := Label.new()
	hint.text = "[F10] to close"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", Tokens.FONT_SM)
	hint.add_theme_color_override("font_color", Tokens.INK_MUTED)
	column.add_child(hint)
