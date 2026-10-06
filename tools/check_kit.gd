extends Node
## Headless regression check for the in-world kit check, now one interaction.
##
##   & "C:\Program Files\Godot.exe" --headless --path <project> res://tools/check_kit.tscn
##
## Drives the real main scene over the Events bus: clicks bench objects, answers
## the naming menu as it comes back, raises the review card, and asserts on what
## Assessment ends up holding. No window, no mouse - which is the point of
## keeping KitBench free of UI.
##
## The check used to have two stages to cover: a selection sweep graded as
## `kit_selected`, then naming graded as `kit_identified`. They are one act now.
## Clicking an object raises the naming menu, naming it is what claims it as
## kit, clicking a claimed object takes the claim back, and anything never
## clicked is the trainee saying it is not in the bag. One step, one grade, and
## the grade is a quality factor rather than a pass or a fail.
##
## Whole sections here are about what the trainee is NOT told. That is the
## easiest property to regress by accident, because every individual leak looks
## like a helpful little improvement. The review card is the newest place one
## could open up: it reads the trainee's own answer back and must say nothing
## whatever about it.
##
## Exits non-zero on any failed assertion.

const MAIN := preload("res://main.tscn")

## The grading formula is ours, not the client's, so it is asserted by
## arithmetic rather than by a remembered number - a formula that changes should
## fail these loudly instead of drifting.
const EPSILON := 0.0005

var _failures: int = 0
var _main: Node
var _bench: KitBench
var _panel: Node

## Traffic captured off the bus.
var _asked: StringName = &""
var _offered: PackedStringArray = PackedStringArray()
var _recorded: Array[StringName] = []
var _finished: bool = false
var _finish_args: int = -1
var _toggles: Array = []            # [item_id, claimed] pairs
var _stages: Array[int] = []
var _review: Dictionary = {}        # the last review_requested payload
var _reviews: int = 0


