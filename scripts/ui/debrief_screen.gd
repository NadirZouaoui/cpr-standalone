extends CanvasLayer
## End-of-exercise debrief — the success counterpart to `fail_screen.gd`.
##
## `Events.cpr_completed` was the last thing that happened in the run: the
## camera was released and the trainee was left standing in the room with no
## result. This takes over the screen, grades the whole checklist through
## Assessment, reports to the LMS and offers a restart.
##
## Only the fatal path goes through FailScreen. A non-fatal run still reaches
## this screen even when it did not pass — a debrief that only shows up on a
## win teaches nothing.
##
## Runs on PROCESS_MODE_ALWAYS so it animates and takes input while the tree
## is paused, exactly like the fail screen.

## Seconds between `cpr_completed` and the screen appearing, so the last
## compression and the centre prompt land before the world stops.
@export var appear_delay: float = 1.8

## Pause the simulation behind the overlay.
@export var pause_on_finish: bool = true

## Two sequence columns need the room: the correct order on the left, the
## trainee's actual order on the right, both readable without wrapping every
## second title. The checklist still scrolls for the rest.
const CARD_WIDTH := 880
const EDGE_MARGIN := 28
const CHECKLIST_HEIGHT := 240

## The three columns, under their own headings: what was done, when, and what
## the grader made of it. Everything ahead of Action - the sequence number and
## the status glyph - is gutter, sized once here so the headings sit exactly
## over the cells they name.
const NUM_WIDTH := 22
const GLYPH_WIDTH := 32
const TIME_WIDTH := 48
## Observation carries the longest strings on the screen ("after: Isolate the
## circuit at the breaker"), so it takes a real share of the width rather than
## whatever Action leaves behind. Both trim with an ellipsis and keep the full
## text as a tooltip.
const OBSERVATION_MIN_WIDTH := 260
## Time and Observation are both text on a pale ground, and at the row
## separation they ran together into one sentence - "00:06 late" read as a
## single phrase rather than two columns. This is the gutter that tells them
## apart, applied identically to the headings so the table stays square.
const COLUMN_GAP := 34
const TITLE_MIN_WIDTH := 180
const ROW_SEPARATION := 8

## One line per row, tight. Rows are separated by a hairline rather than by
## whitespace: the rule does the work of the gap at a fifth of the height, so
## more of the run fits on screen without the list reading as a solid block.
const ROW_HEIGHT := 19
const ROW_LINE_ALPHA := 0.15
const HEADER_LINE_ALPHA := 0.30

## The sequence rows are read as a list, not as headings: one notch below body
## size and in the lighter font cut, so nineteen step titles stacked in two
## columns scan cleanly instead of reading as a wall of bold.
const STEP_FONT := Tokens.FONT_SM

var _dim: ColorRect
var _root: Control
var _column: VBoxContainer
var _hint: Label
var _armed: bool = false
var _exit_button: Button
var _shown: bool = false
var _metrics: Dictionary = {}
var _scroll: ScrollContainer


func _ready() -> void:
	layer = 99
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_shell()
	_root.visible = false
	Events.cpr_completed.connect(_on_cpr_completed)
	# A fatality is terminal and FailScreen owns that screen; make sure a
	# late cpr_completed cannot stack a debrief on top of it.
	Events.fatal_violation.connect(_on_fatal_violation)


# =============================================================================
# Shell
# =============================================================================
func _build_shell() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(Tokens.OVERLAY_DIM.r, Tokens.OVERLAY_DIM.g, Tokens.OVERLAY_DIM.b, 0.0)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_dim)

	# The card used to sit in a bare CenterContainer, which hands a child its
	# minimum size and lets it run off the screen — at 648p the checklist ran
	# past the bottom edge and took the buttons with it. A MarginContainer fits
	# its child to its own rect instead, so the card can never be taller than
	# the viewport less the margin, and the checklist inside absorbs the squeeze.
	var frame := MarginContainer.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	for edge in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		frame.add_theme_constant_override(edge, EDGE_MARGIN)
	_root.add_child(frame)

	var card := PanelContainer.new()
	# The shared glass card pads for prose. This screen is a dense report and
	# every row of padding pushes the checklist further off the bottom edge, so
	# it takes the same skin with tighter content margins.
	var skin := Tokens.glass_panel(Tokens.RADIUS_XL)
	skin.content_margin_left = 20
	skin.content_margin_right = 20
	skin.content_margin_top = 14
	skin.content_margin_bottom = 14
	card.add_theme_stylebox_override("panel", skin)
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.add_child(card)

	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 5)
	card.add_child(_column)


