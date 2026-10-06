extends Node3D
## The diegetic naming menu of the kit check.
##
## A SubViewport rendered onto a full-billboard quad - the same construction
## as CprPanel3D, but clickable. It floats above the bench object the trainee
## has just clicked, shows the choices as a vertical stack of glass pills -
## the casualty-pointers look, not a big card - and is picked with the
## crosshair: the mouse never leaves capture, the crosshair is the cursor, and
## `interact` chooses the aimed pill. The pill under the crosshair is found by
## ray-plane intersection against the camera's own basis - no collider, no
## physics query, exactly like the casualty menu card that preceded this
## pattern.
##
## A pure view besides. It never grades and never touches Assessment; KitBench
## owns all of that and talks to this over Events. The panel does not know
## which choice is right, and now there is nothing on it that could give that
## away: the struck-out red pill and its "choose again" notice are gone. The
## answer stands as given, and a trainee who wants to change one takes the
## claim back on the bench and names the object again - the review card is
## where a list gets corrected now.

const VIEWPORT_SIZE := Vector2i(768, 448)

## World-space size of the quad, metres - the reference size at the distance
## the bench is worked from. Never allowed to project larger than
## max_screen_fraction of the viewport, whatever the distance.
@export var panel_world_size: Vector2 = Vector2(0.72, 0.42)

## Ceiling on how much screen the panel may occupy: the quad is shrunk each
## frame so its projected size never exceeds this fraction of the viewport.
@export_range(0.1, 1.0) var max_screen_fraction: float = 0.3

## Lower bound for the screen clamp, so the panel cannot shrink to nothing
## if the trainee walks right up to it.
const MIN_WORLD_SIZE := Vector2(0.3, 0.175)

## How far above the asked item's bounding box the lowest pill floats, metres.
## Small on purpose: tall items like the kit bag must not push the panel up
## to head height - the stack-sag lift keeps the pills clear at this gap.
##
## Was 0.15. Playtest, twice: "the diegetic list for the kit bag is too high",
## then "bag list still too high compared to the other items". The bag is the
## tallest thing on the bench, so it is the item where every millimetre of slack
## in the anchor shows; see _anchor_point() for the rest of the fix.
@export var anchor_clearance: float = 0.06

## Heading drawn above the pill stack. Set by kit_check.gd from the manifest
## so the wording stays data, not code.
var heading: String = "Identify this item"

var _viewport: SubViewport
var _canvas: KitIdentifyPanelCanvas
var _quad: MeshInstance3D
var _quad_material: StandardMaterial3D

## The question currently up, or &"" when the panel is down.
var _item_id: StringName = &""
var _choices: PackedStringArray = PackedStringArray()
var _aimed: int = -1

## The bench object the question is about, held while the panel is up so the
## lift can be re-solved every frame. See _reanchor().
var _anchor: KitInspectItem = null

## The size the quad is actually drawn at - panel_world_size scaled down
## whenever the camera is close enough that the clamp bites.
var _current_world_size: Vector2


func _ready() -> void:
	_build_viewport_and_quad()
	visible = false
	set_process(false)

	Events.kit_question_requested.connect(_on_question_requested)
	Events.kit_answer_recorded.connect(_on_answer_recorded)
	Events.kit_check_finished.connect(close)
	Events.simulation_started.connect(close)


