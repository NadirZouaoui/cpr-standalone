extends CanvasLayer
## The screens of the two-stage kit check: the opening brief, the selection
## chip that rides along during the stage-one sweep, and the card that sends
## the trainee into the switchroom once the bench is done.
##
## Stage two - the identification prompts - has no screen-space UI at all.
## It lives in the world on the diegetic panel (kit_identify_panel.gd), which
## this node spawns into the scene root.
##
## Nothing here tells the trainee whether they were right. Not per item, not
## at the end, not by implication. The kit check is assessed like every other
## part of the exercise and reported once, in the debrief, so a trainee who
## misnames the fire blanket walks into the switchroom without knowing it -
## exactly as they would if they had grabbed the wrong thing off a real bench.
##
## A pure view besides. It never grades, never counts and never touches
## Assessment; KitBench owns all of that and talks to this over Events. That
## split is what lets the whole check run headlessly with no window at all.
##
## Built in code rather than as a .tscn, like the rest of the UI here, so the
## layout stays reviewable in diff form.

const KitIdentifyPanelScript := preload("res://scripts/ui/kit_identify_panel.gd")
const TutorialScript := preload("res://scripts/ui/controls_tutorial.gd")

const BRIEF_UI := &"kit_brief"
const CLOSING_UI := &"kit_closing"

## Off leaves the brief and closing card out; the world half still works,
## so this is only useful for iterating on the in-world half.
@export var show_brief: bool = true

## The scenario framing, shown at the top of the opening brief above the kit
## instructions. Kept here rather than on the kit manifest because it is the
## trainee's role in the exercise, not a property of the bag on the bench -
## it stays true even if the kit contents are re-authored.
##
## Rewritten for the illustrated card. The old line named the role and stopped
## there, which left unsaid the two facts that actually matter: that the job is
## to WATCH, and that watching is the whole of it until it suddenly is not.
@export_multiline var scenario_brief: String = \
	"You are the Safety Observer. A worker is about to carry out planned live " \
	+ "low voltage work at the board, and until it goes wrong, watching them " \
	+ "is the whole job."

## What the exercise holds once the bench is done - the shock, the casualty,
## the CPR. Deliberately brief: it sets expectations, not procedure.
##
## It now says out loud that the run is timed and graded on ORDER, and that
## nothing will stop a wrong move. Both were true already and both were being
## discovered in the debrief - and a trainee who does not know the second one
## reads the absence of a warning as permission.
@export_multiline var simulation_brief: String = \
	"It will go wrong. From then you are timed and assessed on the order you " \
	+ "work in, and nothing stops you making a mistake - you read about it " \
	+ "in the debrief."

## Leave empty to load the default. Only read for its wording and item list -
## the answer key is KitBench's business, and this node never consults it.
@export var manifest: KitManifest

var _brief: Control
var _closing: Control

## Focused when the brief opens, so the card is keyboard-drivable and
## so the browser treats the first visible click as "on the button" rather
## than as a pointer-lock recapture gesture.
var _begin_button: Button
var _enter_button: Button

## Non-blocking bottom chip riding along during the selection sweep.
var _chip_root: Control
var _chip_label: Label
var _sweep_active: bool = false
var _selected_count: int = 0
## Whether the tally has been earned yet - see _on_selection_toggled().
var _chip_earned: bool = false

## The diegetic identify panel, spawned into the scene root because a
## CanvasLayer cannot parent world-space geometry.
var _panel: Node3D


func _ready() -> void:
	layer = 20
	visible = false

	if manifest == null:
		manifest = load(KitBench.DEFAULT_MANIFEST) as KitManifest
	if manifest == null:
		push_error("KitCheck: no KitManifest to render")
		return

	_build()
	_spawn_panel.call_deferred()

	Events.kit_selection_toggled.connect(_on_selection_toggled)
	Events.kit_stage_changed.connect(_on_stage_changed)
	Events.kit_check_finished.connect(_on_check_finished)
	Events.simulation_started.connect(_on_simulation_started)

	# On the first launch of a session the controls tutorial runs instead, and
	# reloads the scene into this card when it is done (client, 23 Sep 2026).
	if show_brief and SimState.is_preamble() and not TutorialScript.will_run():
		# One frame of slack so the Player has finished _ready and is
		# listening for ui_opened before the freeze goes out.
		_open_brief.call_deferred()


# =============================================================================
# Shared furniture
# =============================================================================
func _build() -> void:
	_brief = _screen()
	_closing = _screen()
	_build_brief()
	_build_closing()
	_build_chip()