func _rule(colour: Color, alpha: float = 0.35) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(colour.r, colour.g, colour.b, alpha)
	r.custom_minimum_size = Vector2(0, 2)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _centred(text: String, size: int, colour: Color) -> Label:
	var l := Tokens.make_label(text, size, colour)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# =============================================================================
# Finish
# =============================================================================
func _on_fatal_violation(_reason: String) -> void:
	_shown = true


func _on_cpr_completed(metrics: Dictionary) -> void:
	if _shown:
		return
	_shown = true
	_metrics = metrics
	# A real timer rather than a tween, created with process_always so the
	# delay still elapses if something else pauses the tree first.
	var timer := get_tree().create_timer(appear_delay, true, false, true)
	timer.timeout.connect(_show)


func _show() -> void:
	_populate()

	_root.visible = true
	_root.modulate.a = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if pause_on_finish:
		get_tree().paused = true

	Events.close_ui(&"hud")
	Events.open_ui(&"debrief")

	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_root, "modulate:a", 1.0, 0.35)
	tween.parallel().tween_property(_dim, "color:a", Tokens.OVERLAY_DIM.a, 0.35)
	tween.tween_callback(_arm)

	_report()


func _arm() -> void:
	_armed = true
	if _exit_button != null:
		_exit_button.disabled = false


func _report() -> void:
	var passed := Assessment.is_passed()
	var score := Assessment.score_percent()
	Events.simulation_finished.emit(passed, score)
	Lms.report_result(passed, score, Assessment.transcript_as_text())
	Lms.commit()


# =============================================================================
# Content
# =============================================================================
func _populate() -> void:
	for child in _column.get_children():
		_column.remove_child(child)
		child.queue_free()

	var passed := Assessment.is_passed()
	var score := Assessment.score_percent()
	var accent: Color = Tokens.SUCCESS if passed else Tokens.WARNING

	_column.add_child(_centred(
		"EXERCISE COMPLETE" if passed else "EXERCISE NOT PASSED",
		Tokens.FONT_LG, accent))
	_column.add_child(_rule(accent))

	var mark: int = Assessment.procedure.pass_mark if Assessment.procedure != null else 80
	_column.add_child(_centred("%d%%   ·   pass mark %d%%" % [score, mark],
		Tokens.FONT_MD, Tokens.INK))
	_column.add_child(_centred(
		"Elapsed %s   ·   %d of %d steps completed" % [
			Assessment.format_time(SimState.elapsed),
			Assessment.completed.size(),
			Assessment.order.size(),
		], Tokens.FONT_SM, Tokens.INK_MUTED))

	# A critical step can fail the run two ways, and the headline has to say
	# which: "missed" for one that was never done, "out of order" for one that
	# was done but before its prerequisites. Telling a trainee a step they
	# performed was missed teaches nothing.
	var critical := Assessment.failed_critical()
	if not critical.is_empty():
		var missed: Array[String] = []
		var reordered: Array[String] = []
		for id in critical:
			if Assessment.completed.has(id):
				reordered.append(String(Assessment.steps[id].title))
			else:
				missed.append(String(Assessment.steps[id].title))
		if not missed.is_empty():
			_column.add_child(_centred("Critical step(s) missed: " + ", ".join(missed),
				Tokens.FONT_SM, Tokens.DANGER))
		if not reordered.is_empty():
			_column.add_child(_centred(
				"Critical step(s) performed out of order: " + ", ".join(reordered),
				Tokens.FONT_SM, Tokens.WARNING))

	_column.add_child(_metrics_row())
	_column.add_child(_rule(Tokens.INK_FAINT, 0.20))
	_column.add_child(_checklist())
	_column.add_child(_legend())

	_column.add_child(_footer())


