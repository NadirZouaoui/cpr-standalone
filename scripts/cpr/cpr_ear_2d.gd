extends CanvasLayer
## Translucent 2D rescuer ear, drawn over the casualty's mouth during the
## breathing check.
##
## The compression hands' counterpart, and deliberately the same idiom: a flat
## symbol pinned to the body part the input belongs to, which says *where to
## aim* and doubles as the aim indicator — if it is not showing, a press will
## not register. cpr_hands_2d.gd established that for the sternum; this is it
## for the mouth.
##
## It exists because the hold-to-observe had no cue. The trainee took the
## "Check for breathing" pointer and the game then silently demanded a
## different input — a hold, on the body, aimed somewhere unstated — while the
## only feedback was a world-space panel reading "Observing...", which names
## the mechanic rather than the act. An ear that fills as you lean in and
## listen says look-listen-feel without a word of UI.
##
## WORLD-ANCHORED, NOT SCREEN-CENTRED, for the same reason as the hands: the
## clamped mouse-look at the kneel anchor is a real range of motion, and a
## symbol pinned to the middle of the screen slides off the body and reads as a
## HUD decal rather than as the rescuer's own head going down to the mouth. It
## also scales with distance from a real-world ear width, so it sits correctly
## whichever anchor the camera is at.
##
## The mouth position comes from CprRig.pointer_marker("mouth") — the same
## marker the "Check for breathing" pill hangs off, so the cue and the pill
## that offered it cannot drift apart.
##
## Progress comes from BreathingCheck, which owns the hold. This draws it; it
## never decides it.
##
## The glyph is Tabler Icons' "ear" (MIT), whose two paths are stroke-only
## arcs. They are baked here as polylines rather than parsed at runtime: the
## conversion from SVG elliptical-arc commands is exact and only had to happen
## once, and having the icon as plain points is what lets the stroke charge
## along its own length for the hold.
##
## Hand-drawn versions came first and none of them read as an ear. The lesson
## worth keeping is that a filled body was always the mistake — an ear is
## legible as an outline and illegible as a mass, because what identifies it is
## the curl of the rim, which a fill swallows.
##
## NOW SERVES BOTH HOLDS. breathing_check.gd runs the pulse check on the same
## dwell mechanic at a different place on the body, and the pulse check shipped
## with no cue at all: the spine reached PULSE_CHECK, the "Start compressions"
## pill came up beside the chest, and nothing on screen said that a hold at the
## neck was wanted or that one was even possible. The playtest note is "cant
## check for pulse only pill shows but no action can be taken" - and that is
## what it looked like, even though the hold was live and working the whole
## time. A beat whose only instruction is a four-second centre message that has
## already faded is a beat that does not exist.
##
## So the badge follows the hold. At the mouth it is the ear; at the neck it is
## a pulse trace, drawn the same way, charging the same way, off the same
## progress. The file keeps its name for the same reason breathing_check.gd
## does: CprStation reaches it by that name and renaming buys nothing.
##
## Instanced by CprStation._build(). Nothing else references it.


const CPR_RIG_NODE_NAME := "CprRig"
const MOUTH_MARKER := &"mouth"
const NECK_MARKER := &"neck"

## Repeated from breathing_check.gd rather than read off it: that script has no
## class_name, and adding one would not be in the global class cache until the
## editor rescans — which the headless test cannot rely on. Same reason
## cpr_hands_2d.gd keeps its own copy of the mesh name.
const CASUALTY_MESH_NAME := "Casualty_CPR_Posed"
const CASUALTY_SEARCH_DEPTH := 6

## Real-world width of the drawn ear. Everything else is a fraction of this, so
## the overlay is sized by the scene rather than by the window.
## Width of the icon's own box. The disc behind it is sized from this.
const EAR_WIDTH_METRES := 0.075
## Held off the mouth so the badge floats over it rather than lying on it, and
## brought closer as the hold completes — the rescuer's head going down.
const MOUTH_LIFT_METRES := 0.055
const LEAN_TRAVEL_METRES := 0.030

const FADE_SPEED := 6.0
## The disc carries the glyph, so the icon no longer has to fight the skin
## behind it and can sit at a restrained alpha the way the hands do.
const ALPHA_IDLE := 0.55
const ALPHA_LISTENING := 0.95

## Clamped so the badge never becomes either a speck or a screen-filling blob
## if the camera ends up somewhere unexpected.
const PIXELS_MIN := 34.0
const PIXELS_MAX := 620.0

