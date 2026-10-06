extends CanvasLayer
## "How to play" - a practice round before the exercise.
##
## Client feedback, 23 Sep 2026: the tester was not a gamer. The client asked
## for a pre-run: every basic interaction the exercise uses, done for real once
## in the empty room, before anything is timed or graded -
##
##   look, walk, aim, pick a tool up, put it back, click labels, crouch,
##   pause, help.
##
## Hold, compressions and on-screen lists were cut on review: the exercise's
## own prompts teach those at the moment they are needed.
##
## It runs INSTEAD of the opening card on the first launch of a session, with
## the rest of the HUD out of the way, and ends on a centred card with a
## button. That button, or Backspace at any point, reloads the scene exactly as
## "Retry from the start" does, and the run begins properly at the opening
## card. Once per session: the flag lives on Engine meta, so the reload does not
## bring the tutorial back.
##
## Nothing here is assessed. The kit bench is put to sleep for the duration (no
## naming menus, no arrow) and PickupItem.tutorial_sandbox lets the bench tools
## go into the hand and back with no grading side effects. The reload at the
## end throws all of it away.
##
## Never runs headless, so the regression scenes still boot straight into the
## kit check they were written against.

const PointersScript := preload("res://scripts/ui/casualty_pointers.gd")

## Above the HUD (5) and the pills (6), below the centre card (8) and every
## blocking screen.
const LAYER := 7
const READY_UI := &"tutorial_ready"
const DONE_META := &"lvr_tutorial_done"

const CARD_WIDTH := 600.0
const TEXT_WIDTH := 400.0
const TOP_MARGIN := 24.0

## Seconds the green tick shows before the next card.
const ADVANCE_DELAY := 0.9
## A card ignores Space for this long, so one press cannot pass two cards.
const KEY_GUARD := 0.35
const LOOK_TARGET_RAD := 1.4
const WALK_TARGET_M := 2.0

static var running: bool = false
## The `try` of the card on screen. HelpGuide reads it: its chip is hidden for
## the whole tutorial except on the card that teaches it.
static var current_try: StringName = &""


## Whether the tutorial is going to run this launch. KitCheck asks, and holds
## the opening card back if so.
static func will_run() -> bool:
	return not Engine.has_meta(DONE_META) and DisplayServer.get_name() != "headless"


## `try`: what completes the card. `art`: the little picture - mouse, wasd,
## dot, click, label, keys, ready. `keys` lists input actions (StringName) or
## literal key names (String). `last` is the centred closing screen.
const STEPS := [
	{
		"title": "Look around",
		"body": "Move the mouse to look around the room. The arrow keys work too. If the view does not turn, click once on the screen first.",
		"art": "mouse", "try": &"look",
	},
	{
		"title": "Walk",
		"body": "Use W, A, S and D to walk. Hold Shift to go faster.",
		"art": "wasd", "try": &"walk",
	},
	{
		"title": "Aim with the dot",
		"body": "The small dot in the middle of the screen is your pointer. Aim it at a tool on the bench: the tool lights up, and the text under the dot says what a click will do.",
		"art": "dot", "try": &"aim",
	},
	{
		"title": "Pick something up",
		"body": "With a tool lit up, click the LEFT mouse button to pick it up.",
		"art": "click", "try": &"pickup",
	},
	{
		"title": "Put it back",
		"body": "What you are holding shows in the bottom-right corner. Press G to put it back where it was.",
		"art": "keys", "keys": [&"drop"], "try": &"drop",
	},
	{
		"title": "Click the labels",
		"body": "Labels like these appear on the casualty and on some objects. Aim the dot at a label - it turns yellow - and left-click it. Click all three.",
		"art": "label", "try": &"labels",
	},
	{
		"title": "Crouch and kneel",
		"body": "Hold C to crouch down low. Next to the casualty, C kneels you down beside him, and C again stands you back up.",
		"art": "keys", "keys": [&"crouch"], "try": &"crouch",
	},
	{
		"title": "Pause",
		"body": "Press Esc to pause the exercise. To carry on, click Resume.",
		"art": "keys", "keys": ["Esc"], "try": &"pause",
	},
	{
		"title": "Stuck? Press H",
		"body": "Press H at any time. It tells you how to use what is in front of you, and a yellow arrow shows you where. Try it now, then press H again to close it.",
		"art": "keys", "keys": ["H"], "try": &"help",
	},
	{
		"title": "You are ready",
		"body": "That is every control you need. The exercise starts at the opening card, then the rescue kit on the bench. Tab shows or hides your checklist in the top-left corner.",
		"last": true,
	},
]

