extends CanvasLayer
## Full-screen terminal failure.
##
## `Events.fatal_violation` was already being emitted and Assessment was
## already recording it - nothing was showing it. This is the missing half:
## it takes over the screen, stops the world, and ends the session.
##
## Deliberately terminal. A fatal contact is not something the trainee
## recovers from mid-run; the LVR rule only means anything if breaking it
## ends the exercise. The only way on is out: the run is reported as a fail
## and the session closes. Retrying is the LMS's call, not this screen's —
## same reasoning as the debrief, which also has no restart.
##
## Runs on PROCESS_MODE_ALWAYS so it still animates and still takes input
## after the tree is paused.

## Pause the simulation behind the overlay. Off is useful when debugging a
## fatality that needs the animation to keep running underneath.
@export var pause_on_fail: bool = true

var _dim: ColorRect
var _title: Label
var _reason: Label
var _hint: Label
var _root: Control
var _armed: bool = false
var _exit_button: Button


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.visible = false
	Events.fatal_violation.connect(_on_fatal_violation)


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	# Neutral scene dim rather than the old red wash: the card carries the
	# failure colour now, and a neutral dim keeps the room readable behind it.
	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(Tokens.OVERLAY_DIM.r, Tokens.OVERLAY_DIM.g, Tokens.OVERLAY_DIM.b, 0.0)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_dim)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(centre)

	# One frosted card, same family as the pause menu and the kit check, so a
	# fatality does not look like it came out of a different product.
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Tokens.glass_panel(Tokens.RADIUS_XL))
	card.custom_minimum_size = Vector2(620, 0)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(card)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(column)

	_title = _label("EXERCISE FAILED", Tokens.FONT_XL, Tokens.DANGER)
	column.add_child(_title)

	# Hairline rule in the failure colour - the one bit of chrome that says
	# "terminal" without reaching for a full red screen.
	var rule := ColorRect.new()
	rule.color = Color(Tokens.DANGER.r, Tokens.DANGER.g, Tokens.DANGER.b, 0.35)
	rule.custom_minimum_size = Vector2(0, 2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rule)

	# The fatality messages are two sentences; the card width gives them room
	# to wrap instead of running edge to edge across the screen.
	_reason = _label("", Tokens.FONT_MD, Tokens.INK)
	column.add_child(_reason)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_exit_button = Button.new()
	_exit_button.text = "Exit and submit"
	_exit_button.custom_minimum_size = Vector2(180, 40)
	_exit_button.focus_mode = Control.FOCUS_ALL
	_exit_button.add_theme_font_size_override("font_size", Tokens.FONT_MD)
	Tokens.style_button(_exit_button, &"primary")
	_exit_button.pressed.connect(_on_exit)
	row.add_child(_exit_button)
	column.add_child(row)

	_hint = _label("Your result has been recorded.", Tokens.FONT_SM, Tokens.INK_FAINT)
	column.add_child(_hint)


func _label(text: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# =============================================================================
# Failure
# =============================================================================
func _on_fatal_violation(reason: String) -> void:
	# Assessment also listens to this signal. Guard so a second emission
	# cannot restart the fade or double-report to the LMS.
	if _root.visible:
		return

	_reason.text = reason
	_root.visible = true
	_root.modulate.a = 0.0
	# The whole card — reason, button, hint — is up from the first frame and
	# fades in as one; the button takes presses immediately.
	_armed = true

	# Give the mouse back before pausing, or the trainee is stuck looking
	# at a screen they cannot click.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if pause_on_fail:
		get_tree().paused = true

	Events.close_ui(&"hud")
	Events.open_ui(&"fail_screen")

	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_root, "modulate:a", 1.0, 0.35)
	tween.parallel().tween_property(_dim, "color:a", Tokens.OVERLAY_DIM.a, 0.35)

	_report()


## A fatality is a fail regardless of how much of the checklist was ticked,
## so the score goes out as zero rather than as the partial total.
func _report() -> void:
	Events.simulation_finished.emit(false, 0)
	Lms.report_result(false, 0, Assessment.transcript_as_text())
	Lms.commit()


## Ends the session on the first press — the run is already over and
## reported, so there is nothing left to confirm. Only the pause menu's quit
## keeps a two-step, because that one interrupts a live exercise.
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
