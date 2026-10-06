extends CanvasLayer
## Bottom-left key hint for the CPR phase.
##
## The stand-up control is the one thing in the phase a trainee cannot discover
## by looking at the world: every other action is the crosshair plus interact,
## which the reticle and the hover tooltips already teach. Standing up is a
## keypress with nothing on screen pointing at it, and it gates two states, so
## it gets a persistent corner hint rather than another centre message competing
## with the instructions.
##
## Reads the binding from the InputMap rather than hard-coding a letter, so a
## rebound key is never misreported.
##
## Visible for the whole CPR phase and nothing else. Styled off Tokens like the
## rest of the HUD so it reads as part of the same interface.
##
## Instanced by CprStation._build(). Nothing else references it.

const ACTION := &"crouch"
const MARGIN := 24

var _chip: PanelContainer = null
var _label: Label = null
## True between cpr_phase_entered and cpr_completed.
var _active: bool = false


func _ready() -> void:
	layer = 5  # same layer as the HUD's own chips
	_build()
	visible = false
	Events.cpr_phase_entered.connect(_on_cpr_phase_entered)
	Events.cpr_completed.connect(_on_cpr_completed)
	Events.ui_opened.connect(func(_n): _sync())
	Events.ui_closed.connect(func(_n): _sync())


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_chip = PanelContainer.new()
	_chip.add_theme_stylebox_override("panel", Tokens.glass_chip())
	_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Anchored to the bottom-left corner and grown up/right from it, so the
	# chip sizes to its own text at any viewport size.
	_chip.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_chip.grow_horizontal = Control.GROW_DIRECTION_END
	_chip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_chip.position = Vector2(MARGIN, -MARGIN)
	root.add_child(_chip)

	_label = Tokens.make_label(_hint_text(), Tokens.FONT_MD, Tokens.INK)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip.add_child(_label)


## "[C] Crouch / stand up", with whatever key the action actually carries.
##
## InputEvent.as_text() renders a physical binding as "C (Physical)", which is
## engine bookkeeping and not something to show a trainee. The keycode is read
## directly instead.
func _hint_text() -> String:
	return "[%s]  Crouch / stand up" % CprStation.key_name_for(ACTION)


func _on_cpr_phase_entered() -> void:
	_label.text = _hint_text()  # re-read in case the binding changed mid-session
	_active = true
	_sync()


func _on_cpr_completed(_metrics: Dictionary) -> void:
	_active = false
	_sync()


## Hidden behind any blocking UI, matching how hud.gd hides its own root — a
## corner chip floating over the pause menu or the kit check reads as a bug.
func _sync() -> void:
	visible = _active and not Events.is_ui_blocking()
