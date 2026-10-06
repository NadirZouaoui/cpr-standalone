class_name HandSlot
extends Node3D
## The rescuer's hand. Carries at most one world object as a view model.
##
## The held node is the real imported mesh, reparented out of the room and
## put back on release - not a duplicate. That keeps one source of geometry,
## and a tool the trainee puts down is the same object with the same id they
## picked up, sitting where it started.
##
## Orientation is solved rather than authored. The caller says which corner
## of the mesh is the handle and which way the far end should point in view
## space; this works out the rotation. That beats hand-tuned Euler angles,
## which have to be re-guessed whenever an artist changes an object's
## origin in Blender.
##
## Nothing here knows what a tool *means*. The caller passes a return
## callback, so PickupItem keeps ownership of its own state and this node
## stays a piece of presentation.

const GROUP := &"hand_slot"

## Emitted on take and on release. `item_id` is &"" when the hand empties.
signal held_changed(item_id: StringName)

## Emitted when a strike_at() sequence has fully returned to rest.
signal strike_finished

## Emitted the instant the tip reaches the target. The withdraw starts on
## the same frame, so anything that should react to being hooked reacts to
## this, not to strike_finished.
signal strike_contact

@export_group("Placement")
## Where the grip point sits relative to the camera. Right and low, so it
## reads as "in hand" without covering the reticle.
@export var rest_position := Vector3(0.24, -0.20, -0.45)

## Items longer than this are pushed further out so a long tool does not
## fill the screen.
@export var comfortable_size: float = 0.30

@export_group("Motion")
## Degrees of lag behind camera rotation. 0 disables sway.
@export var sway_degrees: float = 4.0
@export var sway_speed: float = 9.0
@export var bob_amount: float = 0.008
@export var bob_speed: float = 2.5

@export_group("Strike")
## Timing of the reach and withdraw beats of strike_at(). The two run back
## to back - a pause at full extension reads as the hook getting stuck.
@export var strike_reach_time: float = 0.40
@export var strike_return_time: float = 0.55
## Extra distance past the target, so the tip visibly makes contact rather
## than stopping exactly on the surface.
@export var strike_overshoot: float = 0.03

var held: Node3D = null
var held_item_id: StringName = &""

# Where the held node came from, so release() can put it back exactly.
var _home_parent: Node = null
var _home_index: int = -1
var _home_transform: Transform3D
var _home_layers: Dictionary = {}
var _on_returned: Callable = Callable()

var _rig: Node3D = null
var _sway := Vector2.ZERO
var _bob_t: float = 0.0
var _last_yaw: float = 0.0
var _last_pitch: float = 0.0

# Handle position and handle-to-tip vector of the held item, both in this
# node's local space. Solved once at take() so a strike can aim the tip
# without re-deriving the item's bounds every time.
var _grip_handle := Vector3.ZERO
var _grip_tip := Vector3.FORWARD
var _striking: bool = false


func _ready() -> void:
	add_to_group(GROUP)
	# Sway and bob move the rig, so the solved grip transform on the item
	# itself is never overwritten by animation.
	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)
	set_process(false)


func is_empty() -> bool:
	return held == null


