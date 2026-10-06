class_name CompressionDriver
extends Node

## Drives compressions during COMPRESSIONS_1 / COMPRESSIONS_2 — CPR_CONTRACT.md
## section 4.
##
## Not wired into main.tscn (frozen). Whoever runs the CPR state machine
## (Agent E's cpr_station.gd) is expected to instance this with
## CompressionDriver.new() and add_child() it once, then leave it alone —
## it activates and deactivates itself off Events.cpr_state_changed.
##
## Input: press = downstroke, release = recoil. Mouse left button or Space —
## the contract does not distinguish them, so either drives the same rep.
##
## All timing is Time.get_ticks_msec(); never delta (CPR_CONTRACT.md section 8:
## WebGL2 frame pacing inside a SCORM iframe is unreliable).
##
##   depth = clamp(hold_ms / 180.0, 0.0, 1.0)     # good at >= 0.75
##   rate  = 60000.0 / press_to_press_ms          # rolling median of last 5, good 100-120
##
## A rep counts on depth; rate only colours the UI ring and never blocks a rep.
##
## Fast-forward: after 10 consecutive in-depth reps, `fast_forward_available`
## fires. Nothing in CPR_CONTRACT.md section 2 (the Events bus) carries this
## offer — it is not a past-tense fact about the trainee, it's an option being
## presented — so it is a local signal here instead of a new Events signal.
## Whoever shows "Continue compressions" (Agent E's station, or Agent B's
## panel) connects to it and calls accept_fast_forward() if the trainee takes
## it. That fills the set to 30 and marks it assisted; only the real reps that
## already happened count as scored.
##
## OWNED BY AGENT C · COMPRESSIONS — see CPR_CONTRACT.md section 7.

signal fast_forward_available()
## Fires at METRONOME_BPM while a set is active. Not part of the Events bus —
## it's a timing cue, not a fact — hook a click sound or UI beat off it if you
## need one.
signal metronome_tick()


const REP_TARGET_SET_1 := 30   # CprStation.STATE_COMPRESSIONS_1
const REP_TARGET_SET_2 := 30   # CprStation.STATE_COMPRESSIONS_2 — a full set, same as the first
## Both sets are 30. The second used to be 10, which read as a token gesture
## towards resuming: the resuscitation councils want compressions resumed for
## about two minutes after a shock, and a set the trainee is through in seconds
## teaches the reflex without the duration. Kept as two constants so the sets
## can diverge again without hunting for the one that means which.
const DEPTH_MS_FULL := 180.0
const DEPTH_GOOD_THRESHOLD := 0.75
const RATE_WINDOW := 5
const RATE_GOOD_MIN := 100.0
const RATE_GOOD_MAX := 120.0
const METRONOME_BPM := 110.0
## The fast-forward is a TESTING AID, not part of the exercise: shipping to
## trainees, the full 30 reps are the point of the drill and there is no way to
## shorten them. Gated on the debug build rather than deleted so playtesting a
## later state does not mean hand-delivering thirty compressions first — and so
## a shipped build cannot offer it by accident.
##
## REP_TARGET_SET_1 stays 30 either way; nothing about the target depends on
## this flag.
const FAST_FORWARD_STREAK := 10
## How long the fill takes. Long enough to read as compressions continuing,
## short enough that it is still a skip — roughly four beats' worth of time for
## the twenty reps it usually covers.
const FAST_FORWARD_MS := 2400.0

## Owns the blend shape. Created and parented here so there is exactly one
## CasualtyCpr per driver; casualty_cpr.gd's own static accessor is what
## Agent F's arms read from, so nothing else needs a reference to this.
var casualty_cpr: CasualtyCpr = null

var _active: bool = false
## Not a const: OS.is_debug_build() is resolved at runtime, so GDScript rejects
## it in a constant expression.
var fast_forward_enabled: bool = OS.is_debug_build()

var _fast_forward_offered: bool = false
var _fast_forward_active: bool = false
var _assisted: bool = false
## Guards against a double `compression_set_completed` emission — e.g. if a
## reentrant cpr_state_changed (fired synchronously by the station reacting to
## that same signal) ever routed back through _finish_set() a second time.
var _set_finished: bool = false

var _pressed: bool = false
var _press_start_ms: int = 0
var _last_press_start_ms: int = -1
var _recent_intervals_ms: Array[float] = []

var _rep_index: int = 0
var _rep_target: int = REP_TARGET_SET_1
var _consecutive_in_depth: int = 0

var _fast_forward_start_ms: int = 0
var _fast_forward_from_rep: int = 0

var _metronome_timer: Timer = null


func _ready() -> void:
	casualty_cpr = CasualtyCpr.new()
	casualty_cpr.name = "CasualtyCpr"
	add_child(casualty_cpr)

	_metronome_timer = Timer.new()
	_metronome_timer.name = "Metronome"
	_metronome_timer.wait_time = 60.0 / METRONOME_BPM
	_metronome_timer.one_shot = false
	_metronome_timer.autostart = false
	# Silent until the trainee has taken the "Start compressions" pointer: the
	# set can be entered before that (COMPRESSIONS_2 arrives with the shock,
	# with the pills still up), and a metronome ticking under a decision reads
	# as the minigame having already started.
	_metronome_timer.timeout.connect(func():
		var station := CprStation.get_current()
		if station != null and not station.compressions_armed:
			return
		metronome_tick.emit())
	add_child(_metronome_timer)

	Events.cpr_state_changed.connect(_on_cpr_state_changed)
	set_process(false)
	set_process_unhandled_input(true)


