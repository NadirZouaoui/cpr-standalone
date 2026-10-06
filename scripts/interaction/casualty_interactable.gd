class_name CasualtyInteractable
extends Interactable
## The click target on the casualty's body.
##
## Context-sensitive by design: the same click means "break contact", "drag"
## or "open the treatment menu" depending on the casualty's state and what
## the rescuer is holding. The one thing it never does is silently protect
## the trainee from a wrong choice - reaching for an energised casualty
## bare-handed is allowed, and ends the exercise.

@export var casualty: Casualty

## True while a rescue swing is in flight. See _perform_rescue().
var _rescuing: bool = false


func _ready_impl() -> void:
	if casualty == null:
		casualty = _find_casualty()
	if casualty == null:
		push_error("CasualtyInteractable '%s' has no Casualty" % name)


func _find_casualty() -> Casualty:
	var node := get_parent()
	for _i in 4:
		if node == null:
			break
		if node is Casualty:
			return node
		node = node.get_parent()
	return get_tree().get_first_node_in_group(&"casualty") as Casualty


## The name main.tscn gives the treatment-pointer controller
## (scripts/ui/casualty_action_menu.gd). Resolved by name at call time, not
## cached: main.tscn is frozen and this is the only thing here that needs it.
const TREATMENT_NODE_NAME := "CasualtyActions"


func prompt_text() -> String:
	if casualty == null:
		return ""
	# Nothing to offer while the trainee is already treating: the body pointers
	# are the instruction now, and a tooltip repeating "treat the casualty" over
	# the top of them is noise.
	if _treatment_open() or _cpr_in_progress():
		return ""
	match casualty.state:
		Casualty.State.WAITING:
			return ""
		Casualty.State.FIDDLING:
			return "Worker at the panel"
		Casualty.State.IN_CONTACT:
			return "Break contact with the hook" if Rescuer.can_break_contact() else "Reach for the casualty"
		Casualty.State.COLLAPSING:
			return "Wait - still falling"
		Casualty.State.DOWN:
			return "Drag clear and lay him out for CPR"
		Casualty.State.BEING_DRAGGED:
			return "Dragging..."
		_:
			return "Interact with casualty"


## WAITING is the pre-exercise state: the worker exists in the tree but has
## not been revealed. CasualtyRig already drops the hit target off the
## interaction layer for the same reason, so this is the second of two locks
## rather than the only one - but it is the one that survives someone turning
## the rig's own gate off to test something.
## Deliberately asks whether a pointer is actually DRAWN, not whether the
## sequence is nominally open. A sequence with no pill on screen - the trainee
## walked back from the radio and the body anchors are out of frame - used to
## silence this prompt as well, which left them nothing to click at all.
func _treatment_open() -> bool:
	var node := get_tree().current_scene.get_node_or_null(TREATMENT_NODE_NAME)
	if node == null:
		return false
	if node.has_method("has_visible_pointer"):
		return node.has_visible_pointer()
	return node.has_method("is_open") and node.is_open()


## Whether the compression minigame is live on this casualty.
##
## Playtest: "remove 'treat casualty' when we're...treating the casualty." The
## prompt was drawn over the ghost hands, mid-set, with the count on the card
## beside it - three directions at once, and the one at the crosshair was the
## only one that was wrong.
##
## _treatment_open() does not catch it: that asks whether a body POINTER is on
## screen, and the pointers are stood down the moment the set starts because the
## minigame owns the casualty from there. `compressions_armed` is CprStation's
## own record of exactly that hand-over - not the state, which arrives off the
## breathing check before the trainee has agreed to anything, but the flag set
## when the "Start compressions" pill is taken and cleared by the shock.
##
## Deliberately narrow. Between the sets, and at every anchored beat that is not
## a running set, the prompt is still the way back into the treatment menu after
## standing up, and silencing it there is what left a trainee with nothing to
## click at all - see _treatment_open().
func _cpr_in_progress() -> bool:
	var station := CprStation.get_current()
	return station != null and station.compressions_armed


## The order of the extraction is a SILENT choice, and stays one.
##
## There was a gate here: the treatment menu refused to open until
## `supply_isolated` resolved, with a warning that the circuit was still live.
## It is gone. Drag first then isolate, or isolate first then drag - both are
## real decisions a rescuer makes under time, and the exercise assesses the
## order without ever announcing it. A refusal at the moment of the choice is
## the exercise telling the trainee the answer, which is the one thing every
## other decision in this project is careful not to do; the debrief is where
## they find out, alongside everything else.
##
## Nothing about the assessment changed. The procedure still records when each
## step landed and in what order, so a run that treated him with the conductor
## still live reads that way in the report.