## A dimmed full-screen surface, hidden until something needs it.
func _screen() -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.visible = false
	add_child(root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Tokens.OVERLAY_DIM
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)

	return root


## Centred card inside a screen. Returns the column to fill.
func _card(screen: Control, width: int) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, SCREEN_MARGIN)
	screen.add_child(margin)

	var centre := CenterContainer.new()
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(centre)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, 0)
	panel.add_theme_stylebox_override("panel", Tokens.glass_panel())
	centre.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	return column


## Gap between a card and the edge of the window.
const SCREEN_MARGIN := 32

## Height of the chrome a card's column sits inside: the screen margin twice
## over, plus the glass panel's own top and bottom content margins.
const CARD_CHROME := SCREEN_MARGIN * 2 + 20 * 2


## The opening card does not scroll. It is the first thing the trainee sees and
## a scrollbar on it reads as a form to be got through, so when the window is
## too short the card gives up picture height instead - the pictures are the
## one part of it that is worth less at a smaller size but still worth having.
##
## Text is never what gets cut. A brief with its last line clipped off is worse
## than no brief at all, so below PICTURE_FLOOR the pictures come out entirely
## and the columns stand as headings and lists.
const PICTURE_FLOOR := 72


## Always measured from the card at FULL picture height, and only after the
## layout has settled. Measuring a card that is already shrunk asks "does what
## I did last time still fit", which can only ever shrink further; measuring it
## before it has laid out asks an autowrapping label how tall it is at a width
## it has not been given yet, and the answer is far too tall. The first version
## of this did both, and drove the pictures to the floor on a window with 50px
## to spare.
func _fit_brief() -> void:
	if _brief_body == null or _brief_pictures.is_empty():
		return
	_set_picture_height(BRIEF_IMAGE_HEIGHT)
	await get_tree().process_frame
	await get_tree().process_frame

	var room := get_viewport().get_visible_rect().size.y - float(CARD_CHROME)
	var over := _content_height(_brief_body) - room
	if over <= 0.0:
		return

	# Every picture is on the same row, so the row loses exactly what one
	# picture loses.
	_set_picture_height(int(clampf(float(BRIEF_IMAGE_HEIGHT) - over,
		float(PICTURE_FLOOR), float(BRIEF_IMAGE_HEIGHT))))


## Both axes, so the box keeps its aspect as it gives up height and the three
## pictures stay the same shape as each other.
func _set_picture_height(height: int) -> void:
	_picture_height = height
	for picture in _brief_pictures:
		picture.custom_minimum_size = Vector2(
			float(height) / BRIEF_IMAGE_ASPECT, float(height))


## What the column ACTUALLY occupies, summed from the rows as they were laid
## out. Not get_combined_minimum_size(): an autowrapping label's minimum is
## computed against a width it was never given, and the sum of three of them
## overshoots the card badly.
func _content_height(column: VBoxContainer) -> float:
	var separation := float(column.get_theme_constant(&"separation"))
	var total := 0.0
	var rows := 0
	for child in column.get_children():
		var row := child as Control
		if row == null or not row.visible:
			continue
		total += row.size.y
		rows += 1
	return total + separation * float(maxi(rows - 1, 0))


func _label(text: String, size: int, colour: Color) -> Label:
	var l := Tokens.make_label(text, size, colour)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _button(text: String, kind: StringName) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", Tokens.FONT_MD)
	Tokens.style_button(b, kind)
	return b


## Never under a blocking screen. KitBench posts NAMING while the brief is only
## queued to open, so gating the chip at the moment the sweep is switched on is
## gating against a brief that is not visible YET - it went up a frame later,
## with the tally sitting on top of it offering [Enter] for a key the brief does
## not read. The screens call in here as they open and close instead, so the
## chip is re-decided after the thing it hides behind has moved.
func _sync_chip() -> void:
	if _chip_root == null:
		return
	_chip_root.visible = _sweep_active and _chip_earned 		and not _brief.visible and not _closing.visible


func _show(screen: Control, ui_name: StringName) -> void:
	visible = true
	screen.visible = true
	_sync_chip()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Events.open_ui(ui_name)


func _hide(screen: Control, ui_name: StringName) -> void:
	screen.visible = false
	Events.close_ui(ui_name)
	_sync_chip()
	_update_visibility()


