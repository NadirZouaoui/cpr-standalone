extends CanvasLayer
## Pre-CPR treatment sequence, presented as contextual pointers on the body.
##
## Was a full-screen dimmed modal, then a diegetic world-space card. Both are
## gone: the actions are now glass pills with leader lines to the body part each
## one concerns (scripts/ui/casualty_pointers.gd), and this script drives them.
## What survived every rewrite is the input model — mouse stays captured, the
## crosshair is the cursor, `interact` activates (CPR_CONTRACT.md §4.0) — and
## this node's name and public API.
##
## Still the node named "CasualtyActions" in main.tscn. That file is frozen and
## CprStation resolves this node by name to call suppress(), so it stays a
## CanvasLayer with suppress() and is_open() intact whatever the presentation
## underneath becomes.
##
## SCOPE — DRSABCD. This owns R and A, and hands over at the chest:
##
##   R  Check for a response
##   S  is NOT here. Sending for help is a physical act with a physical object,
##      so it moved to the two-way radio on the bench (emergency_radio.gd),
##      which also prompts for itself once the casualty is found unresponsive.
##   A  Open the airway, then check for breathing — the latter starts the CPR
##      spine's hold-to-observe and hands over to it.
##
## B, C and D belong to the CPR phase: the compression sets and the AED. The
## entries that used to duplicate them ("Check the airway and breathing",
## "Start/Stop chest compressions", "Attach the AED pads", "Stand clear for
## analysis", "Deliver the shock") are gone, as is "Roll into the recovery
## position", which was cut from the design deliberately (see CPR_HANDOFF.md
## §1). Their procedure steps were retired from lvr_cpr_procedure.tres at the
## same time, so nothing grades an action the trainee can no longer take.

const UI_NAME := &"casualty_actions"

const CasualtyPointersScript := preload("res://scripts/ui/casualty_pointers.gd")

## The body-pointer sequence: what is offered, where it points, and when.
##
## Two tracks that advance independently rather than one queue. The mouth track
## is DRSABCD's R and A — response, then airway, then breathing — and the chest
## track is the shirt and the compressions. Keeping them apart is what lets the
## trainee open the shirt while the airway work is still outstanding, which is
## how it goes in life; a single ordered list would have made one wait on the
## other for no reason.
##
## `available` is a StringName matched in `_is_available()`. Predicates live
## there as code rather than as Callables in this table so the table stays a
## readable statement of the procedure.
const CALLOUTS := [
	{
		"id": &"fire_checked", "anchor": &"belly",
		"label": "Check the casualty is not on fire", "available": &"fire",
		"method": &"check_for_fire",
	},
	{
		"id": &"check_response", "anchor": &"mouth",
		"label": "Check for a response", "available": &"response",
		"method": &"check_response",
	},
	{
		"id": &"open_airway", "anchor": &"mouth",
		"label": "Open the airway", "available": &"airway",
		"method": &"open_airway",
	},
	{
		"id": &"check_breathing", "anchor": &"mouth",
		"label": "Check for breathing", "available": &"breathing",
		"method": &"",
	},
	{
		"id": &"inspect_airway", "anchor": &"mouth",
		"label": "Check the airway for a blockage", "available": &"blockage",
		"method": &"",
	},
	{
		"id": &"start_compressions", "anchor": &"chest",
		"label": "Start compressions", "available": &"compressions",
		"method": &"",
	},
]

## "Open the shirt" left CALLOUTS on 3 Sep 2026 and became a spine callout
## instead (see _spine_callouts).
##
## The client walked their "no need to open the shirt" note back to
## "compressions first, then open the shirt for the AED", so the shirt now has
## exactly one moment: between the two compression sets, so the pads reach bare
## skin. Offering it from the trainee's first interaction — which is what the
## CALLOUTS entry did — would teach the order the client asked to change.
##
## THIS DOES NARROW THE TRAINEE'S ROPE, which is against the grain of the rest
## of this file: everywhere else a wrong order is permitted and recorded rather
## than prevented. Flagged for Nadir. The alternative was leaving the pill up
## through the whole primary survey, where it reads as an instruction.
const EXPOSE_CHEST_CALLOUT := {
	"id": &"expose_chest", "anchor": &"chest",
	"label": "Open the shirt", "available": &"shirt",
	"method": &"expose_chest",
}

