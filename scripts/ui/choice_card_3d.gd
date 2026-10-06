extends Node3D
## The generic diegetic choice card: a question and a stack of answers,
## floating over a point in the world.
##
## The same construction as KitIdentifyPanel - a SubViewport rendered onto a
## full-billboard quad, glass pills drawn in code, picked with the crosshair
## by ray-plane intersection against the camera's own basis (no collider, no
## physics query, mouse never leaves capture). Where the kit panel is bound to
## the kit-check events, this one is deliberately dumb: whoever owns the
## question calls open() and listens to choice_made. The card never grades and
## never touches Assessment - it does not know which choice is right.
##
## The first instance is the help decision main.gd opens once the casualty is
## found unresponsive: "Call for help" or "Perform CPR". Being diegetic it
## blocks nothing - the trainee can walk away from it, and the world keeps
## moving; the debrief, not the card, is where a deferred call is judged.

signal choice_made(index: int, label: String)

const VIEWPORT_SIZE := Vector2i(768, 448)

## World-space size of the quad, metres - the reference size at the distance
## the casualty is worked from. Never allowed to project larger than
## max_screen_fraction of the viewport, whatever the distance.
@export var panel_world_size: Vector2 = Vector2(0.72, 0.42)

## Ceiling on how much screen the panel may occupy: the quad is shrunk each
## frame so its projected size never exceeds this fraction of the viewport.
@export_range(0.1, 1.0) var max_screen_fraction: float = 0.3

## Lower bound for the screen clamp, so the panel cannot shrink to nothing
## if the trainee walks right up to it.
const MIN_WORLD_SIZE := Vector2(0.3, 0.175)

## How far above the anchor point the lowest pill floats, metres.
@export var anchor_clearance: float = 0.25

var _viewport: SubViewport
var _canvas: ChoiceCardCanvas
var _quad: MeshInstance3D
var _quad_material: StandardMaterial3D

## True while a question is up.
var is_open: bool = false
var _choices: PackedStringArray = PackedStringArray()
var _aimed: int = -1

## The size the quad is actually drawn at - panel_world_size scaled down
## whenever the camera is close enough that the clamp bites.
var _current_world_size: Vector2

## Metres ahead of the camera a view-opened card is held at, or 0 for a card
## anchored to something in the world. See open_in_view() / _leash().
var _leash_distance: float = 0.0


func _ready() -> void:
	_build_viewport_and_quad()
	visible = false
	set_process(false)


func _build_viewport_and_quad() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "SubViewport"
	_viewport.size = VIEWPORT_SIZE
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_viewport)

	_canvas = ChoiceCardCanvas.new()
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
	# Full billboard, not FIXED_Y: the card floats at whatever height its
	# anchor puts it at and is read from standing, kneeling and leaning
	# angles. Facing the camera outright reads from all of them.
	_quad_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_quad_material.billboard_keep_scale = true
	_quad_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_quad_material.albedo_texture = _viewport.get_texture()
	# Draw after opaque geometry, same convention as CprGhost materials.
	_quad_material.render_priority = 1
	# ...and in front of it. The card is a question that has to be answered
	# before the run continues, so it must never be half-buried in the room.
	# It was: opened at the CPR head anchor the card's centre lands within a
	# centimetre or two of floor height, and the concrete ate the lower half
	# of the quad - the trainee saw the question and the first choice, with
	# "Perform CPR" underneath the floor.
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
## Raise the card over `anchor` (a world-space point, already chosen by the
## owner to sit clear of whatever it concerns - the card lifts it further by
## the stack's own sag).
func open(anchor: Vector3, heading: String, choices: PackedStringArray) -> void:
	var below := _prepare(heading, choices)
	_leash_distance = 0.0
	global_position = anchor + Vector3.UP * (anchor_clearance + below)
	_show()


## Raise the card centred in the trainee's view, a comfortable reading
## distance ahead, rather than pinned above a thing in the world.
##
## For questions that belong to the moment instead of to an object - and for
## the cases where an anchored position simply cannot work. The help question
## is both: it lands while the trainee is kneeling at the CPR head anchor,
## where the camera sits about 0.4 m above the casualty looking down 30
## degrees. From there every point "over the casualty" is either behind the
## view plane or off the bottom of the frame, and the card was placed behind
## the trainee and never seen. The quad billboards anyway, so a view-centred
## card still reads as hanging over the body the camera is pointed at.
##
## LEASHED, not merely placed. Playtest: "pic5 menu too far" - the card was
## hanging off the right edge of the frame with its choices cut in half.
##
## It was placed correctly and then left behind. The position is solved once,
## along the view axis at the instant the question opens, and the camera is
## almost never still at that instant: the help question lands while the CPR
## rig is still tweening onto the head anchor, and the trainee has free look
## within the anchor's yaw limit afterwards. Every degree of that turns the
## card further out of frame, and the same tangent stretch that makes the body
## pills run away (see CAPTURE_RADIUS in casualty_pointers.gd) moves it faster
## than the crosshair.
##
## Pinning it rigidly to the camera is the wrong cure - a card that always sits
## under the crosshair can never have one of its pills aimed at. So the world
## placement stays, and _leash() only pulls it back once it has drifted further
## than VIEW_LEASH_DEG off the view axis, which is outside the card's own
## angular size. Inside that cone it does not move at all and the pick is
## exactly what it was.
func open_in_view(heading: String, choices: PackedStringArray, distance: float = 1.2) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		open(global_position, heading, choices)
		return
	_prepare(heading, choices)
	_leash_distance = distance
	global_position = camera.global_position \
		- camera.global_transform.basis.z * distance
	_show()


