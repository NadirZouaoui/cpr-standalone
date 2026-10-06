extends Node
## Asserts the isolation sign can actually be aimed at once the board is open.
##
##   & "C:\Program Files\Godot.exe" --headless --path <project> res://tools/check_sign_reachable.tscn
##
## WHY THIS EXISTS
##
## Task 4 added a padded, axis-aligned hitbox on `Breaker busbars` so the pass-2
## hazard reassessment could be picked with the crosshair. That box is a crude
## AABB around a long, angled busbar run, and it reaches out in front of the
## board face - far enough to enclose the isolation sign's own collider, which
## sits about 22 mm behind its front face.
##
## The result was a HARD STUCK RUN, found by Nadir in the first real playthrough:
## every aim at the sign resolved to the reassess interactable instead of the
## mount, `isolation_point_signed` could never be completed, and because
## `crook_retrieved` sits behind the scene-safety steps the whole rescue was
## unreachable. Nothing in the logic was wrong - the gates were all open, the
## held item matched, `can_interact()` returned true. It was purely a question
## of which collider the ray met first.
##
## `IsolationSignAnchor.proud_offset` is the fix. This check is what stops it
## being quietly removed as a mystery constant: set it to zero and the first two
## assertions fail with exactly the symptom above.
##
## The busbar assertion is the pair to those on purpose. Pushing the sign forward
## far enough to win must not steal the busbars' own aim, or pass 2 becomes the
## unreachable one and the run stalls a step later instead.
##
## TWO THINGS THIS FILE GOT WRONG BEFORE IT RAN, both worth keeping:
##
## 1. It had no `.tscn`, and its header blamed the game: "instantiating main.tscn
##    headless does not terminate - something in the boot path awaits forever
##    without a rendering device". None of that was true. The script had a parse
##    error (`var script := node.get_script()`, inferring from Variant, which
##    this project treats as an error), so it never loaded, `_ready()` never ran,
##    and nothing ever called `get_tree().quit()`. A check scene whose script
##    fails to parse does not fail - it hangs forever, silently, and the one line
##    of stderr saying so scrolls past. main.tscn instantiates headless in about
##    two frames and always did.
##
## 2. It waited 90 process frames for the door to swing. The swing is a 0.9 s
##    tween and it is what arms the mount; headless frames are microseconds long,
##    so almost no tween time elapsed, the mount was never armed, its collider
##    stayed off layer 2, and the aim assertion failed for a reason that had
##    nothing to do with geometry. Wait on `Time.get_ticks_msec()` and on the
##    state you actually want, never on a frame count.


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
	SimState.begin_exercise()
	await get_tree().process_frame

	var panel: Node = main.get_node_or_null("BreakerPanel")
	if panel == null:
		_fail("no BreakerPanel in main.tscn")
		return _finish()

	# Open the board the way the sequence does, so the anchor is activated and
	# the mount armed. The hazard steps are completed directly - this check is
	# about geometry, and the assessment has its own check.
	Assessment.complete(&"hazard_identified", 1.0)
	# The mount arms only once the open board has been reassessed (client,
	# 23 Sep), so resolve that too before waiting on it.
	Assessment.complete(&"hazards_reassessed", 1.0)
	var interact: Node = panel.get("_interact")
	if interact != null and interact.has_method("_do_open"):
		interact._do_open()

	# Wait on the clock, not on frames. The door swings on a 0.9 s tween and
	# arms the mount when it lands; headless frames are microseconds long, so
	# the 90-frame wait this used to do elapsed almost no tween time at all and
	# the mount was never armed - which then made the aim assertion below fail
	# for a reason that had nothing to do with geometry.
	var deadline: int = Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var m: Node = panel.get("_mount")
		if m != null and bool(m.get("armed")):
			break

	var mount = panel.get("_mount")
	if mount == null:
		_fail("BreakerPanel built no sign mount")
		return _finish()
	var target: Node3D = mount.get_parent()
	var anchor: Node3D = target.get_parent()

	print("\nGeometry")
	print("  sign target at %s" % target.global_position)
	_ok(mount.get("armed"), "mount is armed once the board is open")

	var busbars: Node3D = main.get_node_or_null("ControlRoom/Breaker busbars")
	_ok(busbars != null, "busbars found (the thing that used to swallow the sign)")
	var hitbox: Node = null
	if busbars != null:
		hitbox = busbars.get_node_or_null("BusbarHitbox")
	_ok(hitbox != null, "busbar hitbox is present - without it this check proves nothing")

	# "Toward the trainee" is the anchor's own local +Z - the direction
	# `proud_offset` pushes the collider along - rather than a hard-coded world
	# vector, so this still aims at the board's face if the board is ever moved
	# or turned. Two stand-offs on the sign: square on, which is how the trainee
	# will usually take the shot, and from off to one side, which is the harder
	# ray and the one the busbar hitbox first swallowed.
	var out: Vector3 = anchor.global_basis.z.normalized()
	var up := Vector3(0.0, 1.0, 0.0)
	var side: Vector3 = out.cross(up).normalized()
	var angled: Vector3 = out * 0.8 + side * 0.35 + up * 0.35
	print("\nWhat the crosshair actually acquires")
	_aim_check(target, target.global_position, out * 0.8, "SignMount",
		"square on, the sign resolves to the sign mount")
	_aim_check(target, target.global_position, angled, "SignMount",
		"from off to one side, the sign resolves to the sign mount")
	if busbars != null:
		_aim_check(target, busbars.global_position + Vector3(0.0, -0.12, 0.0),
			angled, "ReassessInteract",
			"aiming at the busbars still resolves to the pass-2 interactable")

	_finish()


