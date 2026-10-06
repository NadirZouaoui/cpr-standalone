extends Node
## The isolation sign cannot be hung before the board has been reassessed.
##
##   & "C:\Program Files\Godot.exe" --headless --path <project> res://tools/check_sign_gate.tscn
##
## WHY THIS EXISTS
##
## Hanging the sign is what sends the worker in to be shocked
## (BreakerPanel._on_sign_hung). The mount used to ask only whether the board
## was open, so a trainee could open it, walk past pass 2 of the hazard survey,
## hang the sign, and be handed a casualty on a live conductor with a 20 s limit
## on `contact_broken` - while `hazards_reassessed`, which `crook_retrieved`
## requires, was still outstanding. The crook could not be taken, so contact
## could not be broken. A run-ending trap, reached by doing exactly what the
## game had just invited: the beacon moves to the sign ghost the moment the
## door swings.
##
## Watched happening on screen before it was fixed. Nothing in the procedure
## resource stops it either - `isolation_point_signed` requires only
## `panel_opened` (lvr_cpr_procedure.tres), and it is still authored that way,
## because the ordering rule and the interlock are different things: the
## resource decides what is scored out of order, this decides what the room
## will physically let you do.
##
## THE THREE THINGS ASSERTED, and why each is separate:
##
##   1. Board open, reassessment outstanding -> no ghost, no prompt, and the
##      interlock still refuses. Until 23 Sep 2026 the mount armed on the door
##      swing and refused with a message; the client asked for the ghost and
##      prompt to stay hidden until the second risk assessment instead, so the
##      next job is not on screen before the one in front of it is done.
##   2. Reassessment resolved -> the mount accepts. A gate that never opens is
##      a worse stuck run than the one it replaced.
##   3. The ordinary order still ends with the sign on the board and
##      `isolation_point_signed` complete, driven through the real bench pickup
##      and the real HandSlot rather than through Assessment.complete().
##
## NOT A GEOMETRY CHECK. `tools/check_sign_reachable.gd` owns which collider the
## crosshair acquires and fires no rays that this repeats; this file fires none
## at all. The two do overlap on one fact - that the mount is armed once the
## board is open - and that is deliberate: it is the precondition both rest on,
## and it has broken before.

const MAIN := preload("res://main.tscn")

var _failures: int = 0

## Last centre message put on the bus, so a refusal can be read back by its
## words. Cleared before each interaction rather than after, so a message left
## over from the door swing can never be mistaken for the mount's answer.
var _last_message: String = ""

