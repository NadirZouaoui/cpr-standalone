extends Node3D
class_name CprPanel3D

## Floating billboard UI for the CPR phase — CPR_CONTRACT.md section 6.
##
## A SubViewport (512x512, transparent, UPDATE_WHEN_VISIBLE) is rendered onto a
## Y-billboarded quad. Content is drawn by a small internal Control (`_PanelCanvas`)
## built entirely in code, so this scene owns nothing but a script — matching the
## project's "no serialised runtime nodes" pattern used by `cpr_rig.gd`.
##
## Position: on `cpr_state_changed`, the panel tweens (0.3 s) to the `panel_*` marker
## `CprRig.panel_for_state()` returns for the new state, and fades out entirely for
## any state with no marker (EXPOSE_CHEST, AED_FETCH, AED_DEPLOY, COMPLETE).
##
## OWNED BY AGENT B · UI — see CPR_CONTRACT.md section 7.

# CPR state ids come from CprStation.STATE_* — never a local copy of the number.
# The spine was renumbered on 3 Sep 2026 (docs/OVERNIGHT_PLAN.md §2) and every
# duplicated integer here was a silent breakage waiting to happen.

# --- mechanics constants (CPR_CONTRACT.md section 4) --------------------------
## Mirrors CompressionDriver.REP_TARGET_SET_1 / _SET_2 — the driver is the
## source of truth, this is display-only, same duplication pattern as the
## other constants in this block.
const COMPRESSION_TARGET_SET_1 := 30
const COMPRESSION_TARGET_SET_2 := 30
const COMPRESSION_GOOD_DEPTH := 0.75
const COMPRESSION_RATE_MIN := 100.0
const COMPRESSION_RATE_MAX := 120.0
const PAD_TARGET := 2

# --- tuning ---------------------------------------------------------------
## World-space size (metres) of the square quad. 512x512 viewport, so width == height.
## Tune this in the inspector while running so the panel reads at ~5-6% of screen
## height at the compression/pad anchors — that's a visual call, not a fixed number.
@export var panel_world_size: float = 0.16

const VIEWPORT_SIZE := Vector2i(512, 512)
const REPOSITION_TWEEN_S := 0.3
const FADE_TWEEN_S := 0.3

# --- runtime ----------------------------------------------------------------
var _rig: CprRig = null
var _viewport: SubViewport = null
var _canvas: _PanelCanvas = null
var _quad: MeshInstance3D = null
var _quad_material: StandardMaterial3D = null

## The spine's named idle, not a bare -1 — see aed_station.gd's note.
var _current_state: int = CprStation.STATE_PRIMARY_SURVEY
var _move_tween: Tween = null
var _fade_tween: Tween = null
var _current_alpha: float = 0.0


## The two halves of the panel's visibility, kept apart so neither can clobber
## the other. `_state_wants_panel` is "this CPR state has something to show";
## `_at_anchor` is CprStation.trainee_at_anchor(). The panel is up only when
## both hold — previously only the first was consulted, so standing up to reach
## the radio left "Observing..." floating over the room.
var _state_wants_panel: bool = false
var _at_anchor: bool = true
## The third half, and the only one that is polled: CprStation.compressions_armed
## is a plain field with no signal behind it (HANDOFF_POINTERS §4). A compression
## state can be entered before the trainee has taken the "Start compressions"
## pointer — COMPRESSIONS_2 always is, since the shock disarms — and the rep
## counter reading "0 of 10" beside the pills said the minigame had already
## started. Last seen value, so _process only refreshes the fade on a change.
var _armed_seen: bool = false
## Connected lazily: the station builds its camera rig off a call_deferred, so
## the rig does not necessarily exist when this node is ready.
var _watched_rig: CprCameraRig = null

## Set once, first time a compression state is reached — the driver instance
## is already built well before enter_cpr_phase() runs (CprStation._build()
## happens off the initial call_deferred, long before any state transition),
## so a lazy connect on first use is enough; no retry loop needed.
var _ff_driver: CompressionDriver = null

var _anim_timer: Timer = null