## Fire a ray at `point` from `stand_off` in front of it and report which
## Interactable the resolver returns, by class name. The stand-off mimics the
## trainee: outside the board, within the interaction ray's 2 m reach.
func _aim_check(target: Node3D, point: Vector3, stand_off: Vector3,
		wanted: String, label: String) -> void:
	var from: Vector3 = point + stand_off
	var space := target.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, point)
	query.collision_mask = 7
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		_fail("%s - the ray hit nothing at all" % label)
		return
	var collider: Object = hit["collider"]
	var found := _resolve(collider as Node)
	var got := "nothing" if found == null else found.get_class()
	if found != null and found.get_script() != null:
		got = str(found.get_script().resource_path).get_file().get_basename()
	print("  %s -> %s" % [label, got])
	_ok(_class_matches(found, wanted), "%s (got %s)" % [label, got])


func _class_matches(node: Node, wanted: String) -> bool:
	if node == null:
		return false
	if node.name == wanted:
		return true
	# Typed rather than inferred: get_script() is Variant, and this project
	# treats inference-from-Variant as an error. See the STATUS note above.
	var script: Script = node.get_script() as Script
	if script == null:
		return false
	# SignMount / ReassessInteract are node names; fall back to the script file.
	var stem := str(script.resource_path).get_file().get_basename()
	return (wanted == "SignMount" and stem == "isolation_sign_mount") \
		or (wanted == "ReassessInteract" and stem == "hazard_reassess_interact")


## The same walk InteractionRay does: the collider, then its direct children,
## then up the parent chain. Duplicated rather than reached into so the check
## fails if the ray's own resolution changes shape.
func _resolve(node: Node) -> Node:
	var fallback: Node = null
	for _i in 6:
		if node == null:
			break
		var candidates: Array[Node] = []
		if node is Interactable:
			candidates.append(node)
		for child in node.get_children():
			if child is Interactable:
				candidates.append(child)
		for c in candidates:
			if c.call("can_interact"):
				return c
			if fallback == null:
				fallback = c
		node = node.get_parent()
	return fallback


func _ok(condition: bool, label: String) -> void:
	if condition:
		print("  pass   %s" % label)
	else:
		_fail(label)


func _fail(label: String) -> void:
	_failures += 1
	print("  FAIL   %s" % label)


func _finish() -> void:
	if _failures == 0:
		print("\ncheck_sign_reachable: all assertions passed.")
		get_tree().quit()
		return
	print("\ncheck_sign_reachable: %d assertion(s) FAILED." % _failures)
	get_tree().quit(1)
