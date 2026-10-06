extends CanvasLayer
## Translucent 2D rescuer hands, drawn over the casualty's chest during
## compressions.
##
## Replaces the FpsArms plan. Modelled arms were cut as overkill for what they
## had to convey — where the hands go, and that a compression is landing — and a
## flat overlay says both without an animation rig that has to stay in sync with
## the depth float.
##
## WORLD-ANCHORED, NOT SCREEN-CENTRED. The hands are drawn at the projection of
## the casualty's chest, so they stay on the sternum while the trainee looks
## freely around the anchored view — the clamped mouse-look at the kneel anchor
## is a real range of motion, and hands pinned to the middle of the screen slid
## off the body and read as a HUD decal instead of the rescuer's own hands. They
## also scale with distance, from a fixed real-world hand width, so they sit
## correctly whichever anchor the camera is at.
##
## The chest position comes from CprRig, whose own transform IS the chest frame
## (it re-poses itself off the casualty's chest bone every frame), so this
## follows the body without measuring anything itself.
##
## Depth comes from CasualtyCpr.current_depth() — the same single source of
## truth the blend shape reads, so the drawing and the chest cannot disagree.
##
## Drawn rather than textured: no asset to import, nothing for a .blend reimport
## to drop, and it resolves at any viewport size.
##
## Instanced by CprStation._build(). Nothing else references it.


const CASUALTY_MESH_NAME := "Casualty_CPR_Posed"
const CPR_RIG_NODE_NAME := "CprRig"

## Real-world width of a pair of stacked hands. Everything else is drawn as a
## fraction of this, so the overlay is sized by the scene rather than by the
## window.
const HAND_WIDTH_METRES := 0.20
## Lifted off the chest frame so the hands read as resting ON the sternum
## rather than sunk into it, and pressed down by this much at full depth.
const CHEST_LIFT_METRES := 0.02
const PRESS_TRAVEL_METRES := 0.045

const FADE_SPEED := 6.0
const ALPHA_IDLE := 0.34
const ALPHA_PRESSED := 0.62

## Clamped so the drawing never becomes either a speck or a screen-filling blob
## if the camera ends up somewhere unexpected.
const PIXELS_MIN := 40.0
const PIXELS_MAX := 900.0

const SKIN := Color(0.93, 0.86, 0.80)
const SKIN_SHADE := Color(0.72, 0.63, 0.57)
const OUTLINE := Color(0.16, 0.13, 0.12)


var _canvas: _HandsCanvas = null
var _visible_amount: float = 0.0
var _state: int = -1
var _cpr_rig: Node3D = null


func _ready() -> void:
	layer = 4  # under the HUD (5), so the reticle and chips stay on top
	_canvas = _HandsCanvas.new()
	_canvas.name = "HandsCanvas"
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)

	Events.cpr_state_changed.connect(_on_cpr_state_changed)
	set_process(false)
	call_deferred("_bind")


func _bind() -> void:
	var root: Node = get_tree().current_scene
	if root == null:
		root = get_tree().root
	_cpr_rig = CprGhost.find_node(root, CPR_RIG_NODE_NAME) as Node3D
	if _cpr_rig == null:
		push_error("CprHands2D: no node named '%s'; the hands have nothing to anchor to." % CPR_RIG_NODE_NAME)


func _on_cpr_state_changed(_from: int, to: int) -> void:
	_state = to
	_sync()


func _sync() -> void:
	set_process(_is_compression_state())
	if not _is_compression_state():
		_visible_amount = 0.0
		_canvas.hide_hands()


## Also false until the trainee takes the "Start compressions" body pointer.
## The spine reaches COMPRESSIONS_1 off the breathing check, which is assessed
## at the mouth with the shirt still on, so the state arriving is not the
## trainee saying they are ready — hands hovering over the body before that
## advertise an action that is refused (compression_driver.gd gates the rep on
## the same fact). The body pointers are the only thing on offer until then,
## deliberately.
func _is_compression_state() -> bool:
	return _state == CprStation.STATE_COMPRESSIONS_1 or _state == CprStation.STATE_COMPRESSIONS_2


