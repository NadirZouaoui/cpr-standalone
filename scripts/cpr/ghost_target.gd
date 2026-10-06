class_name GhostTarget
extends RefCounted

## A clickable ghost built entirely in code around an existing imported MeshInstance3D.
##
## The pad sites and the AED drop location come out of the .blend as plain meshes with
## no scripts, no Area3D and no collision — and they must stay that way, because
## re-importing the .blend would wipe anything authored onto them in `main.tscn`.
##
## So this wrapper is constructed at runtime by the owning station:
##   - builds an Area3D + BoxShape3D from the mesh AABB and parents it to the mesh
##     (only if `build_area` is explicitly passed as true — see below)
##   - drives idle / hover materials via CprGhost
##   - emits `activated` when clicked
##
## Godot's built-in camera picking (Area3D.input_ray_pickable) needs a visible mouse
## cursor at the actual click position and does not work in this project — see
## CPR_CONTRACT.md §4.0. `build_area` therefore now DEFAULTS TO FALSE: by default a
## GhostTarget self-registers with CprInteractBridge instead, which drives it from the
## project's existing crosshair interactor via `set_hovered()` / `activate()` — no
## caller changes needed. The Area3D path stays available (pass `build_area = true`)
## for headless tests that have no bridge/interactor running.
##
## SHARED / FROZEN — see CPR_CONTRACT.md section 7. `set_hovered()` and `activate()`
## are the seam every driver (Area3D or CprInteractBridge) calls into; their own
## behaviour is unchanged.

signal hovered_changed(target: GhostTarget, is_hovered: bool)
signal activated(target: GhostTarget)

var mesh: MeshInstance3D = null
var site_name: String = ""
## Hover tooltip, shown on the HUD prompt chip by CprInteractBridge while the
## crosshair is on this target. Set by the owning station; empty shows nothing.
var prompt: String = ""
## Free-form payload for the owning station (e.g. {"correct": true, "slot": 0}).
var data: Dictionary = {}

var is_hovered: bool = false
var is_placed: bool = false
var enabled: bool = false

var _area: Area3D = null
var _idle_mat: StandardMaterial3D = null
var _hover_mat: StandardMaterial3D = null
## Collider is inflated slightly past the AABB so thin conformed pads stay clickable.
const COLLIDER_PAD_METRES := 0.010


func _init(
		target_mesh: MeshInstance3D,
		idle_mat: StandardMaterial3D,
		hover_mat: StandardMaterial3D,
		build_area: bool = false
	) -> void:
	mesh = target_mesh
	site_name = String(mesh.name) if mesh != null else ""
	_idle_mat = idle_mat
	_hover_mat = hover_mat
	if mesh == null:
		push_error("GhostTarget: null mesh")
		return
	if build_area:
		_build_area()
	else:
		CprInteractBridge.register(self)
	# Start hidden. The station reveals ghosts when its state opens.
	CprGhost.hide_ghost(mesh)


func _build_area() -> void:
	var aabb: AABB = mesh.get_aabb()
	_area = Area3D.new()
	_area.name = "%s_GhostArea" % mesh.name
	_area.input_ray_pickable = true
	_area.monitoring = false
	_area.monitorable = false

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = aabb.size + Vector3.ONE * (COLLIDER_PAD_METRES * 2.0)
	shape.shape = box
	shape.position = aabb.get_center()

	_area.add_child(shape)
	mesh.add_child(_area)

	_area.mouse_entered.connect(_on_mouse_entered)
	_area.mouse_exited.connect(_on_mouse_exited)
	_area.input_event.connect(_on_input_event)


# --- state -------------------------------------------------------------------

## Reveal as an idle ghost and start accepting hover / clicks.
func show_ghost() -> void:
	if mesh == null or is_placed:
		return
	enabled = true
	is_hovered = false
	CprGhost.show_as_ghost(mesh, _idle_mat)
	if _area != null:
		_area.input_ray_pickable = true
	else:
		CprInteractBridge.set_enabled(self, true)


## Stop accepting input and hide, unless already placed.
func dismiss() -> void:
	enabled = false
	if _area != null:
		_area.input_ray_pickable = false
	else:
		CprInteractBridge.set_enabled(self, false)
	if not is_placed:
		CprGhost.hide_ghost(mesh)


## Commit: clear the override so the mesh renders with its authored material.
func place() -> void:
	if mesh == null:
		return
	is_placed = true
	enabled = false
	is_hovered = false
	if _area != null:
		_area.input_ray_pickable = false
	else:
		CprInteractBridge.set_enabled(self, false)
	CprGhost.place(mesh)


func set_hovered(value: bool) -> void:
	if not enabled or is_placed or value == is_hovered:
		return
	is_hovered = value
	CprGhost.show_as_ghost(mesh, _hover_mat if value else _idle_mat)
	hovered_changed.emit(self, value)


## Manual activation, for when the project's own interactor drives this instead of
## Godot's camera picking.
func activate() -> void:
	if not enabled or is_placed:
		return
	activated.emit(self)


func free_target() -> void:
	if _area != null and is_instance_valid(_area):
		_area.queue_free()
		_area = null
	CprInteractBridge.unregister(self)


# --- Area3D callbacks --------------------------------------------------------

func _on_mouse_entered() -> void:
	set_hovered(true)


func _on_mouse_exited() -> void:
	set_hovered(false)


func _on_input_event(
		_camera: Node,
		event: InputEvent,
		_pos: Vector3,
		_normal: Vector3,
		_idx: int
	) -> void:
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed:
		activate()