func _build_viewport_and_quad() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "SubViewport"
	_viewport.size = VIEWPORT_SIZE
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_viewport)

	_canvas = KitIdentifyPanelCanvas.new()
	_canvas.name = "Canvas"
	# No anchors: a Control under a SubViewport resolves FULL_RECT against a
	# doubled area on this setup, and the texture then shows only the
	# top-left quadrant of the drawing. Sized outright instead, and re-asserted
	# in set_question so a stray layout pass can never shrink the stack away.
	_canvas.position = Vector2.ZERO
	_canvas.size = Vector2(VIEWPORT_SIZE)
	_viewport.add_child(_canvas)

	_quad_material = StandardMaterial3D.new()
	_quad_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_quad_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_quad_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Full billboard, not FIXED_Y: the panel floats at whatever height the
	# asked item puts it at, and the bench is looked at from standing, kneeling
	# and leaning angles. Facing the camera outright reads from all of them.
	_quad_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_quad_material.billboard_keep_scale = true
	_quad_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_quad_material.albedo_texture = _viewport.get_texture()
	# Draw after opaque geometry, same convention as CprGhost materials.
	_quad_material.render_priority = 1
	# ...and in front of it, like ChoiceCard3D and the hazard panel. The bench
	# stands against a wall and the quad billboards to face the camera, so from
	# most of the places the bench is worked from its left half is inside that
	# wall and the depth test slices the menu off square. Seen on screen: the
	# heading and three of the four choices were cut mid-word on the first
	# question of the run.
	_quad_material.no_depth_test = true

	var quad_mesh := QuadMesh.new()
	quad_mesh.size = panel_world_size
	quad_mesh.material = _quad_material

	_quad = MeshInstance3D.new()
	_quad.name = "Quad"
	_quad.mesh = quad_mesh
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_quad)


# =============================================================================
# Open / close
# =============================================================================
func _on_question_requested(item_id: StringName, choices: PackedStringArray) -> void:
	_item_id = item_id
	_choices = choices
	_aimed = -1

	# Metrics before positioning: the anchor lifts the quad by however far
	# the pill stack hangs below the canvas centre, so set_question runs first.
	_canvas.set_question(choices, heading)

	_current_world_size = panel_world_size
	_quad.mesh.size = _current_world_size

	_anchor = _find_anchor(item_id)
	_reanchor()
	visible = true
	set_process(true)


## The asked object's mark is the anchor: float above its bounding box so the
## panel and the green mark read as one unit.
##
## The object is the one the trainee just clicked, so it is under the
## crosshair and the menu opens over the middle of the screen. It used to open
## over whichever object the queue had reached next, anywhere on the bench,
## which is how it ended up drawn behind the HUD checklist in the top-left
## corner (docs/CLIENT_CONFORMANCE_2026-09-04.md section 7, item 5).
func _anchor_point(item: KitInspectItem) -> Vector3:
	var mesh := item.mesh_to_highlight
	var top: Vector3
	if mesh == null:
		top = item.global_position + Vector3.UP * anchor_clearance
	else:
		var aabb := mesh.get_aabb()
		top = mesh.to_global(aabb.get_center() + Vector3(0.0, aabb.size.y * 0.5, 0.0))
	# The pills occupy the middle of the quad and sag below its centre by
	# however tall the stack is - lift by that amount so the lowest pill
	# clears the item and whatever it is sitting on.
	var below := _canvas.stack_bottom_below_centre_px() \
		/ float(VIEWPORT_SIZE.y) * _current_world_size.y
	return top + _lift_axis() * (anchor_clearance + below)


## Which way is "up the panel". Not Vector3.UP: the quad is a FULL billboard, so
## its own vertical axis is the CAMERA's up vector, and the sag it is being
## lifted by is measured down that axis. Offsetting along world up instead only
## agrees with the drawing when the camera is level, and the bench is worked
## from a standing pitch of 25-35 degrees down - the lift then over-shoots by
## the difference and the stack floats.
##
## Playtest, second pass: "bag list still too high compared to the other items."
## The residual scales with the sag, and the sag is the same for every question,
## but the bag starts highest, so the bag is where it reads as a gap.
##
## Falls back to world up when there is no camera (a headless run measuring the
## anchor), which is the same answer the old code always gave.
func _lift_axis() -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return Vector3.UP
	return camera.global_transform.basis.y


## Re-apply that lift against the size the quad is CURRENTLY drawn at.
##
## Playtest: "the diegetic list for the kit bag is too high." It was, and the
## lift is why. _update_world_size() shrinks the quad every frame so it never
## covers more than max_screen_fraction of the screen, and at the distance the
## bench is worked from that clamp bites hard — the drawn panel ends up well
## under panel_world_size. The lift was solved once, at open, against the FULL
## size (and on the first question of a run against a _current_world_size that
## had never been measured), so the quad climbed by the sag of a stack far
## taller than the one actually on screen. The gap that opened between the bag
## and the lowest pill IS that difference.
##
## Cheap enough to redo every frame - one division and one vector add - and
## doing it every frame is what keeps the anchor honest while the clamp moves.
func _reanchor() -> void:
	if _anchor == null or not is_instance_valid(_anchor):
		return
	global_position = _anchor_point(_anchor)