## Not part of CALLOUTS on purpose: it belongs to the CPR spine's post-shock
## beat, not to the casualty sequence, and is the one callout allowed to show
## while the sequence is stood down (see _refresh_pointers). The gotcha: the
## correct move after a shock is compressions, immediately - the pill offers
## the plausible wrong one, the click answers it, and the debrief logs it.
const SIGNS_OF_LIFE_CALLOUT := {
	"id": &"signs_of_life", "anchor": &"mouth",
	"label": "Check for signs of life", "available": &"signs",
	"method": &"",
}

## Client item 8, first beat. Offered once ROSC has been announced and the spine
## has entered RECOVERY_ROLL. A spine callout rather than a CALLOUTS entry for
## the same reason "Open the shirt" is: the primary-survey sequence is long since
## stood down by the time it is offered.
##
## `recovery_position` was cut from the design and PROJECT_STATUS.md §1 said not
## to re-add it without asking. This is the asking; the client asked for it and
## Nadir said yes (docs/OVERNIGHT_PLAN.md §1 item 8).
const RECOVERY_ROLL_CALLOUT := {
	"id": &"recovery_position", "anchor": &"chest",
	"label": "Roll into the recovery position", "available": &"recovery",
	"method": &"",
}

## Client item 8, second beat: "check for any other injuries". Three sites, all
## offered at once, each retiring as it is looked at. The hands carry the
## finding — an electrical casualty's entry burn is at the contact point — and
## finding it is what ends the survey. See Casualty.INJURY_SITES for the
## findings themselves; the anchors are CprRig.pointer_marker() names.
const INJURY_CALLOUTS := [
	{
		"id": &"injury_hands", "anchor": &"hand",
		"label": "Check the hands", "available": &"injury", "method": &"",
	},
	{
		"id": &"injury_head", "anchor": &"head",
		"label": "Check the head and neck", "available": &"injury", "method": &"",
	},
	{
		"id": &"injury_legs", "anchor": &"legs",
		"label": "Check the legs and feet", "available": &"injury", "method": &"",
	},
]

## Pill id -> the site name Casualty.INJURY_SITES is keyed by. Two vocabularies
## because the pill ids share this file's namespace with every other callout and
## have to stay unique there, while the site names are the casualty's own.
const _INJURY_SITE_FOR_ID := {
	&"injury_hands": &"hands",
	&"injury_head": &"head",
	&"injury_legs": &"legs",
}

## Which injury sites have been looked at. The survey ends when the burn is
## found, so a trainee who checks the other two first still has the hands left
## to check and cannot dead-end.
var _injuries_seen: Dictionary = {}

## Its partner, and the reason the gotcha is a gotcha: the shock leaves the
## trainee with two pills and no compression minigame running, so resuming is
## a decision they make rather than a beat that happens to them. Same id as the
## CALLOUTS entry — one hand-over, taken twice — so _on_pointer_activated has a
## single path into the minigame.
const RESUME_COMPRESSIONS_CALLOUT := {
	"id": &"start_compressions", "anchor": &"chest",
	"label": "Start compressions", "available": &"resume",
	"method": &"",
}

## Removed: the survey used to borrow BREATHING_CHECK's anchor through
## rig.anchor_for_state(MENU_CAMERA_STATE), so that the pointers were read from
## the place the breathing check would be worked from rather than from wherever
## the trainee happened to be standing. It now asks CprRig.survey_anchor()
## instead, which owns both of the survey's poses and the rule for choosing
## between them - see _menu_anchor().
##
## The constant is worth a note rather than a silent deletion: it carried a
## comment warning against ever writing the state as a bare number, after a
## spine reorder turned a literal `1` into the wrong anchor. That hazard did
## not go away with the constant. Read the state constants; never the numbers.

const CHEST_ANCHOR_NAME := "CprRig"

var suppressed: bool = false

## Set while the help choice card is up (main.gd owns it): every pill comes
## down so the screen carries one live direction - the card. Cleared when the
## card is answered, and the outstanding pills return on the next refresh.
var choice_hold: bool = false

