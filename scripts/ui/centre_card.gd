class_name CentreCard
extends CanvasLayer
## A glass card in the middle of the screen, for the one or two beats that are
## announcements rather than instructions.
##
## The HUD already has a centre message: a small pill above the bottom edge,
## used for every piece of transient feedback in the run - "the circuit is still
## live", "no pulse, start compressions", a nudge at the breaker. That pill is
## the right shape for a receipt. It is the wrong shape for the end of the
## exercise.
##
## Playtest: "make the 'ambulance coming' a center screen card." The handover is
## the one moment the trainee does not act - the siren runs, the lights wash the
## edges of the frame, and everything they were doing is finished. Announcing
## that in the same furniture as "you pressed the wrong thing" made the closing
## beat read as one more piece of feedback that happened to be last.
##
## Pure presentation. Nothing here blocks input or freezes the player: the card
## is a thing on screen, not a modal, and the run continues under it. It sits
## above the HUD and below the blocking screens, so the debrief covers it when
## the phase ends.

## Above the HUD (3) and the body pointers (6), below the full-screen assessment
## panels and the debrief.
const LAYER := 8

const FADE_IN := 0.45
const FADE_OUT := 0.7

const CARD_MIN_WIDTH := 460.0
const CARD_PAD := Vector2(48.0, 34.0)
const TITLE_SIZE := Tokens.FONT_LG
const BODY_SIZE := Tokens.FONT_MD
## How far above the vertical centre the card sits.
##
## It used to sit 90px high, to keep the casualty in shot underneath it. In
## the room that read as a card that had drifted off the top of the screen
## rather than one deliberately placed - playtest: "move it a bit lower, centre
## it to screen." Dead centre it is; the body is still visible either side of a
## card this narrow.
const RISE := 0.0

var _panel: PanelContainer = null
var _title: Label = null
var _body: Label = null
var _tween: Tween = null


static func build(parent: Node, node_name: String = "CentreCard") -> CentreCard:
	if parent == null:
		return null
	var card := CentreCard.new()
	card.name = node_name
	card.layer = LAYER
	parent.add_child(card)
	card.owner = null
	return card


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", Tokens.glass_panel(Tokens.RADIUS_XL))
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.position = Vector2(0.0, -RISE)
	_panel.custom_minimum_size.x = CARD_MIN_WIDTH
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.modulate.a = 0.0
	root.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", int(CARD_PAD.x))
	margin.add_theme_constant_override("margin_right", int(CARD_PAD.x))
	margin.add_theme_constant_override("margin_top", int(CARD_PAD.y))
	margin.add_theme_constant_override("margin_bottom", int(CARD_PAD.y))
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", TITLE_SIZE)
	_title.add_theme_color_override("font_color", Tokens.INK)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_title)

	_body = Label.new()
	_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_font_size_override("font_size", BODY_SIZE)
	_body.add_theme_color_override("font_color", Tokens.INK_MUTED)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_body)


## Raise the card for `seconds`, then fade it out. Calling again while one is up
## replaces it - the tween is killed rather than queued, so the newer
## announcement is the one on screen.
func show_card(title: String, body: String, seconds: float) -> void:
	if _panel == null:
		return
	_title.text = title
	_body.text = body
	_body.visible = body != ""

	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_panel, "modulate:a", 1.0, FADE_IN)
	_tween.tween_interval(maxf(seconds - FADE_IN - FADE_OUT, 0.0))
	_tween.tween_property(_panel, "modulate:a", 0.0, FADE_OUT)


## Take it down now, whatever the tween was going to do. For a reset or an
## abandoned run - a card left fading over the debrief is the one way this
## layer can outlive the beat it belongs to.
func hide_card() -> void:
	if _panel == null:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	_panel.modulate.a = 0.0
