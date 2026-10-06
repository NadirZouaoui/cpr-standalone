extends Node
## Owns the LVR + CPR checklist, grades it, and keeps the debrief transcript.
##
## Replaces the substation project's four hard-coded boolean categories.
## Everything here is driven by the ProcedureList resource - this script
## contains no knowledge of any specific step.

const PROCEDURE_PATH := "res://resources/procedures/lvr_cpr_procedure.tres"

var procedure: ProcedureList

## id -> ProcedureStep
var steps: Dictionary = {}
## Authoring order, for HUD and debrief display.
var order: Array[StringName] = []

## id -> { "at": float, "late": bool, "out_of_order": bool }
var completed: Dictionary = {}

## id -> { "at": float, "reason": String }
##
## Steps the trainee got wrong outright and will not get another go at - the
## kit check after its last attempt is the first of these. Kept apart from
## `completed` rather than flagged inside it so that a failed step counts as
## a *missing* prerequisite for anything downstream, which is the honest
## reading: the thing was never done.
var failures: Dictionary = {}

## Array of { "step_id": StringName, "reason": String, "at": float }
var violations: Array = []

## Array of { "category", "message", "status", "detail", "at" }
var transcript: Array = []

## Set when the rescuer does something that would have made them casualty two.
var fatal: bool = false
var fatal_reason: String = ""

## id -> float, when prerequisites for that step were first all satisfied.
var _unlocked_at: Dictionary = {}


func _ready() -> void:
	load_procedure()
	Events.action_logged.connect(_on_action_logged)
	# Phase gates open on their own, with no step completing to trigger a
	# refresh, so the unlock stamps that drive time limits have to be
	# re-taken when the phase moves.
	Events.phase_changed.connect(func(_p, _c): _refresh_unlocks())
	Events.fatal_violation.connect(_on_fatal_violation)
	_start_trail()


# =============================================================================
# Loading
# =============================================================================
func load_procedure(path: String = PROCEDURE_PATH) -> void:
	steps.clear()
	order.clear()

	var res: Resource = load(path)
	if res is not ProcedureList:
		push_error("Assessment: %s is not a ProcedureList" % path)
		return

	procedure = res
	for step in procedure.steps:
		if step == null or step.id == &"":
			push_warning("Assessment: skipping a step with no id")
			continue
		if steps.has(step.id):
			push_warning("Assessment: duplicate step id '%s'" % step.id)
			continue
		steps[step.id] = step
		order.append(step.id)

	_validate_prerequisites()
	_refresh_unlocks()


## Catches typos in `requires` at load time rather than at grading time,
## when a dangling id would silently make a step permanently unavailable.
func _validate_prerequisites() -> void:
	for id in order:
		for req in steps[id].requires:
			if not steps.has(req):
				push_error("Assessment: step '%s' requires unknown step '%s'" % [id, req])


# =============================================================================
# Progress
# =============================================================================
## Mark a step done. Safe to call repeatedly; only the first call counts.
## `quality` is how well the thing was done, 0.0 to 1.0, for the steps that
## can be done well or badly rather than merely done. Most steps are binary and
## leave it at 1.0. The CPR ones are not: CPR_CONTRACT.md section 5 asks for
## `cpr_performed` scaled by depth and `aed_used` halved per wrong pad site,
## and until this existed both were recorded as full marks with the real
## performance written only to the transcript - so forty compressions at 0% in
## depth scored exactly what forty good ones did.
##
## A step completed at quality 0.0 is still *completed*: it happened, it
## satisfies prerequisites, and it is not a `failure`. It simply earns nothing.
## That is the contract's wording for two wrong pads - "scores zero for that
## step" - and it is the honest reading: the trainee did deploy the AED.
func complete(step_id: StringName, quality: float = 1.0) -> void:
	if not steps.has(step_id):
		push_warning("Assessment: unknown step '%s'" % step_id)
		return
	if completed.has(step_id):
		return

	var step: ProcedureStep = steps[step_id]
	var now := SimState.elapsed

	var missing := _missing_prerequisites(step)
	var out_of_order := not missing.is_empty()

	var late := false
	if step.has_time_limit() and _unlocked_at.has(step_id):
		late = (now - float(_unlocked_at[step_id])) > step.time_limit

	completed[step_id] = {
		"at": now,
		"late": late,
		"out_of_order": out_of_order,
		"quality": clampf(quality, 0.0, 1.0),
		# The prerequisites that had not happened yet, kept as ids rather than
		# only as the prose reason below. The debrief needs them to say which
		# step this one jumped ahead of, and to mark that step as the other
		# half of the swap.
		"before": missing.duplicate(),
	}

	if out_of_order:
		var names: Array[String] = []
		for m in missing:
			names.append(String(steps[m].title))
		var reason := "Performed before: %s" % ", ".join(names)
		record_violation(step_id, reason)
		Events.log_action(step.category, step.title, &"warning", reason)
	elif late:
		Events.log_action(step.category, step.title, &"warning", step.late_detail)
	else:
		Events.log_action(step.category, step.title, &"ok", "")

	Events.step_completed.emit(step_id, now)
	_refresh_unlocks()


