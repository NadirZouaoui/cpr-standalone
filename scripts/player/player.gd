class_name Player
extends CharacterBody3D
## First-person rescuer.
##
## Movement and camera only. Interaction lives in InteractionRay; everything
## else talks to the world through Events. The browser mouse-capture
## workarounds are carried over from the substation build verbatim - they
## were hard won and the failure mode without them is unpleasant.

@export_group("Movement")
@export var walk_speed: float = 4.5
@export var sprint_speed: float = 7.5
@export var crouch_speed: float = 2.0
@export var mouse_sensitivity: float = 0.003
## Arrow-key look rate, radians per second. Keyboard look exists because
## SCORM players are often driven on a locked-down machine where the
## pointer never reliably locks to the iframe.
@export var key_look_speed: float = 2.2
@export var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

## VERTICAL field of view, which is what Camera3D.fov means while keep_aspect
## is KEEP_HEIGHT (the default).
##
## Godot's default is 75, and at 16:9 that works out to about 107 degrees
## horizontally — far wider than a person's useful vision, and wide angles push
## everything toward the centre and shrink it. Standing over the casualty, a
## correctly-proportioned adult read as small and further away than he was.
##
## 60 vertical is about 90 horizontal at 16:9, the usual first-person figure.
## Exported so it can be tuned without another code change; note the CPR camera
## rig and the debug fly camera both borrow this same Camera3D, so one value
## covers every view in the exercise.
@export_range(40.0, 100.0, 1.0) var camera_fov: float = 60.0

@export_group("Stance Heights")
@export var head_height_normal: float = 1.7
@export var head_height_crouch: float = 0.9
@export var head_height_kneel: float = 0.7

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var interaction_ray: InteractionRay = $Head/Camera3D/InteractionRay
@onready var hand_slot: HandSlot = $Head/Camera3D/HandSlot
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

## Blocks input and movement. Set while a UI is open or a scripted
## camera sequence (CPR) has taken over.
var is_frozen: bool = false:
	set = _set_frozen

## Forces the kneeling stance - used when working on the casualty.
var is_kneeling: bool = false

var _default_capsule_height: float = 2.0
## Reused for the standing-up test rather than built per frame.
var _headroom_shape: CapsuleShape3D = null


func _ready() -> void:
	add_to_group(&"player")
	camera.fov = camera_fov
	camera.make_current()
	_request_capture()

	if collision_shape.shape is CapsuleShape3D:
		_default_capsule_height = collision_shape.shape.height
		_headroom_shape = CapsuleShape3D.new()
		_headroom_shape.radius = collision_shape.shape.radius

	# The room's collision is imported trimesh, tens of thousands of faces per
	# cabinet, and the default 0.001 m margin lets the capsule settle into the
	# seams between faces and wedge there. A centimetre of margin keeps it
	# sliding along the surface instead, which is what this is for.
	safe_margin = 0.02

	Events.ui_opened.connect(func(_n): _sync_frozen())
	Events.ui_closed.connect(func(_n): _sync_frozen())


func _set_frozen(value: bool) -> void:
	is_frozen = value
	if interaction_ray != null:
		interaction_ray.active = not value
		if value:
			interaction_ray.clear()


func _sync_frozen() -> void:
	if Events.is_ui_blocking():
		self.is_frozen = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		self.is_frozen = false
		_request_capture()


## Waits a whole frame and re-checks, on purpose. One blocking screen often
## closes just before the next one opens (kit review -> "Begin simulation"),
## and a scene reload closes every UI and only opens the new scene's card from
## a deferred call (tutorial "Start exercise", pause "Restart"). Capturing any
## sooner asked the browser for a pointer lock, which it grants asynchronously,
## so it landed after the next card had set the cursor visible: the button sat
## under a locked cursor that could not click it.
##
## The tree check is the half that matters for a reload. The button that ends
## the tutorial (or Restart) is handled at the start of a frame: it closes its
## screen, which queues this, and reloads. The old scene leaves the tree at
## once but is only freed at the end of the frame, so this Player was still
## alive when process_frame fired a moment later - with every screen closed
## and the new scene's card not built yet, nothing said no.
func _request_capture() -> void:
	if not is_inside_tree():
		return
	if not get_tree().process_frame.is_connected(_capture_mouse):
		get_tree().process_frame.connect(_capture_mouse, CONNECT_ONE_SHOT)


func _capture_mouse() -> void:
	if not is_inside_tree() or is_frozen or Events.is_ui_blocking():
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# =============================================================================
# Input
# =============================================================================
func _input(event: InputEvent) -> void:
	# Mouse recapture shield: in the browser, clicking back into the canvas
	# after the pointer was released must re-lock without also firing an
	# interaction. Swallow that first click.
	if is_frozen or Events.is_ui_blocking():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			_capture_mouse()
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if is_frozen:
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_turn_view(-event.relative.x * mouse_sensitivity, -event.relative.y * mouse_sensitivity)

	if event.is_action_pressed(&"interact") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		interaction_ray.activate(global_position)

	# Putting a tool down is always allowed - a trainee who picked up the
	# wrong thing should not have to walk it back to a bench to swap.
	if event.is_action_pressed(&"drop") and not hand_slot.is_empty():
		hand_slot.release()
		get_viewport().set_input_as_handled()


# =============================================================================
# Look
# =============================================================================
## Arrow-key look. Held state, so it is polled per frame rather than driven
## from events - _process and not _physics_process, so the turn rate does not
## quantise to the physics tick.
func _process(delta: float) -> void:
	if is_frozen or Events.is_ui_blocking():
		return

	var look := Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down")
	if look == Vector2.ZERO:
		return

	var step := key_look_speed * delta
	_turn_view(-look.x * step, -look.y * step)