## main.gd raises and lowers the hold around its choice card; the explicit
## refresh is what makes the pills respond the same frame.
func set_choice_hold(on: bool) -> void:
	choice_hold = on
	_refresh_pointers()

## Whether the post-shock signs-of-life pill has been taken. Once only.
var _signs_checked: bool = false

var _casualty: Casualty = null
var _pointers: CanvasLayer = null

## True from the first interaction with the casualty until the CPR minigame
## takes over. Outlives the kneel: the pills stay readable from standing, and
## the chest track still has work outstanding when the breathing check starts.
var _sequence_active: bool = false

## Set while this script — not the CPR phase — is the reason the camera is on
## the head anchor, so it is handed back only when we took it.
var _holds_camera: bool = false
## Restored with the camera. The ray is switched off while kneeling so the
## casualty under the crosshair cannot re-open the sequence on the same click
## that picks a pill.
var _ray_was_active: bool = true


func _ready() -> void:
	layer = 10

	_pointers = CasualtyPointersScript.new()
	_pointers.name = "CasualtyPointers"
	add_child(_pointers)
	_pointers.activated.connect(_on_pointer_activated)

	Events.casualty_actions_requested.connect(_on_requested)
	# Everything the sequence keys on is already a fact on the bus. No new
	# signals — events.gd is frozen.
	Events.step_completed.connect(func(id, _t): _on_step_completed(id))
	Events.breathing_checked.connect(func(_b): _refresh_pointers())
	Events.cpr_state_changed.connect(func(_f, _t): _refresh_pointers())
	# dev_menu.gd force-closes stale screens by setting this CanvasLayer's own
	# `visible` to false. The pointers are a child layer with their own
	# visibility, so mirror that here rather than leaving pills on screen with
	# nothing driving them.
	visibility_changed.connect(func(): if not visible: _stand_down())


## Every completed step refreshes the pills; one of them also closes a step.
func _on_step_completed(step_id: StringName) -> void:
	if step_id == &"send_for_help":
		_retire_fire_check()
	_refresh_pointers()


## The fire check's last moment, passed.
##
## Playtest: "just remove the check on fire pill and mark as not done." Failing
## it is what "not done" means here - the step stays in the debrief, named and
## scored as a miss, rather than sitting open to the end of the run where it
## reads as something still to come. Assessment.fail() is documented for exactly
## this: the moment it is certain the trainee has gone past a step.
##
## `is_resolved`, so a trainee who DID check for fire, and one who was already
## marked down for skipping it, are both left alone.
func _retire_fire_check() -> void:
	if Assessment.is_resolved(&"fire_checked"):
		return
	Assessment.fail(&"fire_checked",
		"The casualty was never checked for fire or residual arc contact."
		+ " That look comes first, before anything else is done to them.")


## CprStation calls this from begin_breathing_check(), to retire the modal card
## this script used to be. That card is gone, and the call now means only "stop
## offering to kneel" — it must NOT tear the sequence down, because the chest
## track still has work outstanding at that moment: the breathing check is
## assessed at the mouth, and the shirt has not been opened yet. Killing the
## pills here is what left the trainee in COMPRESSIONS_1 with a covered chest
## and nothing on screen to open it with.
##
## The pills retire themselves when no callout is available — see
## _refresh_pointers().
func suppress() -> void:
	suppressed = true
	if _holds_camera:
		# The spine owns the camera from here; drop the claim without moving it.
		_holds_camera = false
	_refresh_pointers()


## Kept for CprStation and dev_menu, which both ask. "Open" now means the
## sequence is live, whether or not the trainee is still kneeling.
func is_open() -> bool:
	return _sequence_active