## Disc radius as a fraction of the icon box.
const DISC_RADIUS := 0.70
## The glyph shrunk and recentred inside that disc. Tabler's ear does not fill
## its own 24x24 viewBox evenly — it runs x 6..20, y 3..21, so drawn raw it
## sits off-centre and touches the rim. These put its real bounds in the middle
## with room to breathe.
##
## GLYPH_CENTRE is the ear''s own correction and travels with it; the pulse
## trace is authored centred and passes Vector2.ZERO instead.
const GLYPH_SCALE := 0.78
const GLYPH_CENTRE := Vector2(0.0415, 0.0)
## Soft shadow, faked as a few concentric discs of rising alpha rather than a
## blur pass — cheap, and at this size indistinguishable.
const SHADOW_LAYERS := 5
const SHADOW_SPREAD := 0.20
const SHADOW_DROP := 0.06

## Slate, the colour the HUD already writes in. The charged part of the stroke
## goes gold, the game's one accent.
const LINE_INK := Tokens.INK
## Stroke weight as a fraction of the icon width, so the line stays even at
## every distance instead of thickening as the badge grows.
const STROKE_FRACTION := 0.075
## The pulse trace is one unbroken line rather than two short arcs, so it reads
## much heavier at the same weight - drawn at the ear''s 0.075 it came out as a
## slab. Thinner, the way an instrument trace actually looks.
const PULSE_STROKE_FRACTION := 0.040
const STROKE_MIN := 1.5

var _canvas: _EarCanvas = null
var _visible_amount: float = 0.0
var _state: int = -1
var _cpr_rig: CprRig = null


func _ready() -> void:
	layer = 4  # under the HUD (5), so the reticle and chips stay on top
	_canvas = _EarCanvas.new()
	_canvas.name = "EarCanvas"
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
	_cpr_rig = CprGhost.find_node(root, CPR_RIG_NODE_NAME) as CprRig
	if _cpr_rig == null:
		push_error("CprEar2D: no node named '%s'; the ear has nothing to anchor to." % CPR_RIG_NODE_NAME)


## The two hold states this badge serves, and what it is at each.
##
## Kept as a pair of tiny helpers rather than one config dictionary: there are
## exactly two of them and each answer is one line.
func _is_hold_state(state: int) -> bool:
	return state == CprStation.STATE_BREATHING_CHECK 		or state == CprStation.STATE_PULSE_CHECK


func _marker_name() -> StringName:
	return NECK_MARKER if _state == CprStation.STATE_PULSE_CHECK else MOUTH_MARKER


func _on_cpr_state_changed(_from: int, to: int) -> void:
	_state = to
	set_process(_is_hold_state(_state))
	if not _is_hold_state(_state):
		_visible_amount = 0.0
		_canvas.hide_ear()
		return
	if _state == CprStation.STATE_PULSE_CHECK:
		_canvas.set_glyph(
			[_EarCanvas._PULSE], Vector2.ZERO, PULSE_STROKE_FRACTION, false)
	else:
		_canvas.set_glyph(
			[_EarCanvas._RIM, _EarCanvas._INNER], GLYPH_CENTRE, STROKE_FRACTION, true)


## The hold's owner. Resolved by name rather than held as a reference, per the
## runtime-binder rule: CprStation builds both of us and the order is not this
## file's business.
func _breathing_check() -> Node:
	var station := CprStation.get_current()
	return station.breathing_check if station != null else null


