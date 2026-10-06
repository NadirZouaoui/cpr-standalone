extends CanvasLayer
## The review-and-confirm card. **One panel, two callers, full screen.**
##
## The client asked for the same thing twice - for the bag, "if incorrect
## should be able to correct at that stage with the correction noted", and for
## the hazards the same shape - so the kit check and the hazard assessment
## share this node rather than each growing their own. The controller submits
## a set, this reads it back, and the trainee either goes back to change it or
## locks it in.
##
## It was a diegetic quad picked with the crosshair. It is a screen-space
## overlay now, driven with a real cursor, for the same reason the hazard list
## is (hazard_panel_3d.gd): a read-back can run to every object on the bench,
## and a list that long belongs on the screen rather than billboarded over it.
## It also has to match whatever raised it - a full-screen list that submitted
## into a floating card would re-capture the mouse mid-answer.
##
## Construction is hazard_panel_3d.gd's, verbatim where it can be: a fixed
## design-size canvas drawn in code, scaled to the window, picked in canvas
## coordinates, and raised as a blocking UI so the Player freezes and the
## cursor comes back.
##
## **Nothing on this card says which picks are right or wrong.** It is handed
## strings and it draws them. It has no answer key, no marks, no colours that
## mean anything, and it must never be taught any: the read-back is the
## trainee's own answer in their own words, and the verdict on it belongs in
## the debrief with every other verdict in this exercise. That is what makes
## the correction worth grading at all - a card that named the wrong lines
## would make fixing them free, which is exactly why the old first-attempt
## rule existed.
##
## The one thing it differs from the hazard panel on: **the read-back lines are
## not controls.** They are drawn plain and cannot be aimed at. Only the two
## action pills at the foot pick up, so there is no way to fiddle with the
## answer while it is being confirmed - Correct is the way back to the picking,
## and it is the only way back.

## The canvas is drawn at this fixed size and then scaled to the window, so
## every rect the picker, the painter and the headless checks share stays in
## one coordinate system whatever the resolution.
const VIEWPORT_SIZE := Vector2i(1024, 768)

## How much of the window the card fills at most, per axis.
const FILL_FRACTION := 0.92

## Ceiling on the scale-up, as on the hazard list.
const MAX_SCALE := 1.6

## Our tag on the blocking-UI register. Distinct from the hazard list's, so the
## two can hand over without the register ever emptying mid-flow.
const UI_NAME := &"review_card"

## Action pill indices, in the order they are drawn and cycled.
const ACTION_CORRECT := 0
const ACTION_CONFIRM := 1

var _root: Control
var _canvas: ReviewPanelCanvas

## True while a review is up.
var is_open: bool = false

## The caller currently being served, or &"" when the card is down. Echoed
## back on the answer; never used to decide anything.
var _context: StringName = &""

var _aimed: int = -1

## True while `_aimed` was put there by the arrow keys rather than by the
## cursor, so the per-frame poll leaves it alone until the pointer finds
## something of its own.
var _keyboard_aimed: bool = false

## Whether this card is currently holding the UI register open.
var _ui_held: bool = false


func _ready() -> void:
	layer = 22
	_build_overlay()
	visible = false
	set_process(false)

	Events.review_requested.connect(_on_review_requested)
	# Nothing may be left up once the run moves on, whichever way it moved: the
	# kit check's card is up during the preamble and the hazard card during the
	# exercise, so both seams matter.
	Events.simulation_started.connect(close)
	Events.simulation_finished.connect(func(_passed, _score): close())

	var viewport := get_viewport()
	if viewport != null:
		viewport.size_changed.connect(_layout)


func _build_overlay() -> void:
	_root = Control.new()
	_root.name = "Screen"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	# STOP, not IGNORE: the dimmed surface is what stops a click meant for an
	# action pill from also reaching the world behind it.
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(_on_gui_input)
	add_child(_root)

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Tokens.OVERLAY_DIM
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	_canvas = ReviewPanelCanvas.new()
	_canvas.name = "Canvas"
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.position = Vector2.ZERO
	_canvas.size = Vector2(VIEWPORT_SIZE)
	_root.add_child(_canvas)

	_layout()


## Fit the fixed-size canvas into whatever window it is being shown in, and
## centre it. Scale rather than re-layout, so the picker, the painter and the
## checks all keep agreeing about where a pill is.
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
## Raise the card. `lines` is the trainee's answer read back, already worded.
## `anchor` is ignored and kept only because the Events signal still carries
## one for the diegetic panels that still use theirs.
func open(context: StringName, _anchor: Vector3, heading: String,
		lines: PackedStringArray, correct_label: String,
		confirm_label: String) -> void:
	_context = context
	_aimed = -1
	_keyboard_aimed = false
	is_open = true

	_canvas.set_review(lines, heading, correct_label, confirm_label)
	_layout()
	_show(true)


