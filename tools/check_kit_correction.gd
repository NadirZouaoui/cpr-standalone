extends Node
## Headless regression check for the kit check's correction route - the client's
## feedback item 1, "if incorrect should be able to correct at that stage with
## the correction noted".
##
##   & "C:\Program Files\Godot\Godot_v4.7.2-stable_win64_console.exe" \
##       --headless --path <project> res://tools/check_kit_correction.tscn
##
## The behaviour under test, in one sentence: **an answer stands as given and
## the trainee is told nothing about it**; the way to change one is to click the
## object again, which takes the claim back, and name it afresh; both answers
## are kept; and the SETTLED one is what scores.
##
## What changed, and why this file was rewritten. The naming menu used to strike
## a wrong first answer out in red, keep the object live and take exactly one
## more - the single verdict given at the time anywhere in this exercise. That
## is gone: the review card does the correcting now, so a red pill was both a
## second way of doing the same job and the one place the game still marked a
## trainee's work in the moment. The rule this file now guards is the same rule
## the rest of the exercise follows - nothing is marked until the debrief.
##
## Every assertion here fails if the marking comes back (an answer would stop
## closing its object), if a retraction stops being a correction (the first
## answer would be lost with it), or if the first attempt is graded again (a
## corrected object would still read as an error).
##
## Sits alongside tools/check_kit.tscn rather than inside it: that file's whole
## point is what the trainee is NOT told, and this one is the route they have to
## put something right without being told.
##
## Exits non-zero on any failed assertion.

const MAIN := preload("res://main.tscn")

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
var _logged: Array = []            # [category, message, status, detail]
var _review_lines: PackedStringArray = PackedStringArray()


func _ready() -> void:
	Events.kit_question_requested.connect(func(id, choices):
		_asked = id
		_offered = choices)
	Events.kit_answer_recorded.connect(func(id): _recorded.append(id))
	Events.kit_check_finished.connect(func(): _finished = true)
	Events.action_logged.connect(func(category, message, status, detail):
		_logged.append([category, message, status, detail]))
	Events.review_requested.connect(func(context, _h, lines, _c, _cf, _a):
		if context == KitBench.REVIEW_CONTEXT:
			_review_lines = lines)

	await _boot()
	_check_nothing_is_marked()
	await _check_the_retraction_is_a_correction()

	await _reboot()
	await _check_two_wrong_answers()

	await _reboot()
	_check_the_card_shows_their_words()

	if _failures == 0:
		print("\nkit correction: all assertions passed.")
	else:
		printerr("\nkit correction: %d assertion(s) FAILED." % _failures)
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


func _section(title: String) -> void:
	print("\n%s" % title)


func _boot() -> void:
	Assessment.reset()
	SimState.reset()
	_finished = false
	_recorded.clear()
	_logged.clear()
	_review_lines = PackedStringArray()
	_asked = &""
	_offered = PackedStringArray()
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


func _click(item_id: StringName) -> void:
	Events.kit_item_inspected.emit(item_id)


func _answer(item_id: StringName, choice: String) -> void:
	Events.kit_answer_submitted.emit(item_id, choice)


func _claim(item: KitItem) -> void:
	_click(item.id)
	_answer(item.id, item.title)


## The correction route, as the trainee walks it: click a claimed object to take
## the claim back, click it again to be asked afresh, answer.
func _rename(item: KitItem, choice: String) -> void:
	_click(item.id)
	_click(item.id)
	_answer(item.id, choice)


func _confirm_review() -> void:
	_bench._request_review()
	_panel.call("_activate", _panel.get("ACTION_CONFIRM"))
	await get_tree().process_frame


func _kit() -> Array[KitItem]:
	var out: Array[KitItem] = []
	for item in _bench.manifest.items:
		if item != null and item.in_kit:
			out.append(item)
	return out


## A choice on the current menu that is NOT the right answer - taken off the
## menu itself rather than written here, so a reworded distractor cannot make
## this check silently answer correctly and assert nothing.
func _a_wrong_choice(item: KitItem) -> String:
	for label in _offered:
		if label != item.title:
			return label
	return ""


# =============================================================================
# Cases
# =============================================================================
## The assertion this whole file exists for: a wrong name is taken in silence.
func _check_nothing_is_marked() -> void:
	_section("A wrong answer stands, and nothing is said about it")
	_ok(not Events.has_signal(&"kit_answer_rejected"),
		"the bus has no way left to tell a trainee a name was wrong")

	var item := _kit()[0]
	_click(item.id)
	_ok(_asked == item.id, "the menu is asking about it")

	var wrong := _a_wrong_choice(item)
	_ok(wrong != "", "the menu offers a wrong answer to give")
	_answer(item.id, wrong)

	_ok(_recorded.size() == 1, "the wrong answer closed the object")
	_ok(_bench.answers.has(item.id), "and claimed it")
	if _bench.answers.has(item.id):
		var record: Dictionary = _bench.answers[item.id]
		_ok(not bool(record["correct"]), "recorded as wrong, quietly")
		_ok(not bool(record["corrected"]), "and not as a correction")
	_ok(_bench.stage == KitBench.Stage.NAMING, "the check has not moved on")


