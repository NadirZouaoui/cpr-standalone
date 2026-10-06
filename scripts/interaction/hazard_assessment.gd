class_name HazardAssessment
extends Node
## Owns the two-pass hazard assessment: which lines are offered, when a pass
## may be answered at all, and what the trainee's ticked set is worth.
##
## Replaces the old one-click `hazard_identified`, which awarded a critical
## weight-6 step for clicking a panel and then printed the answer on screen for
## free. Client feedback item 2 asked for "identify the hazards" as a
## drop-down "so it's easier"; this is that, read as a tick-all-that-apply
## assessment (docs/OVERNIGHT_PLAN.md section 5, Task 4).
##
## **Two passes, because of the door.**
##
##   PASS 1  `hazard_identified`, from the floor with the board shut. What is
##           visible, plus what the brief already told the trainee.
##   PASS 2  `hazards_reassessed`, once the board is open. What opening it
##           exposed - principally the busbars, which cannot honestly be named
##           through a closed steel door.
##
## Pass 2 is gated on `panel_opened` and is **unanswerable** before it. The
## gate lives here rather than only on the interactable, so it holds however
## the pass is reached - a dev warp, a test, a future briefing card.
## Reassessing after exposing something is what the trade teaches, so the gate
## is the feature rather than a workaround.
##
## **The settled answer is what scores.** Submitting does not close a pass: it
## raises the shared review card (review_panel_3d.gd), which reads the ticked
## set back and offers Correct or Confirm. Correct returns to the list with
## every tick as it was; Confirm grades what is on it.
##
## It used to be the first attempt that scored, and the reasoning was sound at
## the time: the panel marked the wrong lines in amber and red, so fixing them
## cost nothing and the step would have scored ~1.0 every run. Nothing marks a
## wrong line any more - the review card says nothing whatever about the set it
## reads back - so the reason is gone and the rule goes with it. The client
## asked for "the correction noted", which does not say "the correction not
## counted".
##
## Both attempts are still recorded. The debrief and the SCORM comments have to
## be able to say what happened, not just what it scored.
##
## No UI here at all, and no geometry. This decides *what* is asked and *what
## it was worth*; hazard_panel_3d.gd decides what that looks like in the world,
## and BreakerPanel decides where it hangs.

const PASS1_PATH := "res://resources/hazards/hazards_pass1.tres"
const PASS2_PATH := "res://resources/hazards/hazards_pass2.tres"

## Leave empty to load the shipped lists.
@export var pass_one: HazardList
@export var pass_two: HazardList

## Off leaves both passes inert. The breaker door then never raises anything
## and `hazard_identified` is never completed, which is loud rather than
## silent - the board cannot be opened until it is.
@export var enabled: bool = true

## step_id -> {
##     "quality":       float,           THE GRADE. The settled set.
##     "picks":         PackedInt32Array, the settled ticked set.
##     "corrected":     bool,            whether they went back at all.
##     "first_picks":   PackedInt32Array, what they submitted first.
##     "first_quality": float,            reported, never scored.
## }
##
## Both attempts are kept for the same reason KitBench keeps both answers: the
## debrief and the SCORM comments have to be able to say what happened, not
## just what it scored. `first_*` is absent from a pass confirmed first time.
var attempts: Dictionary = {}

## step_id -> Node3D. Where each pass's panel hangs. Set by BreakerPanel, which
## is the only node that knows which mesh is which.
var anchors: Dictionary = {}

var _lists: Dictionary = {}          ## step_id -> HazardList
var _order: Array[StringName] = []   ## pass order, for reporting only

## The pass currently up, or &"" when nothing is.
var _open_step: StringName = &""
## The set under review, held while the card is up. It is the trainee's answer
## and nothing has been decided about it yet - Confirm grades this, Correct
## throws it away and puts them back in front of the list.
var _pending_picks: PackedInt32Array = PackedInt32Array()
## What they submitted the FIRST time, once they have been back at least once.
## Empty for a pass confirmed on the first submission.
var _first_picks: PackedInt32Array = PackedInt32Array()
var _corrected: bool = false
## True while the review card is up for this pass. A second submission cannot
## arrive over it, and the list is not live behind it.
var _reviewing: bool = false