## The CPR quality numbers the checklist cannot carry: Assessment grades a
## step as done or not done, so depth/rate/pad accuracy would otherwise only
## exist in the transcript.
func _metrics_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER

	var tiles := [
		["Compressions", "%d" % int(_metrics.get("total_compressions", 0))],
		["In depth", "%.0f%%" % (float(_metrics.get("pct_in_depth", 0.0)) * 100.0)],
		["In rate", "%.0f%%" % (float(_metrics.get("pct_in_rate", 0.0)) * 100.0)],
		["Pads correct", "%d / 2" % int(_metrics.get("pads_correct", 0))],
		["Time to shock", Assessment.format_time(float(_metrics.get("time_to_shock", 0.0)))],
	]
	for t in tiles:
		var tile := PanelContainer.new()
		var chip := Tokens.glass_chip(Tokens.RADIUS_MD)
		chip.content_margin_left = 12
		chip.content_margin_right = 12
		chip.content_margin_top = 5
		chip.content_margin_bottom = 5
		tile.add_theme_stylebox_override("panel", chip)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		var value := Tokens.make_label(String(t[1]), Tokens.FONT_MD, Tokens.INK)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var caption := Tokens.make_label(String(t[0]), Tokens.FONT_SM, Tokens.INK_MUTED)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(value)
		col.add_child(caption)
		tile.add_child(col)
		row.add_child(tile)

	if not bool(_metrics.get("assisted", false)):
		return row

	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 6)
	wrap.add_child(row)
	wrap.add_child(_centred(
		"Compression fast-forward was used — this run was not a full set.",
		Tokens.FONT_SM, Tokens.WARNING))
	return wrap


## The bottom half of the card: the procedure as authored on the left, the
## trainee's actual sequence on the right, so an out-of-order run can be read
## against the answer key line by line. One scrollbar sits between the panels
## and drives both — a scrollbar at the card edge would only float on top of
## the right column's timestamps.
func _checklist() -> Control:
	## One list, in the order the trainee actually did things.
	##
	## It used to be two: the answer key on the left, the run on the right,
	## aligned row for row. Diffing two nineteen-row lists by eye is work the
	## screen should be doing, and the alignment actively misled - a step could
	## land on the same row number in both columns while being out of order,
	## which reads as "I did that exactly right". The ordering information now
	## lives on the rows that need it, as arrows and a plain-language reason.
	_scroll = _scroll_panel(_sequence_column("What you did", _trainee_rows()))
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.custom_minimum_size = Vector2(0, CHECKLIST_HEIGHT)
	_scroll.clip_contents = true
	return _scroll