const LABEL_PILLS := [
	{"id": &"tut_a", "label": "Click this label", "offset": Vector2(-0.55, -0.05)},
	{"id": &"tut_b", "label": "Now this one", "offset": Vector2(0.0, -0.35)},
	{"id": &"tut_c", "label": "And this one", "offset": Vector2(0.55, -0.05)},
]

var _root: Control
var _card: PanelContainer
var _counter: Label
var _title: Label
var _body: Label
var _status: Label
var _footer: Label
var _art_holder: CenterContainer

var _ready_screen: Control
var _ready_counter: Label
var _ready_body: Label
var _ready_button: Button

var _pointers: CanvasLayer
var _markers: Array[Marker3D] = []
var _pending: Array = []

var _index: int = -1
var _succeeded: bool = false
var _since_shown: float = 0.0
var _advance_in: float = -1.0
## Set once H has opened the help card on the H step: this card hides under it,
## and the tutorial moves on when the trainee closes it again.
var _waiting_for_help: bool = false
var _pause_seen: bool = false

var _player: Player = null
var _last_yaw: float = 0.0
var _last_pitch: float = 0.0
var _look_total: float = 0.0
var _last_pos: Vector3 = Vector3.ZERO
var _walk_total: float = 0.0


func _ready() -> void:
	layer = LAYER
	_build()
	_build_ready_screen()
	_root.visible = false
	set_process(false)

	_pointers = PointersScript.new()
	_pointers.name = "TutorialPointers"
	_pointers.interactive = true
	add_child(_pointers)
	_pointers.activated.connect(_on_pill)
	for i in LABEL_PILLS.size():
		var marker := Marker3D.new()
		marker.name = "TutorialAnchor%d" % i
		add_child(marker)
		_markers.append(marker)

	Events.focus_changed.connect(_on_focus_changed)
	Events.phase_changed.connect(_on_phase_changed)
	Events.ui_opened.connect(_on_ui_opened)
	Events.ui_closed.connect(_on_ui_closed)

	if will_run() and SimState.is_preamble():
		start.call_deferred()


func _exit_tree() -> void:
	running = false
	current_try = &""
	PickupItem.tutorial_sandbox = false

# =============================================================================
# Start / stop
# =============================================================================
func start() -> void:
	if running or not SimState.is_preamble():
		return
	running = true
	PickupItem.tutorial_sandbox = true
	_player = get_tree().get_first_node_in_group(&"player") as Player
	_sleep_kit_bench()
	var hud := _sibling(^"Hud")
	if hud != null and hud.has_method("set_minimal"):
		hud.call("set_minimal", true)
	var slot := get_tree().get_first_node_in_group(HandSlot.GROUP) as HandSlot
	if slot != null and not slot.held_changed.is_connected(_on_held_changed):
		slot.held_changed.connect(_on_held_changed)
	_index = -1
	set_process(true)
	_next()


## The bench stays exactly as it is and simply stops answering: no naming menu
## on a click, no arrow over it, [Enter] ignored. The reload at the end builds
## a fresh one.
func _sleep_kit_bench() -> void:
	var bench := _sibling(^"KitBench")
	if bench == null:
		return
	bench.set("_active", false)
	if bench.has_method("_set_bench_live"):
		bench.call("_set_bench_live", false)
	if bench.has_method("_refresh_beacon"):
		bench.call("_refresh_beacon")


## Leaves the tutorial where it stands. The run is not reloaded - this is also
## what a dev warp out of the preamble lands on.
func _stop() -> void:
	running = false
	current_try = &""
	PickupItem.tutorial_sandbox = false
	_root.visible = false
	_pointers.clear()
	set_process(false)
	if _ready_screen.visible:
		_ready_screen.visible = false
		Events.close_ui(READY_UI)
	var hud := _sibling(^"Hud")
	if hud != null and hud.has_method("set_minimal"):
		hud.call("set_minimal", false)