## Single place where yaw and pitch are applied. Yaw lives on the head so the
## body does not roll; pitch lives on the camera and is clamped at the poles.
func _turn_view(yaw_delta: float, pitch_delta: float) -> void:
	head.rotate_y(yaw_delta)
	camera.rotate_x(pitch_delta)
	camera.rotation.x = clampf(camera.rotation.x, deg_to_rad(-90), deg_to_rad(90))


# =============================================================================
# Movement
# =============================================================================
func _physics_process(delta: float) -> void:
	if is_frozen:
		velocity = Vector3.ZERO
		return

	if not is_on_floor():
		velocity.y -= gravity * delta

	var speed := walk_speed
	var target_head_y := head_height_normal
	var target_col_height := _default_capsule_height

	if is_kneeling:
		speed = 0.0
		target_head_y = head_height_kneel
		target_col_height = _default_capsule_height * 0.5
	elif Input.is_action_pressed(&"crouch"):
		speed = crouch_speed
		target_head_y = head_height_crouch
		target_col_height = _default_capsule_height * 0.6
	elif Input.is_action_pressed(&"sprint"):
		speed = sprint_speed

	# Standing up under something solid used to drive the capsule straight
	# through it: the shape grew regardless, the physics engine resolved the
	# overlap by shoving the body sideways into the geometry, and the trainee
	# was stuck against the bench with no way out. Now the capsule only grows
	# into space it actually has. Nothing blocks crouching, and nothing stops
	# them walking out from under the overhang and standing up there.
	#
	# It surfaced the moment `crouch` became the CPR stand-up key: the trainee
	# now presses it constantly, and often right beside the cabinet.
	if collision_shape.shape is CapsuleShape3D:
		var current_height: float = collision_shape.shape.height
		if target_col_height > current_height + 0.001 and not _has_headroom(target_col_height):
			target_col_height = current_height
			target_head_y = head.position.y

	var lerp_weight := 10.0 * delta
	head.position.y = lerpf(head.position.y, target_head_y, lerp_weight)
	if collision_shape.shape is CapsuleShape3D:
		var next_height: float = lerpf(collision_shape.shape.height, target_col_height, lerp_weight)
		# Only write when it actually moves. Rewriting a collision shape every
		# frame re-registers it with the physics server for nothing, and does it
		# while the body may be touching something.
		if not is_equal_approx(next_height, collision_shape.shape.height):
			collision_shape.shape.height = next_height
			collision_shape.position.y = next_height * 0.5

	var input_dir := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_backward")
	var direction := (head.global_basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	if direction != Vector3.ZERO and speed > 0.0:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, walk_speed)
		velocity.z = move_toward(velocity.z, 0.0, walk_speed)

	move_and_slide()


## Is there room to grow the capsule to `height` from where the body is now?
##
## Tested against the same collision_mask the body moves with, excluding itself,
## so it agrees exactly with what move_and_slide() would hit.
func _has_headroom(height: float) -> bool:
	if _headroom_shape == null:
		return true
	_headroom_shape.height = height

	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _headroom_shape
	params.transform = Transform3D(Basis.IDENTITY, global_position + Vector3.UP * (height * 0.5))
	params.collision_mask = collision_mask
	params.exclude = [get_rid()]
	params.margin = 0.01
	return get_world_3d().direct_space_state.intersect_shape(params, 1).is_empty()


# =============================================================================
# Scripted sequences
# =============================================================================
## Turn the view to face a world point, overriding mouse look for the
## duration. Yaw lives on the head and pitch on the camera, so they are
## tweened separately rather than via look_at, which would roll the body.
##
## Awaitable. Freezing is the caller's job: this only moves the view, so a
## sequence can turn the head and swing a tool in the same frozen window.
func look_toward(point: Vector3, duration: float = 0.35) -> void:
	var from := camera.global_position
	var offset := point - from
	if offset.length_squared() < 0.0001:
		return

	# atan2 of the world offset gives the yaw the head needs *in world space*.
	# -Z is forward, hence the negated X.
	var target_yaw := atan2(-offset.x, -offset.z)
	var flat := Vector2(offset.x, offset.z).length()
	var target_pitch := clampf(atan2(offset.y, flat), deg_to_rad(-90), deg_to_rad(90))

	# `head.rotation.y` is local to the Player body, and the body is not
	# spawned facing -Z: main.tscn stands it at roughly -87 degrees so it
	# looks across the room at the panel. Comparing a world yaw against a
	# local one therefore threw the view a near-quarter-turn off the casualty
	# every time the hook swing started. Measure the error in world space and
	# apply it as a local delta, which is correct whatever the body's yaw is.
	# Take the short way round rather than unwinding a full turn.
	var world_yaw := head.global_basis.get_euler().y
	var yaw := head.rotation.y + angle_difference(world_yaw, target_yaw)

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(head, "rotation:y", yaw, duration)
	tween.parallel().tween_property(camera, "rotation:x", target_pitch, duration)
	await tween.finished


## Hand the camera to a scripted rig (the CPR sequence). Returns the
## player camera so the caller can restore it.
func release_camera() -> Camera3D:
	self.is_frozen = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	return camera


func reclaim_camera() -> void:
	camera.make_current()
	self.is_frozen = false
	is_kneeling = false
	if not Events.is_ui_blocking():
		_capture_mouse()
