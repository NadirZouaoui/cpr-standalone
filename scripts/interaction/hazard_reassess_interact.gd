class_name HazardReassessInteract
extends Interactable
## "Reassess the open board" - the way into hazard pass 2.
##
## Hangs on the **busbars**, not on the door. The door is the obvious place
## and it is the wrong one: `BreakerPanelInteract` goes inert the moment it is
## opened, and the panel swings 154 degrees clear of the board, so a prompt on
## it would point at a slab of steel that is no longer part of the thing being
## looked at. The busbars are what opening the board exposed, and they are what
## the reassessment is about.
##
## Inert until `panel_opened`, and inert again once the pass is resolved.
## HazardAssessment holds the real gate - this node only decides whether to
## show a prompt.
##
## Built in code by BreakerPanel, which owns the tunables, for the same reason
## everything else on that node is: the room is an imported .blend and its node
## tree is rebuilt wholesale on every reimport.

@export var step_id: StringName = &"hazards_reassessed"

## The step that has to be complete before this becomes live.
@export var requires_step: StringName = &"panel_opened"

var _hitbox: StaticBody3D = null


func _ready_impl() -> void:
	_build_hitbox()


## Live only between the board opening and the reassessment being resolved.
## Before that it is a lie - there is nothing to reassess through a shut door -
## and afterwards it is clutter in front of the sign the trainee now has to
## hang.
func can_interact() -> bool:
	if not enabled or SimState.is_preamble():
		return false
	if requires_step != &"" and not Assessment.is_complete(requires_step):
		return false
	return not Assessment.is_resolved(step_id)


func prompt_text() -> String:
	return "Reassess %s" % label()


func _on_interact(_from_position: Vector3) -> void:
	Events.hazard_assessment_requested.emit(step_id)


## A box that swallows the busbars and stands proud of them.
##
## Same problem the door had, and the same fix: the busbars sit inside a steel
## cabinet whose own collider is nearer the trainee along most rays, so a ray
## aimed into the open board hits the cabinet first, finds no Interactable on
## it, and reports nothing. Padding the volume outward makes this the nearest
## thing along the ray without touching the room's geometry. On the
## interactable layer only, masking nothing, so it stays invisible to movement
## and physics.
func _build_hitbox() -> void:
	var mesh := get_parent() as MeshInstance3D
	if mesh == null or mesh.mesh == null:
		push_warning(
			"HazardReassessInteract: '%s' has no mesh to size a hitbox from; "
			% name
			+ "pass 2 may be unreachable with the crosshair."
		)
		return

	var box := mesh.mesh.get_aabb()
	if box.size == Vector3.ZERO:
		return

	var shape := BoxShape3D.new()
	shape.size = box.size + Vector3(0.10, 0.10, 0.20)

	var collider := CollisionShape3D.new()
	collider.name = "Shape"
	collider.shape = shape
	collider.position = box.get_center()

	_hitbox = StaticBody3D.new()
	_hitbox.name = "BusbarHitbox"
	_hitbox.collision_layer = 2
	_hitbox.collision_mask = 0
	_hitbox.add_child(collider)
	mesh.add_child(_hitbox)
