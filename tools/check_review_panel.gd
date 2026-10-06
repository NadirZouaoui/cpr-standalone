extends Node
## The shared review-and-confirm card does what both callers assume it does.
##
##   & "C:\Program Files\Godot.exe" --headless --path <project> res://tools/check_review_panel.tscn
##
## WHY THIS EXISTS
##
## One panel serves the kit check and the hazard assessment. Neither of them
## can see it - they talk to it over `Events.review_requested` and hear back
## on `Events.review_answered` - so nothing on either side would notice if it
## stopped answering, stopped closing, or started answering the wrong caller.
## A card that fails to close is the same class of fault as the choice card in
## check_help_card: the trainee is left in front of a floating panel with the
## picking behind it and no way back.
##
## The last assertion is the one that matters most and is the least obvious:
## **the read-back lines are not pickable.** They must not be, and not because
## clicking one would misbehave - because the card is the trainee's own answer
## read back, and a line that lights up under the crosshair reads as something
## to fix. The only way back to the picking is Correct.

const MAIN := preload("res://main.tscn")

var _failures: int = 0
var _answers: Array = []


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	Events.review_answered.connect(func(context, confirmed):
		_answers.append([context, confirmed]))

	var panel: Node = main.get_node_or_null("ReviewPanel")
	if not _ok(panel != null, "ReviewPanel is spawned by main.gd"):
		_finish()
		return

	print("\nRaising the card")
	await _open(panel, &"kit_review", PackedStringArray([
		"LV Rescue Bag", "Rescue Crook", "Torch"]))
	_ok(bool(panel.get("is_open")), "the card is up")
	_ok(panel.get("_context") == &"kit_review", "it knows which caller raised it")

	print("\nCorrect goes back to the picking")
	_answers.clear()
	panel.call("_activate", panel.get("ACTION_CORRECT"))
	await get_tree().process_frame
	_ok(_answers.size() == 1, "exactly one answer went out")
	if _answers.size() == 1:
		_ok(_answers[0][0] == &"kit_review", "the answer names the caller back")
		_ok(_answers[0][1] == false, "Correct answers false")
	_ok(not bool(panel.get("is_open")), "the card came down")

	print("\nConfirm locks it in")
	_answers.clear()
	await _open(panel, &"hazard_identified", PackedStringArray([
		"Switchboard is energised and has not been isolated"]))
	panel.call("_activate", panel.get("ACTION_CONFIRM"))
	await get_tree().process_frame
	_ok(_answers.size() == 1, "exactly one answer went out")
	if _answers.size() == 1:
		_ok(_answers[0][0] == &"hazard_identified", "the answer names the caller back")
		_ok(_answers[0][1] == true, "Confirm answers true")
	_ok(not bool(panel.get("is_open")), "the card came down")

	print("\nThe read-back is a read-back, not a control")
	await _open(panel, &"kit_review", PackedStringArray([
		"LV Rescue Bag", "Rescue Crook", "Torch", "Fire Blanket"]))
	var canvas: Control = panel.get("_canvas")
	if _ok(canvas != null, "the canvas exists"):
		# Dead centre of every read-back pill must pick nothing at all.
		var pickable := 0
		for i in 4:
			var rect: Rect2 = canvas.call("_line_rect", i)
			if int(canvas.call("action_at", rect.get_center().x, rect.get_center().y)) >= 0:
				pickable += 1
		_ok(pickable == 0, "no read-back line is pickable (%d were)" % pickable)

		# ...and both actions must be, or the trainee is trapped.
		var correct_rect: Rect2 = canvas.call("_action_rect", 0)
		var confirm_rect: Rect2 = canvas.call("_action_rect", 1)
		_ok(int(canvas.call("action_at",
			correct_rect.get_center().x, correct_rect.get_center().y)) == 0,
			"Correct picks up under the crosshair")
		_ok(int(canvas.call("action_at",
			confirm_rect.get_center().x, confirm_rect.get_center().y)) == 1,
			"Confirm picks up under the crosshair")
		_ok(not correct_rect.intersects(confirm_rect),
			"the two actions do not overlap")

	print("\nA long read-back still fits the canvas")
	var many: PackedStringArray = PackedStringArray()
	for i in 17:
		many.append("Bench object number %d with a long enough name to wrap" % (i + 1))
	await _open(panel, &"kit_review", many)
	if canvas != null:
		var total: float = float(canvas.call("_stack_total_px"))
		var height: float = canvas.size.y
		_ok(total <= height, "17 lines fit inside the canvas (%.0f of %.0f px)"
			% [total, height])
		var last: Rect2 = canvas.call("_action_rect", 1)
		_ok(last.end.y <= height, "the action row is on the canvas, not below it")
	panel.call("close")

	print("\nThe card comes down when the run does")
	await _open(panel, &"hazard_identified", PackedStringArray(["one line"]))
	Events.simulation_finished.emit(false, 0)
	await get_tree().process_frame
	_ok(not bool(panel.get("is_open")), "simulation_finished closes it")

	_finish()


func _open(panel: Node, context: StringName, lines: PackedStringArray) -> void:
	Events.review_requested.emit(context, "Is this your answer?", lines,
		"Correct", "Confirm", Vector3.ZERO)
	await get_tree().process_frame


func _ok(condition: bool, label: String) -> bool:
	if condition:
		print("  pass   %s" % label)
	else:
		_failures += 1
		print("  FAIL   %s" % label)
	return condition


func _finish() -> void:
	if _failures == 0:
		print("\ncheck_review_panel: all assertions passed.")
		get_tree().quit()
		return
	printerr("\ncheck_review_panel: %d assertion(s) FAILED." % _failures)
	get_tree().quit(1)
