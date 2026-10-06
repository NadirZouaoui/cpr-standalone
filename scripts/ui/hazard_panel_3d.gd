extends CanvasLayer
## The tick-all-that-apply panel for the hazard assessment. **Full screen.**
##
## It was a diegetic quad floating over the board, picked with the crosshair
## while the mouse stayed captured. It is a screen-space overlay now, driven
## with a real cursor: the list is long prose, and the client asked for it to
## be "a drop down menu so its easier". Eight sentences billboarded at half a
## metre are not that.
##
## What that costs, said plainly: the mouse leaves capture while the list is
## up, which CPR_CONTRACT.md section 4.0 forbids of the *treatment* UI and
## always will. This is not treatment. An assessment list performs nothing at
## all - ticking "wet floor" does not make the floor wet - so nothing here can
## be mis-clicked into an act on the casualty, which is that rule's whole
## reason. The kit naming menu stays diegetic: four short item names over the
## object being named is exactly what that construction is good at.
##
## The panel raises itself as a blocking UI (Events.open_ui), so the Player
## freezes, the interaction ray goes dead and the cursor comes back - the same
## way the kit brief does it. Closing it hands all three back.
##
## A pure view besides, and more strictly than the kit panel is: it deals in
## **indices** and never sees a hazard id or an `is_real` flag.
## HazardAssessment owns every judgement. The panel cannot tell a real hazard
## from a distractor and must never be taught to.
##
## It used to be handed marks to draw - amber for a line that belonged ticked
## and was not, red and struck through for one that was ticked and did not.
## That is gone. Submitting now raises the shared review card, which reads the
## ticked set back and says nothing about it; only the trainee's own
## reconsideration can change it. Marking the lines was the reason the first
## attempt had to be the graded one, and deleting the marks is what makes
## grading the settled answer honest.

## The canvas is drawn at this fixed size and then scaled to the window, so
## every rect the picker, the painter and the headless checks share stays in
## one coordinate system whatever the resolution. Kept as VIEWPORT_SIZE from
## the SubViewport days: the canvas class reads it, and so does
## check_hazard_assessment.
const VIEWPORT_SIZE := Vector2i(1024, 768)

## How much of the window the card fills at most, per axis. The rest is the
## dimmed room, which is what keeps this reading as a panel over the exercise
## rather than as a screen the exercise went away for.
const FILL_FRACTION := 0.92

## Ceiling on the scale-up. Past about 1.6x the pills are banner-sized and the
## list stops reading as a list.
const MAX_SCALE := 1.6

## Our tag on the blocking-UI register. Distinct from the review card's, so the
## two can hand over without the register ever emptying mid-flow.
const UI_NAME := &"hazard_list"

var _root: Control
var _canvas: HazardPanelCanvas

## True while a pass is up. Independent of `visible`: the panel hides while the
## review card is up and is still holding the pass.
var is_open: bool = false
var _options: PackedStringArray = PackedStringArray()
var _aimed: int = -1

## True while `_aimed` was put there by the arrow keys rather than by the
## cursor - see _process().
var _keyboard_aimed: bool = false

## The submit pill's index in the picker's numbering: one past the last option.
var _submit_index: int = -1

## The pass currently up, or &"" when the panel is down. Carried so the
## submission can name the pass it belongs to; never used to decide anything.
var _step_id: StringName = &""

## Whether this panel is the one currently holding the UI register open, so
## open_ui/close_ui stay balanced across a hide-for-the-review-card and back.
var _ui_held: bool = false


func _ready() -> void:
	layer = 21
	_build_overlay()
	visible = false
	set_process(false)

	Events.hazard_question_requested.connect(_on_question_requested)
	Events.review_requested.connect(_on_review_raised)
	Events.hazard_panel_resumed.connect(_on_resumed)
	Events.hazard_answer_recorded.connect(_on_recorded)
	# Nothing may be left over the room once the run moves on.
	Events.simulation_finished.connect(func(_passed, _score): close())

	var viewport := get_viewport()
	if viewport != null:
		viewport.size_changed.connect(_layout)