func _ready() -> void:
	Events.kit_question_requested.connect(func(id, choices):
		_asked = id
		_offered = choices)
	Events.kit_answer_recorded.connect(func(id): _recorded.append(id))
	Events.kit_selection_toggled.connect(func(id, sel): _toggles.append([id, sel]))
	Events.kit_stage_changed.connect(func(stage): _stages.append(stage))
	Events.kit_check_finished.connect(_on_finished)
	Events.review_requested.connect(_on_review_requested)

	await _boot()
	_check_bindings()
	_check_distractors()
	await _check_naming_and_unclaiming()

	await _reboot()
	await _check_clean_run()
	_check_no_feedback()

	await _reboot()
	await _check_correct_returns_to_the_bench()

	await _reboot()
	await _check_missed_kit_item()

	await _reboot()
	await _check_bench_tool_claimed()

	await _reboot()
	await _check_claimed_nothing()

	if _failures == 0:
		print("\nkit check: all assertions passed.")
	else:
		printerr("\nkit check: %d assertion(s) FAILED." % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


## Bound with no parameters on purpose - the assertion is that the signal
## carries no verdict. If somebody adds a `passed` argument back, this breaks
## loudly rather than quietly leaking it to the UI.
func _on_finished() -> void:
	_finished = true
	_finish_args = 0


func _on_review_requested(context: StringName, heading: String,
		lines: PackedStringArray, correct_label: String, confirm_label: String,
		anchor: Vector3) -> void:
	if context != KitBench.REVIEW_CONTEXT:
		return
	_reviews += 1
	_review = {
		"heading": heading,
		"lines": lines,
		"correct": correct_label,
		"confirm": confirm_label,
		"anchor": anchor,
	}


# =============================================================================
# Harness
# =============================================================================
func _ok(condition: bool, label: String) -> void:
	if condition:
		print("  pass   %s" % label)
	else:
		_failures += 1
		print("  FAIL   %s" % label)


func _section(title: String) -> void:
	print("\n%s" % title)


func _boot() -> void:
	Assessment.reset()
	SimState.reset()
	_finished = false
	_recorded.clear()
	_toggles.clear()
	_stages.clear()
	_asked = &""
	_offered = PackedStringArray()
	_review = {}
	_reviews = 0
	_main = MAIN.instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	_bench = _main.get_node_or_null("KitBench") as KitBench
	_panel = _main.get_node_or_null("ReviewPanel")


func _reboot() -> void:
	_main.queue_free()
	await get_tree().process_frame
	await _boot()


## One click on a bench object. Claims it if it is unclaimed (raising the naming
## menu), takes the claim back if it is not.
func _click(item_id: StringName) -> void:
	Events.kit_item_inspected.emit(item_id)


func _answer(item_id: StringName, choice: String) -> void:
	Events.kit_answer_submitted.emit(item_id, choice)


## Click an object and name it correctly - the whole claim, in one call.
func _claim(item: KitItem) -> void:
	_click(item.id)
	_answer(item.id, item.title)


## Raise the review card. The [Enter] that does this in game goes through
## _unhandled_input, which a headless run has no way to deliver.
func _review_now() -> void:
	_bench._request_review()


## Answer the review card through the REAL panel, so the whole loop is under
## test rather than just KitBench's half of it.
func _answer_review(confirm: bool) -> void:
	_panel.call("_activate",
		_panel.get("ACTION_CONFIRM") if confirm else _panel.get("ACTION_CORRECT"))
	await get_tree().process_frame


func _kit() -> Array[KitItem]:
	var out: Array[KitItem] = []
	for item in _bench.manifest.items:
		if item != null and item.in_kit:
			out.append(item)
	return out


func _not_kit() -> Array[KitItem]:
	var out: Array[KitItem] = []
	for item in _bench.manifest.items:
		if item != null and not item.in_kit:
			out.append(item)
	return out


func _quality() -> float:
	return float(Assessment.quality_of(_bench.manifest.step_id))


## The formula, restated independently of KitBench so the two have to agree:
## half for what they decided is in the bag, half for what they called it.
func _expected(claims_right: int, named: int, named_right: int) -> float:
	var total := _bench.manifest.items.size()
	var selection := float(claims_right) / float(total)
	var naming := 0.0 if named == 0 else float(named_right) / float(named)
	return 0.5 * selection + 0.5 * naming


func _close_to(a: float, b: float) -> bool:
	return absf(a - b) < EPSILON


# =============================================================================
# Cases
# =============================================================================
func _check_bindings() -> void:
	_section("Bench bindings")
	_ok(_bench != null, "KitBench present in main.tscn")
	if _bench == null:
		return
	_ok(_panel != null, "the shared review card is in the scene")
	_ok(_bench.manifest != null, "manifest assigned")
	var problem := _bench.manifest.validate()
	_ok(problem == "", "manifest validates: %s" % problem)

	var room: Node = _main.get_node_or_null("ControlRoom")
	var missing: Array[String] = []
	for item in _bench.manifest.items:
		if item.node == "":
			continue
		var mesh: Node = room.get_node_or_null(NodePath(item.node))
		if mesh == null or mesh.get_node_or_null("KitInspect") == null:
			missing.append("%s (%s)" % [item.node, item.id])
	_ok(missing.is_empty(), "every manifest node bound %s" % ", ".join(missing))

	# The pickable half of the bench must still resolve too - a Blender
	# renaming pass is exactly where those bindings go stale.
	var stale: Array[String] = []
	for entry in ToolRack.TOOLS:
		if room.get_node_or_null(NodePath(entry["node"])) == null:
			stale.append(entry["node"])
	_ok(stale.is_empty(), "ToolRack bindings intact %s" % ", ".join(stale))

	_ok(_bench.stage == KitBench.Stage.NAMING, "the check opens ready to name")
	_ok(Assessment.steps.get(&"kit_selected") == null,
		"the old selection step is gone from the procedure")


## The distractors are the reason the menu cannot be solved by looking round the
## room, so the property worth asserting is not that there are eight of them -
## it is that not one of them names something the trainee can see.
func _check_distractors() -> void:
	_section("The wrong answers are not in the room")
	var manifest := _bench.manifest
	_ok(manifest.name_distractors.size() >= manifest.choices_per_question - 1,
		"enough distractors for a full menu (%d for %d)" % [
			manifest.name_distractors.size(), manifest.choices_per_question - 1])

	var titles := {}
	for item in manifest.items:
		titles[item.title] = true
	var leaks: Array[String] = []
	for label in manifest.name_distractors:
		if titles.has(label):
			leaks.append(label)
	_ok(leaks.is_empty(), "no distractor is a bench object's own name %s"
		% ", ".join(leaks))

	# And the room itself: a distractor naming a mesh the trainee can walk up to
	# would be answerable by sight even though the manifest never lists it.
	var room: Node = _main.get_node_or_null("ControlRoom")
	var in_room: Array[String] = []
	for label in manifest.name_distractors:
		if CprGhost.find_node(room, label) != null:
			in_room.append(label)
	_ok(in_room.is_empty(), "no distractor names a mesh in the room %s"
		% ", ".join(in_room))


func _check_naming_and_unclaiming() -> void:
	_section("Clicking, naming, and taking it back")
	var kit := _kit()
	var first := kit[0]

	_ok(_asked == &"", "nothing is asked before anything is clicked")
	_click(first.id)
	_ok(_asked == first.id, "clicking an object asks for its name")
	_ok(_offered.has(first.title), "its own true name is on the menu")
	_ok(_offered.size() == _bench.manifest.choices_per_question,
		"the menu offers %d choices (offered %d)" % [
			_bench.manifest.choices_per_question, _offered.size()])

	# Every other choice must come from the distractor pool. This is the
	# assertion that would have caught the old behaviour.
	var pool := {}
	for label in _bench.manifest.name_distractors:
		pool[label] = true
	var foreign: Array[String] = []
	for label in _offered:
		if label != first.title and not pool.has(label):
			foreign.append(label)
	_ok(foreign.is_empty(), "every wrong answer comes from the pool %s"
		% ", ".join(foreign))

	_answer(first.id, first.title)
	_ok(_bench.answers.has(first.id), "naming it claims it")
	_ok(_toggles.size() == 1 and _toggles[0][1] == true, "the claim is announced")

	_click(first.id)
	_ok(not _bench.answers.has(first.id), "clicking it again takes the claim back")
	_ok(_toggles.size() == 2 and _toggles[1][1] == false,
		"the retraction is announced")
	_ok(_asked == first.id, "and does NOT re-ask - a retraction is not a question")

	_click(&"no_such_item")
	_ok(_toggles.size() == 2, "an unknown id is ignored")

	# One question at a time: a second click while the menu is up would put two
	# panels over the bench and leave _asking pointing at the wrong object.
	var second := kit[1]
	_click(second.id)
	_click(kit[2].id)
	_ok(_asked == second.id, "a click while the menu is up is ignored")


func _check_clean_run() -> void:
	_section("A clean run")
	var kit := _kit()
	for item in kit:
		_claim(item)
	_ok(_bench.answers.size() == kit.size(),
		"every kit item claimed and named (%d)" % _bench.answers.size())
	_ok(_recorded.size() == kit.size(), "each naming was recorded once")

	_review_now()
	_ok(_reviews == 1, "submitting raises the review card")
	_ok(_bench.stage == KitBench.Stage.REVIEW, "the bench is in review")
	var lines: PackedStringArray = _review.get("lines", PackedStringArray())
	_ok(lines.size() == kit.size(), "the card lists every claim (%d)" % lines.size())

	# The card reads back the trainee's OWN words. Here they were all right, so
	# the two coincide - the case where they do not is asserted in
	# check_kit_correction.
	var names := {}
	for item in kit:
		names[item.title] = true
	var unknown: Array[String] = []
	for line in lines:
		if not names.has(line):
			unknown.append(line)
	_ok(unknown.is_empty(), "every line is one of their own answers %s"
		% ", ".join(unknown))
	_ok(_review.get("anchor", Vector3.ZERO) != Vector3.ZERO,
		"the card is anchored somewhere in the world")

	await _answer_review(true)
	_ok(_finished, "confirming finishes the check")
	_ok(_bench.stage == KitBench.Stage.DONE, "the bench is done")
	_ok(Assessment.is_complete(_bench.manifest.step_id), "the step is completed")
	_ok(not Assessment.is_failed(_bench.manifest.step_id), "and not failed")
	var q := _quality()
	_ok(_close_to(q, 1.0), "a clean run scores 1.0 (scored %.4f)" % q)


## Nothing about the answer key may reach the trainee before the debrief, and
## the review card is the newest surface where it could.
func _check_no_feedback() -> void:
	_section("Nothing is given away")
	_ok(_finish_args == 0, "kit_check_finished carries no pass flag")
	var heading: String = _review.get("heading", "")
	var haystack := heading.to_lower()
	for line in _review.get("lines", PackedStringArray()):
		haystack += " " + String(line).to_lower()
	var leaks: Array[String] = []
	for word in ["correct", "wrong", "right", "incorrect", "missed", "score",
			"pass", "fail", "not in the kit"]:
		if haystack.contains(word):
			leaks.append(word)
	_ok(leaks.is_empty(), "the card says nothing about the answers %s"
		% ", ".join(leaks))


func _check_correct_returns_to_the_bench() -> void:
	_section("Correct goes back with the claims intact")
	var kit := _kit()
	_claim(kit[0])
	_claim(kit[1])
	_review_now()
	_ok(_reviews == 1, "the card is up")

	await _answer_review(false)
	_ok(not _finished, "Correct does NOT finish the check")
	_ok(_bench.stage == KitBench.Stage.NAMING, "the bench is live again")
	_ok(not Assessment.is_resolved(_bench.manifest.step_id),
		"and nothing has been graded")
	_ok(_bench.answers.size() == 2, "both claims survived the round trip")

	# ...and the bench really is workable again, which is the half of "return to
	# picking" that a stage flag alone would not prove.
	_claim(kit[2])
	_ok(_bench.answers.size() == 3, "a third object can still be claimed")
	_click(kit[0].id)
	_ok(_bench.answers.size() == 2, "and an existing claim can still be taken back")

	_review_now()
	_ok(_reviews == 2, "the card can be raised again")
	await _answer_review(true)
	_ok(_finished, "and confirmed the second time")


func _check_missed_kit_item() -> void:
	_section("A kit item left on the bench")
	var kit := _kit()
	for i in kit.size() - 1:
		_claim(kit[i])
	_review_now()
	await _answer_review(true)

	var total := _bench.manifest.items.size()
	# One kit item wrongly excluded, so one judgement of the manifest is wrong.
	var want := _expected(total - 1, kit.size() - 1, kit.size() - 1)
	var q := _quality()
	_ok(Assessment.is_complete(_bench.manifest.step_id),
		"the step is still completed - a poor check is still a check")
	_ok(_close_to(q, want), "scores %.4f, expected %.4f" % [q, want])
	_ok(q < 1.0, "and it costs something")


func _check_bench_tool_claimed() -> void:
	_section("A bench tool named as kit")
	var kit := _kit()
	for item in kit:
		_claim(item)
	# Named correctly, and still not kit. The two judgements are separate: the
	# name is right, the claim is wrong, and only the claim should cost.
	var tool_item := _not_kit()[0]
	_claim(tool_item)
	_review_now()
	await _answer_review(true)

	var total := _bench.manifest.items.size()
	var named := kit.size() + 1
	var want := _expected(total - 1, named, named)
	var q := _quality()
	_ok(_close_to(q, want), "scores %.4f, expected %.4f" % [q, want])
	_ok(_bench.naming_accuracy() == 1.0,
		"naming it correctly still counts as a correct name")
	_ok(_bench.selection_accuracy() < 1.0, "but claiming it costs the selection")


func _check_claimed_nothing() -> void:
	_section("Nothing claimed at all")
	_review_now()
	_ok(_reviews == 1, "the card still goes up")
	var lines: PackedStringArray = _review.get("lines", PackedStringArray())
	_ok(lines.size() == 1, "with one line rather than an empty card")
	await _answer_review(true)

	_ok(Assessment.is_complete(_bench.manifest.step_id), "the step is completed")
	# Every bench tool correctly left alone, every kit item missed, nothing
	# named. Naming accuracy is 0.0 rather than 1.0 - see KitBench.
	var total := _bench.manifest.items.size()
	var want := _expected(total - _kit().size(), 0, 0)
	var q := _quality()
	_ok(_close_to(q, want), "scores %.4f, expected %.4f" % [q, want])
	_ok(q < 0.5, "naming nothing does not pay (%.4f)" % q)