## Finished or skipped: back to the very start, the same teardown as the pause
## menu's "Retry from the start", and the opening card comes up this time.
func _complete() -> void:
	Engine.set_meta(DONE_META, true)
	_stop()
	get_tree().paused = false
	for ui_name in Events.open_uis.keys():
		Events.close_ui(ui_name)
	Assessment.reset()
	SimState.reset()
	Rescuer.reset()
	get_tree().reload_current_scene()


func _on_phase_changed(_previous: int, _current: int) -> void:
	if running and not SimState.is_preamble():
		Engine.set_meta(DONE_META, true)
		_stop()


func _next() -> void:
	_index += 1
	if _index >= STEPS.size():
		_complete()
		return
	_show_step(STEPS[_index])


func _try() -> StringName:
	if _index < 0 or _index >= STEPS.size():
		return &""
	return STEPS[_index].get("try", &"")


func _sibling(path: NodePath) -> Node:
	return get_parent().get_node_or_null(path) if get_parent() != null else null


# =============================================================================
# Frame and input
# =============================================================================
func _process(delta: float) -> void:
	# Hidden while the help card is up: the two share a layer and sit on top of
	# each other otherwise.
	var help_up := _help_card_up()
	_root.visible = running and not Events.is_ui_blocking() and not help_up
	if _waiting_for_help:
		if not help_up:
			_waiting_for_help = false
			_next()
		return
	if not _root.visible:
		return
	_since_shown += delta

	if _advance_in >= 0.0:
		_advance_in -= delta
		if _advance_in < 0.0:
			_next()
		return
	if _succeeded or _player == null:
		return

	match _try():
		&"look":
			var yaw := _player.head.rotation.y
			var pitch := _player.camera.rotation.x
			_look_total += absf(angle_difference(_last_yaw, yaw)) + absf(pitch - _last_pitch)
			_last_yaw = yaw
			_last_pitch = pitch
			if _look_total >= LOOK_TARGET_RAD:
				_succeed()
		&"walk":
			var pos := _player.global_position
			_walk_total += Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length()
			_last_pos = pos
			if _walk_total >= WALK_TARGET_M:
				_succeed()


## _input, not _unhandled_input: Space and Enter are taken before KitBench's
## _unhandled_input could read them as ui_accept ("show me the review"). The
## bench is asleep anyway; this is the belt to that. The closing screen is a
## blocking UI, so its button owns Space and Enter while it is up.
func _input(event: InputEvent) -> void:
	if not running or _index < 0 or _index >= STEPS.size() or Events.is_ui_blocking():
		return
	var trying := _try()

	if event.is_action_pressed(&"crouch") and trying == &"crouch":
		_succeed()
		return

	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return

	if key.keycode == KEY_BACKSPACE:
		get_viewport().set_input_as_handled()
		_complete()
		return

	if key.keycode == KEY_H and trying == &"help" and not _waiting_for_help:
		# Not consumed: HelpGuide opens its card on the same press, which is
		# the lesson. Closing it again is the other half, so the next card
		# waits for that rather than for a timer.
		_succeed()
		_advance_in = -1.0
		_waiting_for_help = true
		return

	var is_space := key.physical_keycode == KEY_SPACE or key.keycode == KEY_SPACE
	var is_enter := key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER
	if not (is_space or is_enter):
		return
	get_viewport().set_input_as_handled()
	if _waiting_for_help or _advance_in >= 0.0 or _since_shown < KEY_GUARD:
		return
	_next()


# =============================================================================
# What completes a card
# =============================================================================
func _on_focus_changed(node: Node) -> void:
	if running and node != null and _try() == &"aim":
		_succeed()


func _on_held_changed(item_id: StringName) -> void:
	if not running:
		return
	match _try():
		&"pickup":
			if item_id != &"":
				_succeed()
		&"drop":
			if item_id == &"":
				_succeed()
			else:
				_status.text = "Now press G to put it back."