## Whether a body pointer is on screen this frame. CasualtyInteractable goes
## quiet while the sequence owns the direction, and the HUD's bottom step pill
## stands down for the same reason - but both have to be able to tell the
## difference between "the pills are speaking" and "the sequence is nominally
## live with nothing drawn". Without that distinction a sequence whose pills
## had all been culled off screen left the trainee with no pill to click and
## no prompt to bring one back.
##
## `_sequence_active` was in this test and had to come out. It is the
## primary-survey sequence's own flag, and _refresh_pointers() draws the SPINE
## callouts while it is false - that is the whole point of the early branch at
## the top of it. So every spine beat that puts a pill on the body - "Open the
## shirt" between the sets, the post-shock pair, the recovery roll, the three
## injury pills - drew its pill and simultaneously reported that nothing was
## drawn. Both callers then spoke over it: the HUD's step pill named a step
## from earlier in the run at the bottom of the screen, and the casualty
## carried "Treat the casualty" at the crosshair, three directions at once.
##
## What is drawn is the only thing either caller wants to know, and
## CasualtyPointers.drawn_count() is documented as the answer to exactly that
## question. Ask it, and nothing else.
func has_visible_pointer() -> bool:
	return _pointers != null and _pointers.visible and _pointers.drawn_count() > 0


# --- open / close ------------------------------------------------------------

func _on_requested(casualty: Casualty) -> void:
	_casualty = casualty
	_sequence_active = true
	_refresh_pointers()
	_take_camera()
	_watch_camera()

	# Deliberately not gated on `suppressed`. That flag is set by
	# CprStation.begin_breathing_check(), and bailing here meant that once the
	# breathing check had started, standing up and interacting again could
	# never kneel the trainee back down — the casualty offered "Treat the
	# casualty" and the click did nothing, with the shirt still closed. There
	# is nothing left to protect: _refresh_pointers() stands the sequence down
	# on its own when no callout is available.

	# Deliberately NOT Events.open_ui(): that is the blocking-UI path, which
	# freezes the player and releases the mouse. These pointers are diegetic —
	# the mouse stays captured and they are picked with the crosshair like
	# everything else in the game (CPR_CONTRACT.md §4.0).


## Everything down: pills gone, camera back, ray back.
func _stand_down() -> void:
	_sequence_active = false
	if _pointers != null:
		_pointers.clear()
	if _holds_camera:
		_hand_back_camera()
	else:
		_restore_ray()
	Events.prompt_requested.emit("")


## [C] stands the trainee up and ends the sequence: pills cleared, camera and
## ray handed back, and the casualty prompts "Treat the casualty" again.
## Getting up to reach the radio is a step away from the casualty, so leaving
## body-anchored pills floating across the room read as stuck UI.
## Interacting with the casualty again kneels back down and re-offers whatever
## is still outstanding.
func _unhandled_input(event: InputEvent) -> void:
	if not _holds_camera:
		return
	if not event.is_action_pressed(&"crouch"):
		return
	get_viewport().set_input_as_handled()
	_stand_down()


func _player() -> Player:
	return get_tree().get_first_node_in_group(&"player") as Player


func _restore_ray() -> void:
	var player := _player()
	if player != null and player.interaction_ray != null:
		player.interaction_ray.active = _ray_was_active


# --- camera ------------------------------------------------------------------

## Drop the trainee onto the CPR phase's first camera anchor for the sequence.
## Reuses CprCameraRig rather than moving the player: the rig already owns
## taking the camera, the clamped look and the tweened handback, and using it
## here means the transition into the breathing check — which lands on this
## same anchor — is a no-op instead of a second camera move.
##
## Silently does nothing if the station has not built yet; the pointers are
## still usable from wherever the trainee is standing.
func _take_camera() -> void:
	if _holds_camera:
		return
	var rig := _camera_rig()
	var anchor := _menu_anchor()
	if rig == null or anchor == null:
		return

	var player := _player()
	if player != null and player.interaction_ray != null:
		_ray_was_active = player.interaction_ray.active
		player.interaction_ray.active = false
		player.interaction_ray.clear()

	_holds_camera = true
	# The clamp is per-state now (CprStation._yaw_limit_for) and the rig carries
	# whatever the last state set. This one is the primary survey, which is the
	# wide case: say so rather than inherit.
	rig.look_yaw_limit_deg = CprCameraRig.DEFAULT_LOOK_YAW_LIMIT
	rig.move_to(anchor)


