extends Node
## Headless regression check for the two-pass hazard assessment - Task 4 of
## docs/OVERNIGHT_PLAN.md, client feedback item 2.
##
##   & "C:\Program Files\Godot\Godot_v4.7.2-stable_win64_console.exe" \
##       --headless --path <project> res://tools/check_hazard_assessment.tscn
##
## The three things the plan asks this file to prove:
##
##   1. **Pass 2 cannot be answered before `panel_opened`.** The busbars are
##      inside the board; naming them through a shut steel door is not an
##      assessment, it is a guess.
##   2. **The quality maths is right** - (hits - false positives) / real
##      count, floored at 0 - and ticking everything does not score full marks.
##   3. **A correction is recorded, and the SETTLED attempt is what gets
##      graded.** That is the reverse of the rule this file used to assert, and
##      the reason is that the panel no longer marks the wrong lines. It used
##      to, which made fixing them free and forced the grade onto the first
##      attempt; the review card in its place reads the ticked set back and
##      says nothing about it, so the correction is a real second look and it
##      pays. Assertions that nothing marks a line at all are part of the job
##      now - it is the one change that would quietly make the grading
##      dishonest again.
##
## Plus the two things that would otherwise rot silently: that the door has
## stopped printing the answer to pass 1 on screen for free, and that the
## shipped hazard content still holds the entries the wording review settled
## on (docs/OVERNIGHT_PROGRESS.md, Task 4).
##
## Exits non-zero on any failed assertion.

const MAIN := preload("res://main.tscn")
const PASS1 := &"hazard_identified"
const PASS2 := &"hazards_reassessed"

var _failures: int = 0
var _main: Node
var _hazards: HazardAssessment

## Traffic captured off the bus.
var _asked: Array = []      # [step_id, heading, options, submit, anchor]
var _reviews: Array = []    # [context, heading, lines, correct, confirm, anchor]
var _resumed: Array = []    # [step_id, picks]
var _recorded: Array = []   # [step_id, quality, corrected]

var _panel: Node             ## the shared review card
var _hazard_panel: Node      ## the tick list