func _check_the_retraction_is_a_correction() -> void:
	_section("Taking the claim back and re-naming is the correction, and it counts")
	var item := _kit()[0]
	var wrong: String = String(_bench.answers[item.id]["final_choice"])

	_rename(item, item.title)
	_ok(_recorded.size() == 2, "the re-naming closed the object again")
	_ok(_bench.answers.has(item.id), "and re-claimed it")

	var record: Dictionary = _bench.answers[item.id]
	_ok(bool(record["corrected"]), "the record says a correction happened")
	_ok(String(record["choice"]) == wrong, "it keeps the first answer")
	_ok(String(record["final_choice"]) == item.title, "and the settled one")
	_ok(bool(record["correct"]),
		"THE SETTLED ANSWER SCORES - a correction that lands is not an error")
	_ok(_bench.errors() == 0, "so it is not counted as an error")

	# "with the correction noted" - the client's own words. The transcript is
	# where that noting has to survive to.
	var noted := false
	for entry in _logged:
		var detail := String(entry[3])
		if detail.contains(wrong) and detail.contains(item.title):
			noted = true
	_ok(noted, "the transcript carries both answers in one line")

	# An answer to an object nobody is being asked about must go nowhere.
	_answer(item.id, wrong)
	_ok(bool(_bench.answers[item.id]["correct"]),
		"a stray answer to a closed object cannot undo the correction")

	# The rest of the bag, named right first time, so the run is otherwise clean
	# and the score isolates what the correction did.
	var kit := _kit()
	for i in range(1, kit.size()):
		_claim(kit[i])
	await _confirm_review()
	_ok(_finished, "the check finished")
	var q := float(Assessment.quality_of(_bench.manifest.step_id))
	_ok(absf(q - 1.0) < EPSILON,
		"a run whose only fault was corrected scores 1.0 (scored %.4f)" % q)


func _check_two_wrong_answers() -> void:
	_section("Two wrong answers settle on the second")
	var kit := _kit()
	var item := kit[0]
	_click(item.id)
	var first := _a_wrong_choice(item)
	_answer(item.id, first)
	_ok(_bench.answers.has(item.id), "the first answer claimed the object")

	# A different wrong answer, so "settled on the second" is a real second
	# choice rather than the same pill twice. The menu is re-offered on the
	# re-click, so the pool is read again after it.
	_click(item.id)
	_click(item.id)
	var second := ""
	for label in _offered:
		if label != item.title and label != first:
			second = label
			break
	_ok(second != "", "the menu offers a second wrong answer")
	_answer(item.id, second)

	_ok(_recorded.size() == 2, "the re-naming closed the object whatever it said")
	var record: Dictionary = _bench.answers[item.id]
	_ok(not bool(record["correct"]), "and it is wrong, because it was wrong")
	_ok(String(record["choice"]) == first, "the first answer is kept")
	_ok(String(record["final_choice"]) == second, "and so is the second")
	_ok(bool(record["corrected"]), "and it is still recorded as a correction")
	_ok(_bench.errors() == 1, "it counts as one error")

	for i in range(1, kit.size()):
		_claim(kit[i])
	await _confirm_review()
	# Every claim right, one name wrong out of six named.
	var want := 0.5 * 1.0 + 0.5 * (float(kit.size() - 1) / float(kit.size()))
	var q := float(Assessment.quality_of(_bench.manifest.step_id))
	_ok(absf(q - want) < EPSILON,
		"the misnaming costs half a name (scored %.4f, expected %.4f)" % [q, want])


## The review card reads back what the trainee SAID, not what the objects are.
## A trainee who settled on the wrong name has to be able to see that name on
## the card - it is the only way the card can be worth going back from, and now
## that nothing marks the pills it is the only reading-back there is.
func _check_the_card_shows_their_words() -> void:
	_section("The card reads back their words, not ours")
	var item := _kit()[0]
	_click(item.id)
	var first := _a_wrong_choice(item)
	_answer(item.id, first)

	_click(item.id)
	_click(item.id)
	var second := ""
	for label in _offered:
		if label != item.title and label != first:
			second = label
			break
	_answer(item.id, second)

	_bench._request_review()
	_ok(_review_lines.size() == 1, "one claim, one line")
	if _review_lines.size() == 1:
		_ok(String(_review_lines[0]) == second,
			"the line is what they settled on ('%s')" % _review_lines[0])
		_ok(String(_review_lines[0]) != item.title,
			"and NOT the object's real name - that would hide the mistake")