func _ready() -> void:
	_rig = _find_rig()
	if _rig == null:
		push_error("CprPanel3D: no CprRig found in the scene; panel will not reposition.")

	_build_viewport_and_quad()
	_build_anim_timer()
	set_process(false)
	_set_alpha_immediate(0.0)

	Events.cpr_state_changed.connect(_on_cpr_state_changed)
	Events.cpr_phase_entered.connect(_on_cpr_phase_entered)
	Events.compression_delivered.connect(_on_compression_delivered)
	Events.compression_set_completed.connect(_on_compression_set_completed)
	Events.aed_pad_hovered.connect(_on_aed_pad_hovered)
	Events.aed_pad_placed.connect(_on_aed_pad_placed)
	Events.stand_clear_confirmed.connect(_on_stand_clear_confirmed)
	Events.aed_shock_delivered.connect(_on_aed_shock_delivered)
	Events.cpr_completed.connect(_on_cpr_completed)


# --- scene construction -------------------------------------------------------

func _build_viewport_and_quad() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "SubViewport"
	_viewport.size = VIEWPORT_SIZE
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_viewport)

	_canvas = _PanelCanvas.new()
	_canvas.name = "Canvas"
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewport.add_child(_canvas)

	_quad_material = StandardMaterial3D.new()
	_quad_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_quad_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_quad_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Full billboard, not FIXED_Y. Y-billboarding only spins the quad about the
	# world up axis, so it stays vertical — fine for the standing pad/shock
	# anchors, but the compression camera looks almost straight down and saw the
	# card edge-on. Facing the camera outright reads correctly from any pitch.
	_quad_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_quad_material.billboard_keep_scale = true
	_quad_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_quad_material.albedo_texture = _viewport.get_texture()
	_quad_material.albedo_color = Color(1.0, 1.0, 1.0, 0.0)
	# Draw after opaque geometry, same convention as CprGhost materials.
	_quad_material.render_priority = 1

	var quad_mesh := QuadMesh.new()
	quad_mesh.size = Vector2(panel_world_size, panel_world_size)
	quad_mesh.material = _quad_material

	_quad = MeshInstance3D.new()
	_quad.name = "Quad"
	_quad.mesh = quad_mesh
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_quad)


func _build_anim_timer() -> void:
	_anim_timer = Timer.new()
	_anim_timer.name = "AnimTimer"
	_anim_timer.wait_time = 0.1
	_anim_timer.autostart = false
	_anim_timer.one_shot = false
	_anim_timer.timeout.connect(_on_anim_tick)
	add_child(_anim_timer)


func _find_rig() -> CprRig:
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		scene_root = get_tree().root
	var found: Node = CprGhost.find_node(scene_root, "CprRig")
	if found == null and scene_root != get_tree().root:
		found = CprGhost.find_node(get_tree().root, "CprRig")
	return found as CprRig


# --- state changes --------------------------------------------------------

func _on_cpr_phase_entered() -> void:
	set_process(false)
	_current_state = CprStation.STATE_PRIMARY_SURVEY
	_state_wants_panel = false
	_stop_anim()
	_set_alpha_immediate(0.0)


func _on_cpr_state_changed(_from: int, to: int) -> void:
	_current_state = to
	_reposition_for_state(to)
	_canvas.set_fast_forward_offer(false)

	match to:
		CprStation.STATE_BREATHING_CHECK:
			# No panel during the breathing check. The ear at the mouth
			# (cpr_ear_2d.gd) carries the cue and the progress now, and the arc
			# out here said "Observing..." — the name of the mechanic, floating
			# at head height with no connection to the act being asked for.
			_state_wants_panel = false
			_stop_anim()
			_update_visibility()
		CprStation.STATE_COMPRESSIONS_1, CprStation.STATE_COMPRESSIONS_2:
			_enter_compressions()
		CprStation.STATE_PAD_PLACEMENT:
			_exit_compressions()
			_enter_pads()
		CprStation.STATE_SHOCK:
			_exit_compressions()
			_enter_shock()
		_:
			_exit_compressions()
			_stop_anim()


