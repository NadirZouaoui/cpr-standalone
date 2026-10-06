extends Node

## Station H · Shock — CPR_CONTRACT.md §4.3 point 4.
##
## Everything here is gated to state 6 (SHOCK); every entry point checks
## `_active` (and, for the interact itself, `_armed`) before doing anything.
## Sequence, per CPR_AGENTS.md's Agent H brief:
##
##   1. On entering SHOCK, bind "AED Defibrilator CPR" by name — it is
##      already visible with its authored material from AED_DEPLOY — and
##      register a GhostTarget-shaped adapter with CprInteractBridge, but
##      hold it disabled. The trainee cannot shock yet.
##   2. Standing up emits `Events.stand_clear_confirmed` — the panel's
##      "STAND CLEAR" beat hangs off it — but it no longer gates the button.
##      A real AED has no such interlock: clearing the casualty is the
##      rescuer's job, and the button being unpressable until they stood up
##      taught that by making it impossible to get wrong. It is now armed by
##      the charge tone alone, and pressing it while still down at the
##      casualty is a fatal violation (see _on_activate).
##   3. From arming onward, a pulsing `material_overlay` (never
##      `material_override` — the AED keeps its authored material) marks the
##      AED as interactable, built from CprGhost's material factory.
##   4. On interact, disarm immediately (no double-fire), emit
##      `Events.aed_shock_delivered`, and trigger the `Shock` blend shape via
##      `CasualtyCpr.trigger_shock_static()` — casualty_cpr.gd is Agent C's
##      file and is only ever called into here, never edited.
##   5. Leaving state 6 (however that happens) clears the overlay and
##      unregisters, so a re-entry via debug_jump_to_state rebinds cleanly.
##
## Read CPR_CONTRACT.md §4.0 and cpr_interact_bridge.gd before touching this
## file — every clickable thing in the CPR phase goes through that bridge,
## never Godot's own Area3D picking.
##
## Reaches the running CprCameraRig via CprStation.get_current().camera_rig
## rather than a node reference wired in from outside, following the
## project's static-accessor convention (CprStation._current,
## CasualtyCpr._active). That connection is made once in _ready() and simply
## ignored for every move_finished that lands outside SHOCK — see
## _on_camera_move_finished.
##
## OWNED BY AGENT H · SHOCK — see CPR_CONTRACT.md section 7. Run after
## Agent G (cpr_interact_bridge.gd must already exist).

const AED_DEPLOYED_NODE_NAME := "AED Defibrilator CPR"  # exact, per CPR_CONTRACT.md §3

## The unit will not let the trainee shock before it has finished charging —
## the same interlock a real AED has, and the fix for the cue ordering going
## wrong once the recorded lines landed. Stand-clear (the camera landing, or
## the trainee standing up) no longer arms the button by itself: it emits
## `stand_clear_confirmed` exactly as before, and the button goes live when
## AedVoice reports its `charging` line done.
const VOICE_CHARGE_LINE := &"charging"
## Belt and braces: audio must never be able to stall the exercise. If the
## charge line has not reported in by now — no AedVoice in the tree, a missing
## asset, a queue wedged behind something unforeseen — arm anyway. Comfortably
## longer than the analyse/advise/charge run (~7.4 s of recordings plus gaps).
const VOICE_WAIT_TIMEOUT_S := 12.0

## Delivering a shock into a casualty someone is still touching is one of the
## few errors in this whole procedure that kills the rescuer rather than the
## patient, which is what the fail screen is for. Same category as reaching in
## to a live casualty (casualty.gd), and the wording is the line that was
## sitting unreachable in Casualty.deliver_shock() until now.
const CONTACT_FATAL_TEXT := \
	"The shock was delivered while a rescuer was still in contact with the casualty."

const PULSE_PERIOD_S := 0.9
const PULSE_ALPHA_MIN := 0.18
const PULSE_ALPHA_MAX := 0.55
## Reuses CprGhost's "drop" color family (the AED_DEPLOY ghost's own green) so
## the armed AED reads as part of the same visual language, not a new signal.
## The phase's one highlight colour — see cpr_ghost.gd, where the CPR palette
## was consolidated onto Tokens.ATTENTION. This was left on the old green.
const PULSE_COLOR := CprGhost.COLOR_IDLE