func _hand_back_camera() -> void:
	_holds_camera = false
	var rig := _camera_rig()
	if rig == null or not rig.active:
		_restore_ray()
		return
	# Once the spine has left the primary survey the CPR phase owns this camera
	# and is already driving it to its own anchors — handing it back here would
	# yank the trainee to their feet in the middle of the breathing check.
	#
	# The test used to read `> STATE_EXPOSE_CHEST`, which was the same statement
	# while EXPOSE_CHEST was state 0 and the spine's idle. EXPOSE_CHEST is now
	# state 4, sitting between the first compression set and the AED, so that
	# test would have handed the camera back during BREATHING_CHECK,
	# AIRWAY_INSPECT, PULSE_CHECK and COMPRESSIONS_1 — every anchored beat of
	# the phase. STATE_PRIMARY_SURVEY (-1) is the only state this script may
	# release from, so the test is against the first real state instead.
	if _cpr_state() >= CprStation.STATE_BREATHING_CHECK:
		return
	# The ray comes back with the camera, not before it: restoring it now would
	# let the trainee hover things through a view still flying back to their
	# own eyes.
	rig.released.connect(_restore_ray, CONNECT_ONE_SHOT)
	rig.release_smooth()


## The pills come down whenever the trainee leaves the camera anchor, however
## they left it.
##
## [C] does not always reach this script: once begin_breathing_check() has run,
## suppress() has dropped `_holds_camera`, so _unhandled_input() early-returns
## and CprStation._handle_stance_key() does the standing up instead. The pills
## stayed up through that — body-anchored callouts floating over the room while
## the trainee walked off to the radio. `released` is the one signal both routes
## go through, so it is the honest place to hang this.
func _watch_camera() -> void:
	var rig := _camera_rig()
	if rig == null or rig.released.is_connected(_on_camera_released):
		return
	rig.released.connect(_on_camera_released)


func _on_camera_released() -> void:
	if not _sequence_active:
		return
	# The shared rule, same one the panel and the hands read: not at an anchor
	# means not treating the casualty. `released` can fire while the rig is
	# already on its way back down, so the flag is what decides, not the signal.
	var station := CprStation.get_current()
	if station != null and station.trainee_at_anchor():
		return
	_stand_down()


func _camera_rig() -> CprCameraRig:
	var station := CprStation.get_current()
	return station.camera_rig if station != null else null


## The pose the survey is read from, which is not one pose.
##
## Opens wide - the first two questions are "is this scene safe" and "are they
## responsive", and the pills for them sit at opposite ends of the body. Once
## the response check is answered, everything left is at the head, so the survey
## leans in. See CprRig.head_close_pos.
##
## The move is issued from _on_pointer_activated() when the response pill is
## taken, because nothing else re-enters this beat: the menu holds the camera
## for the whole survey and _take_camera() has already run by then.
func _menu_anchor() -> Marker3D:
	var rig := _cpr_rig()
	if rig == null:
		return null
	return rig.survey_anchor(Assessment.is_complete(&"check_response"))


## Re-issues the survey camera move after something changed which anchor
## _menu_anchor() picks. No-op unless the menu is actually holding the camera:
## if the trainee is standing, the survey does not get to move them.
func _resettle_camera() -> void:
	if not _holds_camera:
		return
	var rig := _camera_rig()
	var anchor := _menu_anchor()
	if rig != null and anchor != null:
		rig.move_to(anchor)


func _cpr_rig() -> CprRig:
	return CprGhost.find_node(get_tree().current_scene, CHEST_ANCHOR_NAME) as CprRig


func _cpr_state() -> int:
	var station := CprStation.get_current()
	return station.current_state if station != null else -1


# --- body pointers -----------------------------------------------------------