func _on_cpr_completed(_metrics: Dictionary) -> void:
	_exit_compressions()
	_stop_anim()
	_state_wants_panel = false
	_update_visibility()


# --- positioning / fade -----------------------------------------------------

func _reposition_for_state(state: int) -> void:
	var marker: Marker3D = _rig.panel_for_state(state) if _rig != null else null
	if marker == null:
		_state_wants_panel = false
		_update_visibility()
		return

	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
	_move_tween = create_tween()
	_move_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_move_tween.tween_property(self, "global_position", marker.global_position, REPOSITION_TWEEN_S)
	_state_wants_panel = true
	_watch_camera()
	_update_visibility()


## Hangs the panel off the shared "at the anchor" rule. Both signals are needed:
## `released` covers standing up by any route ([C] handled here or in
## CprStation._handle_stance_key()), `move_started` covers kneeling back down.
func _watch_camera() -> void:
	var station := CprStation.get_current()
	var rig: CprCameraRig = station.camera_rig if station != null else null
	if rig == null or rig == _watched_rig:
		return
	_watched_rig = rig
	rig.released.connect(_on_anchor_changed)
	rig.move_started.connect(func(_anchor): _on_anchor_changed())


func _on_anchor_changed() -> void:
	var station := CprStation.get_current()
	_at_anchor = station == null or station.trainee_at_anchor()
	_update_visibility()


func _update_visibility() -> void:
	_fade_to(1.0 if _state_wants_panel and _at_anchor and _compressions_ready() else 0.0)


## True unless the panel is sitting in a compression state the trainee has not
## started yet. Every other state answers yes — this gate is about the minigame,
## not about the panel in general.
func _compressions_ready() -> bool:
	if _current_state != CprStation.STATE_COMPRESSIONS_1 and _current_state != CprStation.STATE_COMPRESSIONS_2:
		return true
	var station := CprStation.get_current()
	return station == null or station.compressions_armed


func _fade_to(target_alpha: float) -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_method(_set_alpha_immediate, _current_alpha, target_alpha, FADE_TWEEN_S)


func _set_alpha_immediate(a: float) -> void:
	_current_alpha = a
	if _quad_material != null:
		_quad_material.albedo_color.a = a


# --- breathing ---------------------------------------------------------------
#
# There is no breathing panel any more. The state deliberately shows nothing
# (see _on_cpr_state_changed): the ear at the mouth carries the cue and the
# progress, and the arc out here named the mechanic rather than the act.
#
# `_enter_breathing()` and an `Events.breathing_checked` handler used to live
# here and both are gone. The handler was actively wrong: it read the signal as
# "released early, restart the arc", but breathing_check.gd emits it only when a
# hold COMPLETES - the `false` is the finding, that the casualty is not
# breathing, not a report of an abort. An early release emits nothing at all.
#
# It had no visible effect in the state it guarded, because the panel is hidden
# there. What it did was leave the canvas in BREATHING mode, which then faded
# straight back in at PULSE_CHECK still showing "Observing...". Two wrongs
# meeting: this one put the stale pixels there, and CprRig.panel_for_state()
# gave PULSE_CHECK a marker to show them on.
#
# _PanelCanvas.Mode.BREATHING and its drawing are now unreachable. Left in
# place rather than deleted - if a head-anchored card ever comes back it is the
# worked example - but nothing calls set_breathing() any more.


# --- compressions --------------------------------------------------------

func _enter_compressions() -> void:
	_stop_anim()
	_armed_seen = _compressions_ready()
	_update_visibility()
	_ensure_fast_forward_connected()
	_last_rate_hint = _PanelCanvas.RATE_UNKNOWN
	_canvas.set_compressions(0.0, false, _PanelCanvas.RATE_UNKNOWN, 0, _target_for_state(_current_state))
	# Poll the driver every frame rather than waiting on compression_delivered.
	# A press lasts ~180 ms and the signal only fires on release, so a gauge fed
	# by the signal alone showed the depth of the press the trainee had already
	# finished. This is a read-only poll of live_depth() — the driver still owns
	# every decision, the panel just watches it.
	set_process(true)