## Adapter shaped like GhostTarget (mesh / set_hovered / activate) but not one
## itself: the AED mesh is real, already-placed geometry with its authored
## material — not a ghost that starts hidden — same reasoning as
## aed_station.gd's `_CabinetTarget`. Delegates back to the owning node so the
## SHOCK-state gating lives in one place.
class _ShockTarget:
	extends RefCounted

	var mesh: MeshInstance3D
	## Hover tooltip, read duck-typed by CprInteractBridge — same property name
	## GhostTarget and aed_station.gd's cabinet adapter use.
	var prompt: String = ""
	var _owner: Node

	func _init(target_mesh: MeshInstance3D, owner: Node) -> void:
		mesh = target_mesh
		_owner = owner

	func set_hovered(_is_hovered: bool) -> void:
		pass  # The arm/pulse is the only hover-style feedback this needs.

	func activate() -> void:
		if is_instance_valid(_owner):
			_owner._on_activate()


var _mesh: MeshInstance3D = null
var _target: _ShockTarget = null
var _camera_rig: CprCameraRig = null

var _active: bool = false   # true for the whole time state == CprStation.STATE_SHOCK
var _armed: bool = false    # true once stand-clear has fired; gates activate()

## Stand-clear has happened; the button is waiting only on the charge tone.
var _stand_clear_done: bool = false
var _voice: AedVoice = null
var _voice_timeout: Timer = null

var _pulse_material: StandardMaterial3D = null
var _pulse_running: bool = false
var _pulse_t: float = 0.0


func _ready() -> void:
	Events.cpr_state_changed.connect(_on_cpr_state_changed)
	call_deferred("_bind_camera_rig")


func _bind_camera_rig() -> void:
	var station := CprStation.get_current()
	if station == null or station.camera_rig == null:
		push_error("ShockButton: no CprStation/CprCameraRig found; stand-clear will never fire.")
		return
	_camera_rig = station.camera_rig
	_camera_rig.move_finished.connect(_on_camera_move_finished)

	# Same deferred pass, same station: the voice node is built alongside the
	# camera rig in CprStation._build().
	_voice = station.aed_voice
	if _voice != null:
		_voice.line_finished.connect(_on_voice_line_finished)


func _process(delta: float) -> void:
	if not _pulse_running or _pulse_material == null:
		return
	_pulse_t += delta
	var phase := (sin(_pulse_t * TAU / PULSE_PERIOD_S) + 1.0) * 0.5
	_pulse_material.albedo_color.a = lerpf(PULSE_ALPHA_MIN, PULSE_ALPHA_MAX, phase)


# --- state -------------------------------------------------------------------

func _on_cpr_state_changed(_from: int, to: int) -> void:
	if to == CprStation.STATE_SHOCK:
		_enter_shock_state()
	elif _active:
		_leave_shock_state()


func _enter_shock_state() -> void:
	_active = true
	_armed = false
	_stand_clear_done = false
	# The charge wait starts here rather than on the stand-clear: the unit
	# charges whether or not anybody has stepped back, and so does the button.
	_start_voice_timeout()
	_try_go_live()
	call_deferred("_bind_mesh")


func _start_voice_timeout() -> void:
	if _voice_timeout == null:
		_voice_timeout = Timer.new()
		_voice_timeout.name = "ShockVoiceTimeout"
		_voice_timeout.one_shot = true
		_voice_timeout.timeout.connect(_on_voice_timeout)
		add_child(_voice_timeout)
	_voice_timeout.start(VOICE_WAIT_TIMEOUT_S)


func _bind_mesh() -> void:
	if not _active:
		return
	var root: Node = get_tree().current_scene
	if root == null:
		root = get_tree().root

	_mesh = CprGhost.find_node(root, AED_DEPLOYED_NODE_NAME) as MeshInstance3D
	if _mesh == null:
		push_error("ShockButton: no MeshInstance3D named '%s' found." % AED_DEPLOYED_NODE_NAME)
		_active = false
		return

	_target = _ShockTarget.new(_mesh, self)
	CprInteractBridge.register(_target)
	# Held inert until the charge tone arms it — see _go_live().
	# Guard against the (unlikely) case move_finished already landed before
	# this deferred bind ran: honour whatever _armed already is instead of
	# clobbering it back to disabled.
	CprInteractBridge.set_enabled(_target, _armed)
	if _armed:
		_start_pulse()