func can_interact() -> bool:
	if not enabled or casualty == null:
		return false
	return casualty.state != Casualty.State.BEING_DRAGGED \
		and casualty.state != Casualty.State.WAITING


func _on_interact(_from_position: Vector3) -> void:
	match casualty.state:
		Casualty.State.WAITING:
			return

		Casualty.State.FIDDLING:
			# Nothing has gone wrong yet. Interrupting the worker is not a
			# gradable act, so this is a nudge rather than a violation.
			Events.center_message_requested.emit(
				"The worker is busy at the breaker.", Tokens.SCENE_TEXT_MUTED, 2.0
			)

		Casualty.State.IN_CONTACT:
			# Insulated hook AND insulated gloves, or the trainee becomes the
			# second casualty. Nothing here stops them making that choice.
			if Rescuer.can_break_contact():
				_perform_rescue()
			else:
				casualty.touch_unsafely(Rescuer.unsafe_contact_reason())

		Casualty.State.COLLAPSING:
			casualty.touch_bare_handed()

		Casualty.State.DOWN:
			_put_down_held_item()
			casualty.drag_to_safety()

		_:
			if _cpr_in_progress():
				return
			_put_down_held_item()
			Events.casualty_actions_requested.emit(casualty)


# =============================================================================
# Rescue sequence
# =============================================================================
## Turn to the casualty, swing the hook at his hips, then let him fall.
##
## The view is driven to the hips rather than left where the trainee was
## aiming, so the hook always lands on the body and not on whatever part of
## him happened to be under the reticle. The player is frozen for the
## duration - roughly a second - so mouse look cannot fight the turn.
##
## The fall starts on `strike_contact`, the frame the tip arrives, so the
## collapse and the withdraw overlap the way they would in life. Awaiting
## the whole swing instead would leave him rigid while the hook came back.
##
## If the hand is empty the fall still happens. The rescue is a rule about
## state, not about whether the flourish played.
##
## Re-entrancy: a second click while the swing is in flight would connect a
## second one-shot to `strike_contact` and re-freeze a player who is about to
## be unfrozen by the first pass. `_rescuing` closes that window; the state
## check alone does not, because the casualty stays IN_CONTACT until the tip
## actually lands.
func _perform_rescue() -> void:
	if _rescuing:
		return
	_rescuing = true

	var player := _player()
	var hand := _hand()
	var target := casualty.hips_position()

	if player != null:
		player.is_frozen = true
		await player.look_toward(target, 0.3)

	if hand != null and not hand.is_empty():
		# One-shot: the hand outlives this rescue and must not still be
		# wired to it on a later swing.
		hand.strike_contact.connect(casualty.break_contact_with_crook, CONNECT_ONE_SHOT)
		await hand.strike_at(target)
		# The hook has done the one thing it is for. Playtest: "make the crook
		# be put back once they break contact." Everything after this beat -
		# the drag, the isolation, the whole of CPR - needs both hands, and the
		# trainee was carrying a two-metre fibreglass pole through all of it
		# because nothing put it down until _put_down_held_item() happened to
		# run on the drag click.
		#
		# After the swing, not on strike_contact: the strike IS the hook
		# landing, and releasing on that signal takes the pole out of the
		# rescuer''s hands mid-arc.
		_put_down_held_item()
	else:
		casualty.break_contact_with_crook()

	if player != null:
		player.is_frozen = false
	_rescuing = false


func _player() -> Player:
	return get_tree().get_first_node_in_group(&"player") as Player


func _hand() -> HandSlot:
	return get_tree().get_first_node_in_group(HandSlot.GROUP) as HandSlot


## Working on the casualty needs both hands, so whatever the trainee is
## carrying goes back to where it was picked up before the drag or the
## treatment menu starts.
##
## The rescue path calls it too, but only AFTER the swing has finished - there
## the held hook is the very tool the strike swings, and releasing it any
## earlier would empty the hand mid-arc.
func _put_down_held_item() -> void:
	var hand := _hand()
	if hand != null and not hand.is_empty():
		hand.release()
