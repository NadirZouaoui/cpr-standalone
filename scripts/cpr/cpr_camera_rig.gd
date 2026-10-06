class_name CprCameraRig
extends Node

## Scripted camera controller for the CPR phase state anchors.
##
## OWNERSHIP: Agent A · Camera. See CPR_CONTRACT.md section 7.
##
## Anchors come from `CprRig.anchor_for_state()` (shared/frozen) — this file never
## authors positions itself. A station (e.g. Agent E's cpr_station.gd, not owned here)
## drives state transitions and calls `move_to(anchor)` / `release()` on those
## transitions, per the per-state table in CPR_CONTRACT.md section 1:
##   - anchored states (BREATHING_CHECK, COMPRESSIONS_1, PAD_PLACEMENT, SHOCK,
##     COMPRESSIONS_2) call move_to(CprRig.anchor_for_state(state))
##   - free states (EXPOSE_CHEST, AED_FETCH, AED_DEPLOY, COMPLETE) call release()
##     (or never move_to in the first place)
##
## OWNS THE PLAYER HANDOFF: `move_to()` takes the camera from `Player` via
## `release_camera()` the first time it is called (this also freezes player movement —
## see Player.is_frozen, which exists specifically for "a scripted camera sequence
## (CPR) has taken over"). `release()` hands the camera and movement back via
## `reclaim_camera()`. Callers do not need to touch Player themselves.
##
## USAGE: instantiate once and add to the tree (needs _process/_unhandled_input),
## e.g. `var rig := CprCameraRig.new(player); add_child(rig)`. Then per state:
##   rig.move_to(cpr_rig.anchor_for_state(new_state))
##   ...
##   rig.release()
##
## LOOK MODEL: while a move_to() tween is in flight, look input is gated (locked) so
## the trainee cannot fight the transition. Once landed, mouse-look is re-enabled but
## clamped relative to the anchor's own orientation — see the @export limits below —
## never full free-look. The rig re-reads the anchor's live global_transform every frame
## (CprRig re-poses its anchors continuously off the casualty's skeleton), so the
## camera keeps tracking the body without re-triggering a tween.
##
## Sign conventions for mouse input mirror Player._turn_view() exactly (same
## -relative.x / -relative.y negation, same MOUSE_MODE_CAPTURED gate) so look feel is
## consistent between free-roam and anchored CPR states.

signal move_started(anchor: Marker3D)
signal move_finished(anchor: Marker3D)
## Fires once the camera is fully back with the player, by either release path.
signal released()

## Playtest fix (CPR_AGENTS.md, Agent L brief, task 3): the old hard-coded
## ±30°/-45°/+15° clamp was too tight in play. Exported so the human can tune
## these in the inspector without another agent round-trip.
## Playtest fix: 60/-70/+35 still was not enough to look at the deployed AED
## from Anchor_Shock, which left SHOCK unreachable. Widened rather than removed
## — the clamp is what keeps the anchored states framed on the casualty.
##
## These are @export for tuning, but this rig is instanced in code by
## CprStation._build() rather than authored in a scene, so the inspector never
## sees it: change the defaults here, not in the editor.
## The widest any anchored state needs, and the value every state gets unless
## its caller narrows it. CprStation._yaw_limit_for() is the one that does, and
## its docstring says why 110 is a SHOCK-shaped number rather than a good
## general one.
const DEFAULT_LOOK_YAW_LIMIT := 110.0

@export var look_yaw_limit_deg: float = DEFAULT_LOOK_YAW_LIMIT  # degrees, either side of the anchor's own forward
@export var look_pitch_min_deg: float = -80.0   # degrees, looking down
@export var look_pitch_max_deg: float = 55.0    # degrees, looking up

@export var mouse_sensitivity: float = 0.003
@export var default_duration: float = 0.6

var player: Player = null
var camera: Camera3D = null
var current_anchor: Marker3D = null
## True once this rig holds the player's camera (from move_to() until release()).
var active: bool = false

var _yaw_offset: float = 0.0    # radians
var _pitch_offset: float = 0.0  # radians
## True while a move_to() tween is in flight, or before the first move_to(). Blocks
## look input and the per-frame anchor-follow update.
var _locked: bool = true
var _tween: Tween = null
## The camera's local transform relative to Player/Head at the moment this rig
## took it. This rig drives `camera.global_transform` directly every frame, which
## clobbers that local transform: after release() the camera would keep whatever
## local offset and basis the last anchor happened to imply. Since the camera is
## a child of Head, and Player._turn_view() yaws Head and pitches the camera on
## top of that local basis, the symptom is a first-person view sitting at the
## anchor's height (low, kneeling by the casualty) that rolls/tilts on mouse-look
## instead of panning. Captured on take, restored on release.
var _camera_rest_xform: Transform3D = Transform3D.IDENTITY


func _init(p: Player = null) -> void:
	player = p


func _unhandled_input(event: InputEvent) -> void:
	if not active or _locked:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_apply_look(-event.relative.x * mouse_sensitivity, -event.relative.y * mouse_sensitivity)


func _process(_delta: float) -> void:
	if not active or _locked or camera == null or current_anchor == null:
		return
	if not is_instance_valid(current_anchor):
		return
	camera.global_transform = _looked_transform(current_anchor.global_transform)