## Both blocking screens down, whatever state they were in. For dev_menu.gd's
## [F10] warps, which drop the trainee into the middle of a run whose preamble
## never happened.
##
## Setting this CanvasLayer's own `visible` to false from outside is not enough
## and never was: `visible` here is recomputed by _update_visibility() from the
## screens' OWN flags, so a layer hidden that way came straight back the next
## time anything called _set_sweep_active() - which _on_simulation_started()
## does, on the first warp. The brief then reappeared on top of a run in
## progress, mouse captured, with a full-rect MOUSE_FILTER_STOP control eating
## every click behind it. Calling the force-close twice with a wait between
## looked like a fix because the second call landed before the warp; it never
## survived the warp itself.
func force_close_screens() -> void:
	if _brief != null and _brief.visible:
		_hide(_brief, BRIEF_UI)
	if _closing != null and _closing.visible:
		_hide(_closing, CLOSING_UI)


## The layer carries the blocking screens and the selection chip. The chip is
## non-blocking - the mouse stays captured for the sweep - so it only keeps
## the layer alive while it is up.
func _update_visibility() -> void:
	visible = _brief.visible or _closing.visible or _sweep_active


func _spawn_panel() -> void:
	if _panel != null:
		return
	_panel = KitIdentifyPanelScript.new()
	_panel.heading = manifest.question
	var root := get_tree().current_scene
	if root == null:
		root = get_tree().root
	root.add_child(_panel)


# =============================================================================
# Brief
# =============================================================================
## The three acts of the exercise, as the opening card presents them. Each is a
## picture, a name and the three things that happen in it.
##
## Modelled on the Substation 3D Training intro card, which is the other half of
## this product and the thing a trainee will most likely have done first: a row
## of illustrated columns under a red headline. The shape is doing real work
## rather than decoration - the LVR exercise has a preamble that looks like a
## quiz, a middle that looks like standing around watching, and an end that is
## the actual rescue, and a trainee who does not know that arrives at the bench
## thinking the bench IS the exercise.
##
## `image` is a path under textures/UI. A missing file is not an error: the
## column draws as a heading and its list, which is what the card was before the
## pictures existed. See _brief_column().
const BRIEF_COLUMNS := [
	{
		"image": "res://textures/UI/brief_kit.png",
		"title": "The Rescue Kit",
		"points": [
			"Name every item in the bag",
			"Know what is NOT kit",
			"Take the torch with you",
		],
	},
	{
		"image": "res://textures/UI/brief_panel.png",
		"title": "The Live Work",
		"points": [
			"Observe the worker at the board",
			"PPE on, hazards identified",
			"Sign the point of isolation",
		],
	},
	{
		"image": "res://textures/UI/brief_cpr.png",
		"title": "The Rescue",
		"points": [
			"Break contact with the crook",
			"Drag clear, then isolate",
			"DRSABCD, CPR and the AED",
		],
	},
]

const BRIEF_TITLE := "LOW VOLTAGE RESCUE"

## Height the column pictures are drawn at, in pixels. They are photographs and
## renders of wildly different proportions, so the height is fixed and the width
## is whatever the aspect gives - a row of images that agree on their height
## reads as a set.
## One aspect for all three, cropped to it rather than fitted inside it. The
## sources are a wide bench photograph, an upright worker and a body on the
## floor; fitting each at its own shape gave three different pictures in three
## different amounts of white. Cropping is not stretching - nothing in frame
## changes proportion, there is just less of it.
const BRIEF_IMAGE_ASPECT := 0.64
## The picture does not run the width of its card. A band edge to edge made the
## column read as a picture with a caption under it; inset, the three of them
## read as three cards that happen to be illustrated.
const BRIEF_IMAGE_WIDTH := 172
const BRIEF_IMAGE_HEIGHT := int(BRIEF_IMAGE_WIDTH * BRIEF_IMAGE_ASPECT)

const BRIEF_COLUMN_WIDTH := 228

## The prose sits in a narrower column than the card it is on. See
## _build_brief().
const BRIEF_PROSE_WIDTH := 690

const BRIEF_CARD_WIDTH := 780

## The column the brief's content lives in, kept for _fit_brief().
var _brief_body: VBoxContainer = null
## The three pictures, kept because they are what gives way on a short window.
var _brief_pictures: Array[Control] = []
var _picture_height: int = BRIEF_IMAGE_HEIGHT


