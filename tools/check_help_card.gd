extends Node
## The one choice card of the run must always be able to close.
##
##   & "C:\Program Files\Godot.exe" --headless --path <project> res://tools/check_help_card.tscn
##
## WHY THIS EXISTS
##
## `main.gd::_on_help_card_trigger` raises the card on `check_response` and
## lowers `CasualtyActions.choice_hold` again when the question is answered.
## While the card is up that hold stands EVERY casualty pill down, so a card
## that fails to close takes the airway, the compressions, the recovery roll and
## the injury survey with it - there is no other way to reach any of them.
##
## The branch that closes it on `send_for_help` sat underneath an early return
## on `_help_card_spent`, and opening the card is what sets `spent`. So the
## branch could never fire on the case its own comment described: "the radio
## answered while the card was up". A trainee who answered the question by
## walking to the two-way radio and using it - the correct action, and the one
## the card's own "Call for help" option merely points at - was left with the
## card on screen and no body pointer for the rest of the run.
##
## Both routes out of the card are asserted here: the pill, and the radio.
## The radio one is the one that was broken; the pill one is asserted so a fix
## to it cannot quietly break the other.

const MAIN := preload("res://main.tscn")

var _failures: int = 0


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	print("\nAnswered at the radio, not on the card")
	await _run(main, true)

	print("\nAnswered on the card")
	await _run(main, false)

	_finish()


## One pass of the card. `by_radio` completes `send_for_help` while the card is
## up, standing in for walking to the bench and using the two-way radio;
## otherwise the card's own first option is taken.
func _run(main: Node, by_radio: bool) -> void:
	Assessment.reset()
	SimState.reset()
	SimState.begin_exercise()

	var card: Node = main.get_node_or_null("HelpCard")
	var menu: Node = main.get_node_or_null("CasualtyActions")
	if not _ok(card != null, "HelpCard is spawned"):
		return
	if not _ok(menu != null, "CasualtyActions is in the scene"):
		return

	# main.gd latches `_help_card_spent` for the life of the run, so a second
	# pass needs it cleared the way a fresh run would have it.
	main.set("_help_card_spent", false)
	if card.has_method("close"):
		card.close()
	menu.set_choice_hold(false)

	Assessment.complete(&"check_response")
	await get_tree().process_frame
	_ok(bool(card.get("is_open")), "the card opens on check_response")
	_ok(bool(menu.get("choice_hold")), "the casualty pills stand down while it is up")

	if by_radio:
		# What emergency_radio.gd does: both steps in one use.
		Assessment.complete(&"send_for_help")
		Assessment.complete(&"call_for_aed")
	else:
		card.call("_submit", 0)
	await get_tree().process_frame

	_ok(not bool(card.get("is_open")), "the card closed")
	_ok(not bool(menu.get("choice_hold")),
		"the pills are released - without this every later beat is unreachable")


func _ok(condition: bool, label: String) -> bool:
	if condition:
		print("  pass   %s" % label)
	else:
		_failures += 1
		print("  FAIL   %s" % label)
	return condition


func _finish() -> void:
	if _failures == 0:
		print("\ncheck_help_card: all assertions passed.")
		get_tree().quit()
		return
	printerr("\ncheck_help_card: %d assertion(s) FAILED." % _failures)
	get_tree().quit(1)