func _ready() -> void:
	Events.hazard_question_requested.connect(
		func(step, heading, options, submit, anchor):
			_asked.append([step, heading, options, submit, anchor]))
	Events.review_requested.connect(
		func(context, heading, lines, correct, confirm, anchor):
			_reviews.append([context, heading, lines, correct, confirm, anchor]))
	Events.hazard_panel_resumed.connect(
		func(step, picks): _resumed.append([step, picks]))
	Events.hazard_answer_recorded.connect(
		func(step, quality, corrected):
			_recorded.append([step, quality, corrected]))

	_check_content()
	_check_quality_maths()

	await _boot()
	_check_wiring()

	await _reboot()
	_check_pass_two_is_gated()

	await _reboot()
	_check_clean_first_attempt()

	await _reboot()
	_check_correction_grades_the_settled_attempt()

	await _reboot()
	_check_nothing_is_marked()

	await _reboot()
	_check_second_attempt_still_closes()

	await _reboot()
	_check_quality_floor_still_completes()

	await _reboot()
	_check_empty_submission()

	# These last two are coroutines - they drive real interactables and have to
	# let a frame pass. They MUST be awaited: called bare, each one suspends at
	# its first `await` and control returns here, the next `_reboot()` frees the
	# scene out from under it, and it resumes holding a freed door. That failed
	# as a script error rather than an assertion, so it cost coverage silently.
	await _reboot()
	await _check_door_no_longer_answers_pass_one()

	await _reboot()
	await _check_pass_two_after_opening()

	if _failures == 0:
		print("\ncheck_hazard_assessment: all assertions passed.")
	else:
		printerr("\ncheck_hazard_assessment: %d assertion(s) FAILED." % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


# =============================================================================
# Harness
# =============================================================================
func _ok(condition: bool, label: String) -> void:
	if condition:
		print("  pass   %s" % label)
	else:
		_failures += 1
		print("  FAIL   %s" % label)


func _near(a: float, b: float, label: String) -> void:
	_ok(absf(a - b) < 0.0005, "%s (%.4f vs %.4f)" % [label, a, b])


func _section(title: String) -> void:
	print("\n%s" % title)


func _boot() -> void:
	Assessment.reset()
	SimState.reset()
	_asked.clear()
	_reviews.clear()
	_resumed.clear()
	_recorded.clear()
	_main = MAIN.instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	_hazards = _main.get_node_or_null("BreakerPanel/HazardAssessment") as HazardAssessment
	_panel = _main.get_node_or_null("ReviewPanel")
	# The hazard panel is added to BreakerPanel's own parent, deferred, so it
	# is a sibling of everything else under Main rather than a child of the
	# breaker node.
	_hazard_panel = _main.find_child("HazardPanel", true, false)


func _reboot() -> void:
	_main.queue_free()
	await get_tree().process_frame
	await _boot()


## Interactables belonging to the CURRENT boot only.
##
## `get_nodes_in_group` spans the whole tree, and the group is global: a scene
## that has been `queue_free`d but not yet reaped is still in it. Taking the
## first match therefore risks a node from the *previous* boot, which is then
## freed underneath the assertions using it. Filtering by ancestry is the cheap
## guarantee that never happens again.
func _interactables() -> Array:
	var out: Array = []
	if _main == null:
		return out
	for node in get_tree().get_nodes_in_group(Interactable.GROUP):
		if is_instance_valid(node) and _main.is_ancestor_of(node):
			out.append(node)
	return out


func _list(step_id: StringName) -> HazardList:
	if _hazards != null:
		return _hazards.list_for(step_id)
	return load("res://resources/hazards/hazards_pass1.tres") as HazardList


## Indices of the real hazards in a list - the perfect answer.
func _real_indices(list: HazardList) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for i in list.items.size():
		if list.items[i] != null and list.items[i].is_real:
			out.append(i)
	return out


func _distractor_indices(list: HazardList) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for i in list.items.size():
		if list.items[i] != null and not list.items[i].is_real:
			out.append(i)
	return out


func _all_indices(list: HazardList) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for i in list.items.size():
		out.append(i)
	return out


func _ids(list: HazardList, picks: PackedInt32Array) -> Array:
	var out: Array = []
	for i in picks:
		out.append(list.items[i].id)
	return out


func _request(step_id: StringName) -> void:
	Events.hazard_assessment_requested.emit(step_id)


func _submit(step_id: StringName, picks: PackedInt32Array) -> void:
	Events.hazard_answer_submitted.emit(step_id, picks)


## Answer the review card through the REAL panel, so the whole loop is under
## test rather than just HazardAssessment's half of it.
func _answer_review(confirm: bool) -> void:
	_panel.call("_activate",
		_panel.get("ACTION_CONFIRM") if confirm else _panel.get("ACTION_CORRECT"))


# =============================================================================
# 1. The content the wording review settled on
# =============================================================================
## Not a style check. Four of the plan's twelve drafted entries did not survive
## verification against the room, and the replacements are load-bearing: #3 and
## #4 were factually wrong as written, #12 was unanswerable either way. If any
## of them is reverted to the draft wording this fails, which is the only thing
## standing between an invented list and a quiet regression to a worse one.
func _check_content() -> void:
	_section("shipped hazard content")

	var one := load("res://resources/hazards/hazards_pass1.tres") as HazardList
	var two := load("res://resources/hazards/hazards_pass2.tres") as HazardList
	_ok(one != null and two != null, "both hazard lists load")
	if one == null or two == null:
		return

	_ok(one.validate() == "", "pass 1 validates ('%s')" % one.validate())
	_ok(two.validate() == "", "pass 2 validates ('%s')" % two.validate())
	_ok(one.step_id == PASS1, "pass 1 grades '%s'" % PASS1)
	_ok(two.step_id == PASS2, "pass 2 grades '%s'" % PASS2)
	_ok(one.requires_step == &"", "pass 1 has no prerequisite step")
	_ok(two.requires_step == &"panel_opened", "pass 2 requires 'panel_opened'")

	_ok(one.items.size() == 8, "pass 1 offers 8 lines (%d)" % one.items.size())
	_ok(one.real_count() == 4, "pass 1 holds 4 real hazards (%d)" % one.real_count())
	_ok(two.items.size() == 4, "pass 2 offers 4 lines (%d)" % two.items.size())
	_ok(two.real_count() == 3, "pass 2 holds 3 real hazards (%d)" % two.real_count())

	# The reworded entries, by id and by verdict.
	var live_work := one.find(&"live_work_planned")
	_ok(live_work != null and live_work.is_real,
		"pass 1 #3 is the reworded 'live low voltage work', still a real hazard")
	_ok(live_work != null and not live_work.label.contains("about to open"),
		"pass 1 #3 no longer claims a worker is about to open the panel")

	var tools := one.find(&"metal_hand_tools")
	_ok(tools != null and tools.is_real, "pass 1 #4 is real")
	_ok(tools != null and not tools.label.contains("next to"),
		"pass 1 #4 no longer places the tools next to the board")
	_ok(tools != null and tools.needs_review,
		"pass 1 #4 is flagged - its placement is still unmeasured")

	# Deleted on Nadir's instruction of 4 Sep 2026. It described the room going
	# dark on isolation; the room does not go dark and will not, so a trainee
	# who did not tick it lost marks for failing to perceive something that is
	# not there. Asserted absent rather than simply removed from this file:
	# putting it back is a content decision, not a tidy-up.
	_ok(one.find(&"lighting_lost_on_isolation") == null,
		"the lighting hazard is gone - the simulation never modelled it")
	for item in one.items:
		_ok(not item.label.to_lower().contains("lighting"),
			"no line mentions lighting ('%s')" % item.label)

	var unlabelled := two.find(&"board_unlabelled")
	_ok(unlabelled != null and unlabelled.is_real,
		"pass 2 #12 is now the real 'board is not labelled at all'")
	_ok(two.find(&"board_mislabelled") == null,
		"pass 2 no longer carries the unanswerable 'incorrectly labelled'")

	# The distractors that were verified absent stay distractors.
	for id in [&"wet_floor", &"ladder_in_walkway", &"overhead_pipework"]:
		var item := one.find(id)
		_ok(item != null and not item.is_real, "pass 1 '%s' is a distractor" % id)
	var rodent := two.find(&"rodent_damage")
	_ok(rodent != null and not rodent.is_real, "pass 2 'rodent_damage' is a distractor")

	# The unmeasured pair must stay flagged: if either really is in the way,
	# the trainee is being marked wrong for being right.
	for id in [&"ladder_in_walkway", &"overhead_pipework"]:
		var item := one.find(id)
		_ok(item != null and item.needs_review,
			"pass 1 '%s' is flagged as unmeasured" % id)

	_ok(one.review_notes().size() >= 3,
		"pass 1 still reports its open questions (%d)" % one.review_notes().size())
	_ok(two.review_notes().size() >= 1,
		"pass 2 still reports its open questions (%d)" % two.review_notes().size())


# =============================================================================
# 2. The quality maths
# =============================================================================
func _check_quality_maths() -> void:
	_section("quality = (hits - false positives) / real count, floored at 0")

	var one := load("res://resources/hazards/hazards_pass1.tres") as HazardList
	var two := load("res://resources/hazards/hazards_pass2.tres") as HazardList
	if one == null or two == null:
		return

	var real1 := _ids(one, _real_indices(one))
	var fake1 := _ids(one, _distractor_indices(one))

	_near(one.quality_for([]), 0.0, "ticking nothing scores 0")
	_near(one.quality_for(real1), 1.0, "ticking exactly the 4 real hazards scores 1")
	# THE distractor assertion: a trainee who ticks the lot must not pass.
	_near(one.quality_for(_ids(one, _all_indices(one))), 0.0,
		"ticking all 8 scores (4-4)/4")
	_near(one.quality_for(fake1), 0.0,
		"ticking only the 4 distractors floors at 0 rather than going negative")
	_near(one.quality_for([real1[0], real1[1], real1[2]]), 0.75, "3 hits, 0 false = 0.75")
	_near(one.quality_for([real1[0], real1[1], real1[2], fake1[0]]), 0.5,
		"3 hits, 1 false = 0.5 - a false positive costs exactly one hit")
	_near(one.quality_for([&"not_a_hazard_id"]), 0.0,
		"an id that is not on the list is ignored, not counted against")

	var real2 := _ids(two, _real_indices(two))
	_near(two.quality_for(real2), 1.0, "pass 2: the 3 real hazards score 1")
	_near(two.quality_for(_ids(two, _all_indices(two))), 2.0 / 3.0,
		"pass 2: ticking all 4 scores (3-1)/3")


# =============================================================================
# 3. Wiring
# =============================================================================
func _check_wiring() -> void:
	_section("wiring")
	_ok(_hazards != null, "BreakerPanel builds a HazardAssessment")
	if _hazards == null:
		return
	_ok(_hazards.list_for(PASS1) != null, "pass 1 list is bound")
	_ok(_hazards.list_for(PASS2) != null, "pass 2 list is bound")
	_ok(_hazards.anchors.has(PASS1), "pass 1 has a world anchor")
	_ok(_hazards.anchors.has(PASS2),
		"pass 2 has a world anchor on the busbars (missing means the "
		+ "'%s' mesh was not found)" % "Breaker busbars")

	var panel := _main.get_parent().get_node_or_null("HazardPanel")
	if panel == null:
		panel = _main.get_node_or_null("HazardPanel")
	_ok(panel != null, "the diegetic hazard panel is built")

	var busbars_interact: Node = null
	for node in _interactables():
		if node is HazardReassessInteract:
			busbars_interact = node
			break
	_ok(busbars_interact != null,
		"an interactable is bound on the busbars for pass 2")
	if busbars_interact != null:
		_ok(not (busbars_interact as HazardReassessInteract).can_interact(),
			"the busbar prompt is not offered before the board is open")


# =============================================================================
# 4. THE GATE - pass 2 is unanswerable before panel_opened
# =============================================================================
func _check_pass_two_is_gated() -> void:
	_section("pass 2 is unanswerable before 'panel_opened'")
	if _hazards == null:
		_ok(false, "no HazardAssessment to test")
		return

	_ok(not Assessment.is_complete(&"panel_opened"),
		"precondition: the board is shut")
	_ok(not _hazards.can_answer(PASS2),
		"can_answer('%s') is false while the board is shut" % PASS2)

	_request(PASS2)
	_ok(_asked.is_empty(), "asking for pass 2 raises no question")
	_ok(not _hazards.is_open(PASS2), "pass 2 does not open")

	# The harder half: a submission that arrives anyway - a replayed signal, a
	# dev warp, a future briefing card - must not grade the step either.
	var two := _list(PASS2)
	_submit(PASS2, _real_indices(two))
	_ok(not Assessment.is_complete(PASS2),
		"a submission for pass 2 is refused outright while the board is shut")
	_ok(_recorded.is_empty(), "nothing is recorded")
	_ok(not _hazards.attempts.has(PASS2), "no attempt is stored")

	# ...and opening the board unlocks it.
	Assessment.complete(&"panel_opened")
	_ok(_hazards.can_answer(PASS2), "opening the board unlocks pass 2")
	_request(PASS2)
	_ok(_asked.size() == 1, "asking now raises the question")
	if not _asked.is_empty():
		_ok(_asked[0][0] == PASS2, "the question is pass 2's")
		_ok((_asked[0][2] as PackedStringArray).size() == 4,
			"four lines are offered")


# =============================================================================
# 5. A clean assessment is read back, confirmed, and closes the pass
# =============================================================================
func _check_clean_first_attempt() -> void:
	_section("a clean assessment is read back, confirmed, and scores 1")
	if _hazards == null:
		return
	var one := _list(PASS1)

	_request(PASS1)
	_ok(_asked.size() == 1 and _asked[0][0] == PASS1, "pass 1 opens")
	_ok((_asked[0][2] as PackedStringArray).size() == 8, "eight lines are offered")
	_ok(_hazards.is_open(PASS1), "the pass is open")

	# Re-aiming at the door mid-assessment must not restart it.
	_request(PASS1)
	_ok(_asked.size() == 1, "a repeated request does not re-raise the panel")

	var real := _real_indices(one)
	_submit(PASS1, real)

	# Submitting is not grading any more. It puts the set to the review card.
	_ok(_reviews.size() == 1, "submitting raises the review card")
	_ok(_recorded.is_empty(), "and grades nothing yet")
	_ok(not Assessment.is_complete(PASS1), "the step is still open")
	if _reviews.size() == 1:
		_ok(_reviews[0][0] == PASS1, "the card is tagged with the pass")
		var lines: PackedStringArray = _reviews[0][2]
		_ok(lines.size() == real.size(),
			"it lists every line they ticked (%d)" % lines.size())
		# The words on the card are the lines' own labels, in the order the
		# trainee ticked them. Anything else would be the card editorialising.
		var labels := one.labels()
		var foreign: Array[String] = []
		for line in lines:
			if not labels.has(line):
				foreign.append(line)
		_ok(foreign.is_empty(), "every line is one of the panel's own %s"
			% ", ".join(foreign))
		_ok(String(_reviews[0][1]) == one.review_heading,
			"the heading is the resource's wording, not code's")
		_ok(String(_reviews[0][3]) == one.review_correct_label
			and String(_reviews[0][4]) == one.review_confirm_label,
			"and so are both button labels")

	# The tick list must stand down while the card is up: both are aimed at
	# with the same crosshair and taken with the same button.
	if _hazard_panel != null:
		_ok(not bool(_hazard_panel.get("visible")),
			"the tick list stands down behind the card")

	_answer_review(true)
	_ok(_recorded.size() == 1, "confirming records the pass")
	_ok(Assessment.is_complete(PASS1), "'%s' completes" % PASS1)
	_near(Assessment.quality_of(PASS1), 1.0, "it scores full quality")
	_ok(not _hazards.attempts[PASS1]["corrected"], "no correction is recorded")
	_ok(not _hazards.is_open(), "the panel is closed")


# =============================================================================
# 6. THE CORRECTION - recorded, and the SETTLED attempt is what scores
# =============================================================================
## The reverse of what this file used to assert, and section 6a is the reason:
## nothing marks a wrong line any more, so correcting is no longer free.
func _check_correction_grades_the_settled_attempt() -> void:
	_section("a correction is recorded and the SETTLED attempt is graded")
	if _hazards == null:
		return
	var one := _list(PASS1)
	var real := _real_indices(one)
	var fake := _distractor_indices(one)

	# One real hazard found, one distractor wrongly reported: 1 hit, 1 false
	# positive, 4 real -> 0.0. Wrong in BOTH directions on purpose.
	var poor := PackedInt32Array([real[0], fake[0]])
	_request(PASS1)
	_submit(PASS1, poor)
	_ok(_reviews.size() == 1, "the poor set goes to the card like any other")
	_ok(not Assessment.is_complete(PASS1), "nothing is graded yet")

	_answer_review(false)
	_ok(_recorded.is_empty(), "Correct does not close the pass")
	_ok(not Assessment.is_complete(PASS1), "and does not grade it")
	_ok(_hazards.is_open(PASS1), "the pass is still open")
	_ok(_resumed.size() == 1, "the tick list comes back up")
	if _resumed.size() == 1:
		_ok((_resumed[0][1] as PackedInt32Array) == poor,
			"with their own ticks restored, exactly as they left them")
	if _hazard_panel != null:
		_ok(bool(_hazard_panel.get("visible")), "and it is visible again")

	# Now the correction: a perfect set. It closes the pass, and it IS what
	# scores.
	_submit(PASS1, real)
	_answer_review(true)
	_ok(_recorded.size() == 1, "the correction closes the pass")
	_ok(Assessment.is_complete(PASS1), "'%s' completes" % PASS1)

	# THE ASSERTION THIS SECTION EXISTS FOR, and it is the opposite of the one
	# that used to stand here. Grade the first attempt and this reads 0.0.
	_near(Assessment.quality_of(PASS1), 1.0,
		"the SETTLED attempt's quality is what the step is worth")
	_near(float(_recorded[0][1]), 1.0, "the recorded grade is the settled one")
	_ok(bool(_recorded[0][2]), "the record says a correction happened")

	var attempt: Dictionary = _hazards.attempts[PASS1]
	_ok(bool(attempt["corrected"]), "the attempt is stored as corrected")
	_ok((attempt["picks"] as PackedInt32Array) == real,
		"the settled picks are the grade's own set")
	_ok((attempt.get("first_picks", PackedInt32Array()) as PackedInt32Array) == poor,
		"the first submission is kept alongside them")
	_near(float(attempt.get("first_quality", -1.0)), 0.0,
		"the first attempt's own score is reported, but not scored")

	# "with the correction noted" - the client's own words.
	var said_corrected := false
	for row in Assessment.transcript:
		if String(row["message"]).contains("after first reporting"):
			said_corrected = true
			break
		if String(row["detail"]).contains("First submitted"):
			said_corrected = true
			break
	_ok(said_corrected, "the transcript carries what they first reported")


# =============================================================================
# 6a. NOTHING MARKS A WRONG LINE
# =============================================================================
## The property the whole grading change rests on. If any of this comes back,
## grading the settled answer becomes free marks and section 6 is wrong to
## assert what it asserts.
func _check_nothing_is_marked() -> void:
	_section("nothing tells the trainee which lines were wrong")
	if _hazards == null:
		return
	var one := _list(PASS1)
	var real := _real_indices(one)
	var fake := _distractor_indices(one)

	_request(PASS1)
	_submit(PASS1, PackedInt32Array([real[0], fake[0]]))

	# The card reads back what they ticked - all of it, wrong lines included,
	# with nothing to separate them.
	_ok(_reviews.size() == 1, "the card is up")
	if _reviews.size() == 1:
		var lines: PackedStringArray = _reviews[0][2]
		_ok(lines.size() == 2, "both their ticks are listed, right and wrong alike")
		_ok(lines.has(one.items[fake[0]].label),
			"including the distractor, unmarked and unremarked on")
		var haystack := String(_reviews[0][1]).to_lower()
		for line in lines:
			haystack += " " + String(line).to_lower()
		var leaks: Array[String] = []
		for word in ["wrong", "incorrect", "not correct", "missed", "should",
				"complete assessment", "adjust"]:
			if haystack.contains(word):
				leaks.append(word)
		_ok(leaks.is_empty(), "the card says nothing about the answer %s"
			% ", ".join(leaks))

	# And the panel has no mark machinery left. A set_marks still on the canvas
	# is a set_marks something can start calling again.
	if _hazard_panel != null:
		var canvas: Node = _hazard_panel.get("_canvas")
		if canvas != null:
			_ok(canvas.has_method("set_ticked"),
				"the canvas restores ticks")
			_ok(not canvas.has_method("set_marks"), "and set_marks is gone")

# =============================================================================
# 7. The trainee can go round the loop as often as they like
# =============================================================================
## The old rule took exactly one correction and closed the pass whatever the
## second attempt said, because a marked-up panel makes retrying free. Nothing
## is marked now, so there is nothing to farm: every trip round the loop is the
## trainee re-reading their own unannotated list. Capping it would only strand
## somebody who is still thinking.
##
## What must NOT happen is the pass closing on its own. A trainee parked in
## front of a card they cannot leave, with a door behind it that will not open,
## is the failure mode this section guards.
func _check_second_attempt_still_closes() -> void:
	_section("the review loop can be walked more than once, and always closes")
	if _hazards == null:
		return
	var one := _list(PASS1)
	var real := _real_indices(one)
	var fake := _distractor_indices(one)

	_request(PASS1)
	_submit(PASS1, PackedInt32Array([real[0]]))
	_answer_review(false)
	_ok(_hazards.is_open(PASS1), "first trip back: the pass is still open")

	_submit(PASS1, PackedInt32Array([real[0], fake[0]]))
	_answer_review(false)
	_ok(_hazards.is_open(PASS1), "second trip back: still open, still unmarked")
	_ok(_recorded.is_empty(), "and still ungraded")
	_ok(_resumed.size() == 2, "the ticks were restored both times")
	if _resumed.size() == 2:
		_ok((_resumed[1][1] as PackedInt32Array)
			== PackedInt32Array([real[0], fake[0]]),
			"the second restore carries the ticks as they were the second time")

	# Whatever they settle on is what counts, good or bad.
	_submit(PASS1, PackedInt32Array([real[0], real[1], fake[0]]))
	_answer_review(true)
	_ok(Assessment.is_complete(PASS1), "confirming closes it whatever it says")
	_ok(bool(_hazards.attempts[PASS1]["corrected"]),
		"and it is recorded as corrected")
	# 2 hits, 1 false positive, 4 real -> 0.25.
	_near(Assessment.quality_of(PASS1), 0.25,
		"graded on the settled set: 2 hits, 1 false positive, 4 real")


# =============================================================================
# 8. A quality-0 assessment still completes the step
# =============================================================================
## Failing it outright would leave `panel_opened` behind a prerequisite that
## can never be satisfied, and the run would stall at a door that never opens.
## Assessment.complete's own contract says a quality-0.0 completion is a
## completion: the trainee did carry out an assessment, it was just worthless.
func _check_quality_floor_still_completes() -> void:
	_section("a worthless assessment still completes the step")
	if _hazards == null:
		return
	var one := _list(PASS1)

	_request(PASS1)
	_submit(PASS1, _distractor_indices(one))    # every distractor, no hazard
	_answer_review(true)
	_ok(Assessment.is_complete(PASS1), "'%s' still completes" % PASS1)
	_ok(not Assessment.is_failed(PASS1), "it is completed, not failed")
	_near(Assessment.quality_of(PASS1), 0.0, "and is worth nothing")
	_ok(Assessment.is_partial(PASS1), "the debrief can see it was partial")


## Ticking nothing at all is still an answer, and the card still has to be
## raisable on it - an empty set that could not be submitted would trap the
## trainee behind a panel with no way out.
func _check_empty_submission() -> void:
	_section("an empty assessment can still be submitted and confirmed")
	if _hazards == null:
		return
	var one := _list(PASS1)

	_request(PASS1)
	_submit(PASS1, PackedInt32Array())
	_ok(_reviews.size() == 1, "the card goes up on an empty set")
	if _reviews.size() == 1:
		var lines: PackedStringArray = _reviews[0][2]
		_ok(lines.size() == 1, "with one line rather than an empty card")
		_ok(String(lines[0]) == one.review_empty_line,
			"and it is the resource's wording")
	_answer_review(true)
	_ok(Assessment.is_complete(PASS1), "it completes")
	_near(Assessment.quality_of(PASS1), 0.0, "and is worth nothing")

# =============================================================================
# 9. The door has stopped answering pass 1 for the trainee
# =============================================================================
func _check_door_no_longer_answers_pass_one() -> void:
	_section("the breaker door no longer gives pass 1 away")

	var door: BreakerPanelInteract = null
	for node in _interactables():
		if node is BreakerPanelInteract:
			door = node
			break
	_ok(door != null, "the door interactable is bound")
	if door == null:
		return

	var has_identify_message := false
	for prop in door.get_property_list():
		if String(prop["name"]) == "identify_message":
			has_identify_message = true
			break
	_ok(not has_identify_message,
		"'identify_message' is gone - it printed the answer to pass 1 for free")

	# Examining the board raises the assessment instead of completing the step.
	SimState.begin_exercise()
	await get_tree().process_frame
	_ok(door.can_interact(), "the door can be examined once the run has begun")
	door.interact(Vector3.ZERO)
	_ok(not Assessment.is_complete(PASS1),
		"examining the board does NOT complete '%s' on its own" % PASS1)
	_ok(_asked.size() == 1 and _asked[0][0] == PASS1,
		"it raises the assessment instead")
	_ok(door.stage() == BreakerPanelInteract.Stage.IDENTIFY,
		"and the board cannot be opened until the assessment is answered")

	# Answering it is what unlocks the door - and answering it means CONFIRMING
	# it. Submitting only raises the review card, so a trainee who is still
	# looking at their own list has not answered anything yet and the door has
	# to stay shut.
	_submit(PASS1, _real_indices(_list(PASS1)))
	_ok(door.stage() == BreakerPanelInteract.Stage.IDENTIFY,
		"submitting alone does not unlock the door - the card is still up")
	_answer_review(true)
	_ok(door.stage() == BreakerPanelInteract.Stage.OPEN,
		"confirming the assessment moves the door to its OPEN beat")


# =============================================================================
# 10. Pass 2 end to end, once the board is open
# =============================================================================
func _check_pass_two_after_opening() -> void:
	_section("pass 2, board open")
	if _hazards == null:
		return
	var two := _list(PASS2)

	Assessment.complete(&"panel_opened")
	SimState.begin_exercise()
	await get_tree().process_frame

	var busbars: HazardReassessInteract = null
	for node in _interactables():
		if node is HazardReassessInteract:
			busbars = node
			break
	if busbars != null:
		_ok(busbars.can_interact(), "the busbar prompt is live once the board is open")
		busbars.interact(Vector3.ZERO)
		_ok(_asked.size() == 1 and _asked[0][0] == PASS2,
			"activating the busbars raises pass 2")
	else:
		_request(PASS2)

	# Tick everything: three hits and one false positive out of three real.
	# Sent straight through the card without going back, so pass 2's grading is
	# read off a set the trainee settled on first time.
	_submit(PASS2, _all_indices(two))
	_ok(_reviews.size() == 1, "the reassessment goes to the review card too")
	_answer_review(true)
	_ok(Assessment.is_complete(PASS2), "'%s' completes" % PASS2)
	_near(Assessment.quality_of(PASS2), 2.0 / 3.0,
		"graded on the settled set: (3 hits - 1 false) / 3 real")

	if busbars != null:
		_ok(not busbars.can_interact(),
			"the busbar prompt goes quiet once the reassessment is resolved")
