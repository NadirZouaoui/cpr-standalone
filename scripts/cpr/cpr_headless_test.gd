extends Node

## Headless regression test for the CPR phase's state spine —
## CPR_CONTRACT.md section 1, driven end-to-end over the Events bus.
##
## Run:
##   & "C:\Program Files\Godot.exe" --headless --path <project> res://scripts/cpr/cpr_headless_test.tscn
##
## Instances the real main scene — so CprRig, Player, and the casualty
## meshes the CPR stations bind to all exist for real, exactly as
## tools/check_spawn_gate.gd already does — then adds one CprStation the
## same way CPR_CONTRACT.md section 9's integration seam describes, and
## walks the whole spine by emitting the Events facts a real playthrough
## would produce, in order (per CPR_AGENTS.md's Agent E brief). Asserts
## COMPLETE is reached and `cpr_completed` fires with a populated metrics
## dictionary. Exit code 0 on success, 1 on failure.
##
## REWRITTEN 3 Sep 2026 for the client's reordered spine
## (docs/OVERNIGHT_PLAN.md §2). What changed, and what each new assertion is
## guarding, because every one of them is here to fail if the reorder is
## reverted:
##
##   * The spine is 14 states, not 9, and `enter_cpr_phase()` no longer enters
##     one at all — it arms the phase at STATE_PRIMARY_SURVEY (-1) and waits
##     for a body pointer. EXPOSE_CHEST used to be state 0 and used to be that
##     idle.
##   * AIRWAY_INSPECT and PULSE_CHECK are new beats between the breathing check
##     and the first compression set (client items 6 and 7).
##   * The first compression set runs with the shirt ON and hands off to
##     EXPOSE_CHEST, not to AED_FETCH (client item 5). The chest is opened
##     between the sets, and `step_completed(chest_exposed)` is EXPOSE_CHEST's
##     only exit.
##   * Casualty.attach_pads()'s `chest_exposed` guard is now reachable, so it
##     is tested: before the reorder the shirt always came off first and the
##     guard was dead code.
##
## OWNED BY AGENT E · STATION — see CPR_CONTRACT.md section 7.

const MAIN := preload("res://main.tscn")

const REQUIRED_METRIC_KEYS := [
	"total_compressions", "pct_in_depth", "pct_in_rate",
	"time_to_breathing_check", "time_to_first_compression", "time_to_shock",
	"pad_errors", "pads_correct", "assisted",
]

## The four ids retired from lvr_cpr_procedure.tres (PROJECT_STATUS.md §6.4,
## docs/OVERNIGHT_PLAN.md §2). Every call that completed one has been deleted
## from casualty.gd; this asserts none of them came back, since a returning
## call is a silent push_warning no-op that nothing else would catch.
const RETIRED_STEP_IDS := [
	&"compressions_started", &"compressions_resumed",
	&"pads_placed", &"shock_delivered",
]