func _build_brief() -> void:
	var column := _card(_brief, BRIEF_CARD_WIDTH)
	column.add_theme_constant_override("separation", 14)
	_brief_body = column

	var headline := Tokens.make_label(BRIEF_TITLE, Tokens.FONT_XL, Tokens.DANGER)
	headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(headline)

	# Role first: the trainee needs to know who they are before they are told
	# to go and sort things on a bench. Then what the exercise holds, so the
	# shock does not come as a surprise when it lands.
	#
	# Centred, and held to a column narrower than the card. Ranged-left prose
	# across the full width of a 850px card gives lines long enough that the
	# eye loses the return, and the card's own axis is its centre - the title
	# above and the button below are both on it.
	var prose := VBoxContainer.new()
	prose.add_theme_constant_override("separation", 4)
	prose.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	prose.custom_minimum_size.x = BRIEF_PROSE_WIDTH
	column.add_child(prose)
	for text: String in [scenario_brief, simulation_brief]:
		if text == "":
			continue
		var line := _label(text, Tokens.FONT_MD,
			Tokens.INK if prose.get_child_count() == 0 else Tokens.INK_MUTED)
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		prose.add_child(line)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(row)
	for entry: Dictionary in BRIEF_COLUMNS:
		row.add_child(_brief_column(entry))

	# Nothing under the columns but the way out. The kit instruction and the
	# key list used to sit here, and both are said again where they are needed:
	# the bench's own prompt names the interaction, and the tally chip carries
	# [Enter]. On the card they were two paragraphs nobody reads standing still.
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(footer)

	var begin := _button("Go to the bench", &"primary")
	begin.custom_minimum_size = Vector2(230, 48)
	begin.add_theme_font_size_override("font_size", Tokens.FONT_LG)
	begin.pressed.connect(_close_brief)
	footer.add_child(begin)
	_begin_button = begin


## A rounded window for one picture.
##
## Not a shader on the TextureRect: with KEEP_ASPECT_COVERED the texture is
## drawn LARGER than the control, and UV spans that oversized draw rect rather
## than the control, so a corner computed in UV space is both the wrong scale
## and, on the two wide pictures, outside the visible area entirely. That is
## why only the squarest of the three looked rounded and its corners looked
## stretched.
##
## CLIP_CHILDREN_ONLY masks children to the parent's own drawing and throws
## that drawing away - so a PanelContainer with a rounded StyleBoxFlat is the
## mask, in the card's own radius, antialiased by the same code that rounds
## every other corner in the project.
func _picture_frame(picture: TextureRect) -> Control:
	var frame := PanelContainer.new()
	var mask := StyleBoxFlat.new()
	mask.bg_color = Color.WHITE
	mask.set_corner_radius_all(Tokens.RADIUS_MD)
	mask.anti_aliasing = true
	frame.add_theme_stylebox_override("panel", mask)
	frame.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.custom_minimum_size = Vector2(
		_picture_height / BRIEF_IMAGE_ASPECT, _picture_height)
	frame.add_child(picture)
	return frame