func _on_review_requested(context: StringName, heading: String,
		lines: PackedStringArray, correct_label: String, confirm_label: String,
		anchor: Vector3) -> void:
	open(context, anchor, heading, lines, correct_label, confirm_label)


## Show or hide the overlay, keeping the blocking-UI register balanced with it.
func _show(shown: bool) -> void:
	visible = shown
	set_process(shown)
	if shown and not _ui_held:
		_ui_held = true
		Events.open_ui(UI_NAME)
	elif not shown and _ui_held:
		_ui_held = false
		Events.close_ui(UI_NAME)


func close() -> void:
	is_open = false
	_context = &""
	_aimed = -1
	_keyboard_aimed = false
	_show(false)


# =============================================================================
# Cursor picking
# =============================================================================
## The cursor wins whenever it is ON something, and only then - otherwise a
## selection made with the arrow keys is wiped by the next idle frame before
## the trainee can press Enter on it.
func _process(_delta: float) -> void:
	var hit := _action_at(_root.get_local_mouse_position())
	if hit < 0 and _keyboard_aimed:
		return
	if hit >= 0:
		_keyboard_aimed = false
	if hit != _aimed:
		_aimed = hit
		_canvas.set_aimed(_aimed)


## Screen point -> action index, or -1. The read-back lines are deliberately
## not in this numbering: they are not controls.
func _action_at(point: Vector2) -> int:
	if not is_open or not visible or _canvas == null:
		return -1
	var factor := _canvas.scale.x
	if factor <= 0.0:
		return -1
	var local := (point - _canvas.position) / factor
	return _canvas.action_at(local.x, local.y)


## The click. It arrives here rather than in _unhandled_input because the
## dimmed surface is MOUSE_FILTER_STOP and consumes mouse buttons.
func _on_gui_input(event: InputEvent) -> void:
	if not is_open or not visible:
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var index := _action_at(event.position)
		_root.accept_event()
		if index >= 0:
			_keyboard_aimed = false
			_aimed = index
			_canvas.set_aimed(index)
			_activate(index)


func _unhandled_input(event: InputEvent) -> void:
	if not is_open or not visible:
		return

	# Left/right and Enter alongside the cursor, so a trainee who would rather
	# not aim still has a plain way to answer. The two actions sit side by
	# side, so the horizontal pair is the one that matches the layout.
	if event.is_action_pressed(&"ui_left"):
		get_viewport().set_input_as_handled()
		_keyboard_aimed = true
		_aimed = ACTION_CORRECT
		_canvas.set_aimed(_aimed)
	elif event.is_action_pressed(&"ui_right"):
		get_viewport().set_input_as_handled()
		_keyboard_aimed = true
		_aimed = ACTION_CONFIRM
		_canvas.set_aimed(_aimed)
	elif event.is_action_pressed(&"ui_accept") and _aimed >= 0:
		get_viewport().set_input_as_handled()
		_activate(_aimed)


## The card goes down on either answer and the controller decides what happens
## next: Correct puts the trainee back in front of their picks with everything
## still as they left it, Confirm locks the set in and grades it.
func _activate(action: int) -> void:
	var context := _context
	var confirmed := action == ACTION_CONFIRM
	close()
	Events.review_answered.emit(context, confirmed)


