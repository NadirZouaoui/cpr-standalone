class_name EmergencyRadio
extends Interactable
## The two-way radio on the bench - how the trainee calls for help.
##
## "Send for help" used to be a line in the casualty menu, which made the most
## time-critical step in DRSABCD a menu pick taken while kneeling over the body.
## It is a physical act with a physical object, so it is now one: walk to the
## bench, use the radio. The casualty menu no longer offers it.
##
## Completes BOTH primary-survey steps in one use. Dispatching someone for an
## AED is part of the same radio call in practice, and splitting it into two
## presses of the same object would be busywork, not training.
##
## The radio never nags. What tells the trainee the call exists is the choice
## card main.gd opens once the casualty is found unresponsive; after that the
## radio speaks for itself through the crosshair prompt below. The step keeps
## its 10 s time limit from the moment check_response lands, so dawdling over
## the card costs exactly what it would cost in the field.
##
## Bound to the Blender object "Radio1" by ToolRack, for the reason given in
## that file: the room is an imported .blend and anything wired in the editor is
## lost on reimport.

const STEPS: Array[StringName] = [&"send_for_help", &"call_for_aed"]

var _called: bool = false


## Silent during the kit check, where this same mesh is a naming question -
## the same rule PickupItem follows for every other object on the bench.
func can_interact() -> bool:
	return enabled and not _called and not SimState.is_preamble()


## Empty once the call is made. InteractionRay keeps a used one-shot as its
## `current` while the crosshair has not moved off it (it falls back to an
## unavailable Interactable rather than to nothing), and every other one-shot
## in the room hides its mesh on use so this never shows. The radio stays on
## the bench, so it clears its own prompt instead of leaving a stale
## "Call 000" chip over a call already placed.
func prompt_text() -> String:
	return "" if _called else "Call 000 and send for an AED"


func _on_interact(_from_position: Vector3) -> void:
	_called = true
	unhighlight()
	for step in STEPS:
		Assessment.complete(step)
	Events.center_message_requested.emit(
		"\"Ambulance - unresponsive casualty, electrical incident.\" Help and an AED are on the way.",
		Tokens.SUCCESS, 3.5
	)
