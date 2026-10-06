extends Node
## Detached fly-through camera for inspecting the scene from anywhere.
##
## Toggled from the [F10] dev menu. Added because the chest artefact could not
## be judged from the places the game lets you stand: the CPR anchors frame the
## casualty from fixed positions, free-roam keeps the eye at 1.7 m, and neither
## lets you put your nose on the chest or look at it from underneath. Whether
## something is a shading problem, an overlapping surface or a texture reads
## very differently once you can orbit it.
##
## Owns nothing the exercise depends on. It borrows the viewport's current
## camera, remembers it, and hands it straight back on toggle-off — including
## when CprCameraRig is the thing holding it, which is why the previous camera
## is stored rather than assuming Player's.
##
## The player is frozen while this is up, so the body does not walk off under
## the exercise's own input and no interaction fires from the crosshair.
##
## Debug builds only, spawned by main.gd next to PauseMenu, DevMenu and
## MeshProbe.

const MOVE_SPEED := 2.0
const SPRINT_MULTIPLIER := 4.0
const SLOW_MULTIPLIER := 0.2
const MOUSE_SENSITIVITY := 0.003
const PITCH_LIMIT_DEG := 89.0
## Mouse wheel trims the speed so close-up inspection does not overshoot.
const SPEED_STEP := 1.25
const SPEED_MIN := 0.1
const SPEED_MAX := 40.0

var active: bool = false

var _camera: Camera3D = null
var _previous_camera: Camera3D = null
var _player: Player = null
var _speed: float = MOVE_SPEED
var _yaw: float = 0.0
var _pitch: float = 0.0


func _ready() -> void:
	if not OS.is_debug_build():
		set_process(false)
		set_process_unhandled_input(false)
		return
	set_process(false)


func is_active() -> bool:
	return active


func toggle() -> void:
	if active:
		disable()
	else:
		enable()


func enable() -> void:
	if active:
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	_previous_camera = viewport.get_camera_3d()
	if _previous_camera == null:
		push_warning("FreeCamera: no current Camera3D to start from.")
		return

	_camera = Camera3D.new()
	_camera.name = "FreeCameraView"
	# Parented to the scene root, not to whatever held the camera before — a
	# CPR anchor re-poses its camera every frame and would drag this with it.
	get_tree().current_scene.add_child(_camera)
	_camera.owner = null
	_camera.global_transform = _previous_camera.global_transform
	_camera.fov = _previous_camera.fov

	# Start facing exactly where the old camera looked, then drive yaw/pitch
	# as separate scalars so the view can never accumulate roll.
	var basis := _previous_camera.global_transform.basis
	var forward := -basis.z
	_yaw = atan2(-forward.x, -forward.z)
	_pitch = asin(clampf(forward.y, -1.0, 1.0))

	_camera.make_current()
	active = true
	_speed = MOVE_SPEED

	_player = get_tree().get_first_node_in_group(&"player") as Player
	if _player != null:
		_player.is_frozen = true

	set_process(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Events.center_message_requested.emit(
		"Free camera ON — WASD, Space/Ctrl, Shift fast, Alt slow, wheel speed. F10 to exit.",
		Tokens.WARNING, 4.0
	)


func disable() -> void:
	if not active:
		return
	active = false
	set_process(false)

	if _camera != null and is_instance_valid(_camera):
		_camera.queue_free()
	_camera = null

	# Hand the view back to whoever had it. CprCameraRig re-asserts its own
	# camera every frame while anchored, so this only has to matter for the
	# free-roam case — but restoring explicitly keeps both paths correct.
	if _previous_camera != null and is_instance_valid(_previous_camera):
		_previous_camera.make_current()
	_previous_camera = null

	if _player != null and is_instance_valid(_player):
		_player.is_frozen = Events.is_ui_blocking()
	_player = null

	if not Events.is_ui_blocking():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Events.center_message_requested.emit("Free camera OFF", Tokens.WARNING, 1.5)


func _unhandled_input(event: InputEvent) -> void:
	if not active or _camera == null:
		return
	if Events.is_ui_blocking():
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * MOUSE_SENSITIVITY
		_pitch = clampf(
			_pitch - motion.relative.y * MOUSE_SENSITIVITY,
			deg_to_rad(-PITCH_LIMIT_DEG), deg_to_rad(PITCH_LIMIT_DEG)
		)
		_apply_rotation()
		get_viewport().set_input_as_handled()
		return

	var button := event as InputEventMouseButton
	if button != null and button.pressed:
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_speed = clampf(_speed * SPEED_STEP, SPEED_MIN, SPEED_MAX)
			get_viewport().set_input_as_handled()
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_speed = clampf(_speed / SPEED_STEP, SPEED_MIN, SPEED_MAX)
			get_viewport().set_input_as_handled()


func _apply_rotation() -> void:
	var basis := Basis.IDENTITY
	basis = basis.rotated(Vector3.UP, _yaw)
	basis = basis.rotated(basis.x.normalized(), _pitch)
	_camera.global_transform = Transform3D(basis, _camera.global_position)


## Polled rather than event-driven — these are held keys. Read straight off
## Input rather than through the project's actions so the fly cam keeps working
## regardless of what the exercise has bound or consumed.
func _process(delta: float) -> void:
	if _camera == null or Events.is_ui_blocking():
		return

	var move := Vector3.ZERO
	var basis := _camera.global_transform.basis
	if Input.is_key_pressed(KEY_W):
		move -= basis.z
	if Input.is_key_pressed(KEY_S):
		move += basis.z
	if Input.is_key_pressed(KEY_A):
		move -= basis.x
	if Input.is_key_pressed(KEY_D):
		move += basis.x
	if Input.is_key_pressed(KEY_SPACE):
		move += Vector3.UP
	if Input.is_key_pressed(KEY_CTRL):
		move -= Vector3.UP
	if move == Vector3.ZERO:
		return

	var speed := _speed
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= SPRINT_MULTIPLIER
	if Input.is_key_pressed(KEY_ALT):
		speed *= SLOW_MULTIPLIER

	_camera.global_position += move.normalized() * speed * delta
