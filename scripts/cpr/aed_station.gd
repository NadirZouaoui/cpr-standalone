extends Node

## Station D · AED — CPR_CONTRACT.md §4 "AED handling"
##
## Two objects, resolved by name at runtime (CPR_CONTRACT.md §3, runtime
## binder doctrine — never editor NodePaths):
##
##   AED_CABINET  — the AED unit sitting on the cabinet. It is ordinary room
##                  dressing: visible and solid from the start, not a ghost.
##                  It is deliberately NOT wrapped in GhostTarget, because
##                  GhostTarget.hide_ghost()s its mesh unconditionally inside
##                  _init() — correct for a hidden ghost, wrong for a prop
##                  that must stay visible (and part of the room) until the
##                  trainee picks it up. `_CabinetTarget` below is a small
##                  adapter shaped like GhostTarget (mesh / set_hovered /
##                  activate) that registers with CprInteractBridge the same
##                  way, reusing CprGhost's material factory for the hover
##                  highlight.
##   AED_DEPLOYED — "AED Defibrilator CPR", hidden at start. Revealed as a
##                  real ghost via GhostTarget when AED_DEPLOY begins;
##                  clicking it places it. Full GhostTarget/CprGhost pattern,
##                  same as the pad sites in pad_station.gd.
##
## AED_CABINET_NODE_NAME is a best guess. CPR_CONTRACT.md §3 gives
## AED_DEPLOYED its exact node name ("AED Defibrilator CPR") but only
## describes AED_CABINET ("AED unit on the cabinet") — no literal name was
## specified. The guess here is the un-suffixed original of the deployed
## duplicate's name. If it does not resolve, push_error names the exact
## string that was tried; check the console and correct the constant to
## match the real node name in the .blend.
##
## INPUT: the cabinet's click handling goes through CprInteractBridge
## (Agent G · Input bridge — CPR_CONTRACT.md §4.0), not Godot's built-in
## Area3D camera picking, which does not work in this project (no visible
## cursor at a stable screen position). Only the input path changed here —
## the cabinet's visible-and-solid behaviour and its material_overlay hover
## highlight are exactly as they were.
##
## Never touches the CPR state machine — only reports via Events. Add this
## node anywhere in the tree (e.g. as a child the CPR station instances at
## runtime); it needs no scene-authored wiring.
##
## OWNED BY AGENT D · AED — see CPR_CONTRACT.md section 7. Its cabinet input
## path was patched by Agent G · Input bridge, per CPR_AGENTS.md.

# CPR state ids come from CprStation.STATE_* — never a local copy of the number.
# The spine was renumbered on 3 Sep 2026 (docs/OVERNIGHT_PLAN.md §2) and every
# duplicated integer here was a silent breakage waiting to happen.

# --- node names (CPR_CONTRACT.md section 3) ------------------------------------
const AED_CABINET_NODE_NAME := "AED Defibrilator Cabinet"        # best guess — see note above
const AED_DEPLOYED_NODE_NAME := "AED Defibrilator CPR"    # exact, per contract

## Playtest fix: the two electrode pads modelled sitting on the deployed AED
## ("AED Defibrilator Pad 1_OnAED", "AED Defibrilator Pad 2_OnAED") are plain
## room dressing with no script and nothing hiding them, so they lay on the
## floor from level load — visible long before the AED they belong to, and
## still there after the trainee had stuck both pads on the casualty.
##
## They now follow the AED through its whole life. On the cabinet the unit and
## its pads are a single mesh; on the floor they are three separate meshes, so
## showing only the body as the drop ghost previewed something that did not
## match what landed. All three are ghosted together for the AED_DEPLOY preview,
## all three go solid on `aed_placed`, and then one pad disappears per
## `aed_pad_placed` as it "moves" onto the chest.
##
## Resolved by prefix rather than by the two literal names so a third pad, or a
## rename of the _OnAED suffix, needs no code change.
const AED_ON_UNIT_PAD_PREFIX := "AED Defibrilator Pad "