var _failures: int = 0
var _completed_fired: bool = false
var _completed_metrics: Dictionary = {}


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	# Let ControlRoom's .blend instance settle before anything binds to it.
	await get_tree().process_frame
	await get_tree().process_frame

	var station := CprStation.new()
	station.name = "CprStation"
	add_child(station)
	# Let every call_deferred("_build") binder in the CPR file set
	# (CprStation's own, plus everything it instances) resolve.
	await get_tree().process_frame
	await get_tree().process_frame

	Events.cpr_completed.connect(_on_cpr_completed)

	var casualty := get_tree().get_first_node_in_group(&"casualty") as Casualty
	_ok(casualty != null, "the casualty is in the scene")

	_check_state_order()
	_check_retired_ids()
	# Before the walk, while the shirt is still closed — the offer this asserts
	# only exists in that window.
	_check_pointer_offers(station, casualty)
	_check_recovery_refuses_without_rosc(station, casualty)

	print("\nDriving the CPR spine")

	# --- primary survey -------------------------------------------------------
	station.enter_cpr_phase()
	_ok(station.current_state == CprStation.STATE_PRIMARY_SURVEY,
		"enter_cpr_phase() -> PRIMARY_SURVEY (arms, does not enter a state)")
	_ok(station.is_phase_entered(), "enter_cpr_phase() -> phase entered")

	# Client item 4. One observation beat during the primary survey, outcome
	# always clear. It is the casualty's, not the station's, so it is driven
	# directly the way the body pointer does.
	if casualty != null:
		casualty.check_for_fire()
	_ok(Assessment.is_complete(&"fire_checked"), "check_for_fire() -> fire_checked complete")
	_ok(station.current_state == CprStation.STATE_PRIMARY_SURVEY,
		"check_for_fire() does not move the spine")

	# --- breathing check ------------------------------------------------------
	# The door into the spine. Taken by the "Check for breathing" body pointer;
	# stood in for here.
	station.begin_breathing_check()
	_ok(station.current_state == CprStation.STATE_BREATHING_CHECK,
		"begin_breathing_check() -> BREATHING_CHECK")

	# breathing_checked records the check and stops. Completing the hold used
	# to advance the spine on its own, which dropped the trainee into the
	# compression beat — camera, panel and metronome — with no decision in
	# between. A body pointer is the only way on now.
	Events.breathing_checked.emit(false)
	_ok(station.current_state == CprStation.STATE_BREATHING_CHECK,
		"breathing_checked -> stays in BREATHING_CHECK")
	# Nothing about a repeat should move the spine either. (The elapsed time
	# itself is not asserted: this whole test runs inside one _ready(), so
	# every stamp is 0.0.)
	Events.breathing_checked.emit(false)
	_ok(station.current_state == CprStation.STATE_BREATHING_CHECK,
		"breathing_checked twice -> still BREATHING_CHECK")

	# --- airway inspection (NEW, client item 6) -------------------------------
	# Roll to the side, look for a blockage, roll back. The roll is a cold mesh
	# swap and degrades to a message when Casualty_Recovery_Posed has not been
	# authored — which is the path this asserts, because it is the one that
	# runs until the Blender work lands.
	station.begin_airway_inspect()
	_ok(station.current_state == CprStation.STATE_AIRWAY_INSPECT,
		"begin_airway_inspect() -> AIRWAY_INSPECT")
	_ok(Assessment.is_complete(&"airway_inspected"),
		"airway inspection -> airway_inspected complete")

	# finish_airway_inspect() is public precisely so this does not have to sleep
	# out the 3 s dwell timer.
	station.finish_airway_inspect()
	_ok(station.current_state == CprStation.STATE_PULSE_CHECK,
		"finish_airway_inspect() -> PULSE_CHECK")
	if casualty != null:
		_ok(not casualty.in_recovery_pose(),
			"finish_airway_inspect() -> casualty rolled back")

	# --- pulse check (NEW, client item 7) -------------------------------------
	# The beat that licenses compressions. It reports through a direct call
	# rather than an Events fact — nothing else in the project needs to know.
	station.complete_pulse_check()
	_ok(Assessment.is_complete(&"pulse_checked"),
		"complete_pulse_check() -> pulse_checked complete")
	_ok(station.current_state == CprStation.STATE_PULSE_CHECK,
		"complete_pulse_check() leaves the decision to the trainee")

	# --- first compression set, SHIRT ON --------------------------------------
	station.begin_compressions_early()
	_ok(station.current_state == CprStation.STATE_COMPRESSIONS_1,
		"begin_compressions_early() -> COMPRESSIONS_1")
	if casualty != null:
		_ok(not casualty.chest_exposed,
			"COMPRESSIONS_1 runs with the shirt still closed")

	# The pads cannot go on through clothing, and until the reorder that guard
	# was unreachable. Now it is the thing that makes EXPOSE_CHEST matter.
	if casualty != null:
		casualty.attach_pads()
		_ok(not casualty.pads_attached,
			"attach_pads() refuses through the shirt")

	# THE ASSERTION THE WHOLE REORDER TURNS ON. This used to read AED_FETCH.
	Events.compression_set_completed.emit(30, false)
	_ok(station.current_state == CprStation.STATE_EXPOSE_CHEST,
		"compression_set_completed(30, false) -> EXPOSE_CHEST (not AED_FETCH)")

	# --- open the shirt, between the sets -------------------------------------
	# EXPOSE_CHEST's only exit is the checklist step: there is no CPR fact on
	# the bus for the shirt, so the station listens for step_completed.
	if casualty != null:
		casualty.expose_chest()
	_ok(Assessment.is_complete(&"chest_exposed"), "expose_chest() -> chest_exposed complete")
	_ok(station.current_state == CprStation.STATE_AED_FETCH,
		"chest_exposed -> AED_FETCH")
	if casualty != null:
		casualty.attach_pads()
		_ok(casualty.pads_attached, "attach_pads() succeeds once the chest is bare")

	# --- AED ------------------------------------------------------------------
	Events.aed_picked_up.emit()
	_ok(station.current_state == CprStation.STATE_AED_DEPLOY, "aed_picked_up -> AED_DEPLOY")

	Events.aed_placed.emit()
	_ok(station.current_state == CprStation.STATE_PAD_PLACEMENT, "aed_placed -> PAD_PLACEMENT")

	Events.aed_pad_placed.emit(0, true, "PadSite_Correct_Upper")
	_ok(station.current_state == CprStation.STATE_PAD_PLACEMENT, "one pad placed -> still PAD_PLACEMENT")

	Events.aed_pad_placed.emit(1, true, "PadSite_Correct_Lower")
	_ok(station.current_state == CprStation.STATE_SHOCK, "two pads placed -> SHOCK")

	# SHOCK must not offer the kneel-back-down toggle. It used to, and the pair
	# of it and ShockButton._on_activate()'s `trainee_at_anchor()` check was a
	# run-ending trap: cpr_station.gd told the trainee to crouch back onto
	# Anchor_Shock "within reach of the unit" after standing clear, and pressing
	# the button there was scored as discharging into a rescuer in contact with
	# the casualty. Reproduced in game: stand, crouch, press, EXERCISE FAILED.
	#
	# Asserted here rather than left to the docstrings, because the two files
	# disagreeing is exactly how it happened. The trainee still stands up out of
	# SHOCK - that is the stand-clear - they just cannot kneel back into it.
	_ok(not CprStation.STANCE_TOGGLE_STATES.has(CprStation.STATE_SHOCK),
		"SHOCK does not offer the kneel-back toggle that made the shock fatal")
	_ok(CprStation.STAND_UP_STATES.has(CprStation.STATE_SHOCK),
		"SHOCK still requires standing up - that is the stand-clear")

	station.compressions_armed = true
	Events.aed_shock_delivered.emit()
	_ok(station.current_state == CprStation.STATE_COMPRESSIONS_2, "aed_shock_delivered -> COMPRESSIONS_2")
	# The shock hands the decision back to the body pointers: resuming is the
	# trainee taking "Start compressions" again, next to the signs-of-life
	# gotcha, not something the state does to them.
	_ok(not station.compressions_armed, "aed_shock_delivered -> compressions disarmed")

	# --- recovery, injuries, handover (client item 8) --------------------------
	# The run no longer ends at the second set.
	Events.compression_set_completed.emit(30, false)
	_ok(station.current_state == CprStation.STATE_RECOVERY_ROLL,
		"compression_set_completed(30, false) -> RECOVERY_ROLL (not COMPLETE)")
	_ok(not _completed_fired, "the phase does not finish at the second set")
	_ok(Assessment.is_complete(&"signs_of_life"),
		"ROSC -> signs_of_life complete")
	if casualty != null:
		_ok(casualty.breathing, "ROSC -> the casualty is breathing again")
		_ok(SimState.phase == SimState.Phase.RECOVERY, "ROSC -> phase is RECOVERY")

	# The roll is the trainee's decision, taken from a body pointer. The station
	# refuses to advance if Casualty.roll_to_recovery() refused.
	station.roll_to_recovery()
	_ok(Assessment.is_complete(&"recovery_position"),
		"roll_to_recovery() -> recovery_position complete")
	_ok(station.current_state == CprStation.STATE_INJURY_SURVEY,
		"roll_to_recovery() -> INJURY_SURVEY")

	# The two clear sites do not end the survey; the burn at the contact point
	# does. That asymmetry is the whole beat — three identical findings would be
	# three clicks rather than a survey.
	_ok(not station.survey_injury(&"head"), "the head and neck are clear")
	_ok(not station.survey_injury(&"legs"), "the legs and feet are clear")
	_ok(station.current_state == CprStation.STATE_INJURY_SURVEY,
		"a clear site does not end the survey")
	_ok(not Assessment.is_complete(&"injuries_checked"),
		"injuries_checked waits for the finding")

	_ok(station.survey_injury(&"hands"), "the hands carry the entry burn")
	_ok(Assessment.is_complete(&"injuries_checked"),
		"the finding -> injuries_checked complete")
	_ok(station.current_state == CprStation.STATE_HANDOVER,
		"the finding -> HANDOVER")

	# The help gate. Nothing in this run called 000, so no ambulance is coming:
	# the station stalls at HANDOVER rather than inventing one, and holds the
	# trainee there with a message until they make the call.
	_ok(station._awaiting_help_call,
		"HANDOVER without 000 -> the station waits for the call")
	_ok(not Assessment.is_complete(&"handover"),
		"HANDOVER without 000 -> no ambulance arrives")

	# The last chance. Calling it now releases the beat, but the call is graded
	# as late rather than quietly forgiven.
	Assessment.complete(&"send_for_help")
	_ok(not station._awaiting_help_call,
		"the late 000 call -> the station stops waiting")
	var flagged := false
	for v in Assessment.violations:
		if v.get("step_id", &"") == &"send_for_help":
			flagged = true
	_ok(flagged, "the late 000 call is flagged, not forgiven")
	_ok(Assessment.is_complete(&"handover"), "HANDOVER -> handover complete")
	_ok(not _completed_fired, "the phase does not finish before the handover dwell")

	# finish_handover() is public for the same reason finish_airway_inspect()
	# is: so this does not have to sleep out the siren.
	station.finish_handover()
	_ok(station.current_state == CprStation.STATE_COMPLETE, "finish_handover() -> COMPLETE")

	print("\ncpr_completed")
	_ok(_completed_fired, "cpr_completed fired")
	if _completed_fired:
		_check_metrics()
	_check_handover_asset()

	_check_pointer_retirement(station)
	_check_rig_anchors()
	_check_graceful_degradation(casualty)

	if _failures == 0:
		print("\ncpr_headless_test: all assertions passed.")
	else:
		printerr("\ncpr_headless_test: %d assertion(s) FAILED." % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _on_cpr_completed(metrics: Dictionary) -> void:
	_completed_fired = true
	_completed_metrics = metrics


## The reorder itself, asserted as an ordering rather than as fourteen magic
## numbers — so the test says what the client asked for rather than restating
## the constant table back to itself. Reverting the renumber fails this without
## anything having to be driven.
func _check_state_order() -> void:
	print("\nState order (docs/OVERNIGHT_PLAN.md §2)")
	_ok(CprStation.STATE_PRIMARY_SURVEY < CprStation.STATE_BREATHING_CHECK,
		"PRIMARY_SURVEY is the idle, below every real state")
	_ok(CprStation.STATE_BREATHING_CHECK < CprStation.STATE_AIRWAY_INSPECT,
		"BREATHING_CHECK before AIRWAY_INSPECT")
	_ok(CprStation.STATE_AIRWAY_INSPECT < CprStation.STATE_PULSE_CHECK,
		"AIRWAY_INSPECT before PULSE_CHECK")
	_ok(CprStation.STATE_PULSE_CHECK < CprStation.STATE_COMPRESSIONS_1,
		"PULSE_CHECK before COMPRESSIONS_1")
	# Client item 5, the walked-back one: compressions first, shirt second.
	_ok(CprStation.STATE_COMPRESSIONS_1 < CprStation.STATE_EXPOSE_CHEST,
		"COMPRESSIONS_1 before EXPOSE_CHEST")
	_ok(CprStation.STATE_EXPOSE_CHEST < CprStation.STATE_AED_FETCH,
		"EXPOSE_CHEST before AED_FETCH")
	_ok(CprStation.STATE_COMPRESSIONS_2 < CprStation.STATE_RECOVERY_ROLL,
		"COMPRESSIONS_2 before RECOVERY_ROLL")
	_ok(CprStation.STATE_HANDOVER < CprStation.STATE_COMPLETE,
		"HANDOVER before COMPLETE")
	_ok(CprStation.STATE_NAMES.size() == 14, "fourteen named states")
	for state: int in CprStation.STATE_NAMES.keys():
		if not _ok(CprStation.STATE_NAMES[state] != "", "state %d is named" % state):
			break


## docs/OVERNIGHT_PLAN.md §2: four dead ids stay dead and their calls are gone.
## Assessment.complete() on an unknown id only push_warnings, so a call that
## crept back would be invisible without this.
func _check_retired_ids() -> void:
	print("\nRetired step ids")
	for id: StringName in RETIRED_STEP_IDS:
		_ok(not Assessment.steps.has(id), "'%s' is not in the procedure" % id)
		_ok(not Assessment.is_complete(id), "'%s' was never completed" % id)


## The beats that only a body pointer can reach, asserted BEFORE the spine walk
## — while the shirt is still closed, which is the only window in which the
## offers under test exist.
##
## scripts/ui/casualty_action_menu.gd owns them, and the reorder moved "Open the
## shirt" out of its always-available set into a spine callout: it now has
## exactly one moment, between the two compression sets. Half-done, that move
## leaves the shirt with no pill at all and a live run stalls at EXPOSE_CHEST
## with nothing on screen to take. Headless cannot click a pill, so this asserts
## the offer, which is the part that broke.
##
## `_is_available` and `_spine_callouts` are read directly. They are private,
## and this is a white-box test on purpose: the alternative is a rendered pill
## and a synthetic click, neither of which exists headless.
func _check_pointer_offers(station: CprStation, casualty: Casualty) -> void:
	print("\nBody pointers")
	var menu := CprGhost.find_node(get_tree().current_scene, "CasualtyActions")
	if not _ok(menu != null, "the CasualtyActions layer is in main.tscn"):
		return
	if not _ok(menu.has_method("_spine_callouts"), "the menu offers spine callouts"):
		return
	# The sequence is normally handed the casualty when the trainee interacts
	# with the body; nothing has here.
	menu.set("_casualty", casualty)

	var previous := station.current_state

	station.debug_jump_to_state(CprStation.STATE_COMPRESSIONS_1)
	_ok(_offered_ids(menu).is_empty(), "COMPRESSIONS_1 offers no spine pill")
	# Client item 5's other half: the shirt is no longer a prerequisite of the
	# compression pill. It was, and leaving it would have made the first set
	# unreachable in the reordered spine.
	_ok(menu.call("_is_available", &"compressions"),
		"'Start compressions' is offered with the shirt closed")

	station.debug_jump_to_state(CprStation.STATE_EXPOSE_CHEST)
	_ok(_offered_ids(menu).has(&"expose_chest"),
		"EXPOSE_CHEST offers the shirt pill")
	_ok(not menu.call("_is_available", &"compressions"),
		"'Start compressions' retires once the first set is behind them")

	station.debug_jump_to_state(CprStation.STATE_COMPRESSIONS_2)
	station.compressions_armed = false
	var ids := _offered_ids(menu)
	_ok(ids.has(&"start_compressions"), "COMPRESSIONS_2 offers the resume pill")
	_ok(ids.has(&"signs_of_life"), "COMPRESSIONS_2 offers the signs-of-life gotcha")

	# Client item 8's three beats, each of which is only reachable through a
	# pill. Un-offered, the run ends at the second compression set.
	station.debug_jump_to_state(CprStation.STATE_RECOVERY_ROLL)
	_ok(_offered_ids(menu).has(&"recovery_position"),
		"RECOVERY_ROLL offers the recovery-position pill")

	station.debug_jump_to_state(CprStation.STATE_INJURY_SURVEY)
	ids = _offered_ids(menu)
	_ok(ids.size() == 3, "INJURY_SURVEY offers three sites")
	_ok(ids.has(&"injury_hands"), "the injury survey offers the hands")

	station.debug_jump_to_state(CprStation.STATE_HANDOVER)
	_ok(_offered_ids(menu).is_empty(),
		"HANDOVER asks nothing of the trainee")

	# Client item 6: the airway-inspection pill exists and is gated on the
	# breathing check having answered, since BREATHING_CHECK is the only state
	# begin_airway_inspect() will move out of.
	station.debug_jump_to_state(CprStation.STATE_BREATHING_CHECK)
	_ok(not menu.call("_is_available", &"blockage"),
		"the airway-blockage pill waits for the breathing check")

	station.current_state = previous


## Rolling a casualty who is not breathing into the recovery position is the one
## thing the recovery beat refuses outright, and it is the reason the station
## reads Casualty.state rather than the checklist step: the step can be
## pre-completed by a dev warp, and then a refused roll would read as a
## successful one and the spine would walk on past a beat that never happened.
##
## Driven before the walk, when the casualty is still DOWN. It leaves one
## synthetic violation on the run's transcript; nothing here reads it.
func _check_recovery_refuses_without_rosc(station: CprStation, casualty: Casualty) -> void:
	print("\nRecovery position, refused")
	if not _ok(casualty != null, "a casualty to refuse with"):
		return
	var previous := station.current_state
	var violations_before: int = Assessment.violations.size()

	station.debug_jump_to_state(CprStation.STATE_RECOVERY_ROLL)
	station.roll_to_recovery()
	_ok(casualty.state != Casualty.State.RECOVERY,
		"a casualty who is not breathing is not rolled")
	_ok(not Assessment.is_complete(&"recovery_position"),
		"a refused roll does not earn recovery_position")
	_ok(station.current_state == CprStation.STATE_RECOVERY_ROLL,
		"a refused roll does not advance the spine")
	_ok(Assessment.violations.size() > violations_before,
		"a refused roll is recorded as a violation")

	station.current_state = previous


## Ids of whatever the menu would draw as spine callouts right now.
func _offered_ids(menu: Node) -> Array:
	var ids: Array = []
	for callout: Dictionary in menu.call("_spine_callouts"):
		ids.append(callout.get("id", &""))
	return ids


## The HANDOVER cue. It is a PLACEHOLDER generated by
## tools/gen_ambulance_arrive.py, and the beat must survive its absence — that
## is aed_voice.gd's asset-optional contract (CPR_CONTRACT.md §9 seam 4) and the
## plan asks for it by name. The spine walk above already proved the beat runs;
## this reports which of the two paths it ran down, so a missing asset shows up
## in the log rather than as a silent handover nobody notices.
func _check_handover_asset() -> void:
	print("\nHandover cue")
	var path: String = CprCueAudio.AMBULANCE_ARRIVE_PATH
	if ResourceLoader.exists(path):
		print("  note   %s is present — the siren played." % path)
	else:
		print("  note   %s is ABSENT — the beat ran as a message, which is the"
			% path)
		print("         asset-optional contract working. Run"
			+ " tools/gen_ambulance_arrive.py.")
	_ok(Assessment.is_complete(&"handover"),
		"the handover completed with or without the siren")


## The post-walk half: the same offers, now that the chest is bare and the run
## is over. State-driven means it knows the difference.
func _check_pointer_retirement(station: CprStation) -> void:
	print("\nBody pointers, after the run")
	var menu := CprGhost.find_node(get_tree().current_scene, "CasualtyActions")
	if menu == null:
		return
	var previous := station.current_state
	station.debug_jump_to_state(CprStation.STATE_EXPOSE_CHEST)
	_ok(not _offered_ids(menu).has(&"expose_chest"),
		"the shirt pill is withheld once the chest is already bare")
	station.current_state = previous


## docs/OVERNIGHT_PLAN.md §8 risk 4, from the other end: CprRig used to match
## bare integers, so a renumber would have silently handed out the wrong anchor
## while still parsing. Asserting the mapping catches that where a grep for
## literals cannot.
func _check_rig_anchors() -> void:
	print("\nCamera anchors")
	var rig := CprGhost.find_node(get_tree().current_scene, "CprRig") as CprRig
	if not _ok(rig != null, "CprRig is in main.tscn"):
		return
	var head := rig.anchor_for_state(CprStation.STATE_BREATHING_CHECK)
	_ok(head != null, "BREATHING_CHECK has a camera anchor")
	_ok(rig.anchor_for_state(CprStation.STATE_PULSE_CHECK) == head,
		"PULSE_CHECK shares the head anchor")
	var kneel := rig.anchor_for_state(CprStation.STATE_COMPRESSIONS_1)
	_ok(kneel != null and kneel != head, "COMPRESSIONS_1 has its own kneel anchor")
	_ok(rig.anchor_for_state(CprStation.STATE_EXPOSE_CHEST) == kneel,
		"EXPOSE_CHEST is worked from the kneel anchor")

	# The four beats with the casualty ON THEIR SIDE take their own anchor, and
	# it must not be the head one. These used to assert the opposite. The head
	# anchor sits 0.5 m above the chest looking 30 degrees down a supine body;
	# rolled, the head bone projected 88% of the way down the screen and the
	# foot bone did not project at all - it was behind the camera - so the
	# injury survey asked the trainee to look at three sites they could not see.
	# Never caught, because "shares the head anchor" was the assertion.
	var rolled := rig.anchor_for_state(CprStation.STATE_RECOVERY_ROLL)
	_ok(rolled != null and rolled != head and rolled != kneel,
		"RECOVERY_ROLL has its own anchor, not the supine head one")
	_ok(rig.anchor_for_state(CprStation.STATE_AIRWAY_INSPECT) == rolled,
		"AIRWAY_INSPECT is worked from the rolled anchor")
	_ok(rig.anchor_for_state(CprStation.STATE_INJURY_SURVEY) == rolled,
		"INJURY_SURVEY is worked from the rolled anchor")
	_ok(rig.anchor_for_state(CprStation.STATE_HANDOVER) == rolled,
		"HANDOVER is worked from the rolled anchor")

	# The three injury sites are bone-bound now, so they land on the body in any
	# pose. Bound means resolved: an unresolved bone silently drops the marker
	# onto the rig origin, which is how all three came to point at bare floor.
	_ok(rig.hand_indices.size() > 0,
		"the hand bones resolved (%d)" % rig.hand_indices.size())
	_ok(rig.foot_indices.size() > 0,
		"the foot bones resolved (%d)" % rig.foot_indices.size())
	_ok(rig.head_idx >= 0, "the head bone resolved")

	# The injury survey's pill anchors. Their OFFSETS are estimated (see
	# cpr_rig.gd) and cannot be checked headless, but a missing marker is a
	# push_warning and a pill with no leader line, which can be.
	var seen: Array = []
	for id: StringName in [&"mouth", &"chest", &"hand", &"head", &"legs"]:
		var marker := rig.pointer_marker(id)
		_ok(marker != null, "body pointer '%s' resolves to a marker" % id)
		_ok(not seen.has(marker), "body pointer '%s' has its own marker" % id)
		seen.append(marker)


## docs/OVERNIGHT_PLAN.md §3: Tasks 5 and 6 must degrade gracefully when the
## Blender assets are absent, so the CPR work stays independent of Track A.
## Casualty_Recovery_Posed had not been authored when this was written, so the
## absent path is the one that runs — and this asserts it is a warning and a
## skipped visual, never a crash and never a blocked beat.
##
## It passes either way ON PURPOSE. When the mesh does land, the pose has to
## actually work; when it has not, the skip has to be silent to the spine. The
## assertion is that the beat completed regardless, which the spine walk above
## already proved.
func _check_graceful_degradation(casualty: Casualty) -> void:
	print("\nGraceful degradation (docs/OVERNIGHT_PLAN.md §3)")
	if not _ok(casualty != null, "a casualty to degrade with"):
		return
	var rolled := casualty.show_recovery_pose(true)
	if rolled:
		print("  note   '%s' exists — the roll ran for real." % Casualty.RECOVERY_MESH_NAME)
		_ok(casualty.in_recovery_pose(), "show_recovery_pose(true) -> rolled")
		casualty.show_recovery_pose(false)
		_ok(not casualty.in_recovery_pose(), "show_recovery_pose(false) -> rolled back")
	else:
		print("  note   '%s' is absent — the skip path is the one under test."
			% Casualty.RECOVERY_MESH_NAME)
		_ok(not casualty.in_recovery_pose(),
			"a missing recovery mesh leaves the body where it was")
	# Either way the beats it belongs to completed, which is the real claim.
	_ok(Assessment.is_complete(&"airway_inspected"),
		"the airway inspection completed with or without the mesh")


## The driven sequence above never emits compression_delivered, so the
## per-rep metrics (total_compressions, pct_in_depth, pct_in_rate,
## time_to_first_compression) are legitimately at their zero defaults here —
## this only checks that every key CPR_CONTRACT.md section 2 promises is
## present, and that the facts this sequence did drive (both pads correct,
## no errors, not assisted) landed correctly.
func _check_metrics() -> void:
	for key in REQUIRED_METRIC_KEYS:
		_ok(_completed_metrics.has(key), "metrics dictionary has '%s'" % key)
	_ok(_completed_metrics.get("pads_correct", -1) == 2, "pads_correct == 2")
	_ok(_completed_metrics.get("pad_errors", -1) == 0, "pad_errors == 0")
	_ok(_completed_metrics.get("assisted", true) == false, "assisted == false")


func _ok(condition: bool, label: String) -> bool:
	if condition:
		print("  pass   %s" % label)
	else:
		_failures += 1
		print("  FAIL   %s" % label)
	return condition