## Armed by the "Start compressions" body pointer. Tested in _process rather
## than gating set_process(): arming is a plain field on the station, not a
## state change or a step, so there is no signal to re-sync on — polling a bool
## on the frames the compression states are already running is cheaper than
## inventing one.
func _compressions_armed() -> bool:
	var station := CprStation.get_current()
	if station == null:
		return true
	# Also the shared "at the anchor" rule (CprStation.trainee_at_anchor()):
	# the hands are pinned to the sternum in world space, so standing up left
	# a pair of them lying on the casualty from across the room.
	return station.compressions_armed and station.trainee_at_anchor()


## Visible while the trainee is looking at the casualty — the same test that
## gates a rep from counting (compression_driver.gd), so the hands double as
## aiming feedback: if they are not showing, a press will not register. Also
## held visible for the duration of a press already under way, so a compression
## started on target cannot have its own feedback yanked mid-stroke.
func _process(delta: float) -> void:
	if _cpr_rig == null or not is_instance_valid(_cpr_rig):
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	if not _compressions_armed():
		_visible_amount = 0.0
		_canvas.hide_hands()
		return

	var depth := CasualtyCpr.current_depth()
	var on_body := depth > 0.01 or CprInteractBridge.crosshair_on_casualty()
	_visible_amount = move_toward(_visible_amount, 1.0 if on_body else 0.0, FADE_SPEED * delta)
	if _visible_amount <= 0.005:
		_canvas.hide_hands()
		return

	var chest := _cpr_rig.global_position + Vector3.UP * (
		CHEST_LIFT_METRES - PRESS_TRAVEL_METRES * depth
	)
	if camera.is_position_behind(chest):
		_canvas.hide_hands()
		return

	# Size from a real width rather than a viewport fraction: project a segment
	# of HAND_WIDTH_METRES lying across the camera's own right axis and measure
	# how many pixels it covers from here.
	var right := camera.global_transform.basis.x.normalized()
	var span := camera.unproject_position(chest + right * HAND_WIDTH_METRES) \
		- camera.unproject_position(chest)
	var pixels := clampf(span.length(), PIXELS_MIN, PIXELS_MAX)

	_canvas.set_pose(_visible_amount, depth, camera.unproject_position(chest), pixels)


