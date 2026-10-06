extends CanvasLayer
## Floating contextual pointers on the casualty's body.
##
## A callout is a glass pill with a leader line back to a marked point on the
## body: the line says *which body part*, the pill says *what to do there*, and
## the pill is the thing the trainee clicks.
##
## Drawn in 2D and anchored to the world, the way cpr_hands_2d.gd already is,
## rather than as a billboarded quad in the scene. The text stays crisp at any
## distance (the SubViewport card blurs as you lean in), the leader line is a
## two-segment polyline instead of mesh work, there is no per-callout viewport,
## and pills can be nudged apart in screen space — which matters, because an
## overlap between two pills is an ambiguous click, not just an ugly frame.
##
## Anchors come from CprRig.pointer_marker(), which re-poses them off the
## casualty's skeleton every frame, so the callouts follow the body without
## measuring anything here.
##
## Input follows the rest of the game (CPR_CONTRACT.md §4.0): mouse stays
## captured, the crosshair is the cursor, `interact` activates. No Area3D, no
## colliders — the hit test is the crosshair against the pill's own screen rect.

## Emitted when the trainee clicks a pill. The id is the caller's own, straight
## back out of the callout it passed in.
signal activated(id: StringName)

## Slop around a pill's rect, in pixels, so a click that lands a hair outside
## still counts.
const HIT_SLOP := 6.0

## How close the crosshair has to get to a pill's centre before that pill is
## the one selected, when the crosshair is not inside any pill at all.
##
## Playtest: "the pills seem to run away from you when you go to click them."
## They do, and it is geometry rather than a bug. A perspective camera projects
## an off-axis point at `f * tan(angle)`, so a pill hanging off a body part 30-40
## degrees out from the centre of the frame travels further across the screen
## than the crosshair does for the same mouse movement. Aiming at it walks it
## outwards, and the further out it already is, the worse the chase gets - which
## is exactly the moment the trainee is trying to click it.
##
## Requiring the crosshair to land INSIDE a ~300x40 px rect is what makes that
## chase matter. With a capture radius, aiming in the pill's direction is
## enough: nearest-centre-within-the-radius wins, the pill lights up, and the
## click lands. Nothing else about the layout changes.
##
## Measured from the EDGE of the pill, not its centre, and deliberately modest.
##
## It was 220 from the centre, which is most of a pill-width of slop on top of
## a pill that is already 300 px wide - in practice a chest-anchored pill owned
## a third of the screen. The casualty''s body is not all pills: the breathing
## check is a hold at the mouth, offered by CasualtyInteractable, and a pill
## that captures the crosshair also eats the click (see _unhandled_input). A
## trainee aiming at the mouth for look-listen-feel got "Start compressions"
## instead, which is not a mis-click - the click never reached the mouth at
## all.
##
## Edge distance is the honest measure anyway: it means "just outside the pill"
## regardless of how long the label is, where centre distance quietly gave long
## labels a bigger catchment than short ones.
const CAPTURE_RADIUS := 70.0

## Hysteresis on that capture: once a pill is selected it keeps the selection
## until the crosshair is this much further away than the radius that won it.
##
## Without it, two pills the crosshair sits between swap the highlight back and
## forth on sub-pixel camera drift - the body is re-posed off the skeleton every
## frame, so the projection is never quite still - and the pill under the click
## is not reliably the one that was gold when the trainee pressed.
const CAPTURE_STICKY := 24.0

## Pills are hit targets before they are labels: this is a comfortable minimum
## at 1080p rather than whatever the text happens to measure.
const PILL_MIN_HEIGHT := 40.0
const PILL_PAD_X := 20.0
const PILL_PAD_Y := 10.0
const FONT_SIZE := 20

## Where a pill sits relative to its anchor, before collision nudging: out to
## the side and up, so it lands clear of the body instead of on top of it.
##
## Pulled in from (150, -95). The offset is added to an already off-axis anchor,
## so it pushes the pill further out into the part of the frame where the
## tangent stretch above is worst - see CAPTURE_RADIUS. Close enough to still
## clear the body, near enough that the leader line stays short and the pill
## stays in the half of the frame the trainee is looking at.
const PILL_OFFSET := Vector2(105.0, -70.0)