func _exit_compressions() -> void:
	set_process(false)


## Mirrors the live press onto the depth gauge. Cheap: the canvas only calls
## queue_redraw() when a drawn value actually changes, so a still hand costs a
## comparison per frame and nothing else.
func _process(_delta: float) -> void:
	var armed := _compressions_ready()
	if armed != _armed_seen:
		_armed_seen = armed
		_update_visibility()
	if _ff_driver == null:
		_ensure_fast_forward_connected()
		if _ff_driver == null:
			return
	_canvas.set_compressions(
		_ff_driver.live_depth(),
		_ff_driver.is_pressing(),
		_last_rate_hint,
		_ff_driver.rep_index(),
		_ff_driver.rep_target()
	)


func _target_for_state(state: int) -> int:
	return COMPRESSION_TARGET_SET_2 if state == CprStation.STATE_COMPRESSIONS_2 else COMPRESSION_TARGET_SET_1


## Lazy-connects to the running CompressionDriver's fast_forward_available —
## a local (non-Events) signal, so this panel reaches it directly rather than
## through a bus fact. Safe to call repeatedly; only wires once.
func _ensure_fast_forward_connected() -> void:
	if _ff_driver != null:
		return
	var station := CprStation.get_current()
	if station == null or station.compression_driver == null:
		return
	_ff_driver = station.compression_driver
	_ff_driver.fast_forward_available.connect(_on_fast_forward_available)


func _on_fast_forward_available() -> void:
	if _current_state != CprStation.STATE_COMPRESSIONS_1 and _current_state != CprStation.STATE_COMPRESSIONS_2:
		return
	_canvas.set_fast_forward_offer(true)


## Rate is only knowable on release — it is the interval between two presses —
## so unlike depth it stays signal-fed, and _process carries the last verdict
## forward onto each frame's redraw.
##
## Kept as a direction, not a pass/fail: "too slow" and "too fast" need opposite
## corrections, and a trainee told only that the tempo is wrong has to guess
## which way to move.
var _last_rate_hint: int = _PanelCanvas.RATE_UNKNOWN

func _on_compression_delivered(_depth: float, rate: float, index: int) -> void:
	if _current_state != CprStation.STATE_COMPRESSIONS_1 and _current_state != CprStation.STATE_COMPRESSIONS_2:
		return
	if rate < COMPRESSION_RATE_MIN:
		_last_rate_hint = _PanelCanvas.RATE_SLOW
	elif rate > COMPRESSION_RATE_MAX:
		_last_rate_hint = _PanelCanvas.RATE_FAST
	else:
		_last_rate_hint = _PanelCanvas.RATE_OK
	_canvas.set_compressions(
		0.0, false, _last_rate_hint, index + 1, _target_for_state(_current_state)
	)


func _on_compression_set_completed(count: int, _assisted: bool) -> void:
	if _current_state != CprStation.STATE_COMPRESSIONS_1 and _current_state != CprStation.STATE_COMPRESSIONS_2:
		return
	_canvas.set_fast_forward_offer(false)
	_canvas.set_compression_count(count, _target_for_state(_current_state))


# --- pads ----------------------------------------------------------------

var _pad_count: int = 0
## Connected lazily on the first pad beat, like the fast-forward driver above.
var _pad_station: Node = null


## Content ready, panel held down. "0 / 2 · Select a pad site" used to come up
## the moment the AED was placed, while the unit was still saying "Unit ready"
## and before any site was visible to select — a counter for a task that had
## not been given. PadStation now reveals the sites on the unit's "attach pads"
## line and says so; the card comes up with them.
func _enter_pads() -> void:
	_stop_anim()
	_pad_count = 0
	_canvas.set_pads(0, PAD_TARGET, "Select a pad site")
	_state_wants_panel = false
	_update_visibility()
	_watch_pad_station()