## Half-angle of the cone a leashed card is kept inside, degrees.
##
## Has to be wider than the card's own half-height in angle, or the leash would
## fight the trainee aiming at the bottom pill. At the default 1.2 m and
## max_screen_fraction 0.3 the card is about 0.42 m tall in a 60-degree frame,
## so its own half-height subtends about 10 degrees; 14 leaves the whole card
## reachable and still cannot let it reach the margin.
const VIEW_LEASH_DEG := 14.0


## Bring the card back toward the view axis if it has drifted out of that cone.
## A no-op for an anchored card: that one belongs to a thing in the world and
## must stay on it.
func _leash() -> void:
	if _leash_distance <= 0.0:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var forward := -camera.global_transform.basis.z
	var to_card := global_position - camera.global_position
	if to_card.length() < 0.001:
		global_position = camera.global_position + forward * _leash_distance
		return
	var limit := deg_to_rad(VIEW_LEASH_DEG)
	var dir := to_card.normalized()
	var angle := forward.angle_to(dir)
	if angle <= limit:
		return
	var axis := forward.cross(dir)
	if axis.length_squared() < 0.000001:
		axis = camera.global_transform.basis.y
	global_position = camera.global_position \
		+ forward.rotated(axis.normalized(), limit) * _leash_distance


## Shared setup. Metrics come before positioning: an anchored card lifts the
## quad by however far the pill stack hangs below the canvas centre, which is
## only known once the question has been laid out. Returns that sag in metres.
func _prepare(heading: String, choices: PackedStringArray) -> float:
	_choices = choices
	_aimed = -1
	is_open = true

	_canvas.set_question(choices, heading)
	_current_world_size = panel_world_size
	_quad.mesh.size = _current_world_size

	return _canvas.stack_bottom_below_centre_px() \
		/ float(VIEWPORT_SIZE.y) * _current_world_size.y


func _show() -> void:
	visible = true
	set_process(true)


func close() -> void:
	is_open = false
	_choices = PackedStringArray()
	_aimed = -1
	visible = false
	set_process(false)


# =============================================================================
# Crosshair picking
# =============================================================================
func _process(_delta: float) -> void:
	_leash()
	_update_world_size()
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
	if not is_open or _choices.is_empty():
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
	if not is_open or _choices.is_empty():
		return

	if event.is_action_pressed(&"interact"):
		if _aimed >= 0:
			get_viewport().set_input_as_handled()
			_submit(_aimed)
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
		_submit(_aimed)


func _submit(index: int) -> void:
	var label := String(_choices[index])
	close()
	choice_made.emit(index, label)


# =============================================================================
# The drawn pills
# =============================================================================
## All of the panel's pixels, drawn in code - matching the project's
## "no serialised runtime nodes" pattern and CprPanel3D's _PanelCanvas.
## One glass pill per choice, stacked above one another and centred in the
## quad; the pill under the crosshair picks up an accent ring. Geometry is in
## viewport pixels; pill_at() is the inverse map the crosshair picker uses.
class ChoiceCardCanvas extends Control:
	const PILL_WIDTH := 600.0
	const PILL_HEIGHT := 66.0
	const PILL_GAP := 14.0
	const HEADING_PILL_HEIGHT := 52.0
	const HEADING_PAD_X := 40.0
	const HEADING_GAP := 14.0
	const HEADING_SIZE := 28
	const CHOICE_SIZE := 34

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

		for i in _choices.size():
			var rect := _pill_rect(i)
			draw_style_box(_aim_style if i == _aimed else _pill_style, rect)
			var text_size := _font.get_string_size(
				_choices[i], HORIZONTAL_ALIGNMENT_LEFT, -1, CHOICE_SIZE)
			var baseline := rect.position + Vector2(
				(rect.size.x - text_size.x) * 0.5,
				(rect.size.y + text_size.y) * 0.5 - _font.get_descent(CHOICE_SIZE))
			_font.draw_string(get_canvas_item(), baseline, _choices[i],
				HORIZONTAL_ALIGNMENT_LEFT, -1, CHOICE_SIZE, Tokens.INK)