## How far past the right margin an anchor has to be before its pill gives up
## and flips to the left of the body.
##
## The flip used to trigger the instant the pill''s right edge crossed the
## margin, which on a moving camera is a threshold the anchor sits exactly on:
## a degree of look sent the pill to the far side of the casualty and back,
## every frame, with the leader line sweeping across the body each time. The
## deadband means an anchor drifting along the edge stays where it is, and only
## a real commitment to the right-hand side moves it.
const FLIP_HYSTERESIS := 90.0

## Seconds for a pill to cover 63% of the distance to where the solver has just
## decided it belongs (exponential, so it never quite arrives and never
## overshoots).
##
## Every frame re-solves the whole layout from scratch - project, flip, stack -
## and the stack in particular is discontinuous: two anchors swapping vertical
## order teleports both pills. Solving is right; snapping to the solution is
## not. The pill is drawn chasing its solved rect instead, which turns each of
## those rearrangements into a short slide.
##
## Deliberately short. This is damping, not animation: at a still camera the
## pill is on its mark within about a tenth of a second, and the click target
## the trainee is aiming at is the rect they can see, because _pick() is handed
## the smoothed rects and not the solved ones.
const SETTLE_TAU := 0.055

## Below this the pill is close enough that smoothing is just jitter; it snaps
## the rest of the way. Also what stops a pill that has settled from being
## recomputed forever at sub-pixel scale.
const SETTLE_SNAP := 0.75

## Anything further than this is a new pill, a flip, or a camera cut rather
## than drift, and is not worth sliding across the screen.
const SETTLE_TELEPORT := 420.0
## Kept this far from the viewport edge.
const SCREEN_MARGIN := 24.0

## The bottom strip the HUD owns, measured from the bottom edge, and the one
## place a body pill may not go.
##
## hud.gd parks two centred glass pills there - the transient feedback message
## at MESSAGE_BOTTOM_MARGIN (92) and the standing step pill at
## STEP_PILL_BOTTOM_MARGIN (34), each about 39 px tall - so the furniture runs
## from roughly 131 px above the bottom edge down to the edge itself.
##
## Without this the chest pill lands right on top of the feedback message,
## because the chest anchor projects near the bottom of the frame at the head
## and kneel anchors. Seen in playtest: "Look, listen and feel - hold Left
## Click at the mouth" with "Start compressions" drawn across the last two
## words of it. The step pill already stands down for body pointers (see
## hud.gd::_sync_step_pill), but the feedback message must not - it is the
## receipt for the action that just happened.
##
## A pill pushed up out of the band keeps its leader line, which is the whole
## reason the leader line exists.
const HUD_BOTTOM_BAND := 136.0
## Vertical gap when one pill has to be pushed off another.
const STACK_GAP := 8.0

## Deadband on the choice between stacking down and stacking up. See _avoid().
const STACK_HYSTERESIS := 60.0

## The leader line runs from the anchor to a short horizontal stub at the
## pill's edge, giving it the elbow a hand-drawn callout has.
const ELBOW_LENGTH := 22.0
const ANCHOR_DOT_RADIUS := 4.0
const LINE_WIDTH := 2.0

## Anchor dot, leader line and the pill rim. The scene colour, not the ink
## colour: these are drawn over the room, not on glass.
const LINE_COLOR := Color(1, 1, 1, 0.85)

## A pill fades and rises into place rather than appearing between frames — the
## set changes mid-procedure (one step completing reveals the next), and a
## silent swap reads as a glitch rather than as a new instruction.
const APPEAR_SECONDS := 0.18
const APPEAR_RISE := 12.0

var _root: Control = null
var _canvas: _PointerCanvas = null

## Array of { "id": StringName, "anchor": StringName, "label": String }.
var _callouts: Array = []
var _hovered: StringName = &""
var _active: bool = false

## When false the layer is a signpost: it draws, it follows the world, and it
## never highlights or claims the interact key.
##
## The extraction beat needs that. Its two pills name things across the room -
## the casualty and the breaker handle - and the trainee acts on them by
## walking up and using the object itself. A pill that could be clicked from
## the far side of the switchroom would isolate the board without the trainee
## ever going back to it, which is the opposite of what the beat teaches; and
## a pill that merely SWALLOWED the interact key would be worse still, because
## standing at the handle and pressing it would then do nothing at all.
var interactive: bool = true