func _scroll_panel(content: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(content)
	return scroll


## The list: a heading row, then one row per action, hairline-separated.
func _sequence_column(header: String, rows: Array) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var caption := Tokens.make_light_label(header, STEP_FONT, Tokens.INK_MUTED)
	caption.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	col.add_child(caption)

	col.add_child(_column_headings())
	col.add_child(_hairline(HEADER_LINE_ALPHA))

	for i in rows.size():
		col.add_child(rows[i])
		# No trailing rule: a line under the last row reads as a row that
		# failed to render.
		if i < rows.size() - 1:
			col.add_child(_hairline(ROW_LINE_ALPHA))
	return col


## Column headings, built through the same shell as the rows so each one sits
## over its own cell however the widths are retuned.
func _column_headings() -> Control:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", ROW_SEPARATION)
	line.custom_minimum_size = Vector2(0, ROW_HEIGHT)

	var pad := Control.new()
	pad.custom_minimum_size = Vector2(NUM_WIDTH + GLYPH_WIDTH + ROW_SEPARATION, ROW_HEIGHT)
	line.add_child(pad)

	line.add_child(_heading_cell("Action", TITLE_MIN_WIDTH, HORIZONTAL_ALIGNMENT_LEFT, true))
	line.add_child(_heading_cell("Time", TIME_WIDTH, HORIZONTAL_ALIGNMENT_RIGHT, false))
	line.add_child(_gutter())
	line.add_child(_heading_cell(
		"Observation", OBSERVATION_MIN_WIDTH, HORIZONTAL_ALIGNMENT_LEFT, true))
	return line


## Fixed blank column between Time and Observation.
func _gutter() -> Control:
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(COLUMN_GAP, ROW_HEIGHT)
	return pad


func _heading_cell(
		text: String, width: int, align: HorizontalAlignment, expand: bool) -> Label:
	var cell := Tokens.make_light_label(text, STEP_FONT, Tokens.INK_FAINT)
	cell.custom_minimum_size = Vector2(width, ROW_HEIGHT)
	cell.horizontal_alignment = align
	cell.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if expand:
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return cell


## A hairline between rows. Kept at one pixel and very low alpha: it is there
## to stop the eye sliding between rows, not to draw a table.
func _hairline(alpha: float) -> ColorRect:
	var line := ColorRect.new()
	line.color = Color(Tokens.INK_FAINT, alpha)
	line.custom_minimum_size = Vector2(0, 1)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return line


## One row of the list: fixed height, fixed gutters, so the marks and the
## timestamps line up down the page however long the titles are.
func _row_shell(seq: int) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", ROW_SEPARATION)
	line.custom_minimum_size = Vector2(0, ROW_HEIGHT)

	var num := Tokens.make_light_label("%d." % seq, STEP_FONT, Tokens.INK_FAINT)
	num.custom_minimum_size = Vector2(NUM_WIDTH, ROW_HEIGHT)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(num)
	return line


## The status glyph slot. Wide enough for a mark and an arrow beside it -
## "!" says the step was wrong, the arrow says which way it needed to move.
func _row_glyph(mark: String, colour: Color) -> Label:
	var glyph := Tokens.make_light_label(mark, STEP_FONT, colour)
	glyph.custom_minimum_size = Vector2(GLYPH_WIDTH, ROW_HEIGHT)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return glyph


## Titles are single-line and trimmed rather than wrapped, so every row is the
## same height and the list scans as a column. With one list instead of two
## there is room for the reason to sit inline after the title; the full text
## stays available as a tooltip either way.
func _row_title(text: String, colour: Color) -> Label:
	var title := Tokens.make_light_label(text, STEP_FONT, colour)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.clip_text = true
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.custom_minimum_size = Vector2(TITLE_MIN_WIDTH, ROW_HEIGHT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.tooltip_text = text
	return title


## What the trainee actually did, in the order they did it. Completed and
## failed steps interleave by timestamp; anything never resolved trails the
## sequence in authoring order so it stays visible.
func _trainee_rows() -> Array:
	var rows: Array = []
	var seq := 0
	for e in _trainee_entries():
		seq += 1
		rows.append(_trainee_row(seq, e))
	return rows


func _trainee_entries() -> Array:
	var entries: Array = []
	for id in Assessment.completed:
		entries.append({"id": id, "at": float(Assessment.completed[id]["at"]), "failed": false})
	for id in Assessment.failures:
		entries.append({"id": id, "at": float(Assessment.failures[id]["at"]), "failed": true})
	entries.sort_custom(func(a, b): return float(a["at"]) < float(b["at"]))
	for id in Assessment.order:
		if not Assessment.is_resolved(id):
			entries.append({"id": id, "at": -1.0, "failed": false})
	return entries


## A step that jumped its prerequisites reads "! ↓" - it happened too early,
## so it needs to move down the list. The prerequisite it overtook reads a
## faint "↑" with no "!": that step is the other half of one swap, not a second
## mistake, and marking it as an error would double-count a single transposition
## and put a warning on a row where nothing was done wrong.
##
## "Late" keeps a bare "!" and no arrow. It was in the right place in the
## sequence and simply took too long, so there is no direction to point.
##
## Observation is deliberately terse - "After: Isolate the circuit at the
## breaker" rather than a sentence. The arrow has already said which way the
## step has to move, so the column only has to name the other end of the swap.
func _trainee_row(seq: int, e: Dictionary) -> Control:
	var id: StringName = e["id"]
	var step: ProcedureStep = Assessment.steps[id]
	var mark := "—"
	var colour: Color = Tokens.INK_FAINT
	var stamp := ""
	var note := "Not attempted"
	var observation := ""

	if bool(e["failed"]):
		mark = "✕"
		colour = Tokens.DANGER
		note = String(Assessment.failures[id]["reason"])
		observation = note
		stamp = Assessment.format_time(float(e["at"]))
	elif float(e["at"]) >= 0.0:
		var entry: Dictionary = Assessment.completed[id]
		stamp = Assessment.format_time(float(entry["at"]))
		var overtook := Assessment.performed_before(id)
		var overtaken_by := Assessment.overtaken_by(id)

		if entry["out_of_order"]:
			mark = "!  ↓"
			colour = Tokens.WARNING
			observation = "After: %s" % _titles_of(overtook)
			note = "Out of order — should come after %s" % _titles_of(overtook)
		elif entry["late"]:
			mark = "!"
			colour = Tokens.WARNING
			observation = "Late"
			note = "Late"
		elif not overtaken_by.is_empty():
			# Correct in itself; it was simply overtaken by a row above.
			mark = "↑"
			colour = Tokens.INK_MUTED
			observation = "Before: %s" % _titles_of(overtaken_by)
			note = "Should have come before %s" % _titles_of(overtaken_by)
		else:
			mark = "✓"
			colour = Tokens.SUCCESS
			note = "In order"

		# Scored below full marks for how it was done rather than when - see
		# Assessment.complete()'s quality factor.
		if Assessment.is_partial(id):
			var pct := int(round(Assessment.quality_of(id) * 100.0))
			var quality_text := "%d%% quality" % pct
			observation = quality_text if observation == "" 				else "%s · %s" % [observation, quality_text]
			note = "%s · scored %d%% for quality" % [note, pct]
			if mark == "✓":
				colour = Tokens.WARNING

	var line := _row_shell(seq)
	line.add_child(_row_glyph(mark, colour))

	# Critical steps are starred: the score alone does not explain why a run
	# with a high percentage still did not pass.
	var title_text := step.title + ("  *" if step.critical else "")
	var title := _row_title(title_text, Tokens.INK_FAINT if mark == "—" else Tokens.INK)
	title.tooltip_text = "%s — %s" % [title_text, note]
	line.add_child(title)

	var time_cell := Tokens.make_light_label(stamp, STEP_FONT, Tokens.INK_MUTED)
	time_cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	time_cell.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	time_cell.custom_minimum_size = Vector2(TIME_WIDTH, ROW_HEIGHT)
	line.add_child(time_cell)
	line.add_child(_gutter())

	var obs := Tokens.make_light_label(observation, STEP_FONT, colour)
	obs.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	obs.autowrap_mode = TextServer.AUTOWRAP_OFF
	obs.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	obs.clip_text = true
	obs.custom_minimum_size = Vector2(OBSERVATION_MIN_WIDTH, ROW_HEIGHT)
	obs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	obs.tooltip_text = note
	line.add_child(obs)

	return line


## Step titles for a list of ids, joined for a one-line reason.
func _titles_of(ids: Array) -> String:
	var names: Array[String] = []
	for id in ids:
		if Assessment.steps.has(id):
			names.append(String(Assessment.steps[id].title))
	return ", ".join(names)


## A one-line key for the glyph column. With the per-row "out of order" text
## gone, this is where the marks are explained.
func _legend() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for pair in [
		["✓ in order", Tokens.SUCCESS],
		["!↓ too early", Tokens.WARNING],
		["↑ overtaken", Tokens.INK_MUTED],
		["! late", Tokens.WARNING],
		["✕ error", Tokens.DANGER],
		["— not attempted", Tokens.INK_FAINT],
		["*  critical", Tokens.INK_MUTED],
	]:
		row.add_child(Tokens.make_light_label(String(pair[0]), STEP_FONT, pair[1]))
	return row


# =============================================================================
# Footer
# =============================================================================
## One way out, deliberately. There is no retry from this screen and no [R]
## shortcut: by the time it is up the trainee has seen the score, the pass mark
## and every step they missed, so a second attempt from here would be graded
## against an answer key they have already read. Re-attempts are the LMS's call,
## not something the debrief hands out.
func _footer() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER

	_exit_button = _button("Exit and submit", &"primary", _on_exit)
	# Held inert until the fade-in finishes, so a click already in flight when
	# the screen appears cannot end the session by accident.
	_exit_button.disabled = not _armed
	row.add_child(_exit_button)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 3)
	stack.add_child(row)
	_hint = _centred(
		"Your result has been recorded.", Tokens.FONT_SM, Tokens.INK_FAINT
	)
	stack.add_child(_hint)
	return stack


func _button(text: String, kind: StringName, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(160, 34)
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", Tokens.FONT_MD)
	Tokens.style_button(b, kind)
	b.pressed.connect(handler)
	return b


## Ends the session on the first press — the run is finished and already
## reported to the LMS, so there is nothing left to confirm. Only the pause
## menu's quit keeps a two-step, because that one interrupts a live exercise.
func _on_exit() -> void:
	if not _armed:
		return

	Lms.set_value("cmi.core.exit", "")
	Lms.commit()
	Lms.quit_session()

	if OS.has_feature("web"):
		# A page cannot close itself, so say the session is over rather than
		# leaving a dead screen behind.
		_show_session_ended()
	else:
		get_tree().paused = false
		get_tree().quit()


func _show_session_ended() -> void:
	for child in _root.get_children():
		if child != _dim:
			child.queue_free()

	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text = "Exercise closed.\nYour result has been sent to the LMS.\nYou can close this window."
	label.add_theme_font_size_override("font_size", Tokens.FONT_LG)
	label.add_theme_color_override("font_color", Color.WHITE)
	_root.add_child(label)