func _on_cpr_state_changed(_from: int, to: int) -> void:
	var should_be_active := to == CprStation.STATE_COMPRESSIONS_1 or to == CprStation.STATE_COMPRESSIONS_2
	if should_be_active and not _active:
		_start_set(to)
	elif not should_be_active and _active:
		_stop_set()


# --- set lifecycle -------------------------------------------------------

func _start_set(state: int) -> void:
	_active = true
	_rep_target = REP_TARGET_SET_2 if state == CprStation.STATE_COMPRESSIONS_2 else REP_TARGET_SET_1
	_fast_forward_offered = false
	_fast_forward_active = false
	_assisted = false

	_pressed = false
	_press_start_ms = 0
	_last_press_start_ms = -1
	_recent_intervals_ms.clear()

	_rep_index = 0
	_consecutive_in_depth = 0
	_set_finished = false

	if casualty_cpr != null:
		casualty_cpr.depth = 0.0
	set_process(false)
	_metronome_timer.start()


func _stop_set() -> void:
	_active = false
	_pressed = false
	if casualty_cpr != null:
		casualty_cpr.depth = 0.0
	set_process(false)
	_metronome_timer.stop()


# --- input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not _active or _fast_forward_active:
		return
	if _is_press_event(event):
		_on_press()
	elif _is_release_event(event):
		_on_release()