## Draw each pill ON its anchor instead of beside it on a leader line, and let
## it leave the frame with the thing it names.
##
## The ordinary layout is built for a body the trainee is kneeling over: every
## anchor is on the casualty, a few hand-widths apart, so the pills are offset
## out to the side, stacked apart, kept out of the HUD's band and pinned inside
## the screen margin when their anchor runs off the edge. All of that is right
## for the body and wrong for a signpost.
##
## Playtest, the extraction beat: "we don't have to keep the pills on screen for
## this, keep them at their locations (body/breaker)." The breaker is across the
## room and frequently behind the trainee; its anchor clamped to the screen
## margin and the pill sat over a patch of empty floor with a leader line
## running off-frame, naming nothing the trainee could see. The two pills are
## the whole point of the beat - they exist to say WHERE the two jobs are - and
## a pill that has been dragged into the frame no longer says that.
##
## So a pinned pill is a label on an object: centred on it, no leader line, no
## edge clamp, and gone when the object is out of shot. Turning round to find it
## is the beat.
var pin_to_anchor: bool = false

## id -> ticks_msec when it first appeared, for the entry animation. Kept
## across solves so a pill already on screen does not restart its fade every
## time the set is rebuilt.
var _appeared: Dictionary = {}

## id -> +1 (pill to the right of its anchor) or -1 (to the left). Persists
## across frames so the flip can be hysteretic; see FLIP_HYSTERESIS.
var _side: Dictionary = {}

## id -> the Vector2 the pill is actually drawn at, chasing the solved
## position. See SETTLE_TAU.
var _settled: Dictionary = {}

## id -> +1 (this pill stacks BELOW the ones already placed) or -1 (above).
## Persists across frames so the choice can be hysteretic; see _avoid().
var _stack_dir: Dictionary = {}

## Ticks at the last _solve(), for the smoothing step. Gameplay timing is
## msec-based project-wide rather than frame-delta based (CLAUDE.md), and this
## runs inside a WebGL canvas where the two disagree.
var _last_solve_ms: int = 0


func _ready() -> void:
	layer = 6  # above the HUD chips, below the blocking screens
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_canvas = _PointerCanvas.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_canvas)

	visible = false
	set_process(false)


# =============================================================================
# Public API
# =============================================================================
## Replace the visible set. Empty hides the layer.
##
## Callers own the sequencing: this draws exactly what it is handed, in the
## order it is handed, and reports back which one was clicked.
func set_callouts(callouts: Array) -> void:
	_callouts = callouts
	_hovered = &""
	_active = not _callouts.is_empty()
	visible = _active
	set_process(_active)
	# Anything no longer offered forgets its appear time, so that if the same
	# step comes back it animates in again.
	var live: Dictionary = {}
	for callout in _callouts:
		live[callout.get("id", &"")] = true
	for id in _appeared.keys():
		if not live.has(id):
			_appeared.erase(id)
			_side.erase(id)
			_settled.erase(id)
			_stack_dir.erase(id)

	if _active:
		_solve()
	else:
		_canvas.pills = []
		_canvas.queue_redraw()


func clear() -> void:
	set_callouts([])


func hovered_id() -> StringName:
	return _hovered


## How many pills are actually drawn right now, as opposed to how many
## callouts were handed over. The two differ while the CPR camera is tweening
## into an anchor, and anything that reads "is the trainee being given a
## direction on screen" has to ask this one.
func drawn_count() -> int:
	return _canvas.pills.size() if _canvas != null else 0


# =============================================================================
# Layout
# =============================================================================
func _process(_delta: float) -> void:
	_solve()


