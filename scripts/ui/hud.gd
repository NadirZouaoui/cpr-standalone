extends CanvasLayer
## In-world HUD: reticle, interaction prompt, checklist, contact clock.
##
## Built in code rather than as a .tscn so the layout stays reviewable in
## diff form. Everything it displays arrives through Events - the HUD never
## reaches into the simulation to ask questions.

const CHECKLIST_WIDTH := 340

## Feedback pill: how far its bottom edge sits above the bottom of the screen,
## clear of the "[C] Crouch / stand up" chip in the corner.
const MESSAGE_BOTTOM_MARGIN := 92
## Current-step pill: sits under the feedback pill, at the very bottom.
const STEP_PILL_BOTTOM_MARGIN := 34
## Saturated scene colours callers pass (gold, amber, red) are only readable
## on white glass once clamped below this luminance. Neutrals never get here —
## see _ink_for_glass().
const MESSAGE_MAX_LUMINANCE := 0.42

var _reticle: Panel
var _prompt_chip: PanelContainer
var _prompt: Label
var _contact_chip: PanelContainer
var _checklist_panel: PanelContainer
var _checklist_items: VBoxContainer
var _center_message: Label
## The glass pill the message sits on. The fade is driven on this, not on the
## label, so the chip fades with its text.
var _message_pill: PanelContainer
var _contact_clock: Label
var _phase_label: Label
var _held_chip: PanelContainer
var _held_label: Label
var _kit_label: Label
var _step_pill: PanelContainer
## What _refresh_step_pill() decided the pill should say, before the body
## pointers get their veto. See _sync_step_pill().
var _step_pill_wanted: bool = false
var _step_label: Label

## Everything the HUD draws hangs off this, so a blocking UI can take the
## whole thing down in one line. Without that, the reticle floats over the
## kit check and the debrief like a bug.
var _root: Control

var _message_tween: Tween
var _urgent_tween: Tween
var _checklist_rows: Dictionary = {}  # step_id -> Label
## The single row the checklist shows from the primary survey on. See
## _lumped_title().
var _lump_row: Label


func _ready() -> void:
	layer = 5
	_build()
	_rebuild_checklist()
	_refresh_step_pill()

	Events.prompt_requested.connect(_on_prompt_requested)
	Events.center_message_requested.connect(_on_center_message)
	Events.step_completed.connect(func(_id, _t): _refresh_checklist())
	Events.step_failed.connect(func(_id, _r): _refresh_checklist())
	Events.step_completed.connect(func(_id, _t): _refresh_step_pill())
	Events.step_failed.connect(func(_id, _r): _refresh_step_pill())
	# The spine moves between beats without completing a step on the way - the
	# whole AED sequence is one step - so the checklist signals above do not
	# cover it, and without this the pill kept the previous beat's line.
	Events.cpr_state_changed.connect(func(_f, _t): _refresh_step_pill())
	Events.cpr_state_changed.connect(func(_f, _t): _refresh_checklist())
	Events.phase_changed.connect(_on_phase_changed)
	Events.kit_stage_changed.connect(_on_kit_stage_changed)
	Events.focus_changed.connect(_on_focus_changed)
	Events.ui_opened.connect(func(_n): _sync_visibility())
	Events.ui_closed.connect(func(_n): _sync_visibility())
	_sync_visibility()

	# The player is a sibling built at the same time, so its hand does not
	# exist yet on the first frame.
	_connect_hand.call_deferred()


func _connect_hand() -> void:
	var slot := get_tree().get_first_node_in_group(HandSlot.GROUP) as HandSlot
	if slot == null:
		return
	slot.held_changed.connect(_on_held_changed)
	_on_held_changed(slot.held_item_id)


## The tutorial runs with the checklist off the screen: it is a practice round,
## and a list of steps it is not asking for is noise. Everything the tutorial
## itself uses - the dot, the prompt, the held item, the feedback pill - stays.
## Faded rather than hidden so it cannot fight the [Tab] toggle's own state.
func set_minimal(on: bool) -> void:
	if _checklist_panel != null:
		_checklist_panel.modulate.a = 0.0 if on else 1.0


func _process(_delta: float) -> void:
	_sync_step_pill()
	if SimState.phase == SimState.Phase.BREAK_CONTACT:
		_contact_chip.visible = true
		_contact_clock.text = "IN CONTACT  %.1fs" % SimState.contact_seconds
	else:
		_contact_chip.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_checklist"):
		_checklist_panel.visible = not _checklist_panel.visible


