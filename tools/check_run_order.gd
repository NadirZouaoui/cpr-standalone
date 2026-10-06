extends Node
## Plays a whole clean run through the real objects and asserts that nothing the
## trainee did in the right order is scored as out of order.
##
##   & "C:\Program Files\Godot.exe" --headless --path <project> res://tools/check_run_order.tscn
##
## WHY THIS EXISTS
##
## check_procedure_order validates the resource against itself: no dangling
## requires, no cycles, and the resource's own array order as a happy path. All
## of that passed while two steps were flagged out of order in every single run.
##
## The gap is that the array order is the order the steps are AUTHORED in, and
## the run completes them in a different one. `cpr_performed` and `aed_used` are
## graded off `Events.cpr_completed` (CPR_CONTRACT.md §5, so the depth and pad
## metrics are final), which fires at the very end of the spine - after the
## handover. Anything listing them as a prerequisite is therefore asking for
## something that has not happened yet, however correctly the trainee plays:
##
##   chest_exposed   required cpr_performed. The shirt comes off between the two
##                   compression sets, which is what the client asked for.
##   signs_of_life   required aed_used. ROSC is announced after the second set.
##
## Both cost the ×0.5 out-of-order multiplier and put a violation in the debrief
## against a step the trainee performed at exactly the right moment. Neither is
## critical, or every run would have failed outright - which is how the same
## defect on `recovery_position` was caught earlier (see Casualty._achieve_rosc).
##
## This check is the one that can see it, because it plays the run rather than
## reading the resource. Drive new beats through the real station and casualty
## methods when they land, not through Assessment.complete().

const MAIN := preload("res://main.tscn")

var _failures: int = 0


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var dev: Node = main.get_node_or_null("DevMenu")
	if dev != null and dev.has_method("_force_close_blocking_screens"):
		dev._force_close_blocking_screens()

	Assessment.reset()
	SimState.reset()
	SimState.begin_exercise()

	var station: CprStation = main.get_node_or_null("CprStation") as CprStation
	var casualty: Casualty = get_tree().get_first_node_in_group(&"casualty") as Casualty
	if not _ok(station != null, "CprStation is in the scene"):
		return _finish()
	if not _ok(casualty != null, "the casualty is in the scene"):
		return _finish()

	await _play_run(station, casualty)
	_report()
	_finish()


## The run, in the order a trainee performs it. Everything before the CPR spine
## is completed directly - those beats belong to the room and have their own
## checks - but everything from the breathing check on goes through the real
## station and casualty methods, because the point here is WHEN each step lands.
func _play_run(station: CprStation, casualty: Casualty) -> void:
	# `torch_taken` sits with the gloves, before the incident. It gates nothing,
	# but main.gd fails it on leaving SCENE_SAFETY, so a clean run has to take
	# it here rather than at the end - which is exactly the ordering this file
	# exists to assert.
	for id in [&"kit_identified", &"ppe_donned", &"torch_taken",
			&"hazard_identified", &"panel_opened", &"hazards_reassessed",
			&"isolation_point_signed", &"crook_retrieved", &"contact_broken",
			&"drag_to_safe_area", &"supply_isolated", &"fire_checked",
			&"check_response", &"send_for_help", &"call_for_aed"]:
		Assessment.complete(id)
	casualty.open_airway()
	await get_tree().process_frame

	station.enter_cpr_phase()
	await get_tree().process_frame
	station.begin_breathing_check()
	await get_tree().process_frame
	Events.breathing_checked.emit(false)
	await get_tree().process_frame

	station.begin_airway_inspect()
	await get_tree().process_frame
	station.finish_airway_inspect()
	await get_tree().process_frame
	station.complete_pulse_check()
	await get_tree().process_frame

	station.begin_compressions_early()
	station.compressions_armed = true
	_deliver_set(30)
	Events.compression_set_completed.emit(30, false)
	await get_tree().process_frame

	casualty.expose_chest()
	await get_tree().process_frame

	Events.aed_picked_up.emit()
	await get_tree().process_frame
	Events.aed_placed.emit()
	await get_tree().process_frame
	Events.aed_pad_placed.emit(0, true, "PadSite_Correct_Upper")
	Events.aed_pad_placed.emit(1, true, "PadSite_Correct_Lower")
	await get_tree().process_frame

	station.compressions_armed = true
	Events.aed_shock_delivered.emit()
	await get_tree().process_frame
	station.compressions_armed = true
	_deliver_set(30)
	Events.compression_set_completed.emit(30, false)
	await get_tree().process_frame

	station.roll_to_recovery()
	await get_tree().process_frame
	# The whole body, not just the site with the finding. Checking the hands
	# alone used to end the survey and call the ambulance with two sites never
	# looked at; the beat now waits for every site in CprStation.INJURY_SITES.
	for site in CprStation.INJURY_SITES:
		station.survey_injury(site)
		await get_tree().process_frame

	# HANDOVER runs a siren on a real timer before COMPLETE, and COMPLETE is what
	# emits cpr_completed and so grades cpr_performed / aed_used. Wait on the
	# state, on the clock - a frame count elapses almost no time headless.
	var deadline: int = Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if station.current_state == CprStation.STATE_COMPLETE:
			break


## Reps good on both counts, so `cpr_performed`'s quality factor is 1.0 and the
## score reflects a run done properly rather than one that merely happened. The
## set-completed signal alone leaves pct_in_depth at zero, and a "clean run
## passes" assertion against a zero-quality CPR set is not worth much.
func _deliver_set(count: int) -> void:
	for i in count:
		Events.compression_delivered.emit(0.9, 110.0, i + 1)


func _report() -> void:
	print("\nEvery step reached")
	var missing: Array[String] = []
	for id in Assessment.order:
		if not Assessment.completed.has(id):
			missing.append(String(id))
	_ok(missing.is_empty(),
		"a clean run completes all %d steps%s" % [
			Assessment.order.size(),
			"" if missing.is_empty() else " - never reached: " + ", ".join(missing)])

	print("\nNothing correct is scored as out of order")
	var bad: Array[String] = []
	for id in Assessment.order:
		if not Assessment.completed.has(id):
			continue
		var rec: Dictionary = Assessment.completed[id]
		if not bool(rec.get("out_of_order", false)):
			continue
		var before: Array = rec.get("before", [])
		var names: Array[String] = []
		for b in before:
			names.append(String(b))
		bad.append("%s (waiting on %s)" % [id, ", ".join(names)])
	_ok(bad.is_empty(), "no step in a clean run is out of order%s" % [
		"" if bad.is_empty() else ": " + "; ".join(bad)])

	print("\nAnd it passes")
	_ok(Assessment.failed_critical().is_empty(),
		"no critical step reads as failed or out of order")
	var pct := Assessment.score_percent()
	print("  info   score_percent = %d" % pct)
	_ok(Assessment.is_passed(), "a clean run passes (%d%%)" % pct)


func _ok(condition: bool, label: String) -> bool:
	if condition:
		print("  pass   %s" % label)
	else:
		_failures += 1
		print("  FAIL   %s" % label)
	return condition


func _finish() -> void:
	if _failures == 0:
		print("\ncheck_run_order: all assertions passed.")
		get_tree().quit()
		return
	printerr("\ncheck_run_order: %d assertion(s) FAILED." % _failures)
	get_tree().quit(1)
