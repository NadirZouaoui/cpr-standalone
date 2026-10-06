@tool
class_name IsolationSignAnchor
extends Marker3D
## Where the "Isolate here" sign goes: a hand-placed marker in the editor,
## and a translucent amber ghost of the sign in game.
##
## Solving this position from the breaker's bounds did not work. The Blender
## object's origin sits on the floor rather than at its centre, its children
## are the *neighbouring* cabinets' front panels, and the busbars stand proud
## of the face - so every rule derived from the AABB put the sign somewhere
## slightly wrong, and each correction cost a full run to evaluate. A marker
## moved with the gizmo is faster and exact.
##
## The same box serves both sides. In the editor it shows size and facing
## while dragging, which a bare Marker3D cross cannot. In game it is the
## target the trainee aims at and clicks: a ghost of the sign sitting where
## the sign belongs says "put it here" without a line of instruction, and it
## gives the interaction a collider of its own rather than borrowing the
## breaker's - so the prompt appears on the spot the sign will occupy, not
## anywhere on a two-metre cabinet.
##
## Runtime visibility is owned by BreakerPanel via activate(): hidden until
## the board is open, gone once the sign is up.

## The sign's footprint. Set this to match the real sign - it is both the
## editor guide and the in-game target the trainee clicks.
@export var preview_size := Vector3(0.22, 0.16, 0.012):
	set(value):
		preview_size = value
		_rebuild_editor()
		_resize_target()

## Editor-only guide colour.
@export var preview_color := Color(0.98, 0.75, 0.14, 0.65):
	set(value):
		preview_color = value
		_rebuild_editor()

## Shows the guide box in the editor viewport. Does not affect the game.
@export var show_preview: bool = true:
	set(value):
		show_preview = value
		_rebuild_editor()

@export_group("In game")
## The ghost the trainee aims at. Deliberately fainter than the editor
## guide: it is a hint about where the sign goes, not an object in the room.
@export var ghost_color := Color(0.98, 0.75, 0.14, 0.32)

## Breathe the ghost's alpha so it reads as a placeholder rather than as
## something already mounted.
@export var pulse: bool = true
@export var pulse_speed: float = 2.2
@export var pulse_depth: float = 0.14

## How far the clickable volume sits proud of the ghost, toward the trainee.
##
## NOT cosmetic, and do not set it to zero. The busbars carry a padded
## axis-aligned hitbox (HazardReassessInteract, pass 2 of the hazard
## assessment) whose box encloses this spot - it is a crude AABB around a long,
## angled busbar run, so it reaches out in front of the board face even with its
## padding removed. Without this offset the interaction ray hits that hitbox
## first, every aim at the sign resolves to the reassess interactable instead of
## the mount, and `isolation_point_signed` becomes impossible: a hard stuck run.
## Measured on the real geometry - the hitbox face sat 22 mm in front of this
## collider - so the default clears it with room to spare.
##
## It also happens to be physically right: a sign hung on a board stands off it.
@export var proud_offset: float = 0.06

var _preview: MeshInstance3D = null
var _target: Node3D = null
var _ghost: MeshInstance3D = null
var _ghost_material: StandardMaterial3D = null
var _body: StaticBody3D = null
var _shape: CollisionShape3D = null
var _t: float = 0.0


func _ready() -> void:
	set_process(false)
	if Engine.is_editor_hint():
		_rebuild_editor()
	else:
		_build_target()
		activate(false)


# =============================================================================
# In-game target
# =============================================================================
## The node the sign-mount interactable attaches to. The interaction ray
## walks up from a collider and checks that node's direct children, so the
## mount has to be a sibling of the body - hence the wrapper.
func target() -> Node3D:
	return _target


func _build_target() -> void:
	_target = Node3D.new()
	_target.name = "SignTarget"
	add_child(_target)

	_ghost_material = StandardMaterial3D.new()
	_ghost_material.albedo_color = ghost_color
	_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var mesh := BoxMesh.new()
	mesh.size = preview_size

	_ghost = MeshInstance3D.new()
	_ghost.name = "Ghost"
	_ghost.mesh = mesh
	_ghost.material_override = _ghost_material
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_target.add_child(_ghost)

	var box := BoxShape3D.new()
	# A ghost the size of a postcard is hard to hit across a room, so the
	# clickable volume is padded well past the visual.
	box.size = preview_size + Vector3(0.06, 0.06, 0.06)

	_shape = CollisionShape3D.new()
	_shape.name = "Shape"
	_shape.shape = box
	# Proud of the ghost, toward the trainee - see `proud_offset`. This is what
	# keeps the sign reachable past the busbars' hitbox.
	_shape.position = Vector3(0.0, 0.0, proud_offset)

	_body = StaticBody3D.new()
	_body.name = "Body"
	# Interactable layer only: this is a hint, not something to walk into.
	_body.collision_layer = 2
	_body.collision_mask = 0
	_body.add_child(_shape)
	_target.add_child(_body)


## Show the ghost and let the ray see it. BreakerPanel calls this on when
## the panel opens and off once the sign is hung.
func activate(on: bool) -> void:
	if _target == null:
		return
	_target.visible = on
	if _body != null:
		_body.collision_layer = 2 if on else 0
	set_process(on and pulse)
	if not on:
		return
	_t = 0.0
	if _ghost_material != null:
		_ghost_material.albedo_color = ghost_color


func _process(delta: float) -> void:
	if _ghost_material == null:
		return
	_t += delta
	var alpha: float = clampf(
		ghost_color.a + sin(_t * pulse_speed) * pulse_depth, 0.0, 1.0
	)
	_ghost_material.albedo_color = Color(
		ghost_color.r, ghost_color.g, ghost_color.b, alpha
	)


func _resize_target() -> void:
	if _ghost != null and _ghost.mesh is BoxMesh:
		(_ghost.mesh as BoxMesh).size = preview_size
	if _shape != null and _shape.shape is BoxShape3D:
		(_shape.shape as BoxShape3D).size = preview_size + Vector3(0.06, 0.06, 0.06)


# =============================================================================
# Editor guide
# =============================================================================
func _rebuild_editor() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return

	if _preview != null and is_instance_valid(_preview):
		_preview.queue_free()
		_preview = null
	if not show_preview:
		return

	var mesh := BoxMesh.new()
	mesh.size = preview_size

	var material := StandardMaterial3D.new()
	material.albedo_color = preview_color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	_preview = MeshInstance3D.new()
	_preview.name = "Preview"
	_preview.mesh = mesh
	_preview.material_override = material
	_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Internal and unowned: an editor-only aid must not reach the .tscn.
	add_child(_preview, false, Node.INTERNAL_MODE_BACK)
