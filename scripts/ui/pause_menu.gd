extends CanvasLayer
## Pause overlay: resume, retry, quit.
##
## Built in code and spawned by main.gd rather than authored into main.tscn.
## The room is rebuilt wholesale on every .blend reimport and the editor has
## previously dropped properties out of main.tscn on a stale save, so
## anything the exercise cannot run without lives in script.
##
## Runs on PROCESS_MODE_ALWAYS: it is the thing that pauses the tree, so it
## has to keep processing and taking input after it has done so.
##
## It does not touch the mouse or freeze the player directly. Opening a
## blocking UI through Events is enough - Player._sync_frozen() already
## releases the pointer on ui_opened and recaptures it on ui_closed, and the
## HUD already hides itself. One mechanism, not three.

const UI_NAME := StringName("pause_menu")
const PANEL_WIDTH := 420

var _root: Control
var _dim: ColorRect
var _quit_button: Button
var _quit_hint: Label
var _resume_button: Button

## Quit ends the LMS session, so it asks twice. Reset every time the menu
## closes - a trainee who armed it, resumed, and paused again later should
## not find a live quit button under their cursor.
var _quit_armed: bool = false

## Browser only: the callback scorm_shell.html calls when the browser, not the
## game, took the pointer lock away. Held so it is not freed while registered.
var _lock_lost_cb: JavaScriptObject


func _ready() -> void:
	layer = 90  # Above the HUD (5), below the fail screen (100).
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.visible = false
	if OS.has_feature("web"):
		_lock_lost_cb = JavaScriptBridge.create_callback(_on_browser_took_lock)
		var window := JavaScriptBridge.get_interface("window")
		if window != null:
			window.lvrOnLockLost = _lock_lost_cb


func _exit_tree() -> void:
	if _lock_lost_cb != null:
		var window := JavaScriptBridge.get_interface("window")
		if window != null:
			window.lvrOnLockLost = null


## Browser: the browser taking the pointer lock IS the pause.
##
## Client, 23 Sep 2026: "friction in the browser between Escape and mouse
## clicks." In the SCORM iframe Escape is the browser's: it drops the pointer
## lock and usually swallows the keydown, so the game was left running with a
## loose cursor, no menu, and a first click that only re-locked the pointer.
## Now the browser dropping the lock - Escape, alt-tab, a click outside the
## frame - opens this menu, and the Resume button (a real click, which the
## browser needs before it will lock the pointer again) is the way back.
##
## Only the browser's release counts, never the game's own. This used to
## watch Input.mouse_mode for any fall from captured, and the game frees the
## cursor itself all the time - the CPR camera taking over at the casualty,
## the AED going down, the shock button - so each of those paused the
## exercise. The shell can tell the two apart and calls this only for the
## browser's; see scorm_shell.html. Deferred because it arrives from inside a
## browser event, not from a frame.
func _on_browser_took_lock(_args: Array) -> void:
	_open_after_lock_loss.call_deferred()


func _open_after_lock_loss() -> void:
	if not is_open() and not Events.is_ui_blocking():
		open()


func is_open() -> bool:
	return _root != null and _root.visible


# =============================================================================
# Input
# =============================================================================
## Escape is the obvious binding and P is the one that survives the browser:
## in a SCORM iframe, Escape releases the pointer lock and the keydown is
## swallowed before the canvas ever sees it.
func _unhandled_input(event: InputEvent) -> void:
	var wants_toggle := event.is_action_pressed(&"ui_cancel")
	if not wants_toggle and event is InputEventKey and event.pressed and not event.echo:
		wants_toggle = event.keycode == KEY_P or event.keycode == KEY_ESCAPE
	if not wants_toggle:
		return

	get_viewport().set_input_as_handled()
	if is_open():
		# In the browser Escape cannot take the menu down: a keypress of
		# Escape is not a gesture the browser will re-lock the pointer on, so
		# closing here left the game running with a loose cursor. Resume (a
		# click) or P closes it.
		if OS.has_feature("web") and event is InputEventKey \
				and (event as InputEventKey).keycode == KEY_ESCAPE:
			return
		close()
	else:
		open()