## Rebuild the visible callout set from what the trainee has actually done.
## Cheap, and driven off signals rather than polled, so it can be called from
## anywhere something might have changed.
func _refresh_pointers() -> void:
	if _pointers == null:
		return

	# The body is on its side for the airway inspection. Nothing offered on this
	# layer is a thing you do to a rolled casualty, and the beat is scripted and
	# three seconds long - roll, look, roll back - so there is nothing for the
	# trainee to do in it but watch.
	#
	# Playtest: "when checking for blockage (recovery position) remove all
	# interaction pills until he's back in supine." It was "Start compressions"
	# that stayed up, whose rule is an upper bound on the spine state and
	# AIRWAY_INSPECT is under it; taking it there hands a rolled body to the
	# compression minigame.
	#
	# Returning BEFORE the _sequence_active branch, so it covers the spine's own
	# callouts as well, and WITHOUT _stand_down(): standing the sequence down
	# here would retire it for good and the trainee would come back supine at
	# the pulse check with no pills at all. That exact fault is why
	# _is_available() tests State.RECOVERY rather than the pose - see its
	# docstring - and it is the reason this is a clear() and an early return
	# rather than another rule down there.
	if _cpr_state() == CprStation.STATE_AIRWAY_INSPECT:
		_pointers.clear()
		return

	if not _sequence_active:
		# The casualty sequence is stood down, but the spine's own beats outlive
		# it: open the shirt between the compression sets, then resume
		# compressions or check for signs of life after the shock. The CPR spine
		# owns the camera at that point and every anchor is readable from it.
		var spine := _spine_callouts()
		if spine.is_empty():
			_pointers.clear()
		else:
			_pointers.set_callouts(spine)
		return

	# A choice card owns the moment: no pills, so the screen carries one live
	# direction until the card is answered.
	if choice_hold:
		_pointers.clear()
		return

	var live: Array = []
	for callout in CALLOUTS:
		if _is_available(callout.get("available", &"")):
			live.append(callout)
	# A spine beat can be live while the primary-survey sequence still has work
	# outstanding — EXPOSE_CHEST arrives with the fire check possibly unanswered
	# — so the two sets are merged rather than chosen between.
	for callout in _spine_callouts():
		if not live.has(callout):
			live.append(callout)

	# Nothing left to point at means the CPR minigame owns the casualty now.
	if live.is_empty():
		_stand_down()
		return
	_pointers.set_callouts(live)


## Every rule below describes an action taken on a casualty lying on his back:
## looking in the mouth, tilting the head, kneeling on the sternum. None of
## them is a thing you do to a body that has been rolled onto its side, and
## the pills are the instruction - offering one there teaches the wrong move.
##
## Found in playtest: clicking the body during the injury survey re-opened the
## primary-survey sequence on the rolled casualty and put "Open the airway"
## back on screen. Nadir reported the same hole with "Start compressions",
## which additionally breaks the spine if taken - it hands the body to the
## compression minigame mid-roll.
##
## Gated here, at the one place every CALLOUTS rule passes through, rather than
## rule by rule: the condition is a property of the body's pose, not of any
## individual step, and a per-rule test would be six chances to miss one. The
## spine's own callouts are not filtered by this function and do not want to be
## - the recovery roll and the injury survey are the beats that happen WHILE
## the body is rolled.
##
## The test is the casualty's STATE, not in_recovery_pose(). Those two are not
## the same question and the difference stranded a run: the airway inspection
## rolls the body too, and it is a transient - roll, look, roll back, inside the
## primary survey. Asking the pose there made every callout unavailable for the
## length of the dwell, and a refresh landing in that window found an empty set
## and called _stand_down(), which retires the sequence for good. The trainee
## came back supine at the pulse check with no pills and no way to get them
## short of standing up and crouching again. State.RECOVERY is the beat this
## rule is actually about, and the inspection never enters it.
func _is_available(rule: StringName) -> bool:
	if _casualty == null:
		return false
	if _casualty.state == Casualty.State.RECOVERY:
		return false
	var state := _cpr_state()
	match rule:
		&"fire":
			# Client item 4, and the first thing in the primary survey: the
			# procedure resource puts `fire_checked` between `supply_isolated`
			# and `check_response`.
			#
			# It also has a LAST moment, and that is the second half of the
			# rule. Playtest: "i delayed checking not on fire and now can't
			# access the pill because of the anchor - at that point (after
			# calling help) just remove the check on fire pill and mark as not
			# done." Checking for fire is the very first look at the casualty;
			# a trainee who has already gone through the response check and the
			# call for help is past it, and the pill hanging on from there is
			# an out-of-order instruction sharing the frame with the pills that
			# are in order. _retire_fire_check() records the miss.
			return not Assessment.is_resolved(&"fire_checked") \
				and not Assessment.is_resolved(&"send_for_help")
		&"response":
			return not Assessment.is_complete(&"check_response")
		&"airway":
			return Assessment.is_complete(&"check_response") and not _casualty.airway_open
		&"breathing":
			# Only while the spine is still armed but not started. Past that the
			# check is either running or already done. The gate used to name
			# EXPOSE_CHEST, which was state 0 and the spine's idle; the idle is
			# now STATE_PRIMARY_SURVEY and EXPOSE_CHEST has moved to after the
			# first compression set.
			return _casualty.airway_open and state == CprStation.STATE_PRIMARY_SURVEY
		&"blockage":
			# Client item 6: roll and look for an obstruction, between the
			# breathing check and the pulse check. Offered only from
			# BREATHING_CHECK, because that is the only state
			# CprStation.begin_airway_inspect() will move out of.
			return (state == CprStation.STATE_BREATHING_CHECK
				and Assessment.is_complete(&"breathing_checked")
				and not Assessment.is_complete(&"airway_inspected"))
		&"compressions":
			# The chest requirement is GONE. The client asked for the first set
			# with the shirt on and the shirt opened afterwards for the pads
			# (docs/OVERNIGHT_PLAN.md §1 item 5), so requiring a bare chest here
			# would have made the beat unreachable.
			#
			# Nothing else replaces it: going straight here skips DRSABCD's B,
			# C and the pulse check, which is a mistake the trainee is allowed
			# to make and which the debrief will show. The upper bound is what
			# retires the pill once the set is behind them.
			return state <= CprStation.STATE_COMPRESSIONS_1
		_:
			return false