## Also gated on the shared "at the anchor" rule (CprStation.trainee_at_anchor()):
## the ear is pinned to the mouth in world space, so standing up would otherwise
## leave one lying on the casualty's face from across the room.
func _process(delta: float) -> void:
	if _cpr_rig == null or not is_instance_valid(_cpr_rig):
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	var station := CprStation.get_current()
	if station != null and not station.trainee_at_anchor():
		_visible_amount = 0.0
		_canvas.hide_ear()
		return

	var check := _breathing_check()
	# The station stays in BREATHING_CHECK after the hold completes, waiting on
	# the "Start compressions" pointer, so state alone no longer means there is
	# something to do at the mouth. Once the check is done the cue goes.
	if check != null and check.is_done():
		_visible_amount = 0.0
		_canvas.hide_ear()
		return

	var progress: float = check.hold_progress() if check != null else 0.0
	var holding: bool = check.is_holding() if check != null else false

	# Same aim test the hold itself uses, so the ear showing and the press
	# counting are the same fact. Held visible for the duration of a hold
	# already under way, so a hold started on target cannot have its own
	# feedback yanked mid-listen.
	var on_body := holding or CprInteractBridge.crosshair_on_casualty(CASUALTY_SEARCH_DEPTH)
	_visible_amount = move_toward(_visible_amount, 1.0 if on_body else 0.0, FADE_SPEED * delta)
	if _visible_amount <= 0.005:
		_canvas.hide_ear()
		return

	var marker := _cpr_rig.pointer_marker(_marker_name())
	if marker == null:
		_canvas.hide_ear()
		return
	# Centred on the mouth now, not offset beside it: the disc gives the glyph
	# its own ground, so it no longer disappears into the face the way a bare
	# outline did.
	var mouth := marker.global_position 		+ Vector3.UP * (MOUTH_LIFT_METRES - LEAN_TRAVEL_METRES * progress)
	if camera.is_position_behind(mouth):
		_canvas.hide_ear()
		return

	# Size from a real width rather than a viewport fraction: project a segment
	# of EAR_WIDTH_METRES lying across the camera's own right axis and measure
	# how many pixels it covers from here.
	var right := camera.global_transform.basis.x.normalized()
	var span := camera.unproject_position(mouth + right * EAR_WIDTH_METRES) \
		- camera.unproject_position(mouth)
	var pixels := clampf(span.length(), PIXELS_MIN, PIXELS_MAX)

	_canvas.set_pose(_visible_amount, progress, camera.unproject_position(mouth), pixels)