func _on_pill(id: StringName) -> void:
	if not running or _try() != &"labels":
		return
	_pending.erase(id)
	_show_pills()
	if _pending.is_empty():
		_succeed()
	else:
		_status.text = "%d to go." % _pending.size()


func _on_ui_opened(ui_name: StringName) -> void:
	if running and _try() == &"pause" and ui_name == &"pause_menu":
		_pause_seen = true


func _on_ui_closed(ui_name: StringName) -> void:
	if running and _try() == &"pause" and ui_name == &"pause_menu" and _pause_seen:
		_succeed()


func _help_card_up() -> bool:
	var guide := _sibling(^"HelpGuide")
	if guide == null:
		return false
	var card: Variant = guide.get("_card")
	return card is Control and (card as Control).visible


func _held() -> StringName:
	var slot := get_tree().get_first_node_in_group(HandSlot.GROUP) as HandSlot
	return slot.held_item_id if slot != null else &""


func _succeed() -> void:
	if _succeeded:
		return
	_succeeded = true
	_status.text = "\u2713  Well done"
	_status.add_theme_color_override("font_color", Tokens.SUCCESS)
	_advance_in = ADVANCE_DELAY

# =============================================================================
# Cards
# =============================================================================
func _show_step(step: Dictionary) -> void:
	_succeeded = false
	_waiting_for_help = false
	_pause_seen = false
	_since_shown = 0.0
	_advance_in = -1.0
	_look_total = 0.0
	_walk_total = 0.0
	_pointers.clear()
	current_try = step.get("try", &"")
	if _player != null:
		_last_yaw = _player.head.rotation.y
		_last_pitch = _player.camera.rotation.x
		_last_pos = _player.global_position

	var counter := "HOW TO PLAY  \u00b7  %d of %d" % [_index + 1, STEPS.size()]
	if step.get("last", false):
		_open_ready_screen(counter, String(step["body"]))
		return

	_counter.text = counter
	_title.text = String(step["title"])
	_body.text = String(step["body"])
	_status.add_theme_color_override("font_color", Tokens.WARNING)
	_status.text = "Try it now."
	_footer.text = "[Space]  Skip this one        [Backspace]  Skip the tutorial"

	for child in _art_holder.get_children():
		child.queue_free()
	_art_holder.add_child(_make_art(step))

	match current_try:
		&"pickup":
			if _held() != &"":
				_succeed()
		&"drop":
			if _held() == &"":
				_status.text = "Pick a tool up first, then press G."
		&"labels":
			_place_markers()
			_pending = []
			for pill in LABEL_PILLS:
				_pending.append(pill["id"])
			_show_pills()


## Hangs the practice labels in the air in front of wherever the trainee is
## looking, so every one of them starts on screen.
func _place_markers() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var basis := cam.global_basis
	var base := cam.global_position - basis.z * 1.8
	for i in LABEL_PILLS.size():
		var off: Vector2 = LABEL_PILLS[i]["offset"]
		_markers[i].global_position = base + basis.x * off.x + basis.y * off.y


func _show_pills() -> void:
	var callouts: Array = []
	for i in LABEL_PILLS.size():
		var pill: Dictionary = LABEL_PILLS[i]
		if _pending.has(pill["id"]):
			callouts.append({"id": pill["id"], "node": _markers[i], "label": pill["label"]})
	if callouts.is_empty():
		_pointers.clear()
	else:
		_pointers.set_callouts(callouts)


## The closing card: centred, with a button. A blocking UI, so the mouse
## pointer comes back to click it and the player stands still under it.
func _open_ready_screen(counter: String, body: String) -> void:
	current_try = &""
	_ready_counter.text = counter
	_ready_body.text = body
	_ready_screen.visible = true
	Events.open_ui(READY_UI)
	_ready_button.grab_focus()