## One illustrated column of the opening card: a picture, a heading, a rule and
## the list, in that order.
##
## The picture is FITTED, never cropped and never stretched. All three sources
## are different shapes - a bench photographed wide, a worker shot upright, a
## body on the floor - and both of the alternatives are worse than the white
## they leave around them: STRETCH_SCALE distorts a photograph of real kit, and
## KEEP_ASPECT_COVERED crops it, which on the live-work frame cut the board the
## column is about. The band is a fixed height so the three headings line up.
##
## ResourceLoader.exists() first rather than a bare load(): a load() on a
## missing path is an error in the log and a null in the tree on every run.
## Degrading to the heading and the list is the same card this was before the
## pictures existed, so a missing one costs the trainee nothing.
func _brief_column(entry: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(BRIEF_COLUMN_WIDTH, 0)
	# card_row(), not panel(): the glass family carries an 18px drop shadow, and
	# three shadowed cards sitting ON a shadowed card read as a stack of things
	# coming loose. A flat fill with a hairline edge is enough to separate them
	# from the glass they are printed on.
	var face := Tokens.card_row(Tokens.RADIUS_MD, Tokens.CARD_FILL)
	face.content_margin_left = 14
	face.content_margin_right = 14
	face.content_margin_top = 14
	face.content_margin_bottom = 16
	card.add_theme_stylebox_override("panel", face)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)

	var path := String(entry.get("image", ""))
	if path != "" and ResourceLoader.exists(path):
		var picture := TextureRect.new()
		picture.texture = load(path)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		var frame := _picture_frame(picture)
		box.add_child(frame)
		_brief_pictures.append(frame)

	var title := Tokens.make_label(
		String(entry.get("title", "")), Tokens.FONT_LG, Tokens.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	# The one rule on the card, and it earns its place: it is what separates a
	# heading from the list that belongs to it, inside a box that has no other
	# structure.
	box.add_child(HSeparator.new())

	for point: String in entry.get("points", []):
		var line := _label(point, Tokens.FONT_SM, Tokens.INK)
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(line)

	return card


func _open_brief() -> void:
	_show(_brief, BRIEF_UI)
	_fit_brief()
	if _begin_button != null:
		_begin_button.grab_focus()


func _close_brief() -> void:
	_hide(_brief, BRIEF_UI)
	# The sweep begins the moment the brief is down.
	_set_sweep_active(SimState.is_preamble())


# =============================================================================
# Selection chip
# =============================================================================
func _build_chip() -> void:
	_chip_root = Control.new()
	_chip_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_chip_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip_root.visible = false
	add_child(_chip_root)

	var bottom := MarginContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.add_theme_constant_override("margin_bottom", 48)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip_root.add_child(bottom)

	var centre := CenterContainer.new()
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(centre)

	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", Tokens.glass_chip())
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(chip)

	_chip_label = Tokens.make_label("", Tokens.FONT_MD, Tokens.INK)
	chip.add_child(_chip_label)


func _refresh_chip(count: int) -> void:
	_chip_label.text = "%d named  -  [Enter] to review" % count


func _on_selection_toggled(_item_id: StringName, selected: bool) -> void:
	# The count on the chip is the trainee's own tally, not the answer key:
	# it moves on every toggle, kit or tool, so watching it tells them
	# nothing about which is which. Tallied here from the toggles rather
	# than read back from KitBench, so the view stays decoupled from the
	# bench and the headless harness needs no scene-tree reach.
	_selected_count += 1 if selected else -1
	# Playtest: "only show '0 selected press Enter' once they select the first
	# item." A tally of nothing is not a tally, and [Enter] offered before
	# there is a list to review reads as the way out of the bench rather than
	# the way to check the work. Latched, not tied to the count: a trainee who
	# takes their only claim back still needs the key they were shown.
	if selected:
		_chip_earned = true
	if not _sweep_active:
		_set_sweep_active(true)
	_sync_chip()
	_refresh_chip(_selected_count)


## `keep_count` is the whole reason this takes an argument. The review card is
## a round trip - the trainee can go back and forth between the bench and their
## own list as often as they like - and a tally that reset itself on the way
## out would be wrong the moment they came back.
func _set_sweep_active(active: bool, keep_count: bool = false) -> void:
	_sweep_active = active
	if not active and not keep_count:
		_selected_count = 0
		_chip_earned = false
	_sync_chip()
	_update_visibility()
	if active:
		_refresh_chip(_selected_count)


## The chip follows the bench's own stage rather than a signal of its own.
## KitBench emits the opening NAMING deferred, while the brief is still up, so
## the brief's own visibility is what decides whether the tally may appear yet.
func _on_stage_changed(stage: int) -> void:
	match stage:
		KitBench.Stage.NAMING:
			if SimState.is_preamble() and not _brief.visible:
				_set_sweep_active(true, true)
		KitBench.Stage.REVIEW:
			# The card owns the screen while it is up, and the tally under it
			# would be offering [Enter] for a key the card does not read.
			_set_sweep_active(false, true)
		KitBench.Stage.DONE:
			_set_sweep_active(false)


func _on_simulation_started() -> void:
	_set_sweep_active(false)


# =============================================================================
# Closing
# =============================================================================
func _build_closing() -> void:
	var column := _card(_closing, 640)

	column.add_child(_label("Kit check complete", Tokens.FONT_XL, Tokens.INK))
	column.add_child(_label(manifest.closing_note, Tokens.FONT_MD, Tokens.INK_MUTED))

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(footer)

	var enter := _button("Begin simulation", &"primary")
	enter.pressed.connect(_close_closing)
	footer.add_child(enter)
	_enter_button = enter


## Neutral by design: same heading, same colour, same wording whether they
## named every item correctly or none of them.
func _on_check_finished() -> void:
	_show(_closing, CLOSING_UI)
	# Grab focus so the button is keyboard-reachable and so the browser
	# recognises a click on it as intentional input rather than as a
	# pointer-lock recapture gesture (which would swallow the press).
	if _enter_button != null:
		_enter_button.grab_focus()


func _close_closing() -> void:
	_hide(_closing, CLOSING_UI)
	# Leaves the untimed preamble and starts the exercise clock. The casualty
	# rig and the shock cue are both watching for this.
	SimState.begin_exercise()