## Projects every anchor, lays its pill out beside it, pushes overlapping pills
## apart, then works out which one the crosshair is on. Re-solved every frame:
## the body, the camera and the trainee's aim all move.
func _solve() -> void:
	var camera := get_viewport().get_camera_3d()
	var rig := _rig()
	if camera == null or (rig == null and not _all_callouts_carry_nodes()):
		# Cleared, not left standing: the selection is sticky now (see _pick),
		# and a stale id would come back the moment the camera does.
		_hovered = &""
		_settled.clear()
		_canvas.pills = []
		_canvas.hovered = _hovered
		_canvas.queue_redraw()
		return

	var screen := get_viewport().get_visible_rect().size
	var crosshair := screen * 0.5
	var placed: Array = []

	var now := Time.get_ticks_msec()
	var dt: float = clampf(float(now - _last_solve_ms) / 1000.0, 0.0, 0.25)
	_last_solve_ms = now

	for callout in _ordered_callouts(camera, rig):
		var marker := _marker_for(callout, rig)
		if marker == null:
			continue
		# Behind the camera unprojects to a mirrored point in front of it,
		# which would draw a pill for a body part nobody can see.
		if camera.is_position_behind(marker.global_position):
			continue

		var projected := camera.unproject_position(marker.global_position)
		# An anchor off the edge of the screen is clamped into the margin
		# rather than dropped. Dropping it was a hard block: at the head
		# anchor the chest marker projects below the bottom edge, so "Open
		# the shirt" vanished - and CasualtyInteractable stays silent while
		# the sequence is open, leaving nothing on screen to click and no
		# prompt to bring it back. A pill pinned to the edge with its leader
		# line pointing off-frame still says which way the body part is.
		#
		# A pinned pill is the opposite case and wants the opposite rule: it
		# names a place, so it leaves with the place. See pin_to_anchor.
		if pin_to_anchor and not Rect2(Vector2.ZERO, screen).has_point(projected):
			continue
		var anchor := projected if pin_to_anchor \
			else _clamp_to_screen(projected, screen)

		var id: StringName = callout.get("id", &"")
		var label := String(callout.get("label", ""))
		var size := _measure(label)
		var pill := Rect2(anchor - size * 0.5, size) if pin_to_anchor \
			else _pill_rect(id, anchor, size, screen)
		if not pin_to_anchor:
			pill = _avoid(id, pill, placed, screen)
		pill.position = _settle(id, pill.position, dt)

		if not _appeared.has(id):
			_appeared[id] = Time.get_ticks_msec()
		var age := float(Time.get_ticks_msec() - int(_appeared[id])) / 1000.0
		var t := clampf(age / APPEAR_SECONDS, 0.0, 1.0)
		var eased := 1.0 - pow(1.0 - t, 3.0)
		pill.position.y += (1.0 - eased) * APPEAR_RISE

		placed.append({
			"id": id,
			"label": label,
			"anchor": anchor,
			"rect": pill,
			"alpha": eased,
		})

	_hovered = _pick(placed, crosshair) if interactive else &""
	_canvas.pinned = pin_to_anchor
	_canvas.pills = placed
	_canvas.hovered = _hovered
	_canvas.queue_redraw()


## Vertical bucket the placement order is decided in, pixels. See
## _ordered_callouts().
const ORDER_BUCKET := 8.0


## The callouts, highest anchor on screen first.
##
## _avoid() pushes each pill DOWN past the ones already placed, so whatever
## order this returns is the order the pills end up in from the top of the
## screen. Handing it the caller's list order meant the stack followed the
## PROCEDURE rather than the body, and the two disagree: `fire_checked` is
## offered before `start_compressions` and hangs off the belly, which is the
## LOWER anchor. The fire pill therefore took the upper slot and pushed
## compressions below it, and the two leader lines crossed over each other on
## the way to their anchors.
##
## Playtest: "'start compression' pill still going under 'check not on fire', it
## should never do that." Ordering by anchor instead makes that structural: a
## pill can only ever be below another pill whose body part is higher up the
## casualty, so the leader lines can no longer cross whatever set is live.
##
## The y is quantised before it is compared, and ties fall back to the caller's
## own order. Anchors are re-posed off the skeleton every frame and never quite
## still, so a bare comparison on two anchors at the same height would swap the
## stack back and forth once a frame - the same class of fault STACK_HYSTERESIS
## and FLIP_HYSTERESIS exist for. Everything on this body is at least a bucket
## apart; this only decides what happens if that ever stops being true.
func _ordered_callouts(camera: Camera3D, rig: CprRig) -> Array:
	var keyed: Array = []
	for i in _callouts.size():
		var callout: Dictionary = _callouts[i]
		var marker := _marker_for(callout, rig)
		var bucket := 0
		if marker != null and not camera.is_position_behind(marker.global_position):
			bucket = int(floor(
				camera.unproject_position(marker.global_position).y / ORDER_BUCKET))
		keyed.append({"callout": callout, "bucket": bucket, "index": i})
	keyed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["bucket"] != b["bucket"]:
			return a["bucket"] < b["bucket"]
		return a["index"] < b["index"])

	var out: Array = []
	for entry: Dictionary in keyed:
		out.append(entry["callout"])
	return out