func _leave_shock_state() -> void:
	_active = false
	_armed = false
	_stand_clear_done = false
	if _voice_timeout != null:
		_voice_timeout.stop()
	_stop_pulse()
	if _target != null:
		CprInteractBridge.unregister(_target)
		_target = null
	_mesh = null


# --- stand-clear / arm --------------------------------------------------------

## Fires for every anchored-state camera landing across the whole CPR phase
## (CprCameraRig is shared) — `_active` filters that down to only the SHOCK
## transition, and `_armed` makes this a one-shot per SHOCK entry.
func _on_camera_move_finished(_anchor: Marker3D) -> void:
	arm()


## Records the stand-clear and reports it. Kept public and kept the name
## because cpr_station.gd calls it when the trainee stands (there is no camera
## landing to hang it on — standing hands the camera back to the player), and
## CPR_CONTRACT.md §4.3 still has `stand_clear_confirmed` firing at this
## moment, with the floating panel's "STAND CLEAR" beat reading it.
##
## What it no longer does is arm the button. See _on_activate.
func arm() -> void:
	if not _active or _stand_clear_done:
		return
	_stand_clear_done = true
	Events.stand_clear_confirmed.emit()


func _on_voice_line_finished(id: StringName) -> void:
	if id != VOICE_CHARGE_LINE:
		return
	_try_go_live()


func _on_voice_timeout() -> void:
	if _active and not _armed:
		push_warning("ShockButton: charge cue never reported after %.0f s; arming anyway." % VOICE_WAIT_TIMEOUT_S)
		_go_live()


## Both halves in, or no voice to wait for at all.
func _try_go_live() -> void:
	if _voice == null or _voice.has_finished(VOICE_CHARGE_LINE):
		_go_live()


func _go_live() -> void:
	if not _active or _armed:
		return
	_armed = true
	if _voice_timeout != null:
		_voice_timeout.stop()
	if _target != null:
		_target.prompt = "Deliver the shock"
		CprInteractBridge.set_enabled(_target, true)
	_start_pulse()


# --- interact ------------------------------------------------------------------

## Nothing here checks whether the trainee stood up before letting them press
## the button — that is the point. What it does check is where they were when
## they pressed it.
##
## `trainee_at_anchor()` is the shared "is the trainee down at the casualty"
## predicate the panel, the hands and the body pointers all read. Down at an
## anchor means hands on the patient; standing means clear. The unit has
## already said "stand clear" by this point, so this is an ignored instruction,
## not a trap.
func _on_activate() -> void:
	if not _active or not _armed:
		return
	_armed = false
	_stop_pulse()
	if _target != null:
		_target.prompt = ""
		CprInteractBridge.set_enabled(_target, false)

	var station := CprStation.get_current()
	if station != null and station.trainee_at_anchor():
		Events.fatal_violation.emit(CONTACT_FATAL_TEXT)
		return

	Events.aed_shock_delivered.emit()
	CasualtyCpr.trigger_shock_static()


# --- pulse ---------------------------------------------------------------------

func _start_pulse() -> void:
	if _mesh == null:
		return
	# Duplicate rather than mutate the cached material CprGhost.material()
	# returns — CprGhost's own contract: "do not mutate a returned material,
	# swap to a different one instead." This is our own instance to animate.
	_pulse_material = CprGhost.material(PULSE_COLOR, PULSE_ALPHA_MIN).duplicate()
	_mesh.material_overlay = _pulse_material
	_pulse_t = 0.0
	_pulse_running = true


func _stop_pulse() -> void:
	_pulse_running = false
	_pulse_material = null
	if _mesh != null:
		_mesh.material_overlay = null


func _exit_tree() -> void:
	if _target != null:
		CprInteractBridge.unregister(_target)