## Close a step as failed. Scores nothing, blocks nothing, and cannot be
## undone - the alternative, leaving it open, would park it permanently at
## the top of the HUD checklist as the step the trainee is still supposed to
## be doing.
##
## Failing a step with dependents is safe: `_missing_prerequisites` counts
## only OUTSTANDING prerequisites, so closing this one here records the
## violation against it and leaves everything downstream to be judged on its
## own merits. Use this - rather than leaving the step open - the moment it is
## certain the trainee has gone past it.
func fail(step_id: StringName, reason: String) -> void:
	if not steps.has(step_id):
		push_warning("Assessment: unknown step '%s'" % step_id)
		return
	if completed.has(step_id) or failures.has(step_id):
		return

	var step: ProcedureStep = steps[step_id]
	failures[step_id] = {"at": SimState.elapsed, "reason": reason}

	record_violation(step_id, reason)
	Events.log_action(step.category, step.title, &"error", reason)
	Events.step_failed.emit(step_id, reason)
	_refresh_unlocks()


func record_violation(step_id: StringName, reason: String) -> void:
	violations.append({
		"step_id": step_id,
		"reason": reason,
		"at": SimState.elapsed,
	})
	Events.step_violated.emit(step_id, reason)


func is_complete(step_id: StringName) -> bool:
	return completed.has(step_id)


func is_failed(step_id: StringName) -> bool:
	return failures.has(step_id)


## Done with, one way or the other. Neither completed nor failed steps are
## still on the trainee's plate.
func is_resolved(step_id: StringName) -> bool:
	return completed.has(step_id) or failures.has(step_id)


## True when every prerequisite of `step_id` is satisfied - i.e. the trainee
## is *supposed* to be doing this now. Drives the HUD's current-step marker.
func is_available(step_id: StringName) -> bool:
	if not steps.has(step_id) or is_resolved(step_id):
		return false
	var step: ProcedureStep = steps[step_id]
	# Phase gate before prerequisites: a step whose moment has not arrived is
	# not the trainee''s next job even if everything it depends on is done.
	if step.min_phase >= 0 and int(SimState.phase) < step.min_phase:
		return false
	return _missing_prerequisites(step).is_empty()


## The next step the trainee should perform, or &"" if none remain.
func next_step() -> StringName:
	for id in order:
		if is_available(id):
			return id
	return &""


## Prerequisites that are still OUTSTANDING - neither done nor closed.
##
## `is_resolved`, not `is_complete`, and the distinction is the whole point. A
## step the trainee definitively skipped is closed as a failure at the moment
## they skipped it (see CprStation.begin_compressions_early), which records the
## violation once, against the step that was actually missed. Counting it as
## missing here as well would charge every correctly-performed step downstream
## of it with the same mistake.
##
## That is not hypothetical. A trainee who took "Start compressions" without
## holding the carotid check finished the run with "Expose the chest" flagged
## amber on the HUD - a step they had performed, in order, at the right moment -
## because `chest_exposed` requires `pulse_checked`. The amber belonged on the
## pulse check and nowhere else.
##
## The other half of the same change: a failed prerequisite no longer parks
## everything behind it as permanently unavailable, so `is_available` and
## `next_step` keep answering after a skip instead of going quiet for the rest
## of the run.
func _missing_prerequisites(step: ProcedureStep) -> Array[StringName]:
	var missing: Array[StringName] = []
	for req in step.requires:
		if not is_resolved(req):
			missing.append(req)
	return missing


## Stamp the moment each step became available, so time limits can be judged.
func _refresh_unlocks() -> void:
	for id in order:
		if not _unlocked_at.has(id) and is_available(id):
			_unlocked_at[id] = SimState.elapsed


# =============================================================================
# Scoring
# =============================================================================
func max_score() -> int:
	var total := 0
	for id in order:
		total += steps[id].weight
	return total


## How well a completed step was performed, 0.0 to 1.0. Steps that were never
## completed, and every step that does not measure quality, read 1.0 - so
## callers can multiply by this unconditionally. Entries written before quality
## existed have no key and read 1.0 too.
func quality_of(step_id: StringName) -> float:
	if not completed.has(step_id):
		return 1.0
	return float(completed[step_id].get("quality", 1.0))


## Whether a step earned less than full marks for how it was done, as opposed
## to when. The debrief marks these so a run cannot pass with a line of clean
## ticks over forty compressions that never reached depth.
func is_partial(step_id: StringName) -> bool:
	return completed.has(step_id) and quality_of(step_id) < 1.0


## The steps this one was performed ahead of - empty unless it was out of
## order. These are the rows the debrief points its arrows at.
func performed_before(step_id: StringName) -> Array:
	if not completed.has(step_id):
		return []
	return completed[step_id].get("before", [])


## The reverse lookup: steps that jumped ahead of `step_id`. A step named here
## was overtaken - it should have happened earlier than it did - which is the
## other half of a swap and is marked, quietly, as such.
func overtaken_by(step_id: StringName) -> Array:
	var out: Array = []
	for id in completed:
		if performed_before(id).has(step_id):
			out.append(id)
	return out


