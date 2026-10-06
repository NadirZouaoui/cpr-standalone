class_name IsolationSignMount
extends Interactable
## Hanging the "Isolate here" sign, on the breaker face itself.
##
## This lives on `Breaker-convcol` - the front of the board - and not on the
## door. The door has swung 154 degrees out of the way by the time the sign
## is due, so a prompt attached to it points the trainee at a panel that is
## no longer part of the thing they are looking at. It also matches the real
## procedure: the notice goes on the isolating device, not on its cover.
##
## Stays silent until BreakerPanel arms it, so the prompt cannot appear
## before the board has been opened.
##
## **It also waits for the reassessment**, which is not a tidiness rule.
## Hanging the sign is what sends the worker in to be shocked
## (BreakerPanel._on_sign_hung). Before this gate existed a trainee could open
## the board, walk past pass 2 of the hazard survey, hang the sign, and find
## themselves with a casualty on a live conductor and a 20 s limit on
## `contact_broken` while `hazards_reassessed` - the step `crook_retrieved`
## requires - was still outstanding. The crook could not be taken, so contact
## could not be broken: a run-ending trap reached by doing exactly what the
## game had just invited.

## The sign is up. BreakerPanel gates the incident on this.
signal sign_hung()

@export var step_id: StringName = &"isolation_point_signed"

## Item id the trainee has to be holding. Matches the ToolRack bench entry.
@export var sign_item_id: StringName = &"isolation_sign"

## Correction for the sign mesh's own baked orientation, in degrees, applied
## on top of the anchor's rotation. The anchor decides where it goes and
## which way it faces; this only fixes the mesh being modelled face-down or
## back-to-front.
@export var sign_rotation_deg: Vector3 = Vector3.ZERO

## The step that has to be off the trainee's plate before the sign will go up.
## Same name and same idiom as HazardReassessInteract.requires_step, which is
## the interactable that resolves it.
@export var requires_step: StringName = &"hazards_reassessed"

@export_multiline var missing_message: String = "Fetch the Danger Isolate Sign from the bench first."
@export_multiline var locked_message: String = "Reassess the open board before you sign the point of isolation."
@export_multiline var done_message: String = "Isolation point marked. The board is signed for work."

## Placed by hand in the editor and handed over by BreakerPanel. Falls back
## to this node's own origin, which is visibly wrong rather than silent.
var anchor: Node3D = null

## No prompt until the panel is open.
var armed: bool = false

var _hung: bool = false


func arm() -> void:
	armed = true


func is_hung() -> bool:
	return _hung


func prompt_text() -> String:
	return "Hang the Isolation Sign"


## Deliberately does NOT carry the reassessment gate - see accepts_sign().
func can_interact() -> bool:
	return enabled and armed and not _hung and not SimState.is_preamble()


## Whether the mount will take the sign, holding it aside.
##
## `is_resolved`, not `is_complete`: a failed pass is off the trainee's plate
## the same way a completed one is, and gating on completion alone would let a
## failed reassessment hold the sign shut forever - and with it the crook, and
## with it the whole rescue. It is also exactly when HazardReassessInteract
## goes inert, so the mount opens as the busbar prompt disappears rather than
## a beat either side of it.
##
## A prerequisite the loaded procedure does not contain is not a gate. That
## would mean a typo or an edited resource, and this file has already cost one
## hard-stuck run; it must not be able to cause a second.
func accepts_sign() -> bool:
	if requires_step == &"":
		return true
	if not Assessment.steps.has(requires_step):
		return true
	return Assessment.is_resolved(requires_step)


func _on_interact(_from_position: Vector3) -> void:
	# Refused here rather than in can_interact(), which is not the same thing:
	# InteractionRay drops a focus whose can_interact() is false, so the mount
	# would stop answering the crosshair at all and the ghost would read as the
	# wrong spot. The prompt stays up and the click says what is outstanding -
	# the same shape as the "fetch the sign first" refusal below.
	#
	# And ahead of the hand check, so a trainee standing at the ghost
	# empty-handed is told the real reason rather than being sent to the bench
	# for a sign the mount would then refuse anyway.
	if not accepts_sign():
		Events.center_message_requested.emit(locked_message, Tokens.WARNING, 3.0)
		return

	var slot := get_tree().get_first_node_in_group(HandSlot.GROUP) as HandSlot
	if slot == null or slot.held_item_id != sign_item_id:
		Events.center_message_requested.emit(missing_message, Tokens.WARNING, 3.0)
		return

	# hand_over(), not release(): release() would carry the sign straight
	# back to the bench it was picked up from.
	var sign_node := slot.hand_over()
	if sign_node == null:
		return
	if Rescuer.is_holding(sign_item_id):
		Rescuer.drop()

	_mount(sign_node)

	_hung = true
	Assessment.complete(step_id)
	Events.center_message_requested.emit(done_message, Tokens.SUCCESS, 3.5)
	unhighlight()
	sign_hung.emit()


## Park the sign on the anchor. Scale is carried across explicitly: Blender
## bakes object scale into the node rather than into the mesh, so rebuilding
## the basis from Euler angles alone would resize the sign.
func _mount(node: Node3D) -> void:
	var parent: Node3D = anchor if anchor != null else self
	var previous := node.get_parent()
	if previous != null:
		previous.remove_child(node)
	parent.add_child(node)

	var item_scale := node.transform.basis.get_scale()
	var basis := Basis.from_euler(Vector3(
		deg_to_rad(sign_rotation_deg.x),
		deg_to_rad(sign_rotation_deg.y),
		deg_to_rad(sign_rotation_deg.z)
	)) * Basis.from_scale(item_scale)

	node.transform = Transform3D(basis, Vector3.ZERO)
	node.visible = true

	# Mounted is mounted. It stops being something the trainee can pick back
	# up, and stops being something the interaction ray can focus at all.
	for child in node.get_children():
		if child is PickupItem:
			(child as PickupItem).enabled = false
	for body in _bodies(node):
		body.collision_layer = 0
		body.collision_mask = 0


func _bodies(root: Node) -> Array[CollisionObject3D]:
	var out: Array[CollisionObject3D] = []
	if root is CollisionObject3D:
		out.append(root)
	for child in root.get_children():
		out.append_array(_bodies(child))
	return out
