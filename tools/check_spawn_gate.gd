extends Node
## Confirms the room is empty behind the kit check, and that the trainee
## starts where they are meant to.
##
##   & "C:\Program Files\Godot.exe" --headless --path <project> res://tools/check_spawn_gate.tscn
##
## Instances the real main scene and asserts that during the preamble the
## casualty is neither visible nor clickable, then advances the phase and
## asserts that both come back. Hiding the rig is not enough on its own -
## the interaction capsule is top-level and survives it.
##
## The spawn assertions are geometric rather than exact: the transform came
## off the Blender viewport camera and will be nudged by hand, so pinning
## coordinates would just make this fail every time somebody moves it.

const MAIN := preload("res://main.tscn")

var _failures: int = 0


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	var armature: Node3D = main.get_node_or_null("ControlRoom/Armature")
	var rig: Node = main.get_node_or_null("Casualty/Rig")
	var cue: Node = main.get_node_or_null("ShockCue")

	print("\nDuring the preamble")
	_ok(SimState.is_preamble(), "SimState reports preamble")
	_ok(armature != null, "armature found in the imported room")
	if armature != null:
		_ok(not armature.visible, "casualty is hidden")
	_ok(cue != null and not cue._armed, "shock cue is holding")
	if rig != null and rig.body != null:
		_ok(rig.body.collision_layer == 0, "casualty is not clickable")

	_check_spawn(main)

	SimState.begin_exercise()
	await get_tree().process_frame

	print("\nAfter the exercise starts")
	if armature != null:
		_ok(armature.visible, "casualty is in the room")
	_ok(cue != null and cue._armed, "shock cue armed")
	if rig != null and rig.body != null:
		_ok(rig.body.collision_layer == 2, "casualty is clickable again")

	if _failures == 0:
		print("\nspawn gate: all assertions passed.")
	else:
		printerr("\nspawn gate: %d assertion(s) FAILED." % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


## The trainee must start at the bench, facing it, with the door behind them.
## All three are properties of the brief - the kit check opens on a view of
## the kit, not on a wall.
func _check_spawn(main: Node) -> void:
	print("\nPlayer spawn")
	var player: Node3D = main.get_node_or_null("Player")
	var room: Node = main.get_node_or_null("ControlRoom")
	if player == null or room == null:
		_ok(false, "player and room present")
		return

	var head: Node3D = player.get_node_or_null("Head")
	var facing := -(player.global_transform.basis * head.transform.basis).z
	var flat_facing := Vector3(facing.x, 0.0, facing.z).normalized()
	var here := player.global_position

	_ok(absf(here.y) < 0.1, "spawned on the floor (y = %.2f)" % here.y)

	# Bench: the mean of the kit meshes, which is what they should be
	# looking at when the brief closes.
	var bench := Vector3.ZERO
	var counted := 0
	for name in ["Rescue kit bag", "Hook", "Gloves", "Fire blanket", "Burns_dressings",
		"Flashlight", "Isolate here"]:
		var mesh: Node3D = room.get_node_or_null(NodePath(name))
		if mesh != null:
			bench += mesh.global_position
			counted += 1
	_ok(counted == 7, "found %d kit meshes to aim at" % counted)
	if counted == 7:
		bench /= counted
		var to_bench := Vector3(bench.x - here.x, 0.0, bench.z - here.z)
		_ok(to_bench.length() < 2.5,
			"standing at the bench (%.2f m away)" % to_bench.length())
		_ok(flat_facing.dot(to_bench.normalized()) > 0.5,
			"facing the bench (dot %.2f)" % flat_facing.dot(to_bench.normalized()))

	var door: Node3D = room.get_node_or_null("Control room/LowPolyDoor 03_002")
	if door != null:
		var to_door := Vector3(
			door.global_position.x - here.x, 0.0, door.global_position.z - here.z
		).normalized()
		_ok(flat_facing.dot(to_door) < 0.0,
			"back to the door (dot %.2f)" % flat_facing.dot(to_door))
	else:
		print("  note   door mesh not found, skipping the facing check")


func _ok(condition: bool, label: String) -> void:
	if condition:
		print("  pass   %s" % label)
	else:
		_failures += 1
		print("  FAIL   %s" % label)