# =============================================================================
# Take / release
# =============================================================================
## Move `item` into the hand. Returns false if it could not be taken.
##
## `grip_anchor` is the handle position in normalised bounds space, 0-1 per
## axis, so it is independent of whatever scale Blender baked into the node.
## (0.5, 0.5, 0.5) is the centre of the object.
##
## `aim_direction` is the camera-space direction the far end should point:
## -Z is into the screen, +Y up, +X right.
##
## `roll_degrees` spins the item about that aim axis - the one value that
## still has to be set by eye, since it decides which way an asymmetric
## shape such as a hook opens.
func take(
	item: Node3D,
	item_id: StringName,
	grip_anchor: Vector3 = Vector3(0.5, 0.5, 0.5),
	aim_direction: Vector3 = Vector3(0.0, 0.25, -0.97),
	roll_degrees: float = 0.0,
	grip_offset: Vector3 = Vector3.ZERO,
	hold_rotation: Vector3 = Vector3.ZERO,
	on_returned: Callable = Callable()
) -> bool:
	if item == null or item.get_parent() == null:
		return false
	if held != null:
		release()

	_home_parent = item.get_parent()
	_home_index = item.get_index()
	_home_transform = item.transform
	_on_returned = on_returned

	# Blender scales are baked into the node, not the mesh, so the item's own
	# scale has to survive the move or a 0.01-scaled wrench becomes a girder.
	var item_scale: Vector3 = item.transform.basis.get_scale()

	_home_layers.clear()
	for body in _collision_bodies(item):
		_home_layers[body] = [body.collision_layer, body.collision_mask]
		# Out of the world entirely: no blocking the player, no ray focus.
		body.collision_layer = 0
		body.collision_mask = 0

	_home_parent.remove_child(item)
	_rig.add_child(item)

	var bounds := _mesh_bounds(item)
	var scale_basis := Basis.from_scale(item_scale)

	# The handle, and the far end opposite it, both in the item's own space.
	var anchor_local := bounds.position + bounds.size * grip_anchor
	var tip_local := bounds.position + bounds.size * (Vector3.ONE - grip_anchor)

	# hold_rotation is applied in camera space, outside the aim solve. Roll
	# only spins the item about the aim axis, which for a flat plaque means
	# pinwheeling it in the plane of the screen - it can never turn the face
	# toward the viewer. An explicit pose can, and for a centre-gripped item
	# there is no long axis for the solve to work with anyway.
	var pose := Basis.from_euler(Vector3(
		deg_to_rad(hold_rotation.x),
		deg_to_rad(hold_rotation.y),
		deg_to_rad(hold_rotation.z)
	))
	var grip_basis := pose * _solve_aim(
		scale_basis * (tip_local - anchor_local),
		aim_direction,
		roll_degrees
	) * scale_basis

	item.transform = Transform3D(grip_basis, Vector3.ZERO)

	var rest := rest_position
	var reach: float = (grip_basis * (tip_local - anchor_local)).length()
	if reach > comfortable_size:
		rest.z -= (reach - comfortable_size) * 0.5

	# Put the handle - not the centre of the object - in the hand.
	item.position = rest + grip_offset - (grip_basis * anchor_local)
	item.visible = true

	_grip_handle = item.position
	_grip_tip = grip_basis * (tip_local - anchor_local)

	held = item
	held_item_id = item_id
	_sway = Vector2.ZERO
	_bob_t = 0.0
	_last_yaw = global_basis.get_euler().y
	_last_pitch = global_basis.get_euler().x
	set_process(sway_degrees > 0.0 or bob_amount > 0.0)

	held_changed.emit(item_id)
	return true


## Put the held item back where it came from and notify its owner.
func release() -> void:
	if held == null:
		return

	var item: Node3D = held
	var callback: Callable = _on_returned
	held = null
	held_item_id = &""
	_on_returned = Callable()
	set_process(false)
	_rig.transform = Transform3D.IDENTITY

	_rig.remove_child(item)
	if is_instance_valid(_home_parent):
		_home_parent.add_child(item)
		if _home_index >= 0 and _home_index < _home_parent.get_child_count():
			_home_parent.move_child(item, _home_index)
		item.transform = _home_transform
	else:
		# The room was swapped out from under us. Drop the node rather than
		# leaving an orphan parented to the camera.
		item.queue_free()

	for body: CollisionObject3D in _home_layers:
		if is_instance_valid(body):
			body.collision_layer = _home_layers[body][0]
			body.collision_mask = _home_layers[body][1]

	_home_layers.clear()
	_home_parent = null
	_home_index = -1

	held_changed.emit(&"")
	if callback.is_valid():
		callback.call()


# =============================================================================
# Orientation
# =============================================================================
## Give the held item to something else in the world - a wall bracket, a
## mount, a casualty - instead of returning it to where it was picked up.
##
## Detaches the node and hands it back parentless, with its collision layers
## restored, so the caller decides where it lives now. release() is the wrong
## tool for this: it would carry the item straight back to the bench.
func hand_over() -> Node3D:
	if held == null:
		return null

	var item: Node3D = held
	held = null
	held_item_id = &""
	_on_returned = Callable()
	set_process(false)
	_rig.transform = Transform3D.IDENTITY
	_rig.remove_child(item)

	for body: CollisionObject3D in _home_layers:
		if is_instance_valid(body):
			body.collision_layer = _home_layers[body][0]
			body.collision_mask = _home_layers[body][1]

	_home_layers.clear()
	_home_parent = null
	_home_index = -1

	held_changed.emit(&"")
	return item