## The drawing. Inner class for the same reason cpr_hands_2d.gd keeps its own:
## it has no life outside this node, and nothing else should reach it.
class _EarCanvas extends Control:
	var _amount: float = 0.0
	var _progress: float = 0.0
	var _at: Vector2 = Vector2.ZERO
	var _width: float = 0.0

	## Which glyph is drawn, and its own centring correction. Set when the hold
	## state changes; defaults to the ear so a canvas that has never been told
	## draws what it always drew.
	var _curves: Array = [_RIM, _INNER]
	var _centre: Vector2 = GLYPH_CENTRE
	var _stroke_fraction: float = STROKE_FRACTION
	var _caps: bool = true

	func set_glyph(curves: Array, centre: Vector2, stroke_fraction: float,
			caps: bool) -> void:
		_curves = curves
		_centre = centre
		_stroke_fraction = stroke_fraction
		_caps = caps
		queue_redraw()

	func hide_ear() -> void:
		if _amount == 0.0:
			return
		_amount = 0.0
		queue_redraw()

	func set_pose(amount: float, progress: float, at: Vector2, width: float) -> void:
		# Only redraw when something drawn actually moves — the same rule the
		# CPR panel follows.
		if is_equal_approx(_amount, amount) and is_equal_approx(_progress, progress) \
				and _at.is_equal_approx(at) and is_equal_approx(_width, width):
			return
		_amount = amount
		_progress = progress
		_at = at
		_width = width
		queue_redraw()

	## A glass disc with a soft shadow, carrying Tabler's ear outline, whose
	## stroke charges from slate to gold along its own length as the hold runs.
	##
	## Charging along the path rather than flooding a fill or sweeping a
	## separate ring: the thing that fills is the thing being asked for, and a
	## line that draws itself in reads as an action completing rather than as a
	## meter bolted alongside one.
	func _draw() -> void:
		if _amount <= 0.005 or _width <= 0.0:
			return
		var w := _width
		var alpha := lerpf(ALPHA_IDLE, ALPHA_LISTENING, _progress) * _amount
		var radius := w * DISC_RADIUS

		_draw_shadow(_at, radius, _amount)

		var disc := Tokens.GLASS_FILL
		disc.a *= alpha
		draw_circle(_at, radius, disc)
		var rim := Tokens.GLASS_BORDER
		rim.a *= alpha * 0.7
		draw_arc(_at, radius, 0.0, TAU, 48, rim, maxf(1.0, w * 0.02), true)

		var stroke := maxf(STROKE_MIN, w * _stroke_fraction)
		var ink := LINE_INK
		ink.a = alpha
		var gold := Tokens.ATTENTION
		gold.a = alpha

		# Both paths charge on the same fraction rather than one after the
		# other — the inner hook is short enough that running it second would
		# complete in a blink and read as a glitch.
		for curve in _curves:
			var pts := _fillet(_scaled(curve, _at, w), stroke * CORNER_RADIUS)
			_stroke_path(pts, ink, stroke)
			if _progress > 0.001:
				_stroke_path(_prefix(pts, clampf(_progress, 0.0, 1.0)), gold, stroke)

	## Concentric discs of rising alpha, dropped slightly, standing in for a
	## blur. Drawn largest first so the layers accumulate toward the centre.
	func _draw_shadow(at: Vector2, radius: float, amount: float) -> void:
		var base := Tokens.GLASS_SHADOW
		var centre := at + Vector2(0.0, radius * SHADOW_DROP)
		for i in range(SHADOW_LAYERS):
			var t := float(i) / float(SHADOW_LAYERS - 1)
			var c := base
			c.a = base.a * amount * (0.25 + 0.75 * t) / float(SHADOW_LAYERS)
			draw_circle(centre, radius * (1.0 + SHADOW_SPREAD * (1.0 - t)), c)

	## Corner radius, as a multiple of the stroke width. See _fillet().
	const CORNER_RADIUS := 2.2
	## Points sampled across each rounded corner.
	const CORNER_STEPS := 6

	## Round off every interior corner of a polyline.
	##
	## draw_polyline() miters its joints, and a miter at a sharp angle is
	## several times wider than the line it joins. On the ear that never showed
	## - its two arcs are already smooth - but the pulse trace turns through
	## nearly 180 degrees at the top of the R wave and twice more at the feet of
	## it, and the playtest note is exactly what a miter looks like: "its kind
	## of skewed the thickness varies along the stroke." The spike came out
	## heavy at the apex and light on the flanks.
	##
	## Cutting each corner back by a couple of stroke widths and bridging the
	## gap with a quadratic arc keeps every joint shallow, so the drawn width is
	## the width asked for everywhere along the path. The corner is never cut
	## back further than a third of either adjacent segment, so a short segment
	## cannot be eaten by the two fillets on its ends.
	func _fillet(points: PackedVector2Array, radius: float) -> PackedVector2Array:
		if points.size() < 3 or radius <= 0.0:
			return points
		var out := PackedVector2Array()
		out.append(points[0])
		for i in range(1, points.size() - 1):
			var prev: Vector2 = points[i - 1]
			var here: Vector2 = points[i]
			var next: Vector2 = points[i + 1]
			var back_len := here.distance_to(prev)
			var fwd_len := here.distance_to(next)
			if back_len <= 0.001 or fwd_len <= 0.001:
				out.append(here)
				continue
			var r: float = minf(radius, minf(back_len, fwd_len) / 3.0)
			var a := here + (prev - here).normalized() * r
			var b := here + (next - here).normalized() * r
			for step in range(CORNER_STEPS + 1):
				var t := float(step) / float(CORNER_STEPS)
				out.append(a.lerp(here, t).lerp(here.lerp(b, t), t))
		out.append(points[points.size() - 1])
		return out

	## Round caps, which draw_polyline does not do: a dot at each end at the
	## stroke's own radius. Tabler draws with stroke-linecap="round" and the
	## shape looks bitten off without them.
	##
	## Off for the pulse trace: its two ends are the flat of the baseline, and a
	## dot there reads as a bead on a thread rather than as a cap. The ear''s
	## arcs genuinely stop mid-curve and need them.
	func _stroke_path(points: PackedVector2Array, colour: Color, width: float) -> void:
		if points.size() < 2:
			return
		draw_polyline(points, colour, width, true)
		if not _caps:
			return
		draw_circle(points[0], width * 0.5, colour)
		draw_circle(points[points.size() - 1], width * 0.5, colour)

	## The icon's unit-space points placed and scaled onto the screen.
	func _scaled(curve: Array, at: Vector2, w: float) -> PackedVector2Array:
		var out := PackedVector2Array()
		for p in curve:
			out.append(at + ((p as Vector2) - _centre) * (w * GLYPH_SCALE))
		return out

	## The leading `fraction` of a polyline by arc length, cut mid-segment so
	## the charge advances smoothly rather than snapping point to point.
	func _prefix(points: PackedVector2Array, fraction: float) -> PackedVector2Array:
		var out := PackedVector2Array()
		if points.size() < 2:
			return out
		var total := 0.0
		for i in range(points.size() - 1):
			total += points[i].distance_to(points[i + 1])
		var want := total * fraction
		if want <= 0.0:
			return out
		out.append(points[0])
		var run := 0.0
		for i in range(points.size() - 1):
			var seg := points[i].distance_to(points[i + 1])
			if run + seg >= want:
				var t := 0.0 if seg <= 0.0 else (want - run) / seg
				out.append(points[i].lerp(points[i + 1], t))
				break
			run += seg
			out.append(points[i + 1])
		return out

	const _RIM := [
		Vector2(-0.2500, -0.0833), Vector2(-0.2478, -0.1191), Vector2(-0.2413, -0.1542),
		Vector2(-0.2305, -0.1884), Vector2(-0.2156, -0.2209), Vector2(-0.1969, -0.2514),
		Vector2(-0.1745, -0.2793), Vector2(-0.1489, -0.3044), Vector2(-0.1204, -0.3260),
		Vector2(-0.0895, -0.3441), Vector2(-0.0566, -0.3582), Vector2(-0.0223, -0.3681),
		Vector2(0.0131, -0.3738), Vector2(0.0488, -0.3751), Vector2(0.0845, -0.3721),
		Vector2(0.1195, -0.3647), Vector2(0.1533, -0.3530), Vector2(0.1855, -0.3373),
		Vector2(0.2155, -0.3178), Vector2(0.2429, -0.2947), Vector2(0.2672, -0.2685),
		Vector2(0.2882, -0.2395), Vector2(0.3054, -0.2081), Vector2(0.3187, -0.1749),
		Vector2(0.3278, -0.1403), Vector2(0.3326, -0.1048), Vector2(0.3330, -0.0690),
		Vector2(0.3290, -0.0334), Vector2(0.3207, 0.0014), Vector2(0.3082, 0.0349),
		Vector2(0.2917, 0.0667), Vector2(0.2844, 0.0760), Vector2(0.2769, 0.0852),
		Vector2(0.2692, 0.0941), Vector2(0.2612, 0.1028), Vector2(0.2530, 0.1113),
		Vector2(0.2445, 0.1195), Vector2(0.2358, 0.1275), Vector2(0.2268, 0.1353),
		Vector2(0.2177, 0.1428), Vector2(0.2083, 0.1500), Vector2(0.1975, 0.1606),
		Vector2(0.1872, 0.1718), Vector2(0.1775, 0.1833), Vector2(0.1682, 0.1953),
		Vector2(0.1595, 0.2077), Vector2(0.1514, 0.2205), Vector2(0.1439, 0.2337),
		Vector2(0.1370, 0.2472), Vector2(0.1307, 0.2609), Vector2(0.1250, 0.2750),
		Vector2(0.1144, 0.2927), Vector2(0.1018, 0.3091), Vector2(0.0876, 0.3240),
		Vector2(0.0718, 0.3373), Vector2(0.0546, 0.3488), Vector2(0.0363, 0.3583),
		Vector2(0.0170, 0.3657), Vector2(-0.0029, 0.3710), Vector2(-0.0233, 0.3740),
		Vector2(-0.0440, 0.3748), Vector2(-0.0645, 0.3733), Vector2(-0.0848, 0.3695),
		Vector2(-0.1046, 0.3636), Vector2(-0.1236, 0.3555), Vector2(-0.1416, 0.3454),
		Vector2(-0.1583, 0.3333),
	]

	## A single heartbeat trace, authored centred on the origin. Two fingers on
	## a neck has no icon that reads at badge size - every attempt looked like a
	## peace sign or a pause button - but a QRS complex says "pulse" and nothing
	## else, and it charges left to right along its own length exactly the way
	## the ear''s rim does. Sparse on purpose: _prefix() cuts mid-segment by arc
	## length, so the charge is smooth however few points there are.
	const _PULSE := [
		Vector2(-0.4200, 0.0000), Vector2(-0.1700, 0.0000),
		Vector2(-0.1150, 0.0900), Vector2(-0.0600, -0.3200),
		Vector2(-0.0050, 0.1900), Vector2(0.0450, 0.0000),
		Vector2(0.4200, 0.0000),
	]

	const _INNER := [
		Vector2(-0.0833, -0.0833), Vector2(-0.0815, -0.1059), Vector2(-0.0757, -0.1278),
		Vector2(-0.0660, -0.1483), Vector2(-0.0528, -0.1667), Vector2(-0.0364, -0.1824),
		Vector2(-0.0175, -0.1949), Vector2(0.0033, -0.2038), Vector2(0.0254, -0.2088),
		Vector2(0.0481, -0.2097), Vector2(0.0705, -0.2065), Vector2(0.0920, -0.1992),
		Vector2(0.1118, -0.1883), Vector2(0.1294, -0.1739), Vector2(0.1440, -0.1566),
		Vector2(0.1553, -0.1369), Vector2(0.1628, -0.1156), Vector2(0.1664, -0.0932),
		Vector2(0.1658, -0.0705), Vector2(0.1612, -0.0483), Vector2(0.1527, -0.0273),
		Vector2(0.1405, -0.0082), Vector2(0.1250, 0.0083),
	]