## CprInteractBridge adapter for the cabinet — shaped like GhostTarget
## (mesh / set_hovered / activate) but not one itself, since the cabinet must
## stay visible and solid rather than starting hidden the way GhostTarget's
## _init() forces. Delegates back to AedStation's own gated hover/activate
## logic below, so the cabinet's rules (state, taken) live in one place.
class _CabinetTarget:
	extends RefCounted

	var mesh: MeshInstance3D
	## Hover tooltip, read duck-typed by CprInteractBridge — same property
	## name GhostTarget uses, so the bridge needs no special case here.
	var prompt: String = ""
	var _owner: Node

	func _init(target_mesh: MeshInstance3D, owner: Node) -> void:
		mesh = target_mesh
		_owner = owner

	func set_hovered(is_hovered: bool) -> void:
		if is_instance_valid(_owner):
			_owner._cabinet_set_hovered(is_hovered)

	func activate() -> void:
		if is_instance_valid(_owner):
			_owner._cabinet_activate()


var _cabinet_mesh: MeshInstance3D = null
var _cabinet_target: _CabinetTarget = null
var _cabinet_taken: bool = false
var _cabinet_hovered: bool = false

var _deployed_target: GhostTarget = null

## The _OnAED pad meshes, in stable name order — index 0 is removed first.
var _on_unit_pads: Array[MeshInstance3D] = []
## Which of the three looks the pads currently wear.
enum PadsLook { HIDDEN, GHOST, PLACED }
var _on_unit_pads_look: PadsLook = PadsLook.HIDDEN
var _on_unit_pads_taken: int = 0
## Mirrors the deployed ghost's hover so the pads brighten with it — the
## preview has to read as one object, which is the whole reason they are
## ghosted alongside it.
var _deployed_hovered: bool = false

## The spine's own idle, not a bare -1. It was the literal until the 3 Sep
## reorder gave the idle a name (CprStation.STATE_PRIMARY_SURVEY); a `var`
## initialiser resolves at instantiation, so unlike a `const` one it cannot trip
## the preload cycle breathing_check.gd::_config_for warns about.
var _state: int = CprStation.STATE_PRIMARY_SURVEY

## The cabinet used to wear a slow pulsing gold overlay for the whole of
## AED_FETCH — a grown shell that read as a ghost sitting on a solid prop.
## Removed: the unit is a real object in a labelled cabinet and the hover
## highlight already confirms it when the crosshair lands on it. Marking it as
## well told the trainee where to look in an exercise whose point is that they
## know where the AED is.


func _ready() -> void:
	Events.cpr_state_changed.connect(_on_cpr_state_changed)
	Events.cpr_phase_entered.connect(_on_cpr_phase_entered)
	Events.aed_placed.connect(_on_aed_placed_show_unit_pads)
	Events.aed_pad_placed.connect(_on_aed_pad_placed_take_unit_pad)
	# Scene population (ControlRoom's .blend instance, the casualty drag
	# target) may still be settling on the frame this node enters the tree —
	# same caution CprRig's own binder takes.
	call_deferred("_build")


# --- construction --------------------------------------------------------------