# =============================================================================
# Construction
# =============================================================================
func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", Tokens.glass_panel())
	_card.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_card.offset_left = 0
	_card.offset_right = 0
	_card.offset_top = TOP_MARGIN
	_card.offset_bottom = TOP_MARGIN
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.grow_vertical = Control.GROW_DIRECTION_END
	_card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_card)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(row)

	_art_holder = CenterContainer.new()
	_art_holder.custom_minimum_size = Vector2(160, 120)
	_art_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_art_holder)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(column)

	_counter = _label("", Tokens.FONT_SM, Tokens.ACCENT)
	column.add_child(_counter)
	_title = _label("", Tokens.FONT_XL, Tokens.INK)
	column.add_child(_title)
	_body = _label("", Tokens.FONT_MD, Tokens.INK_MUTED)
	column.add_child(_body)
	_status = _label("", Tokens.FONT_MD, Tokens.WARNING)
	column.add_child(_status)
	_footer = _label("", Tokens.FONT_SM, Tokens.INK_FAINT)
	column.add_child(_footer)


## Its own Control, not under _root: _root hides whenever a blocking UI is up,
## and this is one.
func _build_ready_screen() -> void:
	_ready_screen = Control.new()
	_ready_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ready_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	_ready_screen.visible = false
	add_child(_ready_screen)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Tokens.OVERLAY_DIM
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ready_screen.add_child(dim)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ready_screen.add_child(centre)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Tokens.card_panel())
	centre.add_child(card)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.custom_minimum_size = Vector2(480, 0)
	card.add_child(column)

	var art_row := CenterContainer.new()
	art_row.add_child(Art.new("ready"))
	column.add_child(art_row)

	_ready_counter = _centred(_label("", Tokens.FONT_SM, Tokens.ACCENT))
	column.add_child(_ready_counter)
	column.add_child(_centred(_label("You are ready", Tokens.FONT_XL, Tokens.INK)))
	_ready_body = _centred(_label("", Tokens.FONT_MD, Tokens.INK_MUTED))
	column.add_child(_ready_body)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(footer)
	_ready_button = Button.new()
	_ready_button.text = "Start the exercise"
	_ready_button.focus_mode = Control.FOCUS_ALL
	_ready_button.add_theme_font_size_override("font_size", Tokens.FONT_MD)
	Tokens.style_button(_ready_button, &"primary")
	_ready_button.pressed.connect(_complete)
	footer.add_child(_ready_button)


func _centred(l: Label) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _label(text: String, size: int, colour: Color) -> Label:
	var l := Tokens.make_label(text, size, colour)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(TEXT_WIDTH, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _make_art(step: Dictionary) -> Control:
	var art: String = step.get("art", "")
	if art == "wasd":
		var column := VBoxContainer.new()
		column.alignment = BoxContainer.ALIGNMENT_CENTER
		column.add_theme_constant_override("separation", 6)
		var top := HBoxContainer.new()
		top.alignment = BoxContainer.ALIGNMENT_CENTER
		top.add_child(_key_cap(_key_name(&"move_forward", "W")))
		column.add_child(top)
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 6)
		for pair in [[&"move_left", "A"], [&"move_backward", "S"], [&"move_right", "D"]]:
			row.add_child(_key_cap(_key_name(pair[0], pair[1])))
		column.add_child(row)
		return column
	if art == "keys":
		var keys := HBoxContainer.new()
		keys.alignment = BoxContainer.ALIGNMENT_CENTER
		keys.add_theme_constant_override("separation", 10)
		for k in step.get("keys", []):
			var text: String = _key_name(k, String(k)) if k is StringName else String(k)
			keys.add_child(_key_cap(text))
		return keys
	return Art.new(art)


## The first key an action is bound to, as the trainee would read it.
func _key_name(action: StringName, fallback: String) -> String:
	if not InputMap.has_action(action):
		return fallback
	var shown := CprStation.key_name_for(action)
	return fallback if shown == "" or shown == String(action) else shown


func _key_cap(text: String) -> Control:
	var cap := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.WHITE
	sb.border_color = Tokens.INK_FAINT
	sb.set_border_width_all(2)
	sb.border_width_bottom = 5
	sb.set_corner_radius_all(Tokens.RADIUS_SM + 2)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	cap.add_theme_stylebox_override("panel", sb)
	cap.custom_minimum_size = Vector2(44, 44)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Tokens.make_label(text, Tokens.FONT_MD, Tokens.INK)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.add_child(l)
	return cap