func _ready() -> void:
	if not enabled:
		return

	if pass_one == null:
		pass_one = load(PASS1_PATH) as HazardList
	if pass_two == null:
		pass_two = load(PASS2_PATH) as HazardList

	for list in [pass_one, pass_two]:
		if list == null:
			push_error("HazardAssessment: a hazard list failed to load.")
			continue
		var problem := (list as HazardList).validate()
		if problem != "":
			push_error("HazardAssessment: '%s' is unusable - %s"
				% [(list as HazardList).step_id, problem])
			continue
		# Scramble before anything can read the list. Authoring order is real
		# hazards first, distractors after, which is a free answer to anyone
		# who spots it.
		(list as HazardList).shuffle_items()
		_lists[(list as HazardList).step_id] = list
		_order.append((list as HazardList).step_id)

	Events.hazard_assessment_requested.connect(_on_requested)
	Events.hazard_answer_submitted.connect(_on_submitted)
	Events.review_answered.connect(_on_review_answered)


## The list for a pass, or null. Public so BreakerPanel can hang the panels on
## the right meshes without knowing the file layout.
func list_for(step_id: StringName) -> HazardList:
	return _lists.get(step_id) as HazardList


func step_ids() -> Array[StringName]:
	return _order.duplicate()


func is_open(step_id: StringName = &"") -> bool:
	return _open_step != &"" and (step_id == &"" or step_id == _open_step)


# =============================================================================
# The gate
# =============================================================================
## Whether `step_id` may be answered right now. Pass 2's `panel_opened`
## prerequisite lives here, and this is the function the headless check
## asserts against.
##
## A pass already resolved is not answerable either - not because it is too
## early, but because it is done.
func can_answer(step_id: StringName) -> bool:
	var list := list_for(step_id)
	if list == null or not enabled:
		return false
	if Assessment.is_resolved(step_id):
		return false
	if list.requires_step == &"":
		return true
	return Assessment.is_complete(list.requires_step)


func _on_requested(step_id: StringName) -> void:
	if not enabled:
		return
	var list := list_for(step_id)
	if list == null:
		push_warning("HazardAssessment: no list for '%s'" % step_id)
		return

	# Already up. Re-aiming at the door while the panel floats over it must not
	# reset the trainee's ticks half way through the assessment.
	if _open_step == step_id:
		return
	if _open_step != &"":
		return

	if not can_answer(step_id):
		if not Assessment.is_resolved(step_id) and list.locked_message != "":
			Events.center_message_requested.emit(
				list.locked_message, Tokens.WARNING, 3.0)
		return

	_open_step = step_id
	_pending_picks = PackedInt32Array()
	_first_picks = PackedInt32Array()
	_corrected = false
	_reviewing = false
	Events.hazard_question_requested.emit(
		step_id, list.heading, list.labels(), list.submit_label, _anchor_for(step_id))


func _anchor_for(step_id: StringName) -> Vector3:
	var node := anchors.get(step_id) as Node3D
	return node.global_position if node != null else Vector3.ZERO


# =============================================================================
# Grading
# =============================================================================
## Submitting does not grade. It hands the ticked set to the review card, which
## reads it back and offers Correct or Confirm - the same card the kit check
## uses, and the same reason: the client asked to be able to see the answer and
## fix it before it counts.
func _on_submitted(step_id: StringName, picks: PackedInt32Array) -> void:
	if not enabled or step_id != _open_step:
		return
	var list := list_for(step_id)
	if list == null or attempts.has(step_id) or _reviewing:
		return

	_pending_picks = picks.duplicate()
	_reviewing = true
	Events.review_requested.emit(step_id, list.review_heading,
		_review_lines(list, picks), list.review_correct_label,
		list.review_confirm_label, _anchor_for(step_id))


## Correct puts the trainee back in front of the list with every tick exactly as
## they left it; Confirm is the only thing that grades. The card is keyed on the
## pass's own step_id, and the kit check raises the same card with a context of
## its own, so anything else that comes back is not ours.
func _on_review_answered(context: StringName, confirmed: bool) -> void:
	if not enabled or context != _open_step or not _reviewing:
		return
	_reviewing = false

	if not confirmed:
		# The first submission is the one worth keeping for the transcript: it
		# is what they thought before they saw it written down. Later trips
		# round the loop overwrite nothing.
		if not _corrected:
			_first_picks = _pending_picks.duplicate()
			_corrected = true
		Events.hazard_panel_resumed.emit(context, _pending_picks)
		return

	_grade(context, _pending_picks)