var _sign_hung_fired: bool = false


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	Events.center_message_requested.connect(
		func(text: String, _c: Color, _d: float) -> void: _last_message = text)

	var dev: Node = main.get_node_or_null("DevMenu")
	if dev != null and dev.has_method("_force_close_blocking_screens"):
		dev._force_close_blocking_screens()
	SimState.begin_exercise()
	await get_tree().process_frame

	var panel: Node = main.get_node_or_null("BreakerPanel")
	if panel == null:
		_fail("no BreakerPanel in main.tscn")
		return _finish()

	# Open the board the way the sequence does - `_do_open()` completes
	# `panel_opened`, activates the ghost and arms the mount. `hazard_identified`
	# is completed directly because pass 1 has its own check and this one is
	# about what happens after the door.
	Assessment.complete(&"hazard_identified", 1.0)
	var interact: Node = panel.get("_interact")
	if interact != null and interact.has_method("_do_open"):
		interact._do_open()

	# Wait on the clock and on the state, never on a frame count: the swing is a
	# 0.9 s tween and headless frames are microseconds long, so a frame wait
	# elapses almost no tween time and the mount is never armed. Same trap
	# check_sign_reachable documents at length.
	var deadline: int = Time.get_ticks_msec() + 5000
	var mount: Node = null
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		mount = panel.get("_mount")
		if bool(panel.get("_touched")):
			break

	if mount == null:
		_fail("BreakerPanel built no sign mount")
		return _finish()
	mount.connect("sign_hung", func() -> void: _sign_hung_fired = true)

	if not _ok(Assessment.is_complete(&"panel_opened"), "panel_opened is complete"):
		return _finish()
	if not _ok(not Assessment.is_resolved(&"hazards_reassessed"),
			"hazards_reassessed is still outstanding - the trap's setup"):
		return _finish()

	# --- 1. nothing to hang it on yet -----------------------------------------
	# Client, 23 Sep 2026: "hide the hang isolation sign ghost/prompt until the
	# second risk assessment." The mount used to arm the moment the door swung
	# and refuse with a message; it now stays down - no ghost, no prompt - until
	# the reassessment resolves. accepts_sign() is kept as a second lock.
	print("\nBoard open, reassessment outstanding")
	_ok(not bool(mount.get("armed")), "the mount is not armed yet")
	_ok(not bool(mount.call("can_interact")), "the mount does not answer the crosshair")
	var anchor_node: Node = panel.get("_anchor")
	var ghost_target: Node3D = anchor_node.call("target") if anchor_node != null else null
	_ok(ghost_target == null or not ghost_target.visible, "the ghost is not shown")
	_ok(not bool(mount.call("accepts_sign")), "the interlock still refuses the sign")
	mount.call("interact", Vector3.ZERO)
	await get_tree().process_frame
	_ok(not bool(mount.call("is_hung")), "clicking it does not hang the sign")
	_ok(not Assessment.is_complete(&"isolation_point_signed"),
		"isolation_point_signed does not complete")
	_ok(not _sign_hung_fired, "sign_hung does not fire")

	# --- 2. opens once the pass is resolved ----------------------------------
	print("\nReassessment done")
	Assessment.complete(&"hazards_reassessed", 1.0)
	await get_tree().process_frame
	_ok(bool(mount.get("armed")), "the mount is armed")
	_ok(ghost_target == null or ghost_target.visible, "the ghost is shown")
	_ok(bool(mount.call("accepts_sign")), "the mount now takes the sign")
	# Empty-handed, so the only refusal left is the one that was always there.
	# This is what proves assertion 1 was the gate and not the hand check.
	var missing: String = mount.get("missing_message")
	_last_message = ""
	mount.call("interact", Vector3.ZERO)
	await get_tree().process_frame
	_ok(_last_message == missing,
		"empty-handed it asks for the sign, not for the reassessment (got '%s')"
		% _last_message)

	# --- 3. the ordinary order still finishes --------------------------------
	print("\nThe ordinary order")
	# Typed on the way out of `get()`, never inferred: this project treats
	# inference from a Variant as an error.
	var sign_id: StringName = mount.get("sign_item_id")
	var pickup: Node = _sign_pickup(sign_id)
	if not _ok(pickup != null, "the sign is on the bench to be picked up"):
		return _finish()
	pickup.call("interact", Vector3.ZERO)
	await get_tree().process_frame

	var slot := get_tree().get_first_node_in_group(HandSlot.GROUP) as HandSlot
	if not _ok(slot != null, "the player has a HandSlot"):
		return _finish()
	_ok(slot.held_item_id == sign_id, "the sign is in hand")

	mount.call("interact", Vector3.ZERO)
	await get_tree().process_frame
	_ok(bool(mount.call("is_hung")), "the sign goes up")
	_ok(Assessment.is_complete(&"isolation_point_signed"),
		"isolation_point_signed completes")
	_ok(_sign_hung_fired,
		"sign_hung fires - this is what starts the incident, so without it the "
		+ "run stops here")
	_ok(slot.held_item_id == &"",
		"the hand is empty again - handed over, not released back to the bench")

	_finish()


## The bench pickup for `item_id`, found through the interactable group rather
## than by node path: ToolRack binds these onto the imported room at runtime and
## the room's tree is rebuilt on every reimport, so there is no stable path to
## write down.
func _sign_pickup(item_id: StringName) -> Node:
	for node in get_tree().get_nodes_in_group(Interactable.GROUP):
		var item := node as PickupItem
		if item != null and item.item_id == item_id:
			return item
	return null


func _ok(condition: bool, label: String) -> bool:
	if condition:
		print("  pass   %s" % label)
	else:
		_failures += 1
		print("  FAIL   %s" % label)
	return condition


func _fail(label: String) -> void:
	_failures += 1
	print("  FAIL   %s" % label)


func _finish() -> void:
	if _failures == 0:
		print("\ncheck_sign_gate: all assertions passed.")
		get_tree().quit()
		return
	printerr("\ncheck_sign_gate: %d assertion(s) FAILED." % _failures)
	get_tree().quit(1)