## Which pill the crosshair has, or &"" for none.
##
## Two tiers. A crosshair inside a pill takes that pill outright, which is the
## old behaviour and the unambiguous case. Otherwise the nearest pill EDGE
## within CAPTURE_RADIUS takes it - just missing a pill still counts, so one
## that the camera's own tangent stretch is walking away from the crosshair is
## still clickable. The pill that already held the selection defends it by
## CAPTURE_STICKY, so the highlight does not flicker between two of them.
##
## Everything outside that band belongs to whatever else the trainee is aiming
## at - the mouth hold, the casualty themselves, the room. A pill only takes a
## click it is plausibly the target of.
func _pick(placed: Array, crosshair: Vector2) -> StringName:
	var inside := &""
	var inside_d := INF
	var near := &""
	var near_d := INF

	for entry in placed:
		# Not clickable until it has finished arriving: a pill sliding under
		# the crosshair should not take a click aimed at what was there before.
		if float(entry["alpha"]) < 1.0:
			continue
		var id: StringName = entry["id"]
		var rect: Rect2 = entry["rect"]
		# Two distances: to the edge, which decides whether the pill is in
		# reach at all, and to the centre, which breaks ties between pills the
		# crosshair is inside. The incumbent is measured as if it were closer
		# than it is on both, which is what makes the selection sticky.
		var edge: float = _distance_to_rect(rect, crosshair)
		var centre: float = rect.get_center().distance_to(crosshair)
		if id == _hovered:
			edge -= CAPTURE_STICKY
			centre -= CAPTURE_STICKY

		if rect.grow(HIT_SLOP).has_point(crosshair):
			# Nearest to the centre wins, so two pills the crosshair straddles
			# resolve to the one the trainee is actually looking at.
			if centre < inside_d:
				inside_d = centre
				inside = id
		elif edge < near_d and edge <= CAPTURE_RADIUS:
			near_d = edge
			near = id

	return inside if inside != &"" else near


## Shortest distance from a point to a rectangle; 0 when the point is inside.
## Rect2 has no such method, and Rect2.grow()/has_point() only answers the
## yes/no form.
func _distance_to_rect(rect: Rect2, point: Vector2) -> float:
	var closest := Vector2(
		clampf(point.x, rect.position.x, rect.end.x),
		clampf(point.y, rect.position.y, rect.end.y)
	)
	return closest.distance_to(point)


## Keeps an anchor inside the visible frame, inset by the same margin the
## pills themselves respect. Only ever moves a point that was already off
## screen, so an anchor the trainee can see is laid out exactly as before.
func _clamp_to_screen(point: Vector2, screen: Vector2) -> Vector2:
	return Vector2(
		clampf(point.x, SCREEN_MARGIN, maxf(SCREEN_MARGIN, screen.x - SCREEN_MARGIN)),
		clampf(point.y, SCREEN_MARGIN, maxf(SCREEN_MARGIN, screen.y - SCREEN_MARGIN))
	)


func _measure(label: String) -> Vector2:
	var font := ThemeDB.fallback_font
	var text := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	return Vector2(
		text.x + PILL_PAD_X * 2.0,
		maxf(text.y + PILL_PAD_Y * 2.0, PILL_MIN_HEIGHT)
	)


## Out to the side of the anchor and up, flipped to the other side when that
## would run off the screen, then clamped inside the margin.
##
## Which side it is on is remembered per pill rather than recomputed clean, so
## that the two tests are asymmetric: a right-hand pill has to overrun the
## margin by FLIP_HYSTERESIS to be sent left, and a left-hand one has to have
## that much room to spare before it comes back. An anchor parked on the old
## single threshold used to flip-flop once a frame.
func _pill_rect(id: StringName, anchor: Vector2, pill_size: Vector2, screen: Vector2) -> Rect2:
	var right_edge := screen.x - SCREEN_MARGIN
	var side: float = float(_side.get(id, 1.0))
	var overrun := anchor.x + PILL_OFFSET.x + pill_size.x - right_edge
	if side > 0.0:
		if overrun > 0.0:
			side = -1.0
	elif overrun < -FLIP_HYSTERESIS:
		side = 1.0
	_side[id] = side

	var offset := PILL_OFFSET
	if side < 0.0:
		offset.x = -offset.x - pill_size.x
	var position := anchor + offset
	position.x = clampf(position.x, SCREEN_MARGIN, screen.x - SCREEN_MARGIN - pill_size.x)
	position.y = clampf(position.y, SCREEN_MARGIN, _lowest_top(screen, pill_size.y))
	return Rect2(position, pill_size)


