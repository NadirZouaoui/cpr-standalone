extends Node
## Hold-to-observe breathing check — CPR_CONTRACT.md §4.1.
##
## CPR_AGENTS.md, Agent L brief, task 2: nothing in the project emitted
## `Events.breathing_checked` before this file existed. Grepped the whole
## scripts/ tree: the signal had a declaration (events.gd) and two listeners
## (cpr_station.gd advances the spine on it, cpr_panel_3d.gd resets its arc
## on a false result) but no source anywhere. cpr_panel_3d.gd's own
## `_enter_breathing()` / `_process()` arc is a cosmetic timer local to the
## panel — it loops on its own and was never wired to a real hold completing.
## So the panel showed "Observing..." forever: there was no code left that
## could ever finish it, menu-input-stealing (task 1) or not.
##
## Owned here rather than folded into cpr_station.gd so the station's
## _unhandled_input (fast-forward offer) and this hold don't have to share
## one function's state.
##
## Instanced once by CprStation._build() (see cpr_station.gd) and left in the
## tree for the station's whole lifetime; it no-ops outside
## STATE_BREATHING_CHECK rather than being added/removed per state, matching
## the pattern every other CPR helper here already uses.
##
## Playtest follow-up: the hold had no feedback where the trainee was actually
## looking, and no cue that a hold was wanted at all. That is now cpr_ear_2d.gd
## — an ear pinned to the mouth that fills as the hold runs, the same idiom
## cpr_hands_2d.gd uses on the sternum. A screen-space ring around the reticle
## lived here first; it was removed when the ear landed, because two progress
## indicators for one hold is one more than the trainee needs to read.
##
## This file owns the hold and publishes it through is_holding() /
## hold_progress(). It draws nothing.
##
## NOW SERVES TWO BEATS. The client's reordered spine (docs/OVERNIGHT_PLAN.md §2)
## adds a pulse check between the airway inspection and the compressions, and a
## pulse check is the same mechanic as the breathing check — a timed dwell with
## the crosshair on the casualty — at a different place on the body. So this runs
## both rather than growing a second, near-identical timer somewhere else. The
## file keeps its name because CprStation and cpr_ear_2d.gd both reach it by
## that name and renaming it buys nothing.
##
## What differs per beat is only the wording and what the completed hold reports;
## _config_for() holds both. What is deliberately NOT differentiated is the aim
## test: both holds ask for the crosshair on the casualty's body collider, which
## is a single convex hull with no separate mouth or neck region to hit. Telling
## the mouth from the neck would need geometry that does not exist.

## CPR_CONTRACT.md §4.1 said "~3.0 s". Lengthened to 5 s so the dwell reads as
## a real look-listen-feel rather than a button that happens to be sticky. The
## protocol allows up to 10; 5 keeps the sim moving without making the
## assessment feel skipped.
const HOLD_MS := 5000

## Playtest fix, part 1: the "Observing..." arc never said what to do, and the
## hold worked with the crosshair pointed anywhere in the room — including at
## the far wall. Both halves of that are addressed here: an explicit
## instruction on entering the state, and a requirement that the crosshair is
## actually on the casualty before a hold starts.
##
## The casualty's own body collider (Casualty_CPR_Posed/StaticBody3D, a
## ConvexPolygonShape3D hull on collision layer 1) is what the crosshair has to
## be over. Matched by walking up from whatever the ray hit to a node with this
## name, rather than by holding a node reference, per the runtime-binder rule
## in CPR_CONTRACT.md §3.
const CASUALTY_MESH_NAME := "Casualty_CPR_Posed"
const CASUALTY_SEARCH_DEPTH := 6

## Names the key and the act. "Check casualty breath" said neither what input
## was wanted nor that it was a hold, which is the whole reason the ear exists.
const PROMPT_TEXT := "Look, listen and feel — hold %s at the mouth"
const PROMPT_OFF_BODY_TEXT := "Aim at the casualty's mouth"
const PULSE_PROMPT_TEXT := "Two fingers to the side of the neck — hold %s for a carotid pulse"
const PULSE_PROMPT_OFF_BODY_TEXT := "Aim at the casualty's neck"
const PROMPT_COLOR := Tokens.ATTENTION
const PROMPT_SECONDS := 4.0
## Re-issued while the trainee has not started a successful hold, so the
## instruction is still on screen if they spend a while looking around.
const PROMPT_REPEAT_SECONDS := 8.0

var _holding: bool = false
var _hold_start_ms: int = 0
## Latched when a hold completes. See is_done().
var _done: bool = false

var _progress: float = 0.0
var _prompt_timer: Timer = null


func _ready() -> void:
	Events.cpr_state_changed.connect(_on_cpr_state_changed)

	_prompt_timer = Timer.new()
	_prompt_timer.name = "BreathingPromptTimer"
	_prompt_timer.wait_time = PROMPT_REPEAT_SECONDS
	_prompt_timer.one_shot = false
	_prompt_timer.timeout.connect(_on_prompt_timer_timeout)
	add_child(_prompt_timer)


