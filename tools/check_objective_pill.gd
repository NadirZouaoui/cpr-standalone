extends Node
## The standing objective at the bottom of the screen must name the beat the
## trainee is actually on.
##
##   & "C:\Program Files\Godot.exe" --headless --path <project> res://tools/check_objective_pill.tscn
##
## WHY THIS EXISTS
##
## `cpr_performed` and `aed_used` are graded at the END of the phase, from the
## cpr_completed metrics, not when their own beat finishes. Assessment.next_step()
## returns the first unresolved step whose prerequisites are met, so from the
## moment `pulse_checked` lands, `cpr_performed` is its answer for the whole
## rest of the run. Traced frame by frame in a running game: the pill read
## "Perform the CPR set" while the trainee was being sent to fetch the AED,
## while placing the pads, while standing clear for the shock, and again
## underneath "Ambulance arriving - hand over to the crew" on the closing beat.
##
## CprStation.STATE_STEPS answers it instead, per spine state, and hud.gd asks
## that first. This asserts the answer at every state in the map.
##
## Two traps this is shaped around:
##
##  - HANDOVER completes `handover` on the same frame it is entered, so any
##    version of step_for_state() that skips resolved steps falls straight back
##    to next_step() and puts the compression set back on the closing beat. The
##    handover assertion below is that regression.
##  - hud.gd also stands the pill down while a body pointer is drawn. Headless
##    there is no camera, so no pill is ever drawn and that half does not
##    interfere here. It is covered on screen instead.

const MAIN := preload("res://main.tscn")

## state -> what the pill must read, or "" for "the pill must be down".
##
## Since 23 Sep 2026 (client: "don't tell them what to do next in the correct
## order") the casualty phase is one line - "Perform CPR" through the spine,
## "Treat the casualty" either side of it - so what is asserted now is that the
## pill never names a micro-step, and still stands down on the closing beat.
const EXPECTED := {
	CprStation.STATE_COMPRESSIONS_1: "Perform CPR",
	CprStation.STATE_EXPOSE_CHEST: "Perform CPR",
	CprStation.STATE_AED_FETCH: "Perform CPR",
	CprStation.STATE_AED_DEPLOY: "Perform CPR",
	CprStation.STATE_PAD_PLACEMENT: "Perform CPR",
	CprStation.STATE_SHOCK: "Perform CPR",
	CprStation.STATE_COMPRESSIONS_2: "Perform CPR",
	CprStation.STATE_RECOVERY_ROLL: "Treat the casualty",
	CprStation.STATE_INJURY_SURVEY: "Treat the casualty",
	CprStation.STATE_HANDOVER: "",                 # handover, suppress_prompt
}

var _failures: int = 0


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var hud: Node = main.get_node_or_null("Hud")
	var station := CprStation.get_current()
	if not _ok(hud != null, "the HUD is in the scene"):
		return _finish()
	if not _ok(station != null, "the CPR station is in the scene"):
		return _finish()

	Assessment.reset()
	SimState.reset()
	SimState.begin_exercise()
	station.enter_cpr_phase()

	# The run has to be past the pulse check for `cpr_performed` to be what
	# next_step() answers - which is the condition the whole bug lives in. Close
	# everything up to it, exactly as a clean run would.
	for id in Assessment.order:
		if id == &"cpr_performed":
			break
		Assessment.complete(id)
	_ok(Assessment.next_step() == &"cpr_performed",
		"next_step() answers cpr_performed from here on - the condition under test")
	# Where the spine actually runs. begin_exercise() stops at SCENE_SAFETY.
	SimState.phase = SimState.Phase.PRIMARY_SURVEY

	for state in EXPECTED:
		var want: String = EXPECTED[state]
		station.debug_jump_to_state(state)
		await get_tree().process_frame
		var pill: Control = hud.get("_step_pill")
		var label: Label = hud.get("_step_label")
		var shown := ""
		if pill != null and pill.visible and label != null:
			shown = label.text
		var name: String = CprStation.STATE_NAMES.get(state, str(state))
		if want == "":
			_ok(shown == "", "%s asks nothing of the pill, and the pill is down" % name)
		else:
			_ok(shown == want, "%s names \"%s\" (got \"%s\")" % [name, want, shown])

	_finish()


func _ok(condition: bool, label: String) -> bool:
	if condition:
		print("  pass   %s" % label)
	else:
		_failures += 1
		print("  FAIL   %s" % label)
	return condition


func _finish() -> void:
	if _failures == 0:
		print("\ncheck_objective_pill: all assertions passed.")
		get_tree().quit()
		return
	printerr("\ncheck_objective_pill: %d assertion(s) FAILED." % _failures)
	get_tree().quit(1)