func _build() -> void:
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		scene_root = get_tree().root

	_cabinet_mesh = CprGhost.find_node(scene_root, AED_CABINET_NODE_NAME) as MeshInstance3D
	if _cabinet_mesh == null:
		push_error("AedStation: no node named '%s' found for AED_CABINET. Fix AED_CABINET_NODE_NAME in aed_station.gd to match the real .blend node name." % AED_CABINET_NODE_NAME)
	else:
		_cabinet_target = _CabinetTarget.new(_cabinet_mesh, self)
		_cabinet_target.prompt = "Take the AED"
		CprInteractBridge.register(_cabinet_target)
		# The bridge collider sits over the same mesh the kit check binds a
		# KitInspectItem to, and stays hot from scene load unless told
		# otherwise. Left on, it hijacks the bench: hovering the cabinet
		# during the kit check showed "Take the AED" instead of the toggle
		# prompt, and every hover-off cleared whatever overlay the kit check
		# had just painted. The state gate below owns the switch.
		CprInteractBridge.set_enabled(_cabinet_target, false)

	for n in CprGhost.find_nodes_with_prefix(scene_root, AED_ON_UNIT_PAD_PREFIX):
		var pad_mesh := n as MeshInstance3D
		if pad_mesh == null:
			continue
		_on_unit_pads.append(pad_mesh)
	if _on_unit_pads.is_empty():
		push_error("AedStation: no nodes found with prefix '%s' for the pads sitting on the AED." % AED_ON_UNIT_PAD_PREFIX)
	_apply_on_unit_pads()

	var deployed_mesh := CprGhost.find_node(scene_root, AED_DEPLOYED_NODE_NAME) as MeshInstance3D
	if deployed_mesh == null:
		push_error("AedStation: no node named '%s' found for AED_DEPLOYED." % AED_DEPLOYED_NODE_NAME)
		return

	_deployed_target = GhostTarget.new(
		deployed_mesh, CprGhost.drop_material(false), CprGhost.drop_material(true)
	)
	_deployed_target.prompt = "Place the AED here"
	_deployed_target.activated.connect(_on_deployed_activated)
	_deployed_target.hovered_changed.connect(_on_deployed_hovered_changed)


# --- cabinet: pickup -------------------------------------------------------------

## Called by `_CabinetTarget.set_hovered()` via CprInteractBridge. Clearing the
## highlight (`is_hovered == false`) only runs when this station actually has
## the overlay up - otherwise it would reach across phases and wipe whatever
## the kit check painted on the same mesh. Taking the highlight is gated to
## AED_FETCH and "not already taken", same as the old Area3D
## mouse_entered/mouse_exited pair.
func _cabinet_set_hovered(is_hovered: bool) -> void:
	if not is_hovered:
		if _cabinet_hovered:
			_cabinet_hovered = false
			_apply_cabinet_overlay()
		return
	if _state != CprStation.STATE_AED_FETCH or _cabinet_taken or _cabinet_mesh == null:
		return
	_cabinet_hovered = true
	_apply_cabinet_overlay()


## Single place deciding what sits on the cabinet's material_overlay: the solid
## hover highlight under the crosshair, nothing otherwise.
func _apply_cabinet_overlay() -> void:
	if _cabinet_mesh == null:
		return
	_cabinet_mesh.material_overlay = CprGhost.hover_material() if _cabinet_hovered else null


## Called by `_CabinetTarget.activate()` via CprInteractBridge, on the
## project's "interact" action — same gate the old Area3D input_event click
## handler used.
func _cabinet_activate() -> void:
	if _state != CprStation.STATE_AED_FETCH or _cabinet_taken:
		return
	_pick_up_cabinet()


func _pick_up_cabinet() -> void:
	_cabinet_taken = true
	if _cabinet_target != null:
		_cabinet_target.prompt = ""
	_cabinet_hovered = false
	if _cabinet_target != null:
		CprInteractBridge.set_enabled(_cabinet_target, false)
	if _cabinet_mesh != null:
		_cabinet_mesh.material_overlay = null
		_cabinet_mesh.visible = false
	Events.aed_picked_up.emit()


# --- deployed ghost: placement ---------------------------------------------------

func _on_deployed_activated(_target: GhostTarget) -> void:
	if _state != CprStation.STATE_AED_DEPLOY or _deployed_target == null:
		return
	_deployed_target.place()
	Events.aed_placed.emit()


# --- pads sitting on the deployed unit -------------------------------------------