## The drawing. Kept as an inner class for the same reason cpr_panel_3d.gd keeps
## its own canvas inner: it has no life outside this node, and nothing else
## should be able to reach it.
class _HandsCanvas extends Control:
	var _amount: float = 0.0
	var _depth: float = 0.0
	var _at: Vector2 = Vector2.ZERO
	var _width: float = 0.0

	func hide_hands() -> void:
		if _amount == 0.0:
			return
		_amount = 0.0
		queue_redraw()

	func set_pose(amount: float, depth: float, at: Vector2, width: float) -> void:
		# Only redraw when something drawn actually moves — the same rule the
		# CPR panel follows (CPR_CONTRACT.md §6).
		if is_equal_approx(_amount, amount) and is_equal_approx(_depth, depth) \
				and _at.is_equal_approx(at) and is_equal_approx(_width, width):
			return
		_amount = amount
		_depth = depth
		_at = at
		_width = width
		queue_redraw()

	func _draw() -> void:
		if _amount <= 0.005 or _width <= 0.0:
			return
		var alpha := lerpf(ALPHA_IDLE, ALPHA_PRESSED, _depth) * _amount
		# Heel-of-palm over heel-of-palm, as it is taught. The lower hand is
		# drawn first and slightly larger; the upper one sits back and above so
		# the stacking is unmistakable even at low alpha.
		_draw_hand(_at + Vector2(0.0, _width * 0.06), _width, alpha * 0.85, true)
		_draw_hand(_at - Vector2(0.0, _width * 0.10), _width * 0.94, alpha, false)

	## A hand from behind, at a slight angle: forearm stub, tapered palm,
	## knuckle line, four fanned fingers with rounded tips, thumb tucked to the
	## side. Deliberately a silhouette with one shading pass — at a third alpha
	## over skin, outline and shape are all that survive, and more detail is
	## just noise.
	func _draw_hand(at: Vector2, width: float, alpha: float, lower: bool) -> void:
		var skin := Color(SKIN, alpha)
		var shade := Color(SKIN_SHADE, alpha * 0.55)
		var line := Color(OUTLINE, alpha * 0.75)
		var thickness := maxf(1.0, width * 0.012)
		var lean := -0.10 if lower else 0.06  # radians; the two hands cross slightly

		var palm_w := width * 0.52
		var palm_h := width * 0.60
		var wrist_h := width * 0.30

		# Forearm stub, so the hands read as attached to the trainee rather
		# than floating.
		var wrist := PackedVector2Array([
			_p(at, lean, -palm_w * 0.30, palm_h * 0.45),
			_p(at, lean, palm_w * 0.30, palm_h * 0.45),
			_p(at, lean, palm_w * 0.34, palm_h * 0.45 + wrist_h),
			_p(at, lean, -palm_w * 0.34, palm_h * 0.45 + wrist_h),
		])
		draw_colored_polygon(wrist, shade)

		var palm := PackedVector2Array([
			_p(at, lean, -palm_w * 0.50, palm_h * 0.42),
			_p(at, lean, -palm_w * 0.46, -palm_h * 0.30),
			_p(at, lean, -palm_w * 0.30, -palm_h * 0.44),
			_p(at, lean, palm_w * 0.30, -palm_h * 0.44),
			_p(at, lean, palm_w * 0.46, -palm_h * 0.30),
			_p(at, lean, palm_w * 0.50, palm_h * 0.42),
			_p(at, lean, palm_w * 0.26, palm_h * 0.56),
			_p(at, lean, -palm_w * 0.26, palm_h * 0.56),
		])
		draw_colored_polygon(palm, skin)
		draw_polyline(_closed(palm), line, thickness, true)

		# Knuckle line — the one interior detail that reads at this alpha and
		# sells the hand as pressing down rather than lying flat.
		draw_line(
			_p(at, lean, -palm_w * 0.38, -palm_h * 0.30),
			_p(at, lean, palm_w * 0.38, -palm_h * 0.30),
			shade, thickness
		)

		var finger_w := palm_w * 0.21
		for i in 4:
			# Fanned: the outer fingers splay a little and sit shorter, the
			# middle two reach furthest, as a real hand does.
			var t := float(i) - 1.5
			var x := t * (palm_w * 0.25)
			var length := width * (0.30 if absf(t) < 1.0 else 0.24)
			var tip_x := x + t * palm_w * 0.05
			var base := _p(at, lean, x, -palm_h * 0.40)
			var tip := _p(at, lean, tip_x, -palm_h * 0.40 - length)
			draw_line(base, tip, skin, finger_w)
			draw_circle(tip, finger_w * 0.5, skin)
			draw_line(base, tip, line, thickness * 0.8)

		var thumb_base := _p(at, lean, -palm_w * 0.46, palm_h * 0.10)
		var thumb_tip := _p(at, lean, -palm_w * 0.80, -palm_h * 0.16)
		draw_line(thumb_base, thumb_tip, skin, finger_w * 1.25)
		draw_circle(thumb_tip, finger_w * 0.62, skin)

	## Local offset rotated by `lean` and placed at `at` — lets the whole hand
	## be authored in upright coordinates and then tilted as one.
	func _p(at: Vector2, lean: float, x: float, y: float) -> Vector2:
		return at + Vector2(x, y).rotated(lean)

	func _closed(points: PackedVector2Array) -> PackedVector2Array:
		var out := PackedVector2Array(points)
		out.append(points[0])
		return out