## Moves the drawn position a frame''s worth of the way toward the solved one.
##
## Frame-rate independent: the per-frame factor is derived from elapsed msec
## against SETTLE_TAU, so a 30fps browser tab and a 144Hz desktop settle over
## the same wall-clock time rather than the same number of frames.
##
## A pill with no history, or one that has moved further than SETTLE_TELEPORT
## since the last frame, is placed outright - a pill appearing, or the camera
## cutting to a new anchor, should not be seen flying in from where the last
## one was.
func _settle(id: StringName, target: Vector2, dt: float) -> Vector2:
	if not _settled.has(id) or dt <= 0.0:
		_settled[id] = target
		return target
	var from: Vector2 = _settled[id]
	var gap := from.distance_to(target)
	if gap > SETTLE_TELEPORT or gap < SETTLE_SNAP:
		_settled[id] = target
		return target
	var next := target + (from - target) * exp(-dt / SETTLE_TAU)
	_settled[id] = next
	return next


## The lowest y a pill of this height may start at: above the HUD's own bottom
## band, or - if the frame is too short for that to leave any room at all - the
## ordinary screen margin, so a small viewport degrades to the old behaviour
## rather than to a negative range.
func _lowest_top(screen: Vector2, pill_height: float) -> float:
	var limit: float = screen.y - HUD_BOTTOM_BAND - pill_height
	return limit if limit > SCREEN_MARGIN else maxf(
		SCREEN_MARGIN, screen.y - SCREEN_MARGIN - pill_height)


## Pushes a pill down until it clears the ones already placed. Overlap is a
## correctness problem here, not a cosmetic one: two pills under the crosshair
## at once is an ambiguous click.
func _avoid(id: StringName, rect: Rect2, placed: Array, screen: Vector2) -> Rect2:
	var floor_y := _lowest_top(screen, rect.size.y)
	var dir: float = float(_stack_dir.get(id, 1.0))

	# Stay with the direction this pill stacked last frame unless it stops
	# working, and then only once it has stopped working by a clear margin.
	#
	# Playtest: "''start compressions'' keeps dancing up and down with each
	# mouse movement." It was: the chest anchor projects near the bottom of the
	# survey frame, so the downward push landed right on floor_y - the top of
	# the HUD band - and a degree of mouse-look was enough to cross it. Above
	# the line the pill stacked below its neighbour, below it the pill stacked
	# above, and those two solutions are a pill-height apart, so the pill
	# teleported between them once a frame. _settle() then dutifully animated
	# the jump, which is what turned a flicker into a dance.
	#
	# Same shape of fix as FLIP_HYSTERESIS next door and for the same reason:
	# every threshold in this solver sits on a continuously moving quantity,
	# and a bare threshold on a moving quantity is an oscillator.
	var down := _push(rect, placed, 1.0)
	if dir > 0.0:
		if down.position.y <= floor_y + STACK_HYSTERESIS:
			return down
		dir = -1.0
	elif down.position.y <= floor_y - STACK_HYSTERESIS:
		_stack_dir[id] = 1.0
		return down

	# Pushing down ran out of room above the HUD band. Stacking upward from the
	# original position is the only way left to keep the pills apart; clamping
	# instead would put two of them back under the crosshair, which is the
	# ambiguous click this function exists to prevent.
	_stack_dir[id] = dir
	var moved := _push(rect, placed, -1.0)
	moved.position.y = clampf(moved.position.y, SCREEN_MARGIN, floor_y)
	return moved


## One direction of the stacking loop. `dir` is +1 to push a clashing pill
## below the one it hit and -1 to push it above.
func _push(rect: Rect2, placed: Array, dir: float) -> Rect2:
	var moved := rect
	var guard := 0
	while guard < placed.size() + 1:
		var clash := false
		for entry in placed:
			var other: Rect2 = entry["rect"]
			if moved.intersects(other.grow(STACK_GAP * 0.5)):
				moved.position.y = (other.end.y + STACK_GAP) if dir > 0.0 					else (other.position.y - STACK_GAP - moved.size.y)
				clash = true
		if not clash:
			break
		guard += 1
	if dir > 0.0:
		return moved
	moved.position.y = maxf(moved.position.y, SCREEN_MARGIN)
	return moved


func _rig() -> CprRig:
	return CprGhost.find_node(get_tree().current_scene, "CprRig") as CprRig