## Ghosted with the drop preview, solid once the AED is down, and gone one at a
## time as each is stuck on the casualty.
func _apply_on_unit_pads() -> void:
	for i in _on_unit_pads.size():
		var pad_mesh := _on_unit_pads[i]
		if pad_mesh == null or not is_instance_valid(pad_mesh):
			continue
		if i < _on_unit_pads_taken:
			CprGhost.hide_ghost(pad_mesh)
			continue
		match _on_unit_pads_look:
			PadsLook.GHOST:
				CprGhost.show_as_ghost(pad_mesh, CprGhost.drop_material(_deployed_hovered))
			PadsLook.PLACED:
				CprGhost.place(pad_mesh)
			_:
				CprGhost.hide_ghost(pad_mesh)


func _on_deployed_hovered_changed(_target: GhostTarget, is_hovered: bool) -> void:
	if _on_unit_pads_look != PadsLook.GHOST:
		return
	_deployed_hovered = is_hovered
	_apply_on_unit_pads()


func _on_aed_placed_show_unit_pads() -> void:
	_on_unit_pads_look = PadsLook.PLACED
	_deployed_hovered = false
	_on_unit_pads_taken = 0
	_apply_on_unit_pads()


func _on_aed_pad_placed_take_unit_pad(_slot: int, _correct: bool, _site_name: String) -> void:
	if _on_unit_pads_look != PadsLook.PLACED:
		return
	_on_unit_pads_taken = mini(_on_unit_pads_taken + 1, _on_unit_pads.size())
	_apply_on_unit_pads()


# --- state -----------------------------------------------------------------------

func _on_cpr_phase_entered() -> void:
	_reset()


func _on_cpr_state_changed(_from: int, to: int) -> void:
	_state = to
	# The cabinet only takes hover/clicks while the trainee is meant to be
	# fetching it; every other state (including the pre-CPR preamble) keeps
	# its bridge collider off so the kit check and the bench keep the mesh to
	# themselves.
	if _cabinet_target != null:
		CprInteractBridge.set_enabled(_cabinet_target,
			to == CprStation.STATE_AED_FETCH and not _cabinet_taken)
	if to == CprStation.STATE_AED_DEPLOY:
		if _deployed_target != null:
			_deployed_target.show_ghost()
		# Only ghost the pads if the AED itself is still a ghost — re-entering
		# this state after it was placed must not un-place them.
		if _on_unit_pads_look != PadsLook.PLACED:
			_on_unit_pads_look = PadsLook.GHOST
			_deployed_hovered = false
			_apply_on_unit_pads()
	elif to != CprStation.STATE_AED_FETCH and _deployed_target != null:
		# Leaving the AED beat entirely. No-op if already placed — dismiss()
		# only hides a target that was never placed.
		_deployed_target.dismiss()
	# Left the AED beat without ever placing it: take the preview back down.
	if to != CprStation.STATE_AED_FETCH and to != CprStation.STATE_AED_DEPLOY and _on_unit_pads_look == PadsLook.GHOST:
		_on_unit_pads_look = PadsLook.HIDDEN
		_apply_on_unit_pads()

	if to != CprStation.STATE_AED_FETCH:
		_cabinet_hovered = false
		_apply_cabinet_overlay()


func _reset() -> void:
	_state = CprStation.STATE_PRIMARY_SURVEY
	_cabinet_taken = false
	_cabinet_hovered = false
	_on_unit_pads_look = PadsLook.HIDDEN
	_on_unit_pads_taken = 0
	_deployed_hovered = false
	_apply_on_unit_pads()
	if _cabinet_mesh != null:
		_cabinet_mesh.visible = true
		_cabinet_mesh.material_overlay = null
	if _cabinet_target != null:
		# Off, not on: the state gate re-enables it when AED_FETCH begins.
		CprInteractBridge.set_enabled(_cabinet_target, false)
	if _deployed_target != null:
		_deployed_target.is_placed = false
		_deployed_target.dismiss()


func _exit_tree() -> void:
	if _cabinet_target != null:
		CprInteractBridge.unregister(_cabinet_target)
	if _deployed_target != null:
		_deployed_target.free_target()