func _watch_pad_station() -> void:
	var station := CprStation.get_current()
	var pads: Node = station.pad_station if station != null else null
	if pads == null:
		# Nothing to wait on; do not strand the card off-screen.
		_on_pads_revealed()
		return
	if _pad_station != pads:
		_pad_station = pads
		pads.pads_revealed.connect(_on_pads_revealed)
	# The reveal can beat this connection when there is no voice to wait for —
	# both nodes hang off the same cpr_state_changed and the order is not ours
	# to assume.
	if pads.is_revealed():
		_on_pads_revealed()


func _on_pads_revealed() -> void:
	if _current_state != CprStation.STATE_PAD_PLACEMENT:
		return
	_state_wants_panel = true
	_update_visibility()


func _on_aed_pad_hovered(_site_name: String) -> void:
	# Never surface the site name here — it encodes correctness (CPR_CONTRACT.md
	# section 4: wrong sites are accepted silently, with no visual difference).
	if _current_state != CprStation.STATE_PAD_PLACEMENT:
		return
	if _pad_count < PAD_TARGET:
		_canvas.set_pads(_pad_count, PAD_TARGET, "Placing pad...")


func _on_aed_pad_placed(_slot: int, _correct: bool, _site_name: String) -> void:
	if _current_state != CprStation.STATE_PAD_PLACEMENT:
		return
	_pad_count = mini(_pad_count + 1, PAD_TARGET)
	var instruction := "Both pads placed" if _pad_count >= PAD_TARGET else "Select a pad site"
	_canvas.set_pads(_pad_count, PAD_TARGET, instruction)


# --- shock -----------------------------------------------------------------

## No panel during the shock beat. The card said STAND CLEAR — the name of a
## mechanic, floating out beside a trainee who is being told the same thing by
## the unit's own voice and by the centre prompt — and then PRESS SHOCK, which
## duplicated the AED's own hover prompt while the AED itself was pulsing. Same
## judgement as the breathing check's "Observing...": three sources saying one
## thing is two too many, and the two that are attached to real objects win.
func _enter_shock() -> void:
	_state_wants_panel = false
	_update_visibility()
	_stop_anim()


## Nothing to draw for this any more — the shock card is retired — but the tick
## is still stopped, since a state that shows no panel has nothing to animate.
func _on_stand_clear_confirmed() -> void:
	if _current_state != CprStation.STATE_SHOCK:
		return
	_stop_anim()


func _on_aed_shock_delivered() -> void:
	_stop_anim()


# --- low-frequency animation tick --------------------------------------------
# Ticks at 10 Hz, driven off Time.get_ticks_msec() (never `delta`), and only while
# something is actually animating (breathing arc fill, shock flash). The canvas
# itself only calls queue_redraw() when a drawn value actually changes.

func _start_anim() -> void:
	if _anim_timer.is_stopped():
		_anim_timer.start()


func _stop_anim() -> void:
	_anim_timer.stop()


## Nothing starts the timer any more - the breathing arc was its only ticker and
## the panel does not draw during that state. Kept as the hook for the next
## animated card rather than deleted, and self-stopping so a timer started by
## mistake cannot drive a state that has no animation to run.
func _on_anim_tick() -> void:
	_stop_anim()


# --- drawing ------------------------------------------------------------------