## Callouts that belong to a CPR spine beat rather than to the primary-survey
## sequence, and are therefore the ones allowed to show while the sequence is
## stood down. The spine owns the camera through all of them.
##
## EXPOSE_CHEST is here for exactly that reason: the shirt now comes off between
## the two compression sets, and taking "Start compressions" calls _stand_down().
## Left in CALLOUTS it would have been unreachable — the beat the whole reorder
## exists for, with no pill to take it.
##
## The post-shock pair hang off one moment — the shock has landed and the
## compression minigame has not been re-armed — so they are offered together,
## and the signs-of-life one retires as soon as either is taken: once
## compressions are running the question has been answered.
func _spine_callouts() -> Array:
	var station := CprStation.get_current()
	if station == null:
		return []
	match station.current_state:
		CprStation.STATE_EXPOSE_CHEST:
			var body := _body()
			if body != null and body.chest_exposed:
				return []
			return [EXPOSE_CHEST_CALLOUT]
		CprStation.STATE_COMPRESSIONS_2:
			if station.compressions_armed:
				return []
			var live: Array = [RESUME_COMPRESSIONS_CALLOUT]
			if not _signs_checked:
				live.append(SIGNS_OF_LIFE_CALLOUT)
			return live
		CprStation.STATE_RECOVERY_ROLL:
			return [RECOVERY_ROLL_CALLOUT]
		CprStation.STATE_INJURY_SURVEY:
			var sites: Array = []
			for callout: Dictionary in INJURY_CALLOUTS:
				if not _injuries_seen.has(callout["id"]):
					sites.append(callout)
			return sites
	return []


## The casualty, whether or not the sequence was ever opened on one. The spine
## callouts can be the first pill of a run if the trainee reached compressions
## without interacting with the body (the dev warps do exactly that), so they
## cannot rely on `_casualty` having been handed over.
func _body() -> Casualty:
	if _casualty != null and is_instance_valid(_casualty):
		return _casualty
	return get_tree().get_first_node_in_group(&"casualty") as Casualty