## Where a callout hangs. Two forms, and the older one is still the common one:
##
##   "anchor": StringName   a CprRig marker name, resolved through the rig
##   "node":   Node3D       any node in the world, used as-is
##
## The second exists for the extraction beat, whose two pills sit on the
## casualty AND on the breaker handle across the room - the breaker is not part
## of the casualty's skeleton and there is no marker on the rig that could
## describe it. Everything downstream only ever reads global_position, so a
## plain Node3D is all the layout needs.
func _marker_for(callout: Dictionary, rig: CprRig) -> Node3D:
	var node := callout.get("node", null) as Node3D
	if node != null:
		return node if is_instance_valid(node) else null
	if rig == null:
		return null
	return rig.pointer_marker(callout.get("anchor", &""))


## Whether the rig is needed at all this frame. A set made entirely of world
## nodes must still draw when there is no CprRig in the scene - the extraction
## pills are offered before the casualty has been dragged onto it.
func _all_callouts_carry_nodes() -> bool:
	for callout in _callouts:
		if callout.get("node", null) == null:
			return false
	return not _callouts.is_empty()


# =============================================================================
# Input
# =============================================================================
func _unhandled_input(event: InputEvent) -> void:
	if not _active or not interactive or _hovered == &"":
		return
	if not event.is_action_pressed(&"interact"):
		return
	get_viewport().set_input_as_handled()
	activated.emit(_hovered)


# =============================================================================
# Drawing
# =============================================================================
class _PointerCanvas extends Control:
	## The gold the rest of the game highlights with.
	const HOVER_FILL := Color(0.99, 0.85, 0.45, 0.95)

	var pills: Array = []
	var hovered: StringName = &""
	## Mirrors CasualtyPointers.pin_to_anchor: a pinned pill sits ON its anchor,
	## so there is no distance for a leader line to cover and the anchor dot
	## would land under the middle of the label.
	var pinned: bool = false

	var _font: Font = null
	var _idle_style: StyleBoxFlat = null
	var _hover_style: StyleBoxFlat = null

	func _build_styles() -> void:
		_idle_style = Tokens.glass_chip(Tokens.RADIUS_LG)
		_hover_style = Tokens.glass_chip(Tokens.RADIUS_LG)
		_hover_style.bg_color = HOVER_FILL

	func _draw() -> void:
		if _font == null:
			_font = ThemeDB.fallback_font
		if _idle_style == null:
			_build_styles()

		for entry in pills:
			var rect: Rect2 = entry["rect"]
			var anchor: Vector2 = entry["anchor"]
			var on: bool = entry["id"] == hovered
			var alpha := float(entry.get("alpha", 1.0))

			# Line first, so the pill sits on top of where it lands.
			if not pinned:
				_draw_leader(anchor, rect, alpha)

			# The stylebox is mutated rather than rebuilt per pill: it is drawn
			# immediately, and four of these a frame is not worth allocating.
			var style := _hover_style if on else _idle_style
			style.bg_color.a = (HOVER_FILL.a if on else Tokens.GLASS_FILL.a) * alpha
			style.border_color.a = Tokens.GLASS_BORDER.a * alpha
			draw_style_box(style, rect)

			var text := String(entry["label"])
			var text_size := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
			var baseline := rect.position + Vector2(
				(rect.size.x - text_size.x) * 0.5,
				(rect.size.y + text_size.y) * 0.5 - _font.get_descent(FONT_SIZE)
			)
			var ink := Tokens.INK
			ink.a = alpha
			draw_string(_font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1,
				FONT_SIZE, ink)

	## Anchor dot, a diagonal run, then a short horizontal stub into the pill's
	## near edge — the elbow a callout drawn by hand has.
	func _draw_leader(anchor: Vector2, rect: Rect2, alpha: float) -> void:
		var on_left := rect.get_center().x > anchor.x
		var edge_x := rect.position.x if on_left else rect.end.x
		var edge := Vector2(edge_x, rect.get_center().y)
		var elbow := edge + Vector2(-ELBOW_LENGTH if on_left else ELBOW_LENGTH, 0.0)

		var colour := LINE_COLOR
		colour.a *= alpha
		draw_polyline(PackedVector2Array([anchor, elbow, edge]), colour,
			LINE_WIDTH, true)
		draw_circle(anchor, ANCHOR_DOT_RADIUS, colour)