## Three independent things can cut what a step earns, and they multiply:
## how well it was done (`quality`), whether it was done at the right point in
## the sequence, and whether it was done in time. Quality comes last from the
## caller's point of view but first here, because it is the only one that
## describes the action itself rather than its placement.
##
## Truncating once at the end keeps the arithmetic identical to what it was
## before quality existed for every step that scores full quality.
func raw_score() -> int:
	if fatal:
		return 0
	var total := 0
	for id in completed:
		var step: ProcedureStep = steps[id]
		var entry: Dictionary = completed[id]
		var earned := float(step.weight) * quality_of(id)
		if entry["out_of_order"]:
			earned *= 0.5  # Right action, wrong moment.
		elif entry["late"]:
			earned *= 0.75
		total += int(earned)
	return total


func score_percent() -> int:
	var maximum := max_score()
	if maximum <= 0:
		return 0
	return int(round(100.0 * raw_score() / maximum))


## Any critical step skipped or performed out of order fails the exercise
## outright, as does a fatal violation, regardless of the point total.
func failed_critical() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in order:
		var step: ProcedureStep = steps[id]
		if not step.critical:
			continue
		if failures.has(id) or not completed.has(id) or completed[id]["out_of_order"]:
			out.append(id)
	return out


func is_passed() -> bool:
	if fatal:
		return false
	if not failed_critical().is_empty():
		return false
	var mark := procedure.pass_mark if procedure != null else 80
	return score_percent() >= mark


# =============================================================================
# Transcript
# =============================================================================
func _on_action_logged(category: StringName, message: String, status: StringName, detail: String) -> void:
	transcript.append({
		"category": category,
		"message": message,
		"status": status,
		"detail": detail,
		"at": SimState.elapsed,
	})
	_trail_dirty = true


func _on_fatal_violation(reason: String) -> void:
	fatal = true
	fatal_reason = reason
	Events.log_action(&"safety", "Fatal safety violation", &"error", reason)


## Flat text transcript for the LMS comments field.
func transcript_as_text() -> String:
	var lines: PackedStringArray = []
	for e in transcript:
		var line := "[%s] %s" % [format_time(e["at"]), e["message"]]
		if e["detail"] != "":
			line += " - " + e["detail"]
		lines.append(line)
	return "\n".join(lines)


# =============================================================================
# Crash trail
# =============================================================================
## Nothing reached the LMS until the debrief, so a browser that died at minute
## 22 of a 23-minute run left an attempt indistinguishable from one never
## opened - and on an RTO's LMS "not attempted" is the wrong record for a
## trainee who sat the whole thing. This pushes the transcript out as it grows,
## so the worst case is losing the last TRAIL_INTERVAL seconds of it.
##
## It is a trail, not a resume point: nothing reads cmi.suspend_data back. A
## crashed session is re-sat from the top, which for an assessment is the only
## defensible thing to do anyway.

## Seconds between flushes. Each one is an LMSCommit, which on a real LMS is a
## network round trip, so this is deliberately slack - the transcript is
## evidence of participation, not telemetry.
const TRAIL_INTERVAL := 30.0

var _trail_dirty: bool = false
var _trail_timer: Timer


func _start_trail() -> void:
	Events.simulation_started.connect(_on_trail_started)
	# The verdict has gone out by then and report_result() committed it; the
	# run is over, so there is nothing further worth trailing.
	Events.simulation_finished.connect(func(_passed, _score): _flush_trail(true))

	_trail_timer = Timer.new()
	_trail_timer.wait_time = TRAIL_INTERVAL
	# The pause menu is the likeliest place for a trainee to wander off and
	# close the tab, and it is the one place the tree is paused.
	_trail_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_trail_timer.timeout.connect(_flush_trail.bind(false))
	add_child(_trail_timer)


func _on_trail_started() -> void:
	# Checked here rather than at setup: the autoloads run in the order
	# project.godot lists them, and Lms is created after this one, so at
	# _ready() it has not yet looked for an LMS and would always say no.
	if not Lms.is_available():
		return

	# Claim the attempt immediately. Without this a crash leaves lesson_status
	# at "not attempted", which reads as a trainee who never opened the course.
	# The pause menu's quit already declines to overwrite a status that has
	# gone out, so a real verdict still wins over this one.
	Lms.set_value("cmi.core.lesson_status", "incomplete")
	_trail_dirty = true
	_trail_timer.start()


func _flush_trail(final: bool) -> void:
	# Detached in the editor the flush only prints, and printing the whole
	# transcript every half minute would bury everything else in the console.
	if not Lms.is_available():
		return
	if final:
		_trail_timer.stop()
		return
	if not _trail_dirty:
		return
	_trail_dirty = false
	Lms.save_progress(transcript_as_text())


static func format_time(seconds: float) -> String:
	return "%02d:%02d" % [int(seconds / 60.0), int(seconds) % 60]


func reset() -> void:
	completed.clear()
	failures.clear()
	violations.clear()
	transcript.clear()
	_trail_dirty = false
	_unlocked_at.clear()
	fatal = false
	fatal_reason = ""
	_refresh_unlocks()