# =============================================================================
# Pictures
# =============================================================================
## Small animated drawings, made in code so nothing has to be imported.
class Art extends Control:
	var kind: String = ""
	var _t: float = 0.0

	func _init(k: String) -> void:
		kind = k
		custom_minimum_size = Vector2(150, 110)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		match kind:
			"mouse":
				_mouse(false, true)
			"click":
				_mouse(true, false)
			"dot":
				_dot()
			"label":
				_label_pill()
			"ready":
				_tick()

	func _box(rect: Rect2, fill: Color, radius: int, border: Color = Color(0, 0, 0, 0), width: int = 0) -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = fill
		sb.set_corner_radius_all(radius)
		if width > 0:
			sb.border_color = border
			sb.set_border_width_all(width)
		draw_style_box(sb, rect)

	func _mouse(left_on: bool, wiggle: bool) -> void:
		var c := size * 0.5
		var off := Vector2(sin(_t * 2.4) * 16.0, 0.0) if wiggle else Vector2.ZERO
		var body := Rect2(c + off - Vector2(26, 40), Vector2(52, 76))
		_box(body, Color.WHITE, 26)
		if left_on:
			var glow := 0.55 + 0.45 * sin(_t * 6.0)
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(Tokens.ATTENTION, glow)
			sb.corner_radius_top_left = 24
			draw_style_box(sb, Rect2(body.position + Vector2(3, 3), Vector2(23, 28)))
		var outline := StyleBoxFlat.new()
		outline.draw_center = false
		outline.border_color = Tokens.INK
		outline.set_border_width_all(3)
		outline.set_corner_radius_all(26)
		draw_style_box(outline, body)
		var split_y := body.position.y + 31.0
		draw_line(Vector2(body.position.x + 2, split_y), Vector2(body.end.x - 2, split_y), Tokens.INK, 2.0)
		draw_line(Vector2(body.get_center().x, body.position.y + 2), Vector2(body.get_center().x, split_y), Tokens.INK, 2.0)
		if wiggle:
			for side in [-1.0, 1.0]:
				var tip := Vector2(c.x + side * 66.0, c.y)
				var pts := PackedVector2Array([tip, tip + Vector2(-side * 12.0, -9.0), tip + Vector2(-side * 12.0, 9.0)])
				draw_colored_polygon(pts, Tokens.INK_FAINT)

	func _dot() -> void:
		_box(Rect2(Vector2(4, 8), size - Vector2(8, 16)), Color("#334155"), 10)
		var box := Rect2(Vector2(size.x * 0.58, size.y * 0.38), Vector2(40, 30))
		var phase := clampf(fmod(_t, 3.0) / 3.0 * 1.6, 0.0, 1.0)
		var dot := Vector2(lerpf(size.x * 0.2, box.get_center().x, phase), box.get_center().y)
		var on := box.has_point(dot)
		_box(box, Color("#cbd5e1"), 6, Tokens.ATTENTION, 3 if on else 0)
		draw_circle(dot, 5.0, Tokens.ATTENTION if on else Color.WHITE)

	func _label_pill() -> void:
		_box(Rect2(Vector2(4, 8), size - Vector2(8, 16)), Color("#334155"), 10)
		var spot := Vector2(size.x * 0.35, size.y * 0.74)
		draw_circle(spot, 6.0, Color("#94a3b8"))
		var font := get_theme_default_font()
		var text := "Click this label"
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.FONT_SM).x
		var pill := Rect2(Vector2((size.x - w) * 0.5 - 10.0, 20.0), Vector2(w + 20.0, 24.0))
		draw_line(spot, Vector2(pill.get_center().x, pill.end.y), Color.WHITE, 1.5, true)
		var lit := fmod(_t, 2.0) > 1.0
		_box(pill, Color.WHITE, 12, Tokens.ATTENTION, 3 if lit else 0)
		draw_string(font, pill.position + Vector2(10.0, 17.0), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, Tokens.FONT_SM, Tokens.INK)

	func _tick() -> void:
		var c := size * 0.5
		draw_circle(c, 40.0, Tokens.SUCCESS)
		draw_polyline(PackedVector2Array([c + Vector2(-18, 0), c + Vector2(-5, 13), c + Vector2(19, -13)]), Color.WHITE, 6.0, true)