class_name PickupItem
extends Interactable
## A tool or PPE item the rescuer can take: the rescue crook, insulated
## gloves, the AED, the first aid kit.
##
## There are three kinds. PPE accumulates on Rescuer.ppe_worn. Tools become
## the single held item, so picking up the crook puts down whatever was in
## hand. Stowed items go on the person for good - neither worn nor held, so
## they are outside the PPE gate and nothing displaces them.
##
## A tool marked `holdable` is carried in the HandSlot as a view model and
## can be put back down. One marked `hide_on_pickup` simply disappears,
## which is the right treatment for anything with a worn or attached
## counterpart.

@export_group("Item")
## Matches the ids in Rescuer.REQUIRED_PPE / INSULATED_ITEMS.
@export var item_id: StringName = &""

## PPE is worn and accumulates. Tools are held one at a time.
@export var is_ppe: bool = false

## Taken onto the person and kept there: no hand model, no putting it back,
## and no PPE bookkeeping. The torch is this - the client's words put it with
## the gloves, "before the work commences", but it protects nobody from a
## conductor and must not count toward the PPE gate. Ignored for PPE.
@export var is_stowed: bool = false

## Completed when this item is taken. Leave empty for items with no
## dedicated checklist entry.
@export var step_on_pickup: StringName = &""

@export_group("Holding")
## Carry the object in view rather than hiding it. Ignored for PPE.
@export var holdable: bool = false

## Where the handle is, in normalised bounds space (0-1 per axis). Scale
## independent, so it survives an artist rescaling the object in Blender.
@export var grip_anchor := Vector3(0.5, 0.5, 0.5)

## Camera-space direction the far end should point: -Z into the screen.
@export var aim_direction := Vector3(0.0, 0.25, -0.97)

## Spin about the aim axis, in degrees. Set by eye - it decides which way
## an asymmetric shape such as a hook opens.
@export_range(-180.0, 180.0, 1.0) var roll_degrees: float = 0.0

## Outright pose for the item in the hand, in camera space, degrees. Use
## this rather than `roll_degrees` for flat objects: roll spins about the
## aim axis and cannot turn a face toward the viewer.
@export var hold_rotation_deg := Vector3.ZERO

## Nudge applied after the grip point is placed in the hand.
@export var grip_offset := Vector3.ZERO

@export_group("Presentation")
## Hidden once taken - use for a mesh that has a held/attached counterpart.
## Skipped when the item is holdable, since it is visible in hand instead.
@export var hide_on_pickup: bool = true

var _taken: bool = false

## Set by the controls tutorial while it runs. The tutorial is a practice round
## in the empty room before the kit check: the tools on the bench go into the
## hand and back so the trainee learns how, and nothing is graded, equipped or
## recorded. PPE and stowed items stay where they are - only a tool that goes
## into the hand is any use for "pick it up, then press G".
static var tutorial_sandbox: bool = false


func _ready_impl() -> void:
	if item_id == &"":
		push_warning("PickupItem '%s' has no item_id" % name)


func can_interact() -> bool:
	# Nothing is picked up during the preamble. The bench is a naming
	# exercise until the exercise starts, and a trainee walking into the
	# kit check holding a hammer is not the scene anybody designed.
	if SimState.is_preamble():
		return enabled and not _taken and tutorial_sandbox and holdable \
			and not is_ppe and not is_stowed_kind()
	return enabled and not _taken


func prompt_text() -> String:
	var action: String = "Put on" if is_ppe else "Take"
	return "%s %s" % [action, label()]


## A stowed item is on the person and stays there. Kept as its own predicate
## so the hand-slot paths below cannot be reached for one by accident.
func is_stowed_kind() -> bool:
	return is_stowed and not is_ppe


func _on_interact(_from_position: Vector3) -> void:
	# Tutorial practice (the only way to get here in the preamble): into the
	# hand and nothing else - no Rescuer, no step, no transcript.
	if SimState.is_preamble():
		if _take_into_hand():
			_taken = true
			Events.center_message_requested.emit(
				"%s in hand. Press G to put it back." % label(), Tokens.SCENE_TEXT, 2.0)
		unhighlight()
		return

	_taken = true

	if is_ppe:
		Rescuer.don_ppe(item_id)
		var missing := Rescuer.missing_ppe()
		if missing.is_empty():
			Events.center_message_requested.emit("PPE complete.", Tokens.SUCCESS, 2.0)
		else:
			var plural: String = "" if missing.size() == 1 else "s"
			Events.center_message_requested.emit(
				"%d PPE item%s still required." % [missing.size(), plural],
				Tokens.WARNING, 2.0
			)
	elif is_stowed_kind():
		Rescuer.stow(item_id)
		Events.center_message_requested.emit(
			"%s stowed." % label(), Tokens.SCENE_TEXT, 2.0
		)
	else:
		Rescuer.equip(item_id)
		if holdable and _take_into_hand():
			Events.center_message_requested.emit(
				"%s in hand. Press G to put it back." % label(), Tokens.SCENE_TEXT, 2.0
			)
		else:
			Events.center_message_requested.emit("%s in hand." % label(), Tokens.SCENE_TEXT, 1.5)

	if step_on_pickup != &"":
		Assessment.complete(step_on_pickup)

	unhighlight()

	# A holdable tool moves into view instead of vanishing. PPE and stowed
	# items have no hand model, so their bench mesh is simply gone.
	if hide_on_pickup and not (holdable and not is_ppe and not is_stowed_kind()):
		var target: Node = mesh_to_highlight if mesh_to_highlight != null else get_parent()
		if target is Node3D:
			target.visible = false


# =============================================================================
# Holding
# =============================================================================
## The node that actually travels to the hand - the mesh this interactable
## is attached to, not the interactable itself.
func held_node() -> Node3D:
	if mesh_to_highlight != null:
		return mesh_to_highlight
	var parent := get_parent()
	return parent as Node3D


func _take_into_hand() -> bool:
	var slot := get_tree().get_first_node_in_group(HandSlot.GROUP) as HandSlot
	if slot == null:
		push_warning("PickupItem '%s' is holdable but no HandSlot is in the scene." % name)
		return false

	var node := held_node()
	if node == null:
		push_warning("PickupItem '%s' has no mesh to put in the hand." % name)
		return false

	return slot.take(
		node, item_id, grip_anchor, aim_direction, roll_degrees,
		grip_offset, hold_rotation_deg, _on_returned_to_world
	)


## Called by the HandSlot once the item is back on its bench.
func _on_returned_to_world() -> void:
	_taken = false
	if Rescuer.is_holding(item_id):
		Rescuer.drop()