func _build_overlay() -> void:
	_root = Control.new()
	_root.name = "Screen"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	# STOP, not IGNORE: the dimmed surface is what stops a click meant for a
	# pill from also reaching the world behind it.
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(_on_gui_input)
	add_child(_root)

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Tokens.OVERLAY_DIM
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	_canvas = HazardPanelCanvas.new()
	_canvas.name = "Canvas"
	# Sized outright rather than anchored, and never a mouse target itself:
	# the picking is done in canvas coordinates by _row_at(), which shares
	# _row_rect() with the painter so the two cannot drift.
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.position = Vector2.ZERO
	_canvas.size = Vector2(VIEWPORT_SIZE)
	_root.add_child(_canvas)

	_layout()


## Fit the fixed-size canvas into whatever window it is being shown in, and
## centre it. Scale rather than re-layout: every rect the picker, the painter
## and the headless checks agree on is in design pixels, and re-flowing the
## stack per resolution would put three different geometries in play.
func _layout() -> void:
	if _canvas == null:
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var screen := viewport.get_visible_rect().size
	if screen.x <= 0.0 or screen.y <= 0.0:
		return
	var factor := minf(
		screen.x * FILL_FRACTION / float(VIEWPORT_SIZE.x),
		screen.y * FILL_FRACTION / float(VIEWPORT_SIZE.y))
	factor = clampf(factor, 0.1, MAX_SCALE)
	_canvas.scale = Vector2(factor, factor)
	_canvas.position = (screen - Vector2(VIEWPORT_SIZE) * factor) * 0.5


# =============================================================================
# Open / close
# =============================================================================
## Raise the panel. `anchor` is ignored and kept only because the caller and
## the Events signal still carry one - the diegetic panels this replaced were
## positioned by it, and the choice card and the kit naming menu still are.
func open(step_id: StringName, _anchor: Vector3, heading: String,
		options: PackedStringArray, submit_label: String) -> void:
	_step_id = step_id
	_options = options
	_submit_index = options.size()
	_aimed = -1
	_keyboard_aimed = false
	is_open = true

	_canvas.set_options(options, heading, submit_label)
	_layout()
	_show(true)


func _on_question_requested(step_id: StringName, heading: String,
		options: PackedStringArray, submit_label: String, anchor: Vector3) -> void:
	open(step_id, anchor, heading, options, submit_label)


## Show or hide the overlay, keeping the blocking-UI register balanced with it.
## Everything that raises or drops this panel goes through here: open_ui called
## twice, or close_ui never called, is how a trainee ends up frozen in an empty
## room with a cursor.
func _show(shown: bool) -> void:
	visible = shown
	set_process(shown)
	if shown and not _ui_held:
		_ui_held = true
		Events.open_ui(UI_NAME)
	elif not shown and _ui_held:
		_ui_held = false
		Events.close_ui(UI_NAME)


## The review card for this pass has gone up, so the list stands down. It
## HIDES rather than closes: closing would drop the ticks and the step id, and
## both have to survive a Correct.
##
## Hung off the card going up rather than off this panel's own submit pill,
## because the pill is not the only way a submission reaches HazardAssessment -
## a dev warp or a test emits the signal directly, and a list left drawing
## behind the card would fight it for every click.
##
## It keeps its hold on the blocking-UI register while it is hidden, rather
## than releasing it and letting the card take one out. The register emptying
## for even one frame between the two hands the Player back its freeze and
## re-captures the mouse, and the trainee would see the cursor blink away
## mid-submission. close() is what releases it, and the pass always reaches
## close() - on the recording, on simulation_finished, or on a dev warp.
func _on_review_raised(context: StringName, _heading: String,
		_lines: PackedStringArray, _correct_label: String,
		_confirm_label: String, _anchor: Vector3) -> void:
	if context != _step_id or not is_open:
		return
	visible = false
	set_process(false)
	_aimed = -1
	_keyboard_aimed = false
	_canvas.set_aimed(-1)


## Back from the review card. The ticks go back exactly as the trainee left
## them - the panel clears them on open, so without this a correction would
## start from a blank list and be a fresh assessment rather than a correction.
##
## The stack is NOT relaid out. The trainee is coming back to re-read their own
## list, and every line has to still be where they left it.
func _on_resumed(step_id: StringName, picks: PackedInt32Array) -> void:
	if step_id != _step_id:
		return
	_canvas.set_ticked(picks)
	_show(true)


## The pass closing is the only acknowledgement there is: the panel goes down
## at once, saying nothing about the score. The verdict on a hazard pass
## belongs in the debrief with everything else, and now there are no exceptions
## at all - the review card in between says nothing either.
func _on_recorded(step_id: StringName, _quality: float, _corrected: bool) -> void:
	if step_id == _step_id:
		close()