## Everything the panel can show, built entirely in code and redrawn only when a
## tracked value changes (CPR_CONTRACT.md section 6: "do not redraw a static
## counter at 60 fps").
class _PanelCanvas extends Control:
	enum Mode { HIDDEN, BREATHING, COMPRESSIONS, PADS }

	## Tempo verdict for the last completed rep. UNKNOWN until one has been
	## timed — the card says nothing about a rate it has not measured.
	const RATE_UNKNOWN := 0
	const RATE_OK := 1
	const RATE_SLOW := 2
	const RATE_FAST := 3

	var _mode: int = Mode.HIDDEN

	var _breathing_progress: float = 0.0

	var _compression_depth: float = 0.0
	var _compression_pressing: bool = false
	var _compression_rate: int = RATE_UNKNOWN
	var _compression_index: int = 0
	var _compression_target: int = 30
	var _fast_forward_offer: bool = false

	var _pad_count: int = 0
	var _pad_target: int = 2
	var _pad_instruction: String = ""

	var _font: Font = null

	## Frosted card geometry, in viewport pixels. The quad is only ~0.16 m
	## across in world space, so the rim and shadow are scaled up from the
	## screen-UI values in Tokens - a 1 px border would vanish at this size.
	const CARD_MARGIN := 18.0
	const CARD_RADIUS := 44
	const CARD_BORDER := 3
	const CARD_SHADOW := 26

	## Ink at low alpha for gauge tracks. The old tracks were white-on-dark;
	## on a white card they have to go the other way to read at all.
	const TRACK := Color(0.12, 0.16, 0.22, 0.13)
	const TRACK_EDGE := Color(0.12, 0.16, 0.22, 0.22)

	var _card: StyleBoxFlat = null


	func _ready() -> void:
		_font = ThemeDB.fallback_font
		_card = Tokens.glass_panel(CARD_RADIUS)
		_card.set_border_width_all(CARD_BORDER)
		_card.shadow_size = CARD_SHADOW


	func set_breathing(progress: float) -> void:
		if _mode == Mode.BREATHING and is_equal_approx(_breathing_progress, progress):
			return
		_mode = Mode.BREATHING
		_breathing_progress = progress
		queue_redraw()


	func set_compressions(depth: float, pressing: bool, rate: int, index: int, target: int) -> void:
		# Called every frame while a set is running, so the early-out matters:
		# only an actual change in a drawn value earns a redraw.
		var changed := _mode != Mode.COMPRESSIONS \
			or not is_equal_approx(_compression_depth, depth) \
			or _compression_pressing != pressing \
			or _compression_rate != rate \
			or _compression_index != index \
			or _compression_target != target
		_mode = Mode.COMPRESSIONS
		_compression_depth = depth
		_compression_pressing = pressing
		_compression_rate = rate
		_compression_index = index
		_compression_target = target
		if changed:
			queue_redraw()


	func set_compression_count(count: int, target: int) -> void:
		var changed := _compression_index != count or _compression_target != target
		_compression_index = count
		_compression_target = target
		if changed:
			queue_redraw()


	func set_fast_forward_offer(is_up: bool) -> void:
		if _fast_forward_offer == is_up:
			return
		_fast_forward_offer = is_up
		if _mode == Mode.COMPRESSIONS:
			queue_redraw()


	func set_pads(count: int, target: int, instruction: String) -> void:
		var changed := _mode != Mode.PADS or _pad_count != count or _pad_instruction != instruction
		_mode = Mode.PADS
		_pad_count = count
		_pad_target = target
		_pad_instruction = instruction
		if changed:
			queue_redraw()


	func _draw() -> void:
		var s: Vector2 = size
		if s.x <= 0.0 or s.y <= 0.0:
			return

		# Inset so the card''s own drop shadow has room inside the viewport
		# instead of being clipped flat against the quad edge.
		if _card == null:
			_card = Tokens.glass_panel(CARD_RADIUS)
			_card.set_border_width_all(CARD_BORDER)
			_card.shadow_size = CARD_SHADOW
		draw_style_box(_card, Rect2(Vector2(CARD_MARGIN, CARD_MARGIN), s - Vector2(CARD_MARGIN, CARD_MARGIN) * 2.0))

		match _mode:
			Mode.BREATHING:
				_draw_breathing(s)
			Mode.COMPRESSIONS:
				_draw_compressions(s)
			Mode.PADS:
				_draw_pads(s)
			_:
				pass


	func _draw_breathing(s: Vector2) -> void:
		var center := s * 0.5 + Vector2(0.0, -s.y * 0.08)
		var radius := s.x * 0.28
		var start_angle := -PI / 2.0
		var end_angle := start_angle + TAU * _breathing_progress
		draw_arc(center, radius, 0.0, TAU, 48, TRACK, 14.0, true)
		if _breathing_progress > 0.001:
			draw_arc(center, radius, start_angle, end_angle, 48, Tokens.ACCENT, 14.0, true)
		_draw_centered_text("Observing...", Vector2(center.x, s.y * 0.82), 44, Tokens.INK_MUTED)


	func _draw_compressions(s: Vector2) -> void:
		var ring_centre := Vector2(s.x * 0.605, s.y * 0.470)
		var ring_radius := s.x * 0.235
		var ring_width := s.x * 0.052

		# --- progress ring -------------------------------------------------
		# The ring used to sit at a fixed three-quarter sweep and only its
		# colour moved, which made it decoration. It is now the set itself:
		# one full turn is one full set, so "how much is left" is a glance.
		var progress := 0.0
		if _compression_target > 0:
			progress = clampf(float(_compression_index) / float(_compression_target), 0.0, 1.0)
		draw_arc(ring_centre, ring_radius, 0.0, TAU, 64, TRACK, ring_width, true)
		if progress > 0.0005:
			var start := -PI / 2.0
			var end := start + TAU * progress
			# One colour, always. The ring answers "how far through the set",
			# and that question has no good or bad answer - tying its colour to
			# rate as well put two meanings on one mark and left the card green
			# on green with the depth gauge.
			var ring_colour: Color = Tokens.ACCENT
			draw_arc(ring_centre, ring_radius, start, end, 64, ring_colour, ring_width, true)
			# Round both ends of the sweep so it reads as a drawn stroke rather
			# than a slice cut out of a disc.
			var cap := ring_width * 0.5
			draw_circle(ring_centre + Vector2(0.0, -ring_radius), cap, ring_colour)
			draw_circle(ring_centre + Vector2(cos(end), sin(end)) * ring_radius, cap, ring_colour)

		# --- counter, inside the ring --------------------------------------
		var count_size := int(s.x * 0.155)
		var of_size := int(s.x * 0.058)
		_draw_centered_text(
			str(_compression_index), ring_centre + Vector2(0.0, count_size * 0.30), count_size
		)
		_draw_centered_text(
			"of %d" % _compression_target,
			ring_centre + Vector2(0.0, count_size * 0.30 + of_size * 1.45),
			of_size, Tokens.INK_FAINT
		)

		# Tempo, in words, under the counter, and only when it is wrong and in a
		# known direction. Silence means the rate is fine, so anything appearing
		# here is worth reading.
		match _compression_rate:
			RATE_SLOW:
				_draw_tempo_badge(s, "FASTER", -1.0)
			RATE_FAST:
				_draw_tempo_badge(s, "SLOWER", 1.0)

		# --- depth gauge ---------------------------------------------------
		# Fed from CompressionDriver.live_depth() every frame, so it rises with
		# the hand instead of reporting the press after it is over.
		var bar_cx := s.x * 0.180
		var bar_half := s.x * 0.040
		var bar_top := s.y * 0.205
		var bar_bottom := s.y * 0.795
		var bar_h := bar_bottom - bar_top
		_capsule(bar_cx, bar_top, bar_bottom, bar_half, TRACK)

		# The depth you are aiming for, marked once rather than shaded as a
		# zone - a tinted band reads as "anywhere in here", and it is a floor.
		var good_y := bar_bottom - bar_h * COMPRESSION_GOOD_DEPTH
		var tick_w := maxf(2.0, s.x * 0.009)
		var tick_out := bar_half * 1.20
		var tick_in := bar_half * 2.05
		for side in [-1.0, 1.0]:
			draw_line(
				Vector2(bar_cx + tick_out * side, good_y),
				Vector2(bar_cx + tick_in * side, good_y),
				TRACK_EDGE, tick_w, true
			)

		var depth := clampf(_compression_depth, 0.0, 1.0)
		if depth > 0.004:
			var deep := depth >= COMPRESSION_GOOD_DEPTH
			var fill: Color = Tokens.SUCCESS if deep else Tokens.ACCENT
			if not _compression_pressing:
				fill.a = 0.45
			_capsule(bar_cx, bar_bottom - bar_h * depth, bar_bottom, bar_half, fill)

		if _fast_forward_offer:
			_draw_centered_text(
				"INTERACT TO CONTINUE", Vector2(s.x * 0.5, s.y * 0.11),
				int(s.x * 0.052), Tokens.ACCENT
			)


	## A vertical rounded bar. draw_rect has square corners and draw_line has no
	## cap style, so the shape is a rect with a disc welded on each end.
	## The tempo correction: a chevron and a word, under the counter.
	##
	## Playtest, twice. It began as a bare amber word dropped under "of 30",
	## inside the ring's own column, which read as a third line of the counter -
	## a caption on the number rather than an instruction about the hands. The
	## fix for that was a tinted amber chip with a filled triangle, and the
	## verdict on that was "'slower' looks bad": it was the only boxed thing on
	## a card made entirely of thin arcs and plain type, so a small filled pill
	## sat on it like a button borrowed from another product.
	##
	## The box is gone. What is left is drawn in the card's own language - one
	## stroked chevron at the same weight as the gauge ticks, and the word beside
	## it at counter scale, both in the amber that means "change this". It gets
	## its own band under the ring so it is not read as part of the count, and
	## nothing has to appear or disappear except the mark itself.
	##
	## `direction` is -1 for "speed up" (chevron up) and +1 for "slow down".
	func _draw_tempo_badge(s: Vector2, word: String, direction: float) -> void:
		if _font == null:
			_font = ThemeDB.fallback_font
		var font_size := int(s.x * 0.062)
		var text_size := _font.get_string_size(
			word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)

		var chevron_w := font_size * 0.80
		var chevron_h := chevron_w * 0.52
		var gap := font_size * 0.52
		var total := chevron_w + gap + text_size.x

		# Its own band, below the ring and clear of the depth gauge's foot.
		var centre := Vector2(s.x * 0.605, s.y * 0.815)
		var left := centre.x - total * 0.5

		# Drawn as a stroke rather than a filled triangle: everything else on
		# this card is a line of some width, and a solid wedge at this size
		# reads as a glyph from a different set.
		var chevron_cx := left + chevron_w * 0.5
		var stroke := maxf(2.5, font_size * 0.17)
		draw_polyline(
			PackedVector2Array([
				Vector2(chevron_cx - chevron_w * 0.5, centre.y - chevron_h * 0.5 * direction),
				Vector2(chevron_cx, centre.y + chevron_h * 0.5 * direction),
				Vector2(chevron_cx + chevron_w * 0.5, centre.y - chevron_h * 0.5 * direction),
			]),
			Tokens.WARNING, stroke, true)
		# Round the two open ends, the way the progress ring's sweep is capped.
		for end_x in [chevron_cx - chevron_w * 0.5, chevron_cx + chevron_w * 0.5]:
			draw_circle(
				Vector2(end_x, centre.y - chevron_h * 0.5 * direction),
				stroke * 0.5, Tokens.WARNING)

		draw_string(
			_font,
			Vector2(left + chevron_w + gap,
				centre.y + text_size.y * 0.5 - _font.get_descent(font_size)),
			word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Tokens.WARNING)


	func _capsule(cx: float, top: float, bottom: float, half_w: float, colour: Color) -> void:
		if bottom - top <= 0.0:
			return
		var inner_top := minf(top + half_w, bottom - half_w)
		var inner_bottom := maxf(bottom - half_w, inner_top)
		if inner_bottom > inner_top:
			draw_rect(Rect2(cx - half_w, inner_top, half_w * 2.0, inner_bottom - inner_top), colour, true)
		draw_circle(Vector2(cx, inner_top), half_w, colour)
		draw_circle(Vector2(cx, inner_bottom), half_w, colour)


	func _draw_pads(s: Vector2) -> void:
		var counter_text := "%d / %d" % [_pad_count, _pad_target]
		_draw_centered_text(counter_text, Vector2(s.x * 0.5, s.y * 0.5), 48)
		_draw_centered_text(_pad_instruction, Vector2(s.x * 0.5, s.y * 0.72), 30, Tokens.INK_MUTED)


	func _draw_centered_text(text: String, pos: Vector2, font_size: int, color: Color = Tokens.INK) -> void:
		if _font == null:
			_font = ThemeDB.fallback_font
		var text_size := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		draw_string(
			_font, Vector2(pos.x - text_size.x * 0.5, pos.y), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color
		)