## The ticked lines, in the trainee's own reading order, for the card to read
## back. Labels rather than ids, and no judgement of any kind attached to any of
## them - the card is a pure view and this is all it is ever handed.
func _review_lines(list: HazardList, picks: PackedInt32Array) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for i in picks:
		if i >= 0 and i < list.items.size() and list.items[i] != null:
			out.append(list.items[i].label)
	if out.is_empty():
		out.append(list.review_empty_line)
	return out


func _grade(step_id: StringName, picks: PackedInt32Array) -> void:
	var list := list_for(step_id)
	if list == null:
		return

	var ids := _ids_for(list, picks)
	var quality := list.quality_for(ids)

	attempts[step_id] = {
		"quality": quality,
		"picks": picks.duplicate(),
		"corrected": _corrected,
	}
	if _corrected:
		var first_ids := _ids_for(list, _first_picks)
		attempts[step_id]["first_picks"] = _first_picks.duplicate()
		attempts[step_id]["first_quality"] = list.quality_for(first_ids)

	var headline := "Hazard assessment: %d of %d identified" % [
		_hits(list, ids), list.real_count()]
	var detail := _describe(list, ids)
	if _corrected:
		# "the correction noted" - the client's own words. What they submitted
		# first has to survive into the transcript even though it is the
		# settled set that scores.
		var first_ids := _ids_for(list, _first_picks)
		headline += ", after first reporting %d of %d" % [
			_hits(list, first_ids), list.real_count()]
		detail += " First submitted: %s." % _labels_of(list, first_ids)
	Events.log_action(&"scene_safety", headline,
		&"ok" if quality >= 1.0 else &"error", detail)

	# The step completes whatever the ticked set was worth. A poor assessment
	# is still an assessment - Assessment.complete's own contract is explicit
	# that a quality-0.0 completion is a completion - and failing it outright
	# would block `panel_opened` and stall the run behind a door that never
	# opens.
	Assessment.complete(step_id, quality)

	_open_step = &""
	_pending_picks = PackedInt32Array()
	_first_picks = PackedInt32Array()
	_corrected = false
	Events.hazard_answer_recorded.emit(step_id, quality, attempts[step_id]["corrected"])


func _ids_for(list: HazardList, picks: PackedInt32Array) -> Array:
	var out: Array = []
	for i in picks:
		if i >= 0 and i < list.items.size() and list.items[i] != null:
			out.append(list.items[i].id)
	return out


func _hits(list: HazardList, ids: Array) -> int:
	var n := 0
	for id in ids:
		var item := list.find(id)
		if item != null and item.is_real:
			n += 1
	return n


func _labels_of(list: HazardList, ids: Array) -> String:
	var out: Array[String] = []
	for id in ids:
		var item := list.find(id)
		if item != null:
			out.append(item.label)
	return ", ".join(out) if not out.is_empty() else "nothing"


## The transcript line. Says what was found, what was missed and what was
## called wrongly, and carries each real hazard's rationale - that teaching
## text has to survive into the LMS comments rather than dying in the resource.
func _describe(list: HazardList, ids: Array) -> String:
	var ticked := {}
	for id in ids:
		ticked[id] = true

	var found: Array[String] = []
	var missed: Array[String] = []
	var wrong: Array[String] = []
	for item in list.items:
		if item == null:
			continue
		if item.is_real:
			if ticked.has(item.id):
				found.append(item.label)
			else:
				missed.append("%s (%s)" % [item.label, item.rationale])
		elif ticked.has(item.id):
			wrong.append("%s (%s)" % [item.label, item.rationale])

	var parts: Array[String] = []
	parts.append("Identified: %s." % (", ".join(found) if not found.is_empty() else "nothing"))
	if not missed.is_empty():
		parts.append("Missed: %s." % " ".join(missed))
	if not wrong.is_empty():
		parts.append("Wrongly reported: %s." % " ".join(wrong))
	return " ".join(parts)