func close() -> void:
	is_open = false
	_step_id = &""
	_options = PackedStringArray()
	_submit_index = -1
	_aimed = -1
	_keyboard_aimed = false
	_show(false)


# =============================================================================
# Cursor picking
# =============================================================================
## The cursor wins whenever it is ON a pill, and only then.
##
## Polling it unconditionally made the arrow-key path below dead on arrival: the
## pick reports -1 for every frame the pointer is not over a pill, so a
## selection made with the keys was wiped before the trainee could press Enter
## on it. A pre-existing fault from the crosshair days, kept fixed here.
func _process(_delta: float) -> void:
	var hit := _row_at(_root.get_local_mouse_position())
	if hit < 0 and _keyboard_aimed:
		return
	if hit >= 0:
		_keyboard_aimed = false
	if hit != _aimed:
		_aimed = hit
		_canvas.set_aimed(_aimed)


## Screen point -> row index, or -1 between rows. The canvas is drawn at the
## design size and scaled, so the point is mapped back through that scale
## before it is handed to the shared row geometry.
func _row_at(point: Vector2) -> int:
	if not is_open or not visible or _options.is_empty() or _canvas == null:
		return -1
	var factor := _canvas.scale.x
	if factor <= 0.0:
		return -1
	var local := (point - _canvas.position) / factor
	return _canvas.pill_at(local.x, local.y)


## The click. It arrives here rather than in _unhandled_input because the
## dimmed surface is MOUSE_FILTER_STOP and consumes mouse buttons - which is
## the point of it, and also why the world behind cannot be clicked through.
func _on_gui_input(event: InputEvent) -> void:
	if not is_open or not visible:
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var index := _row_at(event.position)
		_root.accept_event()
		if index >= 0:
			_keyboard_aimed = false
			_aimed = index
			_canvas.set_aimed(index)
			_activate(index)


func _unhandled_input(event: InputEvent) -> void:
	if not is_open or not visible or _options.is_empty():
		return

	# Arrow keys and Enter alongside the cursor, so a trainee who would rather
	# not aim still has a plain way to answer. The submit pill is in the same
	# cycle - it is just the last row.
	var last := _submit_index
	if event.is_action_pressed(&"ui_up"):
		get_viewport().set_input_as_handled()
		_keyboard_aimed = true
		_aimed = clampi(_aimed - 1, 0, last) if _aimed >= 0 else last
		_canvas.set_aimed(_aimed)
	elif event.is_action_pressed(&"ui_down"):
		get_viewport().set_input_as_handled()
		_keyboard_aimed = true
		_aimed = clampi(_aimed + 1, 0, last) if _aimed >= 0 else 0
		_canvas.set_aimed(_aimed)
	elif event.is_action_pressed(&"ui_accept") and _aimed >= 0:
		get_viewport().set_input_as_handled()
		_activate(_aimed)


## A pill toggles; the submit row sends. Nothing here decides anything about
## the set that goes out - HazardAssessment puts it to the review card and, if
## the trainee confirms it there, grades it.
func _activate(index: int) -> void:
	if index == _submit_index:
		Events.hazard_answer_submitted.emit(_step_id, _canvas.ticked())
		return
	_canvas.toggle(index)


