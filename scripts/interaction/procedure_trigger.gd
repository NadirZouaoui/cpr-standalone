class_name ProcedureTrigger
extends Interactable
## Generic "using this completes a checklist step" object.
##
## Covers the switchboard isolator, the phone, the safety observer NPC, the
## AED case - anything whose entire simulation behaviour is "the trainee did
## the thing". Anything with real state of its own gets a purpose-built
## subclass instead.

@export_group("Procedure")
@export var step_id: StringName = &""

## Advance the phase machine when this fires. Leave at BRIEFING to skip.
@export var advance_to_phase: SimState.Phase = SimState.Phase.BRIEFING

@export_group("Feedback")
@export_multiline var confirmation: String = ""
@export var confirmation_seconds: float = 2.5

@export_group("Repeatability")
## Most procedure objects fire once. Set true for things like the isolator
## that can be operated repeatedly.
@export var repeatable: bool = false

var _fired: bool = false


func _ready_impl() -> void:
	if step_id == &"":
		push_warning("ProcedureTrigger '%s' has no step_id" % name)


func can_interact() -> bool:
	return enabled and (repeatable or not _fired)


func _on_interact(_from_position: Vector3) -> void:
	_fired = true

	if step_id != &"":
		Assessment.complete(step_id)

	if advance_to_phase != SimState.Phase.BRIEFING and SimState.phase < advance_to_phase:
		SimState.phase = advance_to_phase

	if confirmation != "":
		Events.center_message_requested.emit(confirmation, Tokens.SCENE_TEXT, confirmation_seconds)

	if not repeatable:
		unhighlight()