func _is_press_event(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		return event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not event.is_echo()
	if event is InputEventKey:
		return event.keycode == KEY_SPACE and event.pressed and not event.is_echo()
	return false


func _is_release_event(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		return event.button_index == MOUSE_BUTTON_LEFT and not event.pressed
	if event is InputEventKey:
		return event.keycode == KEY_SPACE and not event.pressed
	return false


## Playtest fix: a rep counted wherever the crosshair happened to be, so the
## whole set could be delivered staring at the far wall. The downstroke now has
## to start on the casualty — the same test breathing_check.gd uses, shared on
## CprInteractBridge. Only the PRESS is gated: once a compression is under way
## the trainee is free to look around without the rep being voided mid-stroke.
func _on_press() -> void:
	if _pressed:
		return
	# The shirt comes off before the heel of the hand goes on. The spine can
	# reach COMPRESSIONS_1 with the chest still covered — the breathing check
	# is what advances it, and that is now assessed at the mouth before the
	# chest track has been touched — so the gate lives here, on the rep, rather
	# than on the state. The "Open the shirt" body pointer is on screen at this
	# moment saying the same thing.
	# Not until the trainee has taken the "Start compressions" body pointer.
	# Silently: the pills are the only thing being offered on the body at that
	# moment, and a warning would be a second instruction competing with them.
	# The hands are hidden for the same reason (cpr_hands_2d.gd).
	var station := CprStation.get_current()
	if station != null and not station.compressions_armed:
		return
	if not CprInteractBridge.crosshair_on_casualty():
		Events.center_message_requested.emit(
			"Aim at the casualty's chest", Tokens.ATTENTION, 2.0
		)
		return
	_pressed = true
	_press_start_ms = Time.get_ticks_msec()
	set_process(true)


func _on_release() -> void:
	if not _pressed:
		return
	_pressed = false
	set_process(false)
	if casualty_cpr != null:
		casualty_cpr.depth = 0.0

	var hold_ms := float(Time.get_ticks_msec() - _press_start_ms)
	var depth := clampf(hold_ms / DEPTH_MS_FULL, 0.0, 1.0)
	var rate := _rate_for_this_press()
	_last_press_start_ms = _press_start_ms

	_record_rep(depth, rate)


## Recoil is instant per CPR_CONTRACT.md section 4 (no intermediate tween
## specified) — depth only rises while held.
func _process(_delta: float) -> void:
	if _fast_forward_active:
		_process_fast_forward()
		return
	if not _pressed or casualty_cpr == null:
		return
	var elapsed := float(Time.get_ticks_msec() - _press_start_ms)
	casualty_cpr.depth = clampf(elapsed / DEPTH_MS_FULL, 0.0, 1.0)


# --- rate ------------------------------------------------------------------

func _rate_for_this_press() -> float:
	if _last_press_start_ms < 0:
		return 0.0
	var interval_ms := float(_press_start_ms - _last_press_start_ms)
	if interval_ms <= 0.0:
		return 0.0
	_recent_intervals_ms.append(interval_ms)
	if _recent_intervals_ms.size() > RATE_WINDOW:
		_recent_intervals_ms.pop_front()
	return 60000.0 / _median(_recent_intervals_ms)


func _median(values: Array[float]) -> float:
	var sorted_values := values.duplicate()
	sorted_values.sort()
	var n := sorted_values.size()
	if n == 0:
		return 0.0
	if n % 2 == 1:
		@warning_ignore("integer_division")
		return sorted_values[n / 2]
	@warning_ignore("integer_division")
	return (sorted_values[n / 2 - 1] + sorted_values[n / 2]) * 0.5


# --- rep bookkeeping ---------------------------------------------------------

func _record_rep(depth: float, rate: float) -> void:
	var in_depth := depth >= DEPTH_GOOD_THRESHOLD

	Events.compression_delivered.emit(depth, rate, _rep_index)
	_rep_index += 1

	if in_depth:
		_consecutive_in_depth += 1
	else:
		_consecutive_in_depth = 0

	if _rep_index >= _rep_target:
		_finish_set()
		return

	if not fast_forward_enabled:
		return
	if not _fast_forward_offered and _consecutive_in_depth >= FAST_FORWARD_STREAK:
		_fast_forward_offered = true
		fast_forward_available.emit()


## Call when the trainee accepts the "Continue compressions" offer. Fills the
## remaining reps without scoring them and marks the set assisted — only the
## reps already delivered for real (via compression_delivered) count.
## CPR_CONTRACT.md §4.2: "Fills to 30 with a short overlay." It was not filling
## to anything — it snapped _rep_index to the target and ended the set in the
## same frame, so accepting the offer looked like the remaining compressions
## were cancelled rather than performed for you.
##
## Now the chest actually pumps through the remaining reps, compressed into
## FAST_FORWARD_MS so it reads as "carrying on, sped up" rather than a cut. The
## simulated reps deliberately do NOT emit compression_delivered: only reps the
## trainee actually delivered are scored (`assisted` records that help was
## taken), and inventing depth/rate samples would flatter the metrics.
func accept_fast_forward() -> void:
	if not _active or _fast_forward_active or _rep_index >= _rep_target:
		return
	_fast_forward_active = true
	_assisted = true
	_pressed = false
	if casualty_cpr != null:
		casualty_cpr.depth = 0.0
	_fast_forward_start_ms = Time.get_ticks_msec()
	_fast_forward_from_rep = _rep_index
	set_process(true)


## Drives the fill. Runs from the same _process as a live compression, so the
## blend shape has exactly one writer either way.
func _process_fast_forward() -> void:
	var elapsed := float(Time.get_ticks_msec() - _fast_forward_start_ms)
	var progress := clampf(elapsed / FAST_FORWARD_MS, 0.0, 1.0)
	var remaining := _rep_target - _fast_forward_from_rep

	# Count reps off as the fill advances, so anything watching _rep_index (the
	# panel's "12 / 30") climbs instead of jumping.
	_rep_index = _fast_forward_from_rep + int(floor(progress * float(remaining)))

	if casualty_cpr != null:
		# One full down-up per rep: a raised sine, so the chest bottoms out and
		# recoils rather than sliding between two values.
		var phase := progress * float(remaining) * TAU
		casualty_cpr.depth = (1.0 - cos(phase)) * 0.5

	if progress >= 1.0:
		_fast_forward_active = false
		set_process(false)
		if casualty_cpr != null:
			casualty_cpr.depth = 0.0
		_rep_index = _rep_target
		_finish_set()


## The single exit point for a set, reached by both the natural 30-rep route
## (_record_rep) and the fast-forward route (accept_fast_forward). Verified:
## both call this and only this to emit compression_set_completed —
## CPR_CONTRACT.md section 4.2 requires it fire "by either route", since
## COMPRESSIONS_1 hands off to AED_FETCH on that signal alone.
##
## _active is cleared before emitting (not after) so a station that changes
## cpr_state_changed synchronously inside this same emit sees _active already
## false and skips a redundant _stop_set(), rather than us emitting twice.
func _finish_set() -> void:
	if _set_finished:
		return
	_set_finished = true
	_metronome_timer.stop()
	_active = false
	if casualty_cpr != null:
		casualty_cpr.depth = 0.0
	Events.compression_set_completed.emit(_rep_index, _assisted)


## --- live read-out for the UI ------------------------------------------------
## The panel used to learn about a compression only from `compression_delivered`,
## which fires on RELEASE — so the depth gauge jumped to its final value after
## the press was already over and told the trainee nothing while it mattered.
## These four expose the in-flight state so the gauge can track the press as it
## happens. They report; nothing here decides anything.

## Depth of the press currently underway, 0..1, or 0.0 between presses.
func live_depth() -> float:
	if not _pressed:
		return 0.0
	var elapsed := float(Time.get_ticks_msec() - _press_start_ms)
	return clampf(elapsed / DEPTH_MS_FULL, 0.0, 1.0)


func is_pressing() -> bool:
	return _pressed


## Reps completed in the current set.
func rep_index() -> int:
	return _rep_index


func rep_target() -> int:
	return _rep_target


## Whether the fast-forward offer is currently up (offered, not yet accepted,
## set not already finished).
func is_fast_forward_available() -> bool:
	return _active and _fast_forward_offered and not _fast_forward_active