# =============================================================================
# Open / close
# =============================================================================
func open() -> void:
	if is_open():
		return

	# A fatal contact is terminal by design. Letting the trainee pause out of
	# the fail screen and resume would undo the only thing that makes the
	# no-bare-contact rule mean anything.
	if Events.open_uis.has(&"fail_screen"):
		return

	_root.visible = true
	_set_quit_armed(false)
	get_tree().paused = true
	Events.open_ui(UI_NAME)
	Events.log_action(&"session", "Exercise paused", &"info", "")

	# Grab focus so the menu is keyboard-drivable on a locked-down machine
	# where the pointer never reliably locks to the iframe.
	_resume_button.grab_focus()


func close() -> void:
	if not is_open():
		return
	_root.visible = false
	_set_quit_armed(false)
	get_tree().paused = false
	Events.close_ui(UI_NAME)


# =============================================================================
# Actions
# =============================================================================
## Same teardown as the fail screen's restart, plus a sweep of any UI that
## was on screen when the trainee paused. Without the sweep, pausing out of
## the kit check and retrying reloads the scene with `kit_check` still
## registered as open, which leaves the fresh run frozen with a loose cursor.
func _on_retry() -> void:
	_root.visible = false
	get_tree().paused = false

	for ui_name in Events.open_uis.keys():
		Events.close_ui(ui_name)

	Assessment.reset()
	SimState.reset()
	Rescuer.reset()
	# Release the pointer lock before reload so the browser can grant a new one
	# when the opening card's button is clicked in the fresh scene. Without this
	# the mouse stays captured across the scene reload on Web and the begin
	# button is unreachable (requires a raw pointer-lock request, which the
	# browser only grants on a click gesture, not on page-load).
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().reload_current_scene()


func _on_quit() -> void:
	if not _quit_armed:
		_set_quit_armed(true)
		return

	# Do not overwrite a verdict that has already gone out. If the debrief or
	# the fail screen reported first, that result stands; this is only for a
	# trainee who walks away mid-exercise.
	if not Lms.sent.has("cmi.core.lesson_status"):
		Lms.set_value("cmi.core.lesson_status", "incomplete")
	Lms.set_value("cmi.core.exit", "")
	Lms.commit()
	Lms.quit_session()

	if OS.has_feature("web"):
		# The browser will not let the page close itself, so say so rather
		# than freezing on a menu that no longer does anything.
		_show_session_ended()
	else:
		get_tree().quit()


func _set_quit_armed(armed: bool) -> void:
	_quit_armed = armed
	if _quit_button == null:
		return
	_quit_button.text = "Confirm quit" if armed else "Quit"
	_style_button(_quit_button, &"danger")
	_quit_hint.visible = armed


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


# =============================================================================
# Construction
# =============================================================================
func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.color = Tokens.OVERLAY_DIM
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_dim)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(centre)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	panel.add_theme_stylebox_override("panel", Tokens.glass_panel())
	centre.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", Tokens.FONT_XL)
	title.add_theme_color_override("font_color", Tokens.INK)
	column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "The exercise clock is stopped."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", Tokens.FONT_SM)
	subtitle.add_theme_color_override("font_color", Tokens.INK_MUTED)
	column.add_child(subtitle)

	column.add_child(_spacer(8))

	_resume_button = _make_button("Resume", &"primary", _on_resume)
	column.add_child(_resume_button)

	var retry := _make_button("Retry from the start", &"dark", _on_retry)
	column.add_child(retry)

	_quit_button = _make_button("Quit", &"danger", _on_quit)
	column.add_child(_quit_button)

	_quit_hint = Label.new()
	_quit_hint.text = "This ends the session and sends your result to the LMS."
	_quit_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quit_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quit_hint.custom_minimum_size = Vector2(PANEL_WIDTH - 60, 0)
	_quit_hint.add_theme_font_size_override("font_size", Tokens.FONT_SM)
	_quit_hint.add_theme_color_override("font_color", Tokens.DANGER)
	_quit_hint.visible = false
	column.add_child(_quit_hint)

	var hint := Label.new()
	# In the browser Escape only opens it: see _unhandled_input().
	hint.text = "Click Resume or press [P]" if OS.has_feature("web") else "[Esc] or [P] to resume"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", Tokens.FONT_SM)
	hint.add_theme_color_override("font_color", Tokens.INK_MUTED)
	column.add_child(hint)


func _on_resume() -> void:
	close()


func _spacer(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _make_button(text: String, kind: StringName, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", Tokens.FONT_MD)
	_style_button(b, kind)
	b.pressed.connect(handler)
	return b


func _style_button(b: Button, kind: StringName) -> void:
	Tokens.style_button(b, kind)