## Take the camera from the player if this rig doesn't hold it yet, then tween it onto
## `anchor`. Movement and look stay locked for the duration of the tween; look unlocks
## (clamped, relative to the anchor) once it lands. Safe to call again mid-tween — the
## in-flight tween is killed and a new one starts from the camera's current pose.
func move_to(anchor: Marker3D, duration: float = -1.0) -> void:
	if anchor == null:
		push_error("CprCameraRig.move_to: null anchor")
		return
	if not is_instance_valid(anchor):
		push_error("CprCameraRig.move_to: freed anchor")
		return
	if duration < 0.0:
		duration = default_duration

	if not active:
		_take_camera()
	if camera == null:
		return  # _take_camera already reported the failure

	# Item 1 fix (CPR_AGENTS.md, Agent I brief): Player.release_camera() drops
	# Input.mouse_mode to MOUSE_MODE_VISIBLE, which starves this rig's own
	# _unhandled_input gate (`Input.mouse_mode == MOUSE_MODE_CAPTURED`) and
	# kills clamped mouse-look in every anchored CPR state. Every CPR
	# interaction goes through the crosshair + interact action regardless
	# (CPR_CONTRACT.md §4.0), so a visible cursor buys nothing and costs the
	# look — keep the mouse captured for as long as this rig holds the
	# camera, re-asserting it on every move_to() in case something else (a
	# UI open/close cycle) changed it mid-phase. Skipped while a blocking UI
	# is up — that UI needs the cursor more than the CPR camera does.
	if not Events.is_ui_blocking():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	_locked = true
	_yaw_offset = 0.0
	_pitch_offset = 0.0
	move_started.emit(anchor)

	if _tween != null and _tween.is_valid():
		_tween.kill()

	var from_xform := camera.global_transform
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_method(
		func(t: float): _apply_tween_step(t, from_xform, anchor),
		0.0, 1.0, duration
	)
	_tween.finished.connect(_on_move_finished.bind(anchor), CONNECT_ONE_SHOT)


## Hand the camera and movement back to the player. Call on entering a free-movement
## state (AED_FETCH, AED_DEPLOY, COMPLETE) or on leaving the CPR phase. No-op if this
## rig doesn't currently hold the camera.
func release() -> void:
	if not active:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	current_anchor = null
	_locked = true
	# Restore the camera to the pose Player expects before handing it back —
	# see _camera_rest_xform. Without this the player is left low to the ground
	# and mouse-look tilts instead of panning.
	if camera != null and is_instance_valid(camera):
		camera.transform = _camera_rest_xform
	active = false
	camera = null
	if player != null:
		player.reclaim_camera()
	released.emit()


## Hands the camera back the way move_to() takes it — tweened, not cut.
##
## release() teleports, which is right when the phase ends but wrong when the
## trainee stands up mid-phase: the view snapped from kneeling to standing in
## one frame and read as a scene change rather than as getting to your feet.
##
## Tweens to exactly the pose release() would have set — the player's head
## transform composed with the camera's own rest offset — so the handback at
## the end is a no-op and nothing jumps.
func release_smooth(duration: float = -1.0) -> void:
	if not active:
		return
	if player == null or camera == null or player.head == null:
		release()
		return
	if duration < 0.0:
		duration = default_duration

	_locked = true          # no look input while the camera is on rails
	current_anchor = null   # stop tracking the anchor mid-handback
	if _tween != null and _tween.is_valid():
		_tween.kill()

	var from_xform := camera.global_transform
	var to_xform := player.head.global_transform * _camera_rest_xform
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_method(
		func(t: float): _apply_handback_step(t, from_xform, to_xform),
		0.0, 1.0, duration
	)
	_tween.finished.connect(release, CONNECT_ONE_SHOT)


func _apply_handback_step(t: float, from_xform: Transform3D, to_xform: Transform3D) -> void:
	if camera == null or not is_instance_valid(camera):
		return
	camera.global_transform = from_xform.interpolate_with(to_xform, t)


func is_locked() -> bool:
	return _locked


func _take_camera() -> void:
	if player == null:
		push_error("CprCameraRig: no Player assigned, cannot take the camera")
		return
	# Playtest fix (CPR_AGENTS.md, Agent K brief, task 2): release_camera()
	# freezes the player, which sets InteractionRay.active = false. If the ray
	# is hovering something at that instant, the ray that would clear the
	# highlight is now off, so it never clears. Clear the hover here, through
	# the interactor's own clear path, before the freeze takes effect.
	if player.interaction_ray != null:
		player.interaction_ray.clear()
	camera = player.release_camera()
	if camera != null:
		_camera_rest_xform = camera.transform
	active = true


func _on_move_finished(anchor: Marker3D) -> void:
	if not is_instance_valid(anchor):
		return
	current_anchor = anchor
	_locked = false
	move_finished.emit(anchor)


func _apply_tween_step(t: float, from_xform: Transform3D, anchor: Marker3D) -> void:
	if camera == null or not is_instance_valid(anchor):
		return
	camera.global_transform = from_xform.interpolate_with(anchor.global_transform, t)


func _apply_look(yaw_delta: float, pitch_delta: float) -> void:
	_yaw_offset = clampf(_yaw_offset + yaw_delta, deg_to_rad(-look_yaw_limit_deg), deg_to_rad(look_yaw_limit_deg))
	_pitch_offset = clampf(_pitch_offset + pitch_delta, deg_to_rad(look_pitch_min_deg), deg_to_rad(look_pitch_max_deg))


## Anchor's own basis, yawed and pitched by the clamped offsets — both rotations
## applied in world space around the anchor's own (already-rotated) axes, so the
## result is independent of Godot's local/global rotate_* multiply order.
func _looked_transform(anchor_xform: Transform3D) -> Transform3D:
	var oriented_basis := anchor_xform.basis
	oriented_basis = oriented_basis.rotated(Vector3.UP, _yaw_offset)
	oriented_basis = oriented_basis.rotated(oriented_basis.x.normalized(), _pitch_offset)
	return Transform3D(oriented_basis, anchor_xform.origin)