## A pill click performs its own action. Two of them have no Casualty method
## behind them and hand over instead:
##
##   check_breathing     starts the CPR spine's hold-to-observe. This is now
##                       the only thing that starts it — main.gd used to fire
##                       it off `chest_exposed`, which forced the shirt to be
##                       opened before the airway could be assessed.
##   inspect_airway      starts the spine's roll-and-look beat. Same shape: the
##                       station owns the dwell and the roll back, so this only
##                       opens the door.
##   start_compressions  is a hand-over, not an action: the compressions
##                       themselves are the CPR minigame's, so this dismisses
##                       the pointers and gets out of its way.
##   expose_chest        is a Casualty method like the CALLOUTS entries, but it
##                       is a spine callout rather than a CALLOUTS one, so the
##                       generic loop at the bottom never sees it.
func _on_pointer_activated(id: StringName) -> void:
	match id:
		&"check_breathing":
			var station := CprStation.get_current()
			if station != null:
				station.begin_breathing_check()
			_refresh_pointers()
			return
		&"inspect_airway":
			var inspecting := CprStation.get_current()
			if inspecting != null:
				inspecting.begin_airway_inspect()
			_refresh_pointers()
			return
		&"expose_chest":
			var body := _body()
			if body != null:
				body.expose_chest()
			# expose_chest() completes `chest_exposed`, which is what advances
			# the spine to AED_FETCH (CprStation._on_step_completed). The
			# refresh then finds no spine callout and clears the pill.
			_refresh_pointers()
			return
		&"recovery_position":
			# The station owns the transition; Casualty owns the roll, the mesh
			# swap and the step. It refuses on a casualty who is not breathing,
			# in which case the pill stays up and a violation is recorded.
			var rolling := CprStation.get_current()
			if rolling != null:
				rolling.roll_to_recovery()
			_refresh_pointers()
			return
		&"injury_hands", &"injury_head", &"injury_legs":
			_injuries_seen[id] = true
			var surveying := CprStation.get_current()
			if surveying != null:
				surveying.survey_injury(_INJURY_SITE_FOR_ID[id])
			# The station advances to HANDOVER itself if this was the finding;
			# either way the pill has been spent and the set is rebuilt.
			_refresh_pointers()
			return
		&"start_compressions":
			# The hand-over. Nothing about the compression minigame is on
			# screen until this is taken — see CprStation.compressions_armed.
			# Taken twice in a run: once into the first set, once to resume
			# after the shock.
			# Second lock, for the same reason CasualtyInteractable keeps one
			# on WAITING: the availability gate above decides what is OFFERED,
			# and this decides what a click can DO. A pill already on screen
			# when the body rolls would otherwise still be live for a frame.
			var rolled := _body()
			if rolled != null and rolled.state == Casualty.State.RECOVERY:
				Events.center_message_requested.emit(
					"He is in the recovery position and breathing. Roll him onto"
					+ " his back before starting compressions.",
					Tokens.WARNING, 3.5)
				_refresh_pointers()
				return
			var starting := CprStation.get_current()
			if starting != null:
				# Drives the spine forward itself when the breathing check was
				# skipped: the state no longer arrives on its own. A no-op
				# post-shock, where the spine is already in COMPRESSIONS_2.
				starting.begin_compressions_early()
				starting.arm_compressions()
			# The post-shock question is settled either way: resuming is the
			# correct answer to it, so the signs-of-life pill does not come
			# back when the set ends. Only post-shock, though — the same pill
			# starts the first set, and retiring the gotcha there meant it was
			# never offered after the shock at all.
			if _cpr_state() == CprStation.STATE_COMPRESSIONS_2:
				_signs_checked = true
			_stand_down()
			return
		&"signs_of_life":
			# The plausible wrong move after a shock. Nothing is blocked and
			# nothing is completed: the click answers the question, the pill
			# retires, and the transcript keeps the choice for the debrief.
			_signs_checked = true
			Events.center_message_requested.emit(
				"No signs of life.", Tokens.ATTENTION, 2.5)
			Events.log_action(
				&"resuscitation",
				"Checked for signs of life after the shock",
				&"warning",
				"Compressions should resume immediately after a shock - no signs-of-life check.")
			_refresh_pointers()
			return

	for callout in CALLOUTS:
		if callout.get("id", &"") != id:
			continue
		var method: StringName = callout.get("method", &"")
		if method != &"" and _casualty != null and _casualty.has_method(method):
			_casualty.call(method)
		_refresh_pointers()
		if id == &"check_response":
			# The survey's one camera move: everything after the response check
			# is at the head, so the shot leans in. Issued here rather than in
			# _refresh_pointers() so it is a response to the trainee's click
			# and happens once, not a thing the camera might do at any refresh.
			_resettle_camera()
		return