# =============================================================================
# The drawn pills
# =============================================================================
## All of the panel's pixels, drawn in code - matching the project's
## "no serialised runtime nodes" pattern and CprPanel3D's _PanelCanvas.
##
## One glass pill per option with a tick box on its left, stacked and centred
## on the canvas, and a submit pill under them. Geometry is in design pixels -
## the canvas is scaled to the window as a whole; pill_at() is the inverse map
## the cursor picker uses, and it shares _row_rect() with _draw() so the pick
## maths and the pixels cannot drift.
class HazardPanelCanvas extends Control:
	const PILL_WIDTH := 900.0
	const PILL_HEIGHT := 58.0
	const PILL_GAP := 10.0
	const HEADING_PILL_HEIGHT := 52.0
	const HEADING_PAD_X := 36.0
	const HEADING_GAP := 14.0
	const SUBMIT_GAP := 20.0
	const HEADING_SIZE := 26
	const CHOICE_SIZE := 24

	## Tick box geometry, inside the pill on its left.
	const BOX := 26.0
	const BOX_PAD := 22.0
	const TEXT_PAD := 18.0

	## Every fill here is opaque. The stack sits on a white card now, and a
	## translucent row over a white card is just a paler row - it reads as a
	## disabled control rather than as glass.
	const HOVER_FILL := Color(0.99, 0.85, 0.45, 1.0)
	## Ticked. The ONLY fill that means anything on this panel, and all it
	## means is "you ticked this" - there is no colour here for right or wrong.
	const TICKED_FILL := Color(0.78, 0.92, 0.83, 1.0)
	const SUBMIT_FILL := Color(0.83, 0.90, 0.97, 1.0)

	## Breathing room between the outermost row and the card's edge.
	const CARD_PAD_X := 40.0
	const CARD_PAD_Y := 34.0

	var _options: PackedStringArray = PackedStringArray()
	var _heading: String = ""
	var _submit_label: String = ""
	var _aimed: int = -1
	## index -> true. The trainee's current ticks, and the whole of this
	## panel's state about the answer.
	var _ticked: Dictionary = {}

	var _font: Font = null
	var _card_style: StyleBoxFlat = null
	var _pill_style: StyleBoxFlat = null
	var _aim_style: StyleBoxFlat = null
	var _tick_style: StyleBoxFlat = null
	var _submit_style: StyleBoxFlat = null


	func _ready() -> void:
		_font = ThemeDB.fallback_font
		_card_style = Tokens.card_panel(Tokens.RADIUS_XL)
		_pill_style = Tokens.card_row(Tokens.RADIUS_LG)
		_aim_style = Tokens.card_row(Tokens.RADIUS_LG, HOVER_FILL)
		_tick_style = Tokens.card_row(Tokens.RADIUS_LG, TICKED_FILL)
		_submit_style = Tokens.card_row(Tokens.RADIUS_LG, SUBMIT_FILL)


	func set_options(options: PackedStringArray, heading: String,
			submit_label: String) -> void:
		_options = options
		_heading = heading
		_submit_label = submit_label
		_aimed = -1
		_ticked.clear()
		position = Vector2.ZERO
		size = Vector2(VIEWPORT_SIZE)
		queue_redraw()


	## The ticks, restored whole after a trip to the review card. Only the
	## fills and the tick-box glyphs change - the stack geometry is untouched,
	## because the panel was already anchored in the world against that layout
	## and must not shift under the cursor between the submission and the
	## correction. The trainee is coming back to re-read their own list; every
	## line has to still be where they left it.
	func set_ticked(picks: PackedInt32Array) -> void:
		_ticked.clear()
		for i in picks:
			if i >= 0 and i < _options.size():
				_ticked[i] = true
		queue_redraw()


	func set_aimed(index: int) -> void:
		if index == _aimed:
			return
		_aimed = index
		queue_redraw()


	func toggle(index: int) -> void:
		if index < 0 or index >= _options.size():
			return
		if _ticked.has(index):
			_ticked.erase(index)
		else:
			_ticked[index] = true
		queue_redraw()


	## The ticked set, ascending. This is the whole of what leaves the panel.
	func ticked() -> PackedInt32Array:
		var out: PackedInt32Array = PackedInt32Array()
		for i in _options.size():
			if _ticked.has(i):
				out.append(i)
		return out


	## Viewport pixel -> row index, or -1 between rows. The submit pill is the
	## row one past the last option.
	func pill_at(x: float, y: float) -> int:
		var point := Vector2(x, y)
		for i in _options.size() + 1:
			if _row_rect(i).has_point(point):
				return i
		return -1


	func _pill_size() -> Vector2:
		return Vector2(minf(PILL_WIDTH, size.x - 40.0), PILL_HEIGHT)


	func _text_width(text: String, font_size: int) -> float:
		if _font == null:
			_font = ThemeDB.fallback_font
		return _font.get_string_size(
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


	func _heading_rect() -> Rect2:
		var w := minf(_text_width(_heading, HEADING_SIZE) + HEADING_PAD_X * 2.0,
			size.x - 40.0)
		return Rect2(Vector2((size.x - w) * 0.5, _stack_top()),
			Vector2(w, HEADING_PILL_HEIGHT))


	func _stack_top() -> float:
		return (size.y - _stack_total_px()) * 0.5


	func _stack_total_px() -> float:
		var n := float(_options.size())
		var total := n * PILL_HEIGHT + maxf(n - 1.0, 0.0) * PILL_GAP
		if _heading != "":
			total += HEADING_PILL_HEIGHT + HEADING_GAP
		total += SUBMIT_GAP + PILL_HEIGHT
		return total


	## Row geometry, shared by the picker and the painter. `index` in
	## [0, options) is an option; index == options is the submit pill.
	func _row_rect(index: int) -> Rect2:
		var pill := _pill_size()
		var x := (size.x - pill.x) * 0.5
		var y := _stack_top()
		if _heading != "":
			y += HEADING_PILL_HEIGHT + HEADING_GAP
		if index >= _options.size():
			y += float(_options.size()) * (PILL_HEIGHT + PILL_GAP) - PILL_GAP + SUBMIT_GAP
		else:
			y += float(index) * (PILL_HEIGHT + PILL_GAP)
		return Rect2(Vector2(x, y), pill)


	## The white card the stack sits on, sized to the stack rather than to the
	## canvas: the canvas is a fixed design rectangle, and a card filling it
	## would be a wall of white with the rows lost in the middle of it.
	func _card_rect() -> Rect2:
		var w := _pill_size().x
		if _heading != "":
			w = maxf(w, _heading_rect().size.x)
		return Rect2(
			Vector2((size.x - w) * 0.5 - CARD_PAD_X, _stack_top() - CARD_PAD_Y),
			Vector2(w + CARD_PAD_X * 2.0, _stack_total_px() + CARD_PAD_Y * 2.0))


	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0 or _options.is_empty():
			return
		if _font == null:
			_font = ThemeDB.fallback_font

		draw_style_box(_card_style, _card_rect())

		if _heading != "":
			_draw_heading()

		for i in _options.size():
			_draw_option(i)

		_draw_submit()


	## Set in ink on the card itself rather than in a pill of its own: a pill
	## inside a card reads as one more row, and this one is not a row you tick.
	func _draw_heading() -> void:
		_centred_text(_heading_rect(), _heading, HEADING_SIZE, Tokens.INK)


	func _draw_option(i: int) -> void:
		var rect := _row_rect(i)
		var is_ticked := _ticked.has(i)

		# Three states and no fourth. Aimed at, ticked, or neither - there is no
		# fill on this panel that means right or wrong, and there must not be.
		var style := _pill_style
		if i == _aimed:
			style = _aim_style
		elif is_ticked:
			style = _tick_style
		draw_style_box(style, rect)

		# Tick box on the left, text after it.
		var box := Rect2(
			Vector2(rect.position.x + BOX_PAD, rect.position.y + (PILL_HEIGHT - BOX) * 0.5),
			Vector2(BOX, BOX))
		draw_rect(box, Tokens.CARD_FILL, true)
		draw_rect(box, Tokens.INK, false, 2.0)
		if is_ticked:
			# A tick drawn as two strokes rather than a glyph - the fallback
			# font has no dependable check mark.
			draw_line(box.position + Vector2(5.0, 13.0),
				box.position + Vector2(11.0, 20.0), Tokens.INK, 3.0, true)
			draw_line(box.position + Vector2(11.0, 20.0),
				box.position + Vector2(21.0, 6.0), Tokens.INK, 3.0, true)

		var text_x := box.position.x + BOX + TEXT_PAD
		var metrics := _font.get_string_size(
			_options[i], HORIZONTAL_ALIGNMENT_LEFT, -1, CHOICE_SIZE)
		var baseline := Vector2(text_x,
			rect.position.y + (rect.size.y + metrics.y) * 0.5 - _font.get_descent(CHOICE_SIZE))
		_font.draw_string(get_canvas_item(), baseline, _options[i],
			HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - (text_x - rect.position.x) - BOX_PAD,
			CHOICE_SIZE, Tokens.INK)


	func _draw_submit() -> void:
		var rect := _row_rect(_options.size())
		draw_style_box(
			_aim_style if _aimed == _options.size() else _submit_style, rect)
		_centred_text(rect, _submit_label, CHOICE_SIZE, Tokens.INK)


	## Centred by font metrics, the same arithmetic the casualty pointers use -
	## no width-box alignment to get wrong.
	func _centred_text(rect: Rect2, text: String, font_size: int, colour: Color) -> void:
		var metrics := _font.get_string_size(
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var baseline := rect.position + Vector2(
			(rect.size.x - metrics.x) * 0.5,
			(rect.size.y + metrics.y) * 0.5 - _font.get_descent(font_size))
		_font.draw_string(get_canvas_item(), baseline, text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, colour)
