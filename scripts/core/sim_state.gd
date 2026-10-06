extends Node
## Coarse phase machine for the LVR + CPR exercise.
##
## Deliberately coarse: fine-grained ordering lives in Assessment as
## ProcedureStep prerequisites, not as branches here. This tracks only
## "what part of the exercise are we in", for HUD, waypoints and audio.

enum Phase {
	KIT_CHECK,      ## Identify the LVR kit. Untimed, and the room is empty.
	BRIEFING,       ## Intro card and controls tutorial.
	SCENE_SAFETY,   ## Observer posted, PPE on, hazard identified.
	BREAK_CONTACT,  ## Casualty is being shocked. Crook out, supply killed.
	EXTRACTION,     ## Casualty has dropped. One-man drag to the safe area.
	PRIMARY_SURVEY, ## Response, breathing, send for help, call for the AED.
	RESUSCITATION,  ## Compressions, pads, analyse, shock, resume, swap.
	RECOVERY,       ## Signs of life. Recovery position, AED left attached.
	DEBRIEF,        ## Results screen. Terminal.
}

## Everything up to and including BRIEFING is preamble: no clock, no casualty
## in the room, nothing gradeable happening in world. Anything that needs to
## know "has the exercise actually started" should compare against this
## rather than against a specific phase, so inserting another preamble screen
## later does not break it.
const LAST_PREAMBLE_PHASE := Phase.BRIEFING

var phase: Phase = Phase.KIT_CHECK:
	set = _set_phase

## Wall-clock seconds since the exercise proper began (leaving the preamble).
var elapsed: float = 0.0

## Seconds the casualty spent in contact with the live conductor. The single
## most clinically meaningful number the exercise produces, so it is tracked
## independently of the checklist and surfaced in the debrief.
var contact_seconds: float = 0.0

var _running: bool = false
var _contact_live: bool = false


func _process(delta: float) -> void:
	if not _running:
		return
	elapsed += delta
	if _contact_live:
		contact_seconds += delta


func _set_phase(next: Phase) -> void:
	if next == phase:
		return
	var previous := phase
	phase = next

	# The kit check and the briefing are untimed - the trainee is being
	# taught, not assessed, until they are turned loose in the room. Written
	# as a crossing of the preamble boundary rather than "previous was
	# BRIEFING" so that begin_exercise(), which skips straight from
	# KIT_CHECK to SCENE_SAFETY, still starts the clock.
	if previous <= LAST_PREAMBLE_PHASE and next > LAST_PREAMBLE_PHASE:
		_running = true
		elapsed = 0.0
		Events.simulation_started.emit()

	# Contact runs from the moment the trainee is free to act until the
	# casualty is clear of the conductor.
	if next == Phase.BREAK_CONTACT:
		_contact_live = true
	elif previous == Phase.BREAK_CONTACT:
		_contact_live = false

	if next == Phase.DEBRIEF:
		_running = false

	Events.phase_changed.emit(previous, next)


## Advance one phase. Ignores calls past DEBRIEF.
func advance() -> void:
	if phase < Phase.DEBRIEF:
		self.phase = (phase + 1) as Phase


## Leave the preamble and start the clock. Called once, by whichever screen
## is last in the pre-exercise chain - currently the kit check.
func begin_exercise() -> void:
	if phase <= LAST_PREAMBLE_PHASE:
		self.phase = Phase.SCENE_SAFETY


## True while the room should still be empty: no casualty, no arc, no timer.
func is_preamble() -> bool:
	return phase <= LAST_PREAMBLE_PHASE


func is_at_least(p: Phase) -> bool:
	return phase >= p


func phase_name() -> String:
	return String(Phase.keys()[phase]).capitalize()


## Stops the contact clock early - the crook broke contact but the casualty
## has not finished falling, so the phase itself has not ended yet.
func mark_contact_broken() -> void:
	_contact_live = false


func reset() -> void:
	_running = false
	_contact_live = false
	elapsed = 0.0
	contact_seconds = 0.0
	phase = Phase.KIT_CHECK