# =============================================================================
# Construction
# =============================================================================
func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# --- Reticle ---------------------------------------------------------
	_reticle = Panel.new()
	_reticle.custom_minimum_size = Vector2(6, 6)
	_reticle.set_anchors_preset(Control.PRESET_CENTER)
	_reticle.position = Vector2(-3, -3)
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_reticle_colour(Color(1, 1, 1, 0.55))
	_root.add_child(_reticle)

	# --- Interaction prompt ----------------------------------------------
	# A glass chip behind the text: the prompt sits over the busiest part of
	# the scene, and white-on-scene text fights the room. Glass carries the
	# contrast instead.
	# Pinned to the screen centre and grown outwards from it, so the chip
	# hugs its text. The old fixed 400 px label inside made every prompt,
	# however short, render as a full-width slab.
	_prompt_chip = PanelContainer.new()
	_prompt_chip.set_anchors_preset(Control.PRESET_CENTER)
	_prompt_chip.offset_left = 0
	_prompt_chip.offset_right = 0
	_prompt_chip.offset_top = 24
	_prompt_chip.offset_bottom = 24
	_prompt_chip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt_chip.grow_vertical = Control.GROW_DIRECTION_END
	_prompt_chip.add_theme_stylebox_override("panel", Tokens.glass_chip())
	_prompt_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_prompt_chip)

	_prompt = Label.new()
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", Tokens.FONT_MD)
	_prompt.add_theme_color_override("font_color", Tokens.INK)
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_chip.add_child(_prompt)
	_prompt_chip.visible = false

	# --- Contact clock ----------------------------------------------------
	_contact_chip = PanelContainer.new()
	_contact_chip.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_contact_chip.offset_left = 0
	_contact_chip.offset_right = 0
	_contact_chip.offset_top = 28
	_contact_chip.offset_bottom = 28
	_contact_chip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_contact_chip.grow_vertical = Control.GROW_DIRECTION_END
	_contact_chip.add_theme_stylebox_override("panel", Tokens.glass_chip())
	_contact_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_contact_chip)

	_contact_clock = Label.new()
	# The only chip that keeps a fixed width: the seconds tick every frame,
	# and a chip that resizes on each digit reads as a glitch.
	_contact_clock.custom_minimum_size = Vector2(200, 0)
	_contact_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_contact_clock.add_theme_font_size_override("font_size", Tokens.FONT_LG)
	_contact_clock.add_theme_color_override("font_color", Tokens.DANGER)
	_contact_chip.add_child(_contact_clock)
	_contact_chip.visible = false

	# --- Checklist --------------------------------------------------------
	_checklist_panel = PanelContainer.new()
	_checklist_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_checklist_panel.position = Vector2(24, 24)
	_checklist_panel.custom_minimum_size = Vector2(CHECKLIST_WIDTH, 0)
	_checklist_panel.add_theme_stylebox_override("panel", Tokens.glass_panel())
	_checklist_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_checklist_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_checklist_panel.add_child(column)

	_phase_label = Label.new()
	_phase_label.add_theme_font_size_override("font_size", Tokens.FONT_SM)
	_phase_label.add_theme_color_override("font_color", Tokens.ACCENT)
	_phase_label.text = SimState.phase_name().to_upper()
	column.add_child(_phase_label)

	_checklist_items = VBoxContainer.new()
	_checklist_items.add_theme_constant_override("separation", 4)
	column.add_child(_checklist_items)

	# Standing task for the preamble. A reminder, not a counter: any number
	# on screen here would tell the trainee which bench objects are kit by
	# watching whether it moved.
	_kit_label = Label.new()
	_kit_label.add_theme_font_size_override("font_size", Tokens.FONT_SM)
	_kit_label.add_theme_color_override("font_color", Tokens.WARNING)
	_kit_label.text = "Select the LVR kit items"
	_kit_label.visible = SimState.is_preamble()
	column.add_child(_kit_label)

	var hint := Label.new()
	hint.add_theme_font_size_override("font_size", Tokens.FONT_SM)
	hint.add_theme_color_override("font_color", Tokens.INK_FAINT)
	hint.text = "[Tab] hide"
	column.add_child(hint)

	# --- Centre message ---------------------------------------------------
	# Feedback lives on a pill at the bottom of the screen, not across the
	# middle of it. Centre screen is where the trainee is working — it is the
	# crosshair, the casualty, and now the body pointers — and coloured text
	# laid over that competed with the thing it was commenting on. Same glass
	# chip as the rest of the HUD, so it reads as the interface talking rather
	# than as scene text.
	_message_pill = PanelContainer.new()
	_message_pill.add_theme_stylebox_override("panel", Tokens.glass_chip(Tokens.RADIUS_LG))
	_message_pill.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_message_pill.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_message_pill.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_message_pill.position = Vector2(0, -MESSAGE_BOTTOM_MARGIN)
	_message_pill.modulate.a = 0.0
	_message_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_message_pill)

	_center_message = Label.new()
	_center_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# No autowrap. The pill is anchored, not stretched, so its width comes from
	# this label's own minimum — and a wrapping label's minimum width is one
	# character, which is exactly what it collapsed to. Messages are single
	# short lines; the pill sizes itself to whichever one is showing.
	_center_message.autowrap_mode = TextServer.AUTOWRAP_OFF
	_center_message.add_theme_font_size_override("font_size", Tokens.FONT_MD)
	_center_message.add_theme_color_override("font_color", Tokens.INK)
	_center_message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_message_pill.add_child(_center_message)

	# --- Current step -----------------------------------------------------
	# The one thing the trainee is supposed to be doing right now, parked at
	# the bottom centre where the eye lands between tasks. The checklist on
	# the left holds the whole procedure; this pill holds the present. The
	# feedback pill above it stays transient - this one stands for the whole
	# step.
	_step_pill = PanelContainer.new()
	_step_pill.add_theme_stylebox_override("panel", Tokens.glass_chip(Tokens.RADIUS_LG))
	_step_pill.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_step_pill.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_step_pill.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_step_pill.position = Vector2(0, -STEP_PILL_BOTTOM_MARGIN)
	_step_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_step_pill)

	_step_label = Label.new()
	_step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_step_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_step_label.add_theme_font_size_override("font_size", Tokens.FONT_MD)
	_step_label.add_theme_color_override("font_color", Tokens.INK)
	_step_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_step_pill.add_child(_step_label)
	_step_pill.visible = false

	# --- Held item --------------------------------------------------------
	# Grows leftwards and upwards out of the bottom-right corner, so the
	# chip is as wide as the item name and no wider.
	_held_chip = PanelContainer.new()
	_held_chip.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_held_chip.offset_right = -24
	_held_chip.offset_bottom = -24
	_held_chip.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_held_chip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_held_chip.add_theme_stylebox_override("panel", Tokens.glass_chip())
	_held_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_held_chip)

	_held_label = Label.new()
	_held_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_held_label.add_theme_font_size_override("font_size", Tokens.FONT_MD)
	_held_label.add_theme_color_override("font_color", Tokens.INK)
	_held_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_held_chip.add_child(_held_label)
	_held_chip.visible = false


