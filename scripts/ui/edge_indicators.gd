extends CanvasLayer
## Screen-edge arrows to the things the run marks in the world.
##
## Client, 23 Sep 2026: "make the yellow pointers point to the side of the
## screen if the player is not looking in their direction, like in video games.
## Do the same for 'isolate circuit breaker', since that's when the player faces
## the other direction."
##
## Anything that wants an arrow joins GROUP for as long as it wants one, and may
## carry an "edge_label" meta for the tag beside it:
##
##   - the yellow objective beacons (objective_beacon.gd) while they are shown,
##   - the anchors of the two extraction pills (extraction_pointers.gd),
##   - the anchor of the "Interact with casualty" pill (casualty_pill.gd).
##
## Nothing is drawn for a target that is in view - there the beacon or the pill
## is its own sign. Screen-space, so it follows whichever camera is current.

const GROUP := &"edge_target"
## Above the HUD (5) and the pills (6), below the centre card (8) and every
## blocking screen.
const LAYER := 7

## Every marked point this frame, in view or not. HelpGuide reads it so its own
## arrow stands down when a marker is already showing the way.
static var active_points: Array[Vector3] = []

var _canvas: EdgeCanvas


func _ready() -> void:
	layer = LAYER
	_canvas = EdgeCanvas.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)


func _exit_tree() -> void:
	active_points = []


func _process(_delta: float) -> void:
	var points: Array[Vector3] = []
	var items: Array = []
	for node in get_tree().get_nodes_in_group(GROUP):
		var n3 := node as Node3D
		if n3 == null or not n3.is_visible_in_tree():
			continue
		points.append(n3.global_position)
		items.append({
			"point": n3.global_position,
			"label": String(n3.get_meta(&"edge_label", "")),
		})
	active_points = points
	_canvas.items = [] if Events.is_ui_blocking() else items
	_canvas.queue_redraw()


## True when a marker is already guiding the trainee to within `metres` of
## `point`.
static func is_marked_near(point: Vector3, metres: float = 1.2) -> bool:
	for p in active_points:
		if p.distance_to(point) < metres:
			return true
	return false


class EdgeCanvas extends Control:
	const EDGE_MARGIN := 70.0
	const TAG_SIZE := 16

	var items: Array = []
	var _t: float = 0.0
	var _tag_style: StyleBoxFlat

	func _ready() -> void:
		_tag_style = Tokens.glass_chip()

	func _process(delta: float) -> void:
		_t += delta

	func _draw() -> void:
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		var vp := get_viewport_rect().size
		var centre := vp * 0.5
		var bob := sin(_t * 5.0) * 6.0
		for item in items:
			var point: Vector3 = item["point"]
			var behind := cam.is_position_behind(point)
			var s := cam.unproject_position(point)
			if not behind and s.x > 0.0 and s.x < vp.x and s.y > 0.0 and s.y < vp.y:
				continue
			var dir := s - centre
			if behind:
				dir = -dir
			if dir.length() < 0.001:
				dir = Vector2.DOWN
			dir = dir.normalized()
			var half := centre - Vector2(EDGE_MARGIN, EDGE_MARGIN)
			var kx := absf(half.x / dir.x) if absf(dir.x) > 0.0001 else INF
			var ky := absf(half.y / dir.y) if absf(dir.y) > 0.0001 else INF
			var pos := centre + dir * minf(kx, ky) + dir * bob
			_draw_pointer(pos, dir)

			var verb := "turn around" if behind else "turn this way"
			if not behind and absf(dir.y) > absf(dir.x) * 1.5:
				verb = "look up" if dir.y < 0.0 else "look down"
			var label: String = item["label"]
			var line: String = (verb.substr(0, 1).to_upper() + verb.substr(1)) if label == "" \
				else "%s - %s" % [label, verb]
			_draw_tag(pos - dir * 84.0, line)

	## Block arrow, tip at `tip`, pointing along `dir`.
	func _draw_pointer(tip: Vector2, dir: Vector2) -> void:
		var perp := Vector2(-dir.y, dir.x)
		var back := tip - dir * 30.0
		var tail := back - dir * 26.0
		var pts := PackedVector2Array([
			tip, back + perp * 20.0, back + perp * 8.0, tail + perp * 8.0,
			tail - perp * 8.0, back - perp * 8.0, back - perp * 20.0,
		])
		draw_colored_polygon(pts, Tokens.ATTENTION)
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, Tokens.INK, 2.5, true)

	func _draw_tag(at: Vector2, text: String) -> void:
		var font := get_theme_default_font()
		var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, TAG_SIZE)
		var box := Vector2(ts.x + 24.0, ts.y + 12.0)
		var vp := get_viewport_rect().size
		var pos := at - box * 0.5
		pos.x = clampf(pos.x, 8.0, vp.x - box.x - 8.0)
		pos.y = clampf(pos.y, 8.0, vp.y - box.y - 8.0)
		draw_style_box(_tag_style, Rect2(pos, box))
		draw_string(font, pos + Vector2(12.0, 6.0 + font.get_ascent(TAG_SIZE)), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, TAG_SIZE, Tokens.INK)