func _find_anchor(item_id: StringName) -> KitInspectItem:
	for node in get_tree().get_nodes_in_group(KitInspectItem.GROUP_KIT_INSPECT):
		if node is KitInspectItem and node.item_id == item_id:
			return node
	return null


## The answer landing is the only acknowledgement there is: the panel goes
## down at once. The next question, if any, reopens it over the next item.
func _on_answer_recorded(_recorded_id: StringName) -> void:
	close()


func close() -> void:
	_item_id = &""
	_choices = PackedStringArray()
	_aimed = -1
	_anchor = null
	visible = false
	set_process(false)


# =============================================================================
# Crosshair picking
# =============================================================================
func _process(_delta: float) -> void:
	_update_world_size()
	_reanchor()
	var hit := _aimed_pill()
	if hit != _aimed:
		_aimed = hit
		_canvas.set_aimed(_aimed)


## Shrink the quad whenever the camera is close enough that it would project
## past max_screen_fraction of the viewport. Perspective maths inverted: an
## object of height h at distance d spans h / (2 d tan(fov/2)) of the screen,
## so the largest h that stays inside the fraction follows directly.
func _update_world_size() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var dist := camera.global_position.distance_to(_quad.global_position)
	if dist <= 0.05:
		return
	var viewport := get_viewport().get_visible_rect().size
	var aspect := viewport.x / viewport.y
	var half_tan := tan(deg_to_rad(camera.fov * 0.5))
	var h_max := max_screen_fraction * 2.0 * dist * half_tan
	var w_max := h_max * aspect
	var scale := minf(1.0, minf(h_max / panel_world_size.y, w_max / panel_world_size.x))
	_current_world_size = Vector2(
		maxf(panel_world_size.x * scale, MIN_WORLD_SIZE.x),
		maxf(panel_world_size.y * scale, MIN_WORLD_SIZE.y))
	if _quad.mesh.size != _current_world_size:
		_quad.mesh.size = _current_world_size


## Where the crosshair meets the panel's plane, as a pill index. The quad
## billboards to face the camera, so the plane is rebuilt every frame from
## the camera position and the panel centre.
func _aimed_pill() -> int:
	if _item_id == &"" or _choices.is_empty():
		return -1
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return -1

	var centre := _quad.global_position
	var normal := (camera.global_position - centre).normalized()
	var dir := -camera.global_transform.basis.z
	var denom := dir.dot(normal)
	if absf(denom) < 0.0001:
		return -1
	var t := (centre - camera.global_position).dot(normal) / denom
	if t <= 0.0:
		return -1
	var point := camera.global_position + dir * t

	# Camera-space offsets from the panel centre, in metres.
	var right := camera.global_transform.basis.x
	var up := camera.global_transform.basis.y
	var offset := point - centre
	var u := offset.dot(right)
	var v := offset.dot(up)

	var half := _current_world_size * 0.5
	if absf(u) > half.x or absf(v) > half.y:
		return -1

	return _canvas.pill_at(
		(u / half.x * 0.5 + 0.5) * VIEWPORT_SIZE.x,
		(0.5 - v / half.y * 0.5) * VIEWPORT_SIZE.y
	)


