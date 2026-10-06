extends Node
## The torch is a graded precaution that gates nothing, and must stay that way.
##
##   & "C:\Program Files\Godot.exe" --headless --path <project> res://tools/check_torch_step.tscn
##
## WHY THIS EXISTS
##
## `torch_taken` has no prerequisites and blocks nothing, which is exactly what
## was asked for - and exactly what makes it dangerous to the HUD.
## `Assessment.next_step()` returns the first unresolved *available* step in
## list order, and both the objective pill and the checklist card read it. An
## optional step with nothing to close it therefore becomes the answer to "what
## should I be doing now" for the rest of the run the moment it is skipped,
## hiding every real objective behind it. That is the fault
## docs/PLAYTEST_2026-09-04_pass2.md section 3 records "Perform the CPR set"
## causing for the whole second half of a run, and it is worth one test.
##
## So three things are asserted: taking the torch completes the step, skipping
## it does not stall the checklist, and it never gates anything downstream.

const MAIN := preload("res://main.tscn")

var _failures: int = 0


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	print("\nThe step exists and is shaped as agreed")
	var step: ProcedureStep = Assessment.steps.get(&"torch_taken")
	if not _ok(step != null, "torch_taken is in the procedure"):
		_finish()
		return
	_ok(step.weight == 4, "weight 4 (is %d)" % step.weight)
	_ok(not step.critical, "not critical")
	_ok(step.requires.is_empty(), "requires nothing")
	_ok(not step.suppress_prompt, "is offered on the HUD")
	_ok(Assessment.steps.get(&"kit_selected") == null,
		"the merged-away kit_selected step is gone")
	_ok(Assessment.steps[&"kit_identified"].weight == 14,
		"kit_identified carries both old weights (is %d)"
			% Assessment.steps[&"kit_identified"].weight)

	print("\nNothing anywhere requires it")
	var dependents: Array[String] = []
	for id in Assessment.order:
		if &"torch_taken" in Assessment.steps[id].requires:
			dependents.append(String(id))
	_ok(dependents.is_empty(), "no step is gated on it (%s)"
		% (", ".join(dependents) if not dependents.is_empty() else "none"))

	print("\nThe Flashlight on the bench is what completes it")
	var flashlight := _find(main, "Flashlight")
	if _ok(flashlight != null, "the Flashlight is in the room"):
		var pickup: PickupItem = null
		for child in flashlight.get_children():
			if child is PickupItem:
				pickup = child
		if _ok(pickup != null, "ToolRack bound a pickup to it"):
			_ok(pickup.step_on_pickup == &"torch_taken",
				"picking it up completes torch_taken (is '%s')"
					% pickup.step_on_pickup)

	print("\nTaken: the step completes")
	Assessment.reset()
	SimState.reset()
	SimState.begin_exercise()
	Assessment.complete(&"torch_taken")
	_ok(Assessment.is_complete(&"torch_taken"), "completed")

	print("\nSkipped: the checklist moves on regardless")
	Assessment.reset()
	SimState.reset()
	SimState.begin_exercise()
	Assessment.complete(&"kit_identified")
	Assessment.complete(&"ppe_donned")
	await get_tree().process_frame
	# Before the incident the torch IS the honest next job - it is a precaution
	# to sort out now, and the pill saying so is the point of the step.
	_ok(Assessment.next_step() == &"torch_taken",
		"before the incident it is offered (is '%s')" % Assessment.next_step())

	# Once the work has commenced it must stop being the answer, whether or not
	# the trainee ever took it. main.gd closes the window on leaving
	# SCENE_SAFETY.
	SimState.phase = SimState.Phase.BREAK_CONTACT
	await get_tree().process_frame
	_ok(Assessment.is_resolved(&"torch_taken"),
		"leaving SCENE_SAFETY resolves it")
	_ok(Assessment.is_failed(&"torch_taken"), "and resolves it as failed")
	var next := Assessment.next_step()
	_ok(next != &"torch_taken",
		"it is no longer the standing objective (is '%s')" % next)
	_ok(next == &"hazard_identified",
		"the real objective is back in front of the trainee (is '%s')" % next)

	_finish()


func _find(root: Node, node_name: String) -> Node3D:
	var room := root.get_node_or_null("ControlRoom")
	if room == null:
		return null
	var direct := room.get_node_or_null(NodePath(node_name)) as Node3D
	if direct != null:
		return direct
	return CprGhost.find_node(room, node_name) as Node3D


func _ok(condition: bool, label: String) -> bool:
	if condition:
		print("  pass   %s" % label)
	else:
		_failures += 1
		print("  FAIL   %s" % label)
	return condition


func _finish() -> void:
	if _failures == 0:
		print("\ncheck_torch_step: all assertions passed.")
		get_tree().quit()
		return
	printerr("\ncheck_torch_step: %d assertion(s) FAILED." % _failures)
	get_tree().quit(1)