func _set_reticle_colour(c: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(3)
	_reticle.add_theme_stylebox_override("panel", sb)


# =============================================================================
# Checklist
# =============================================================================
func _rebuild_checklist() -> void:
	for child in _checklist_items.get_children():
		child.queue_free()
	_checklist_rows.clear()

	for id in Assessment.order:
		var row := Label.new()
		row.add_theme_font_size_override("font_size", Tokens.FONT_SM)
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.custom_minimum_size = Vector2(CHECKLIST_WIDTH - 40, 0)
		_checklist_items.add_child(row)
		_checklist_rows[id] = row

	_lump_row = Label.new()
	_lump_row.add_theme_font_size_override("font_size", Tokens.FONT_SM)
	_lump_row.add_theme_color_override("font_color", Tokens.INK)
	_lump_row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lump_row.custom_minimum_size = Vector2(CHECKLIST_WIDTH - 40, 0)
	_lump_row.visible = false
	_checklist_items.add_child(_lump_row)

	_refresh_checklist()


## Completed steps the checklist keeps showing. Everything older than these
## disappears: the full record stays in the debrief, and the card would
## otherwise grow past a third of the screen by the CPR phase.
const CHECKLIST_COMPLETED_SHOWN := 2


## Shows the last couple of completed steps, the current one, and nothing
## further ahead or further back - the trainee should be recalling the
## procedure, not reading it off a list.
func _refresh_checklist() -> void:
	var lumped := _lumped_title()
	if _lump_row != null:
		_lump_row.visible = lumped != ""
		_lump_row.text = "\u203a  %s" % lumped
	if lumped != "":
		for row in _checklist_rows.values():
			(row as Label).visible = false
		return

	var current := Assessment.next_step()
	# Indices of the completed/failed steps, in procedure order, so only the
	# most recent few survive the cull.
	var done: Array[int] = []
	for i in Assessment.order.size():
		if Assessment.is_failed(Assessment.order[i]) or Assessment.is_complete(Assessment.order[i]):
			done.append(i)
	var cutoff := maxi(done.size() - CHECKLIST_COMPLETED_SHOWN, 0)

	for i in Assessment.order.size():
		var id: StringName = Assessment.order[i]
		var row: Label = _checklist_rows[id]
		var step: ProcedureStep = Assessment.steps[id]

		# A failed step reads exactly like a passed one here. The checklist
		# is on screen while the trainee works, and a red x would be marking
		# their work mid-exercise - the one thing this exercise refuses to
		# do. The failure is still recorded: it scores nothing and every
		# detail comes out in the debrief.
		if i < cutoff:
			row.visible = false
		elif Assessment.is_failed(id):
			row.text = "✓  %s" % step.title
			row.add_theme_color_override("font_color", Tokens.SUCCESS)
			row.visible = true
		elif Assessment.is_complete(id):
			var entry: Dictionary = Assessment.completed[id]
			var flagged: bool = entry["out_of_order"] or entry["late"]
			row.text = "%s  %s" % ["!" if flagged else "✓", step.title]
			row.add_theme_color_override("font_color", Tokens.WARNING if flagged else Tokens.SUCCESS)
			row.visible = true
		elif id == current:
			var owning: ProcedureStep = Assessment.steps[id]
			if owning.suppress_prompt or not _may_name(owning):
				# Graded but never offered - the gotcha rule. The checklist is the
				# same surface as the pill and stays just as quiet.
				row.visible = false
			else:
				var shown := _display_step(id)
				row.text = "›  %s" % shown.title
				row.add_theme_color_override("font_color", Tokens.DANGER if shown.urgent else Tokens.INK)
				row.visible = true
		else:
			row.visible = false


# =============================================================================
# Signal handlers
# =============================================================================
## The kit check, the casualty menu and the fail screen all draw their own
## full-screen surface. The HUD gets out of the way rather than competing.
func _sync_visibility() -> void:
	if _root != null:
		_root.visible = not Events.is_ui_blocking()


func _on_prompt_requested(text: String) -> void:
	_prompt.text = text
	# An empty glass box on screen is noise; the chip only exists while there
	# is something to say.
	_prompt_chip.visible = text != ""


func _on_focus_changed(interactable: Node) -> void:
	_set_reticle_colour(Tokens.ATTENTION if interactable != null else Color(1, 1, 1, 0.55))


## Reads the id rather than a display name: the hand is a presentation node
## and does not carry one. Underscores out, title case in.
func _on_held_changed(item_id: StringName) -> void:
	if item_id == &"":
		_held_chip.visible = false
		return
	_held_chip.visible = true
	_held_label.text = "%s   [G] put back" % String(item_id).replace("_", " ").capitalize()


func _on_phase_changed(_previous: int, _current: int) -> void:
	_phase_label.text = SimState.phase_name().to_upper()
	_kit_label.visible = SimState.is_preamble()
	_refresh_step_pill()
	_refresh_checklist()


## The standing bottom-centre pill names whatever step is current - "Identify
## the electrical hazard", "Send for help", and so on down the procedure. It
## stays down during the preamble (the kit check brief speaks for itself) and
## goes away once every step is resolved.
##
## Gotcha-aware: a suppressed step is graded but never named, and a step with
## `display_as` speaks with another step's title. `crook_retrieved` is the
## worked example - from the moment the worker goes down the pill says "Break
## contact with the live hazard" and never mentions fetching the crook.
##
## `ppe_donned` used to carry the same `display_as`, from when it sat inside
## that window. It was moved to the front of the procedure (gloves on before
## work commences) and the redirect came with it, so the very first pill of the
## run - straight out of the kit check, with the worker still safely at the
## panel - was a flashing red "Break contact with the live hazard". Redirect a
## step only while it is genuinely inside the beat it points at.
func _refresh_step_pill() -> void:
	if _step_pill == null:
		return
	if SimState.is_preamble():
		_step_pill_wanted = false
		_set_urgent(false)
		_sync_step_pill()
		return
	var lumped := _lumped_title()
	if lumped != "":
		_step_label.text = lumped
		_set_urgent(false)
		_step_pill_wanted = true
		_sync_step_pill()
		return
	var current := _spine_step()
	if current == &"":
		current = Assessment.next_step()
	if current == &"" or not Assessment.steps.has(current):
		_step_pill_wanted = false
		_set_urgent(false)
		_sync_step_pill()
		return
	if Assessment.steps[current].suppress_prompt or not _may_name(Assessment.steps[current]):
		_step_pill_wanted = false
		_set_urgent(false)
		_sync_step_pill()
		return
	var shown := _display_step(current)
	_step_label.text = shown.title
	_set_urgent(shown.urgent)
	_step_pill_wanted = true
	_sync_step_pill()


const TREAT_TITLE := "Treat the casualty"
const CPR_TITLE := "Perform CPR"


## One line for the whole casualty phase, or "" to name steps as before.
##
## Client, 23 Sep 2026: from the primary survey on, the checklist and the bottom
## pill were naming each micro-step in turn - "Check the casualty is not on
## fire", "Check for a response", "Open the airway" - which hands the trainee
## the correct order the exercise is meant to assess. They now say "Treat the
## casualty", or "Perform CPR" through the CPR spine, and the labels on the
## body are the options. The debrief still lists every step and the order.
##
## "" at HANDOVER and after: the closing beat asks nothing, and the pill stays
## down there as it always has.
func _lumped_title() -> String:
	var phase := int(SimState.phase)
	if phase < int(SimState.Phase.PRIMARY_SURVEY) or phase >= int(SimState.Phase.DEBRIEF):
		return ""
	var station := CprStation.get_current()
	if station != null and station.is_phase_entered():
		var state: int = station.current_state
		if state >= CprStation.STATE_HANDOVER:
			return ""
		if state >= CprStation.STATE_BREATHING_CHECK and state <= CprStation.STATE_COMPRESSIONS_2:
			return CPR_TITLE
	return TREAT_TITLE


## What the CPR spine says the trainee is on, or &"" when it has nothing to say
## and the checklist is the better answer.
##
## Asked BEFORE Assessment.next_step(), because two of the phase's steps -
## `cpr_performed` and `aed_used` - are graded from the end-of-phase metrics
## rather than when their beat ends, which left next_step() naming the
## compression set for everything after the pulse check. See
## CprStation.STATE_STEPS for the full account.
func _spine_step() -> StringName:
	var station := CprStation.get_current()
	if station == null or not station.is_phase_entered():
		return &""
	return station.step_for_state()


## The body pointers and this pill were saying the same sentence twice - the
## casualty carrying "Check for a response" on his mouth while the bottom of
## the screen repeated it in larger type. The diegetic pill is the better of
## the two, so this one stands down for as long as any body pointer is drawn
## and comes back the moment they go. Re-checked every frame because the
## pointers appear and disappear with the camera, not with the checklist.
func _sync_step_pill() -> void:
	if _step_pill == null:
		return
	_step_pill.visible = _step_pill_wanted and not _body_pointer_live()


func _body_pointer_live() -> bool:
	var menu := get_tree().current_scene.get_node_or_null(^"CasualtyActions")
	return menu != null \
		and menu.has_method("has_visible_pointer") \
		and menu.has_visible_pointer()


## The step the HUD names on behalf of `id`, following `display_as` until a
## step that speaks for itself. Hop-capped so a mis-authored chain can only
## degrade into showing the wrong title, never hang the refresh.
##
## A redirect is also refused once it reaches a step whose own `min_phase` has
## not arrived - it stops on the last step that is allowed to speak. The
## redirect says "the beat you are in is really about this"; if that beat has
## not started, the sentence is false whatever the checklist order says.
##
## This is the second time the same wrong sentence has reached the screen. The
## first was `ppe_donned` carrying a leftover `display_as` (see
## _refresh_step_pill), fixed by removing the redirect and guarded since by
## check_procedure_order''s category invariant - a redirect must point inside
## its own beat. `crook_retrieved` -> `contact_broken` satisfies that invariant
## honestly: both ARE the break-contact beat. What it could not catch is that
## the trainee can fetch the crook while the worker is still upright at the
## panel, and from that moment the pill flashed danger-red "Break contact with
## the live hazard" over a scene where nobody was in contact with anything.
## Category answers "which beat"; only the phase answers "has it started".
func _display_step(id: StringName) -> ProcedureStep:
	var step: ProcedureStep = Assessment.steps[id]
	var hops := 0
	while step.display_as != &"" and Assessment.steps.has(step.display_as) and hops < 8:
		var next: ProcedureStep = Assessment.steps[step.display_as]
		if next.min_phase >= 0 and int(SimState.phase) < next.min_phase:
			break
		step = next
		hops += 1
	return step


## Whether a step is allowed to be NAMED yet.
##
## `min_phase` started as a guard on the `display_as` redirect above - "do not
## borrow this step''s title before its beat has started". Playtest: "'retrieve
## crook' appears before the incident, not logical." It does, because the
## redirect guard only ever decided which title to show, never whether to show
## one at all: refused the redirect, `crook_retrieved` fell back to its own
## title and the checklist read "› Retrieve the insulated rescue crook" over a
## scene where the worker was still safely at the panel.
##
## `min_phase` now means the plainer thing on the step it is written on: this
## step is not spoken about before that phase. It stays display-only - the step
## is still gradeable, still completable, and a trainee who fetches the crook
## early is neither stopped nor penalised for it. They are simply not told to.
##
## Read by the checklist row and by the bottom-centre pill, which are the only
## two surfaces that name a step.
func _may_name(step: ProcedureStep) -> bool:
	return step.min_phase < 0 or int(SimState.phase) >= step.min_phase


## Seconds for one half of the urgent pill's flash cycle.
const URGENT_FLASH_SECONDS := 0.55


## The urgent treatment: danger-red chip, white text, alpha pulsing. Reserved
## for the break-contact beat, where seconds of delay are the injury itself.
func _set_urgent(on: bool) -> void:
	if _urgent_tween != null and _urgent_tween.is_valid():
		_urgent_tween.kill()
		_urgent_tween = null
	_step_pill.modulate = Color.WHITE
	if on:
		var sb := Tokens.glass_chip(Tokens.RADIUS_LG)
		sb.bg_color = Tokens.DANGER
		_step_pill.add_theme_stylebox_override("panel", sb)
		_step_label.add_theme_color_override("font_color", Color.WHITE)
		_urgent_tween = create_tween().set_loops()
		_urgent_tween.tween_property(_step_pill, "modulate:a", 0.35, URGENT_FLASH_SECONDS)
		_urgent_tween.tween_property(_step_pill, "modulate:a", 1.0, URGENT_FLASH_SECONDS)
	else:
		_step_pill.add_theme_stylebox_override("panel", Tokens.glass_chip(Tokens.RADIUS_LG))
		_step_label.add_theme_color_override("font_color", Tokens.INK)


## The standing preamble label tracks where the kit check is. Naming and
## reviewing ask different things of the trainee, so the reminder says which
## one is in front of them.
func _on_kit_stage_changed(stage: int) -> void:
	if stage == KitBench.Stage.NAMING:
		_kit_label.text = "Name the LVR kit items"
	elif stage == KitBench.Stage.REVIEW:
		_kit_label.text = "Check your list"


## `colour` arrives picked for text floating over the 3D scene — white for
## neutral lines, gold/amber/red for the rest. On the white glass pill the
## neutrals wash out to the faint gray in the bug report and the bright hues
## are barely better, so everything is remapped onto inks that hold contrast
## on white. Callers keep saying what they mean (neutral, attention, warning,
## danger) without knowing what surface the text lands on.
func _on_center_message(text: String, colour: Color, duration: float) -> void:
	_center_message.text = text
	_center_message.add_theme_color_override("font_color", _ink_for_glass(colour))

	if _message_tween != null and _message_tween.is_valid():
		_message_tween.kill()
	_message_tween = create_tween()
	_message_tween.tween_property(_message_pill, "modulate:a", 1.0, 0.25)
	_message_tween.tween_interval(duration)
	_message_tween.tween_property(_message_pill, "modulate:a", 0.0, 0.6)


## White and other low-saturation scene inks have no hue worth keeping —
## darkened they just become the pale gray that started this — so they map to
## the standard dark slate. Saturated colours keep their meaning and are
## darkened only as far as white glass demands.
func _ink_for_glass(colour: Color) -> Color:
	var ink := Color(colour.r, colour.g, colour.b, 1.0)
	if ink.s < 0.2:
		return Tokens.INK

	var luminance := ink.get_luminance()
	if luminance > MESSAGE_MAX_LUMINANCE:
		ink = ink.darkened(1.0 - MESSAGE_MAX_LUMINANCE / luminance)
	return ink