## Rotation taking `from` onto `aim`, then rolled about the aim axis.
func _solve_aim(from: Vector3, aim: Vector3, roll_degrees: float) -> Basis:
	if aim.length_squared() < 0.000001:
		return Basis.IDENTITY

	var b := aim.normalized()

	# A centre grip makes the handle and the far end the same point, so there
	# is no long axis to swing onto the aim - but the roll is still the only
	# thing deciding which way up the object hangs. Bailing to IDENTITY here
	# silently discarded `roll_degrees` for every compact item on the bench.
	if from.length_squared() < 0.000001:
		return Basis(b, deg_to_rad(roll_degrees))

	var a := from.normalized()
	var axis := a.cross(b)

	var swing: Basis
	if axis.length_squared() < 0.000001:
		# Parallel or exactly opposed - no unique axis, so pick one.
		swing = Basis.IDENTITY if a.dot(b) > 0.0 else Basis(Vector3.UP, PI)
	else:
		swing = Basis(axis.normalized(), a.angle_to(b))

	return Basis(b, deg_to_rad(roll_degrees)) * swing


# =============================================================================
# Motion
# =============================================================================
func _process(delta: float) -> void:
	# A strike owns the rig outright; sway and bob would fight the tween.
	if _striking:
		return

	var euler := global_basis.get_euler()
	var d_yaw := angle_difference(_last_yaw, euler.y)
	var d_pitch := angle_difference(_last_pitch, euler.x)
	_last_yaw = euler.y
	_last_pitch = euler.x

	# Target is zero whenever the camera is still, so sway settles on its own.
	var target := Vector2(
		clampf(-d_pitch * 12.0, -1.0, 1.0),
		clampf(-d_yaw * 12.0, -1.0, 1.0)
	) * sway_degrees
	_sway = _sway.lerp(target, clampf(sway_speed * delta, 0.0, 1.0))

	_bob_t += delta * bob_speed
	_rig.rotation = Vector3(deg_to_rad(_sway.x), deg_to_rad(_sway.y), 0.0)
	_rig.position.y = sin(_bob_t) * bob_amount


# =============================================================================
# Strike
# =============================================================================
## Swing the held item at a world point and come straight back to rest.
##
## Aims the *tip* rather than the hand, so a hook held off to one side still
## points its business end at the target. The aim is solved against the
## target directly, which is the whole point: the trainee can be looking at
## the casualty's head or his boots and the hook still goes to the hips.
##
## Awaitable - `await hand_slot.strike_at(p)` returns once the hand is back
## at rest, which is the cue to start the fall.
func strike_at(target: Vector3) -> void:
	if held == null or _striking:
		return

	_striking = true

	# Where the tip sits now, and where we want it pointing, both relative
	# to the hand.
	var tip_now := _grip_handle + _grip_tip
	var to_target := to_local(target)
	if to_target.length_squared() < 0.0001:
		_striking = false
		return

	var swing := _solve_aim(tip_now, to_target, 0.0)

	# Translate the hand by whatever the hook cannot already span. Once the
	# swing has aimed the tip at the target, the tip sits `tip_now.length()`
	# along that line, so the shortfall is the rest of the distance - which
	# makes the reach correct at any range instead of a fixed lunge.
	var shortfall := to_target.length() - tip_now.length() + strike_overshoot
	var push := to_target.normalized() * maxf(shortfall, 0.0)
	var extended := Transform3D(swing, push)

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	# Fast out to the casualty, slower on the way back: the reach is a
	# decisive movement, the withdraw is a controlled one.
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(_rig, "transform", extended, strike_reach_time)
	tween.tween_callback(func() -> void: strike_contact.emit())
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_rig, "transform", Transform3D.IDENTITY, strike_return_time)
	await tween.finished

	# Released mid-swing: release() already reset the rig, so leave it alone.
	if held != null:
		_rig.transform = Transform3D.IDENTITY
	_striking = false
	_sway = Vector2.ZERO
	strike_finished.emit()


## True while a strike is in flight, so callers can avoid overlapping one.
func is_striking() -> bool:
	return _striking


# =============================================================================
# Helpers
# =============================================================================
func _collision_bodies(root: Node) -> Array[CollisionObject3D]:
	var out: Array[CollisionObject3D] = []
	if root is CollisionObject3D:
		out.append(root)
	for child in root.get_children():
		out.append_array(_collision_bodies(child))
	return out


## Bounds of every mesh under `root`, in `root`'s own local space - before
## any grip transform, so normalised anchors mean the same thing every time.
func _mesh_bounds(root: Node3D) -> AABB:
	var out := AABB()
	var seeded := false
	var to_local := root.global_transform.affine_inverse()

	for mesh in _meshes(root):
		if mesh.mesh == null:
			continue
		var box := (to_local * mesh.global_transform) * mesh.mesh.get_aabb()
		if seeded:
			out = out.merge(box)
		else:
			out = box
			seeded = true
	return out


func _meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		out.append(root)
	for child in root.get_children():
		out.append_array(_meshes(child))
	return out