func _unhandled_input(event: InputEvent) -> void:
	if _item_id == &"" or _choices.is_empty():
		return

	if event.is_action_pressed(&"interact"):
		if _aimed >= 0:
			get_viewport().set_input_as_handled()
			Events.kit_answer_submitted.emit(_item_id, _choices[_aimed])
		return

	# Arrow-key and Enter support alongside the crosshair, so a trainee who
	# finds the floating pills fiddly still has a plain way to answer.
	if event.is_action_pressed(&"ui_up"):
		get_viewport().set_input_as_handled()
		_aimed = clampi(_aimed - 1, 0, _choices.size() - 1) if _aimed >= 0 else _choices.size() - 1
		_canvas.set_aimed(_aimed)
	elif event.is_action_pressed(&"ui_down"):
		get_viewport().set_input_as_handled()
		_aimed = clampi(_aimed + 1, 0, _choices.size() - 1) if _aimed >= 0 else 0
		_canvas.set_aimed(_aimed)
	elif event.is_action_pressed(&"ui_accept") and _aimed >= 0:
		get_viewport().set_input_as_handled()
		Events.kit_answer_submitted.emit(_item_id, _choices[_aimed])


# =============================================================================
# The drawn pills
# =============================================================================
## All of the panel's pixels, drawn in code - matching the project's
## "no serialised runtime nodes" pattern and CprPanel3D's _PanelCanvas.
## One glass pill per choice, stacked above one another and centred in the
## quad; the pill under the crosshair picks up an accent ring. Geometry is in
## viewport pixels; pill_at() is the inverse map the crosshair picker uses.
class KitIdentifyPanelCanvas extends Control:
	const PILL_WIDTH := 600.0
	const PILL_HEIGHT := 66.0
	const PILL_GAP := 14.0
	const HEADING_PILL_HEIGHT := 52.0
	const HEADING_PAD_X := 40.0
	const HEADING_GAP := 14.0
	const HEADING_SIZE := 28
	const CHOICE_SIZE := 34
	## Never shrink past this - below it the menu is unreadable at the distance
	## the bench is worked from, and the answer is a wider pill, not smaller
	## type.
	const MIN_CHOICE_SIZE := 20
	## Breathing room inside the pill, each side.
	const TEXT_PAD := 24.0

	const HOVER_FILL := Color(0.99, 0.85, 0.45, 0.95)

	var _choices: PackedStringArray = PackedStringArray()
	var _heading: String = ""
	var _aimed: int = -1

	var _font: Font = null
	var _pill_style: StyleBoxFlat = null
	var _aim_style: StyleBoxFlat = null


	func _ready() -> void:
		_font = ThemeDB.fallback_font
		# The casualty-pointer pair, verbatim: idle pills are the standard
		# glass chip, and the pill under the crosshair lights up the same
		# solid gold the rest of the game highlights with.
		_pill_style = Tokens.glass_chip(Tokens.RADIUS_LG)
		_aim_style = Tokens.glass_chip(Tokens.RADIUS_LG)
		_aim_style.bg_color = HOVER_FILL


	func set_question(choices: PackedStringArray, heading: String) -> void:
		_choices = choices
		_heading = heading
		_aimed = -1
		position = Vector2.ZERO
		size = Vector2(VIEWPORT_SIZE)
		queue_redraw()


	func set_aimed(index: int) -> void:
		if index == _aimed:
			return
		_aimed = index
		queue_redraw()


	## Viewport pixel -> pill index, or -1 between pills. Shared geometry
	## with _draw() so the pick math and the pixels can never drift apart.
	func pill_at(x: float, y: float) -> int:
		for i in _choices.size():
			if _pill_rect(i).has_point(Vector2(x, y)):
				return i
		return -1


	## One width for the whole stack, fixed: every question presents the same
	## footprint, so the stack never jumps about between items.
	func _pill_size() -> Vector2:
		return Vector2(minf(PILL_WIDTH, size.x - 40.0), PILL_HEIGHT)


	## The size every choice is drawn at: CHOICE_SIZE, shrunk until the LONGEST
	## choice on this menu fits inside a pill.
	##
	## Found on screen, not in a test. The wrong answers used to be other bench
	## objects' names - "Torch", "Pliers", "Claw Hammer" - and every one of them
	## fitted at 34. The distractor pool is real LV rescue equipment now, and
	## "Resuscitation Face Shield" at 34 is half as wide again as the pill: the
	## text was drawn centred and unclipped, overflowed both ends, and was cut
	## off square by the edge of the canvas. Three of the four choices on the
	## first menu of the run were unreadable.
	##
	## One size for the whole stack rather than per pill, so the choices read as
	## a set of equals - a distractor in smaller type than the rest is a
	## distractor the trainee can discount without reading it.
	func _choice_font_size() -> int:
		var room := _pill_size().x - TEXT_PAD * 2.0
		var widest := 0.0
		for choice in _choices:
			widest = maxf(widest, _text_width(choice, CHOICE_SIZE))
		if widest <= room or widest <= 0.0:
			return CHOICE_SIZE
		return maxi(int(floor(CHOICE_SIZE * room / widest)), MIN_CHOICE_SIZE)


	func _text_width(text: String, font_size: int) -> float:
		if _font == null:
			_font = ThemeDB.fallback_font
		return _font.get_string_size(
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


	## The heading rides in its own pill, narrower than the choice pills -
	## sized to its text, not to the stack.
	func _heading_rect() -> Rect2:
		var w := minf(_text_width(_heading, HEADING_SIZE) + HEADING_PAD_X * 2.0,
			size.x - 40.0)
		var h := HEADING_PILL_HEIGHT
		return Rect2(Vector2((size.x - w) * 0.5, _stack_top()), Vector2(w, h))


	func _stack_top() -> float:
		return (size.y - _stack_total_px()) * 0.5


	func _stack_total_px() -> float:
		var total := float(_choices.size()) * PILL_HEIGHT \
			+ float(maxi(_choices.size() - 1, 0)) * PILL_GAP
		if _heading != "":
			total += HEADING_PILL_HEIGHT + HEADING_GAP
		return total


	## How far the stack's lowest point hangs below the canvas centre, in
	## pixels. The panel lifts the quad by this so the pills never sink into
	## the item or the bench below it.
	func stack_bottom_below_centre_px() -> float:
		if _choices.is_empty():
			return 0.0
		var top := _stack_top()
		return top + _stack_total_px() - size.y * 0.5


	func _pill_rect(index: int) -> Rect2:
		var pill := _pill_size()
		var x := (size.x - pill.x) * 0.5
		var y := _stack_top()
		if _heading != "":
			y += HEADING_PILL_HEIGHT + HEADING_GAP
		y += float(index) * (PILL_HEIGHT + PILL_GAP)
		return Rect2(Vector2(x, y), pill)


	func _draw() -> void:
		var s := size
		if s.x <= 0.0 or s.y <= 0.0 or _choices.is_empty():
			return

		if _font == null:
			_font = ThemeDB.fallback_font

		if _heading != "":
			var heading := _heading_rect()
			draw_style_box(_pill_style, heading)
			# Centred by font metrics, the same arithmetic the casualty
			# pointers use - no width-box alignment to get wrong.
			var heading_size := _font.get_string_size(
				_heading, HORIZONTAL_ALIGNMENT_LEFT, -1, HEADING_SIZE)
			var heading_baseline := heading.position + Vector2(
				(heading.size.x - heading_size.x) * 0.5,
				(heading.size.y + heading_size.y) * 0.5 - _font.get_descent(HEADING_SIZE))
			_font.draw_string(get_canvas_item(), heading_baseline, _heading,
				HORIZONTAL_ALIGNMENT_LEFT, -1, HEADING_SIZE, Tokens.INK)

		var choice_size := _choice_font_size()
		for i in _choices.size():
			var rect := _pill_rect(i)
			draw_style_box(_aim_style if i == _aimed else _pill_style, rect)
			var text_size := _font.get_string_size(
				_choices[i], HORIZONTAL_ALIGNMENT_LEFT, -1, choice_size)
			var baseline := rect.position + Vector2(
				(rect.size.x - text_size.x) * 0.5,
				(rect.size.y + text_size.y) * 0.5 - _font.get_descent(choice_size))
			# Width-limited as well as sized down, so a choice that somehow
			# still does not fit is ellipsised inside its own pill rather than
			# spilling past the canvas edge and being sliced off square.
			_font.draw_string(get_canvas_item(), baseline, _choices[i],
				HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - TEXT_PAD * 2.0,
				choice_size, Tokens.INK)