# =============================================================================
# The drawn card
# =============================================================================
## All of the card's pixels, drawn in code - matching the project's
## "no serialised runtime nodes" pattern and HazardPanelCanvas, which this is a
## near copy of. Geometry is in design pixels; action_at() is the inverse map
## the cursor picker uses, and it shares _action_rect() with _draw() so the
## pick maths and the pixels cannot drift.
##
## The one piece of geometry this has and the hazard panel does not: the whole
## stack scales down when the read-back is long. A kit review can run to every
## object on the bench, which at the hazard panel's fixed metrics is taller
## than the canvas and simply falls off the bottom.
class ReviewPanelCanvas extends Control:
	const PILL_WIDTH := 900.0
	const PILL_HEIGHT := 52.0
	const PILL_GAP := 8.0
	const HEADING_PILL_HEIGHT := 56.0
	const HEADING_PAD_X := 36.0
	const HEADING_GAP := 16.0
	const ACTION_GAP := 24.0
	const ACTION_SPLIT := 20.0
	const HEADING_SIZE := 26
	const LINE_SIZE := 24

	## Bullet marker geometry, inside the pill on its left. A dot, not a tick
	## box: these lines are a read-back, not a control, and a box invites a
	## click that does nothing.
	const DOT := 8.0
	const DOT_PAD := 30.0
	const TEXT_PAD := 20.0

	## Opaque, like the hazard list: the card underneath is white, and a
	## translucent row on white reads as a disabled control, not as glass.
	const HOVER_FILL := Color(0.99, 0.85, 0.45, 1.0)
	## The two actions are drawn differently, but along the axis of what they
	## DO - go back and edit, or submit - not along right and wrong. Suggesting
	## an answer here is the same mistake as marking the lines, and the pair
	## carries no opinion about the ticks above it. Submit is the filled one
	## because it is the way out of the card, not because it is the good one.
	const ACTION_FILL := Color(0.83, 0.90, 0.97, 1.0)
	## Going back is the quiet one: the card's own row colour, so it reads as
	## a step backwards into the list rather than as a second submit.
	const BACK_FILL := Color("#e8edf3")

	## Breathing room between the outermost row and the card's edge. Scaled
	## with everything else vertical, so a long read-back still fits.
	const CARD_PAD_X := 40.0
	const CARD_PAD_Y := 34.0

	## Smallest gap the card keeps from the edge of the canvas.
	const CARD_EDGE := 8.0

	## Never let the stack scale below this, however long the read-back is -
	## below it the text is unreadable at working distance and the caller
	## should be paging instead.
	const MIN_SCALE := 0.45

	var _lines: PackedStringArray = PackedStringArray()
	var _heading: String = ""
	var _correct_label: String = ""
	var _confirm_label: String = ""
	var _aimed: int = -1

	## Uniform shrink applied to every vertical metric and both font sizes when
	## the stack would not otherwise fit the canvas. 1.0 for short reviews.
	var _scale: float = 1.0

	var _font: Font = null
	var _card_style: StyleBoxFlat = null
	var _pill_style: StyleBoxFlat = null
	var _aim_style: StyleBoxFlat = null
	var _action_style: StyleBoxFlat = null
	var _back_style: StyleBoxFlat = null


	func _ready() -> void:
		_font = ThemeDB.fallback_font
		_card_style = Tokens.card_panel(Tokens.RADIUS_XL)
		_pill_style = Tokens.card_row(Tokens.RADIUS_LG)
		_aim_style = Tokens.card_row(Tokens.RADIUS_LG, HOVER_FILL)
		_action_style = Tokens.card_row(Tokens.RADIUS_LG, ACTION_FILL)
		_back_style = Tokens.card_row(Tokens.RADIUS_LG, BACK_FILL)


	func set_review(lines: PackedStringArray, heading: String,
			correct_label: String, confirm_label: String) -> void:
		_lines = lines
		_heading = heading
		_correct_label = correct_label
		_confirm_label = confirm_label
		_aimed = -1
		position = Vector2.ZERO
		size = Vector2(VIEWPORT_SIZE)
		_recompute_scale()
		queue_redraw()


	func set_aimed(index: int) -> void:
		if index == _aimed:
			return
		_aimed = index
		queue_redraw()


	# -- Geometry ------------------------------------------------------------
	## Everything vertical goes through here, so one factor shrinks the whole
	## card consistently and the picker cannot disagree with the painter.
	func _px(v: float) -> float:
		return v * _scale


	func _recompute_scale() -> void:
		_scale = 1.0
		var wanted := _stack_total_px()
		var room := size.y - 48.0
		if wanted > room and wanted > 0.0:
			_scale = maxf(room / wanted, MIN_SCALE)


	func _pill_size() -> Vector2:
		return Vector2(minf(PILL_WIDTH, size.x - 40.0), _px(PILL_HEIGHT))


	func _stack_total_px() -> float:
		var n := float(_lines.size())
		var total := n * _px(PILL_HEIGHT) + maxf(n - 1.0, 0.0) * _px(PILL_GAP)
		if _heading != "":
			total += _px(HEADING_PILL_HEIGHT) + _px(HEADING_GAP)
		total += _px(ACTION_GAP) + _px(PILL_HEIGHT)
		return total


	func _stack_top() -> float:
		return (size.y - _stack_total_px()) * 0.5


	func _text_width(text: String, font_size: int) -> float:
		if _font == null:
			_font = ThemeDB.fallback_font
		return _font.get_string_size(
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


	func _heading_size() -> int:
		return maxi(int(round(HEADING_SIZE * _scale)), 12)


	func _line_size() -> int:
		return maxi(int(round(LINE_SIZE * _scale)), 11)


	func _heading_rect() -> Rect2:
		var w := minf(_text_width(_heading, _heading_size()) + HEADING_PAD_X * 2.0,
			size.x - 40.0)
		return Rect2(Vector2((size.x - w) * 0.5, _stack_top()),
			Vector2(w, _px(HEADING_PILL_HEIGHT)))


	## One read-back line's pill. Not pickable - see action_at().
	func _line_rect(index: int) -> Rect2:
		var pill := _pill_size()
		var x := (size.x - pill.x) * 0.5
		var y := _stack_top()
		if _heading != "":
			y += _px(HEADING_PILL_HEIGHT) + _px(HEADING_GAP)
		y += float(index) * (_px(PILL_HEIGHT) + _px(PILL_GAP))
		return Rect2(Vector2(x, y), pill)


	## The two action pills, side by side on the last row: 0 Correct, 1
	## Confirm. Shared by the picker and the painter.
	func _action_rect(index: int) -> Rect2:
		var pill := _pill_size()
		var x := (size.x - pill.x) * 0.5
		var y := _stack_top()
		if _heading != "":
			y += _px(HEADING_PILL_HEIGHT) + _px(HEADING_GAP)
		var n := float(_lines.size())
		y += maxf(n * (_px(PILL_HEIGHT) + _px(PILL_GAP)) - _px(PILL_GAP), 0.0)
		y += _px(ACTION_GAP)
		var half := (pill.x - ACTION_SPLIT) * 0.5
		var left := x if index == ACTION_CORRECT else x + half + ACTION_SPLIT
		return Rect2(Vector2(left, y), Vector2(half, _px(PILL_HEIGHT)))


	## Viewport pixel -> action index, or -1. The read-back lines are absent on
	## purpose: aiming at one must do nothing at all.
	func action_at(x: float, y: float) -> int:
		var point := Vector2(x, y)
		for i in 2:
			if _action_rect(i).has_point(point):
				return i
		return -1


	# -- Painting ------------------------------------------------------------
	## The white card the read-back sits on - see the same method on the hazard
	## list. Sized to the stack, not to the canvas.
	func _card_rect() -> Rect2:
		var w := _pill_size().x
		if _heading != "":
			w = maxf(w, _heading_rect().size.x)
		# The vertical padding is the one metric that can push the card off the
		# canvas: a read-back long enough to be scaled down still leaves only
		# 24px above the stack. Clamped rather than shrunk, so the padding
		# stays honest on every shorter card.
		var top := maxf(_stack_top() - _px(CARD_PAD_Y), CARD_EDGE)
		var bottom := minf(_stack_top() + _stack_total_px() + _px(CARD_PAD_Y),
			size.y - CARD_EDGE)
		return Rect2(
			Vector2((size.x - w) * 0.5 - CARD_PAD_X, top),
			Vector2(w + CARD_PAD_X * 2.0, bottom - top))


	func _draw() -> void:
		if size.x <= 0.0 or size.y <= 0.0:
			return
		if _font == null:
			_font = ThemeDB.fallback_font

		draw_style_box(_card_style, _card_rect())

		if _heading != "":
			_draw_heading()

		for i in _lines.size():
			_draw_line_pill(i)

		_draw_action(ACTION_CORRECT, _correct_label)
		_draw_action(ACTION_CONFIRM, _confirm_label)


	## Set in ink on the card rather than in a pill of its own: a pill inside a
	## card reads as one more read-back line.
	func _draw_heading() -> void:
		_centred_text(_heading_rect(), _heading, _heading_size(), Tokens.INK)


	## Plain, always. One style, one colour, no marks - the card is the
	## trainee's own answer read back to them and says nothing about it.
	func _draw_line_pill(i: int) -> void:
		var rect := _line_rect(i)
		draw_style_box(_pill_style, rect)

		var dot := _px(DOT)
		draw_circle(
			Vector2(rect.position.x + _px(DOT_PAD), rect.position.y + rect.size.y * 0.5),
			dot * 0.5, Tokens.INK_MUTED)

		var font_size := _line_size()
		var text_x := rect.position.x + _px(DOT_PAD) + dot + _px(TEXT_PAD)
		var metrics := _font.get_string_size(
			_lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var baseline := Vector2(text_x,
			rect.position.y + (rect.size.y + metrics.y) * 0.5 - _font.get_descent(font_size))
		_font.draw_string(get_canvas_item(), baseline, _lines[i],
			HORIZONTAL_ALIGNMENT_LEFT,
			rect.size.x - (text_x - rect.position.x) - _px(DOT_PAD),
			font_size, Tokens.INK)


	func _draw_action(index: int, label: String) -> void:
		var rect := _action_rect(index)
		var style := _back_style if index == ACTION_CORRECT else _action_style
		draw_style_box(_aim_style if _aimed == index else style, rect)
		var ink: Color = Tokens.INK_MUTED if index == ACTION_CORRECT else Tokens.INK
		_centred_text(rect, label, _line_size(), ink if _aimed != index else Tokens.INK)


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