## The two states this hold serves, and what each one says and reports.
## A function rather than a const Dictionary: a const initialiser referencing
## another script's constants has to resolve at parse time, and CprStation
## preloads this file — a cycle waiting to be tripped. Reading the constants
## inside a function body is a runtime lookup and is what the rest of this file
## already does.
func _config_for(state: int) -> Dictionary:
	if state == CprStation.STATE_BREATHING_CHECK:
		return {"prompt": PROMPT_TEXT, "off_body": PROMPT_OFF_BODY_TEXT}
	if state == CprStation.STATE_PULSE_CHECK:
		return {"prompt": PULSE_PROMPT_TEXT, "off_body": PULSE_PROMPT_OFF_BODY_TEXT}
	return {}


func _on_cpr_state_changed(_from: int, to: int) -> void:
	var config := _config_for(to)
	if not config.is_empty():
		_done = false
		_emit_prompt(config["prompt"])
		_prompt_timer.start()
	else:
		_prompt_timer.stop()
		_end_hold()


func _on_prompt_timer_timeout() -> void:
	var state := _hold_state()
	if state < 0:
		_prompt_timer.stop()
		return
	_emit_prompt(_config_for(state)["prompt"])


## The prompt names whatever `interact` is actually bound to, via the same
## helper the [C] chip uses, so nothing on screen can disagree about the key.
func _emit_prompt(text: String) -> void:
	if text.contains("%s"):
		var station := CprStation.get_current()
		var key := CprStation.key_name_for(&"interact") if station != null else "Left Click"
		text = text % key
	Events.center_message_requested.emit(text, PROMPT_COLOR, PROMPT_SECONDS)


## True when the crosshair is on the casualty. The walk itself lives on
## CprInteractBridge — compression_driver.gd needs exactly the same test.
func _crosshair_on_casualty() -> bool:
	return CprInteractBridge.crosshair_on_casualty(CASUALTY_SEARCH_DEPTH)


## CPR_CONTRACT.md §4.0: this is a hold on the general "interact" action
## while the BREATHING_CHECK anchor has the camera — not a click on a
## specific ghost mesh — so it does not go through CprInteractBridge/
## GhostTarget. It still respects Events.is_ui_blocking() like every other
## input path in the project.
func _unhandled_input(event: InputEvent) -> void:
	var state := _hold_state()
	if state < 0:
		_end_hold()
		return
	if Events.is_ui_blocking():
		return
	# The state outlives the check now — it is held until the trainee takes the
	# pointer that moves the spine on — so refuse a second hold rather than let
	# them re-run an assessment they have already made.
	if _done:
		return

	if event.is_action_pressed(&"interact"):
		if not _crosshair_on_casualty():
			# Silently refusing would read as "the game is broken" — say why.
			_emit_prompt(_config_for(state)["off_body"])
			return
		_holding = true
		_hold_start_ms = Time.get_ticks_msec()
		_progress = 0.0
	elif event.is_action_released(&"interact"):
		# Released before the hold completed: abort, no signal. CPR_CONTRACT
		# §4.1: "Release early aborts and re-prompts." The ear empties with it,
		# since it reads hold_progress() straight off this.
		_end_hold()


func _process(_delta: float) -> void:
	if not _holding:
		return
	var state := _hold_state()
	if state < 0:
		_end_hold()
		return
	if Events.is_ui_blocking():
		return
	# All timing via Time.get_ticks_msec() — CPR_CONTRACT.md §4.2's rule
	# ("never frame deltas") applies project-wide, not just to compressions.
	var elapsed := Time.get_ticks_msec() - _hold_start_ms
	_progress = clampf(float(elapsed) / HOLD_MS, 0.0, 1.0)
	if elapsed >= HOLD_MS:
		_holding = false
		_progress = 0.0
		_done = true
		_prompt_timer.stop()
		_report(state)


## What a completed hold means.
##
## The breathing check publishes an Events fact, because five other things react
## to it — grading, the result tone, the panel, the pointers, the station's own
## metrics. The pulse check tells the station directly instead: nothing else in
## the project needs to know, and events.gd holds past-tense facts the whole
## project cares about rather than one caller's hand-off.
func _report(state: int) -> void:
	if state == CprStation.STATE_BREATHING_CHECK:
		Events.breathing_checked.emit(false)
		return
	if state == CprStation.STATE_PULSE_CHECK:
		var station := CprStation.get_current()
		if station != null:
			station.complete_pulse_check()


func _end_hold() -> void:
	_holding = false
	_progress = 0.0


## Read every frame by cpr_ear_2d.gd, which draws the fill. Kept as plain
## accessors rather than a signal: this changes every frame while held, and the
## ear is already in _process.
func is_holding() -> bool:
	return _holding


## True once the hold has completed. The station no longer leaves this state
## when the check finishes — it waits on the "Start compressions" pointer — so
## without a latch the trainee could hold at the mouth again and re-emit
## breathing_checked, overwriting the recorded time. The ear reads this too, so
## the cue clears itself once there is nothing left to do at the mouth.
func is_done() -> bool:
	return _done


func hold_progress() -> float:
	return _progress


## The hold state the spine is currently sitting in, or -1 if it is somewhere
## this file has no business in. Replaces the old boolean _in_state(): there are
## two hold states now and every caller needs to know which.
func _hold_state() -> int:
	var station := CprStation.get_current()
	if station == null:
		return -1
	if _config_for(station.current_state).is_empty():
		return -1
	return station.current_state

