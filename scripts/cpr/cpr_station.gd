class_name CprStation
extends Node

## Station E · the CPR phase's state spine — CPR_CONTRACT.md section 1, as
## reordered for the client's feedback on 3 Sep 2026 (docs/OVERNIGHT_PLAN.md §2).
##
## Pure sequencer. It does not drive compressions (Agent C), AED/pad meshes
## (Agent D), hover/click (Agent G) or the shock button (Agent H) itself — it
## instances each of their nodes once, then reacts to the Events facts they
## already emit to decide when one state's work is done and the next begins.
## It also assembles the `cpr_completed` metrics dictionary (CPR_CONTRACT.md
## section 2), since the station is the only thing watching the whole phase
## start to finish.
##
## Not wired into main.tscn (frozen). Something outside the CPR agents' file
## set needs to instance this once, e.g.:
##
##   var station := CprStation.new()
##   station.name = "CprStation"
##   add_child(station)
##   ...
##   station.enter_cpr_phase()
##
## See CPR_CONTRACT.md section 9 for the integration seams deliberately left
## outside every agent's file set, and the note at the bottom of this file
## for how they map onto this station's public API.
##
## OWNED BY AGENT E · STATION — see CPR_CONTRACT.md section 7.

# --- states (CPR_CONTRACT.md section 1) --------------------------------------
##
## RENUMBERED 3 Sep 2026 for the client's reordered spine
## (docs/OVERNIGHT_PLAN.md §2): compressions now run with the shirt on and the
## chest is exposed afterwards for the pads, and three new assessment beats sit
## between the breathing check and the first set. Every state moved.
##
## THE RENUMBER IS ONLY SAFE BECAUSE NOTHING COMPARES current_state TO AN
## INTEGER LITERAL. Several sibling files used to carry their own
## `const STATE_X := <n>` copies of this table; they now read these constants
## instead. If you add a state, do not re-introduce a local copy of the number.
const STATE_BREATHING_CHECK := 0
const STATE_AIRWAY_INSPECT := 1
const STATE_PULSE_CHECK := 2
const STATE_COMPRESSIONS_1 := 3
const STATE_EXPOSE_CHEST := 4
const STATE_AED_FETCH := 5
const STATE_AED_DEPLOY := 6
const STATE_PAD_PLACEMENT := 7
const STATE_SHOCK := 8
const STATE_COMPRESSIONS_2 := 9
const STATE_RECOVERY_ROLL := 10
const STATE_INJURY_SURVEY := 11
const STATE_HANDOVER := 12
const STATE_COMPLETE := 13

## The station is armed but the spine has not started — the primary survey is
## running and the body pointers own the screen.
##
## This is the same -1 `current_state` has always held before the phase begins,
## given a name because it is now a real beat of the exercise rather than only
## "not started yet". EXPOSE_CHEST used to sit at 0 and do this job: the phase
## was entered into it at the end of the extraction and nothing happened there
## until a pointer was taken. EXPOSE_CHEST has moved to after the first
## compression set, so it can no longer be the idle, and entering the phase
## straight into BREATHING_CHECK would swing the camera to the casualty's head
## and start prompting for the 5 s hold the instant the drag finished — before
## the response check, before the airway.
##
## So `enter_cpr_phase()` arms the phase and stays here. The first transition is
## `begin_breathing_check()`, taken by a body pointer.
const STATE_PRIMARY_SURVEY := -1

const STATE_NAMES := {
	STATE_BREATHING_CHECK: "BREATHING_CHECK",
	STATE_AIRWAY_INSPECT: "AIRWAY_INSPECT",
	STATE_PULSE_CHECK: "PULSE_CHECK",
	STATE_COMPRESSIONS_1: "COMPRESSIONS_1",
	STATE_EXPOSE_CHEST: "EXPOSE_CHEST",
	STATE_AED_FETCH: "AED_FETCH",
	STATE_AED_DEPLOY: "AED_DEPLOY",
	STATE_PAD_PLACEMENT: "PAD_PLACEMENT",
	STATE_SHOCK: "SHOCK",
	STATE_COMPRESSIONS_2: "COMPRESSIONS_2",
	STATE_RECOVERY_ROLL: "RECOVERY_ROLL",
	STATE_INJURY_SURVEY: "INJURY_SURVEY",
	STATE_HANDOVER: "HANDOVER",
	STATE_COMPLETE: "COMPLETE",
}

const PAD_TARGET := 2  # CPR_CONTRACT.md section 4.4: two placements end the state.

# --- node names resolved at runtime (project binder doctrine) ----------------
const PLAYER_NODE_NAME := "Player"
const CPR_RIG_NODE_NAME := "CprRig"

const AedStationScript := preload("res://scripts/cpr/aed_station.gd")
const PadStationScript := preload("res://scripts/cpr/pad_station.gd")
const ShockButtonScript := preload("res://scripts/cpr/shock_button.gd")
const BreathingCheckScript := preload("res://scripts/cpr/breathing_check.gd")
const CprHands2DScript := preload("res://scripts/cpr/cpr_hands_2d.gd")
const CprEar2DScript := preload("res://scripts/cpr/cpr_ear_2d.gd")
const CprKeyHintScript := preload("res://scripts/cpr/cpr_key_hint.gd")

## Legacy pre-CPR treatment menu (scripts/ui/casualty_action_menu.gd, not a
## CPR agent file). Named node in main.tscn: "CasualtyActions" under Main.
const LEGACY_MENU_NODE_NAME := "CasualtyActions"

## Current state, or -1 before `enter_cpr_phase()` has run.
var current_state: int = -1

## Exposed so other systems (dev menu, HUD/fast-forward prompt) can reach the
## instanced helpers without their own lookup. Null until `_build()` resolves
## the scene.
var camera_rig: CprCameraRig = null
var compression_driver: CompressionDriver = null
var aed_station: Node = null
var pad_station: Node = null
## The AED's spoken prompts (CPR_CONTRACT.md §9 seam 4). Purely reactive — it
## listens to Events and gates nothing — and asset-optional, so it is safe to
## instance before a single voice line has been recorded.
var aed_voice: AedVoice = null
## The phase's two non-diegetic sounds — the metronome and the breathing-check
## result tone (CPR_CONTRACT.md §9 seam 4). Reactive and asset-optional, same
## as aed_voice.
var cue_audio: CprCueAudio = null
## Agent G's crosshair-to-GhostTarget router (CPR_CONTRACT.md §4.0). Built
## first in `_build()` — everything else that registers a clickable with it
## (AedStation, PadStation, ShockButton, and any GhostTarget they own) is
## instanced after it exists.
var interact_bridge: CprInteractBridge = null
## Agent H's shock delivery. Untyped (no class_name on shock_button.gd) —
## reached by other code, if needed, via get_node/get_current() rather than
## a static type.
var shock_button: Node = null
## Agent B's diegetic floating UI (CPR_CONTRACT.md §6). Entirely self-wired —
## it finds CprRig and connects every Events signal it needs in its own
## _ready() (see cpr_panel_stub_emitter.gd for the same feed pattern this
## uses). Instanced here purely so it exists in the tree; nothing else is
## fed to it directly.
var panel: CprPanel3D = null
## Agent L's hold-to-observe implementation (CPR_CONTRACT.md §4.1) — see
## breathing_check.gd for why this file had to exist.
var breathing_check: Node = null
## Translucent 2D hands over the crosshair during compressions — see
## cpr_hands_2d.gd. Self-driven off Events and CasualtyCpr.current_depth();
## nothing is pushed to it.
var hands: CanvasLayer = null
## Translucent 2D ear over the casualty's mouth during the breathing check —
## see cpr_ear_2d.gd. Self-driven off Events and breathing_check's
## hold_progress(); nothing is pushed to it.
var ear: CanvasLayer = null
## Bottom-left "[C] Crouch / stand up" chip — see cpr_key_hint.gd. Self-driven
## off Events; nothing is pushed to it.
var key_hint: CanvasLayer = null

var _cpr_rig: CprRig = null
## The legacy CasualtyActions menu, resolved once in `_build()`. Null if the
## node isn't found under the current scene root.
var _legacy_menu: Node = null

## True while CompressionDriver.fast_forward_available is up and unaccepted,
## for the duration of the compression state it was offered in. Not an
## Events fact (CPR_CONTRACT.md: the offer is not a past-tense fact about the
## trainee), so it lives here as plain state.
var _fast_forward_offer_up: bool = false

## States the trainee has to stand up out of before anything else happens —
## see _apply_camera(). True from entering one of them until they do.
const STAND_UP_STATES := [STATE_AED_FETCH, STATE_SHOCK]

## States where the crouch key stands the trainee up and kneels them back down
## again. See _handle_stance_key().
##
## AIRWAY_INSPECT is deliberately absent: it is a short scripted beat that swaps
## the casualty's mesh for a posed one and swaps it back, and letting the trainee
## walk away mid-swap would leave the body on its side with nothing to bring it
## home. Every other anchored state toggles.
## HANDOVER is absent for the same reason: it is a six-second cue that ends the
## run, and there is nothing to walk away to.
##
## SHOCK is absent because it used to be here and it ended runs. The toggle let
## the trainee kneel back onto Anchor_Shock "within reach of the unit" after
## standing clear, and this file's own docstring told them to - but
## ShockButton._on_activate() tests `trainee_at_anchor()` at the moment of
## press, so kneeling back put them in contact again and the shock killed them.
## Reproduced end to end: stand up, crouch, press, EXERCISE FAILED, with the
## trainee having done exactly what the game asked.
##
## The check is the honest half of that pair and stays. Being down at an anchor
## IS hands on the patient, and discharging into a rescuer who is touching the
## casualty is one of only two outcomes in the exercise that kill the rescuer.
## What had to go is the invitation. Standing up hands the camera back to the
## player with free movement and free look - see _stand_up() - so the AED is
## reachable on foot through the ordinary crosshair. Walking to it is slower
## than crouching was; being killed for crouching is worse.
const STANCE_TOGGLE_STATES := [
	STATE_BREATHING_CHECK, STATE_PULSE_CHECK, STATE_COMPRESSIONS_1,
	STATE_EXPOSE_CHEST, STATE_COMPRESSIONS_2,
	STATE_RECOVERY_ROLL, STATE_INJURY_SURVEY,
]
var _awaiting_stand_up: bool = false

## Alternates the stalled-handover repeat between the goal and the key that
## gets you there. See _on_prompt_timer_timeout().
var _message_was_goal: bool = true

## True from enter_cpr_phase() until reset(). Carries the idempotency that
## `current_state != -1` used to carry — see enter_cpr_phase().
var _phase_entered: bool = false

## One-shot dwell for AIRWAY_INSPECT. Built lazily in begin_airway_inspect().
var _airway_timer: Timer = null

## One-shot dwell for HANDOVER — the siren runs, then the debrief. Built lazily
## in _begin_handover().
var _handover_timer: Timer = null

## True once the trainee has taken the "Start compressions" body pointer
## (scripts/ui/casualty_action_menu.gd). Until then the compression minigame
## stays out of sight: no hands, no reps. The spine reaches COMPRESSIONS_1 off
## the breathing check, which is assessed at the mouth, so the state arriving
## is not the trainee saying they are ready to compress — this is.
##
## Disarmed again by the shock. COMPRESSIONS_2 is not a resumption the trainee
## slides into: the shock lands, the pills come back, and one of them is the
## plausible wrong move (check for signs of life). The gotcha only bites if
## resuming is itself a choice, so the minigame stays out of sight until the
## "Start compressions" pointer is taken a second time. Cleared with the rest
## of the phase.
var compressions_armed: bool = false

## Centre-screen feedback for the phase. Two jobs in one map:
##
##  - INSTRUCTION for the states where the trainee would otherwise be told
##    nothing. AED_FETCH/AED_DEPLOY are the acute case (CPR_HANDOFF.md §5
##    item 1): the diegetic panel deliberately fades out for the phase's one
##    free-movement beat (CPR_CONTRACT.md §6), so the trainee had no prompt at
##    the one moment they must find an object across the room, and the phase
##    read as having stalled after compressions.
##  - CONFIRMATION that the last action registered. Every state here is
##    entered as the direct consequence of one trainee action, so the
##    incoming state's line doubles as the outgoing action's receipt
##    ("AED collected -> place it", "Shock delivered -> resume") and the two
##    never stomp on each other the way a separate confirmation would.
##
## BREATHING_CHECK is absent on purpose — breathing_check.gd owns its own
## prompt, including the off-body hint, and would fight an entry here.
## BREATHING_CHECK and PULSE_CHECK are both absent on purpose — breathing_check.gd
## owns the prompt for each hold, including the off-body hint, and an entry here
## would fight it. AIRWAY_INSPECT is absent because the beat announces its own
## finding through Casualty.inspect_airway().
const STATE_MESSAGES := {
	STATE_COMPRESSIONS_1: "Begin chest compressions",
	STATE_EXPOSE_CHEST: "Set complete — open the shirt so the pads reach bare skin",
	STATE_AED_FETCH: "Stand up and fetch the AED from the shelf",
	STATE_AED_DEPLOY: "AED collected — place it beside the casualty",
	STATE_PAD_PLACEMENT: "AED placed — attach both pads",
	STATE_SHOCK: "Stand clear of the casualty",
	STATE_COMPRESSIONS_2: "Shock delivered — resume compressions",
	STATE_RECOVERY_ROLL: "Breathing has returned — roll the casualty into the recovery position",
	STATE_INJURY_SURVEY: "Check the casualty for other injuries",
	STATE_HANDOVER: "Ambulance arriving — hand over to the crew",
	STATE_COMPLETE: "CPR complete",
}

## The checklist step each spine state is working towards, for the HUD's
## standing objective pill at the bottom of the screen.
##
## Assessment.next_step() cannot answer this, and that is the whole reason this
## exists. It returns the first UNRESOLVED step whose prerequisites are met, and
## `cpr_performed` and `aed_used` are both graded at the very end from the
## cpr_completed metrics rather than when their own beat finishes. So from the
## moment `pulse_checked` lands, `cpr_performed` is what next_step() answers for
## the entire rest of the run: the trainee was told "Perform the CPR set" while
## fetching the AED, while placing the pads, while standing clear for the shock,
## and again underneath "Ambulance arriving - hand over to the crew" on the
## closing beat of the exercise.
##
## States absent from this map hand the question back to next_step(): the
## primary survey grades each of its steps as it happens, so the checklist is
## the honest answer there.
const STATE_STEPS := {
	STATE_COMPRESSIONS_1: &"cpr_performed",
	STATE_EXPOSE_CHEST: &"chest_exposed",
	STATE_AED_FETCH: &"aed_used",
	STATE_AED_DEPLOY: &"aed_used",
	STATE_PAD_PLACEMENT: &"aed_used",
	STATE_SHOCK: &"aed_used",
	STATE_COMPRESSIONS_2: &"cpr_performed",
	STATE_RECOVERY_ROLL: &"recovery_position",
	STATE_INJURY_SURVEY: &"injuries_checked",
	STATE_HANDOVER: &"handover",
}


## The step the standing objective should name, or &"" when the spine has
## nothing to say and Assessment.next_step() is the better answer.
##
## Whether the step is already resolved is deliberately NOT consulted. The map
## says which step a beat is ABOUT, and that stays true after the step is
## graded. A first attempt at this skipped resolved steps and HANDOVER broke on
## it immediately: _begin_handover() completes `handover` on the same frame the
## state becomes HANDOVER, so the beat fell straight back to next_step() and put
## "Perform the CPR set" under "Ambulance arriving - hand over to the crew",
## which is the exact line this was written to remove.
##
## A beat with nothing to ask says so through its step: `handover` and
## `chest_exposed` both carry suppress_prompt, and _refresh_step_pill() stands
## the pill down for those on its own.
func step_for_state() -> StringName:
	return STATE_STEPS.get(current_state, &"")


## Only the free-movement beat repeats its line. Everywhere else the trainee
## is anchored with the panel in view and a second showing is just noise.
const REPEAT_STATES := [STATE_AED_FETCH, STATE_AED_DEPLOY]

const MESSAGE_COLOR := Tokens.ATTENTION  # the sim's one highlight colour
const MESSAGE_SECONDS := 4.0
const MESSAGE_REPEAT_SECONDS := 9.0
const STAND_UP_HINT_SECONDS := 4.5

## Compressions are the one long stretch with no state change to hang a
## receipt on, so each set reports progress at these rep counts.
const COMPRESSION_MILESTONES := [10, 20]

var _prompt_timer: Timer = null

## First instance to reach _ready() wins, mirroring casualty_cpr.gd's own
## static-accessor pattern — lets anything reach the running station without
## a hard node reference. shock_button.gd depends on this to find camera_rig.
static var _current: CprStation = null

# --- metrics (CPR_CONTRACT.md section 2, cpr_completed) ----------------------
var _phase_start_ms: int = 0
var _compression_reps: int = 0
var _in_depth_reps: int = 0
var _in_rate_reps: int = 0
var _time_to_breathing_check: float = 0.0
var _time_to_first_compression: float = -1.0
var _time_to_shock: float = 0.0
var _pad_errors: int = 0
var _pads_correct: int = 0
var _pads_placed_count: int = 0
var _assisted: bool = false


func _ready() -> void:
	_current = self
	Events.breathing_checked.connect(_on_breathing_checked)
	Events.compression_delivered.connect(_on_compression_delivered)
	Events.compression_set_completed.connect(_on_compression_set_completed)
	Events.aed_picked_up.connect(_on_aed_picked_up)
	Events.aed_placed.connect(_on_aed_placed)
	Events.aed_pad_placed.connect(_on_aed_pad_placed)
	Events.aed_shock_delivered.connect(_on_aed_shock_delivered)
	# EXPOSE_CHEST is the one state whose exit condition is a checklist step
	# rather than a CPR-phase fact: the shirt is opened by the "Open the shirt"
	# body pointer, which calls Casualty.expose_chest() and completes the step.
	Events.step_completed.connect(_on_step_completed)
	# Scene population may still be settling on the frame this node enters
	# the tree — same caution CprRig's own binder and the other CPR stations
	# already take (CPR_CONTRACT.md section 3: bind from call_deferred, never
	# straight out of _ready()).
	call_deferred("_build")


func _exit_tree() -> void:
	if _current == self:
		_current = null


static func get_current() -> CprStation:
	return _current


# --- construction --------------------------------------------------------------

func _build() -> void:
	# First: CPR_CONTRACT.md §4.0 routes every clickable in the phase through
	# this bridge. Agent G's brief: "Order matters — the bridge must exist
	# before anything registers with it."
	interact_bridge = CprInteractBridge.new()
	interact_bridge.name = "CprInteractBridge"
	add_child(interact_bridge)

	var root: Node = get_tree().current_scene
	if root == null:
		root = get_tree().root

	_cpr_rig = CprGhost.find_node(root, CPR_RIG_NODE_NAME) as CprRig
	if _cpr_rig == null:
		push_error("CprStation: no node named '%s' found for the camera/panel anchors." % CPR_RIG_NODE_NAME)

	# CPR_AGENTS.md, Agent L brief, task 1: resolved here (not required to
	# exist) so enter_cpr_phase() can hand over from it without a second
	# runtime search. Disabled, not crashed, on failure — see the push_error
	# in _suppress_legacy_menu().
	_legacy_menu = CprGhost.find_node(root, LEGACY_MENU_NODE_NAME)
	if _legacy_menu == null:
		push_error("CprStation: no node named '%s' found; cannot hand over from the legacy casualty menu." % LEGACY_MENU_NODE_NAME)

	# Playtest fix (CPR_AGENTS.md, Agent K brief, task 1): this was the only
	# Agent B deliverable never instanced anywhere, so the diegetic panel from
	# CPR_CONTRACT.md §6 never once reached the screen. CprPanel.tscn carries
	# no serialised children (cpr_panel_3d.gd builds its viewport/quad in
	# code, same "no serialised runtime nodes" pattern as cpr_rig.gd), so a
	# bare CprPanel3D.new() is equivalent to instancing the .tscn.
	panel = CprPanel3D.new()
	panel.name = "CprPanel3D"
	add_child(panel)

	var player := CprGhost.find_node(root, PLAYER_NODE_NAME) as Player
	if player == null:
		push_error("CprStation: no node named '%s' found; camera cannot be handed off." % PLAYER_NODE_NAME)
	else:
		camera_rig = CprCameraRig.new(player)
		camera_rig.name = "CprCameraRig"
		add_child(camera_rig)

	compression_driver = CompressionDriver.new()
	compression_driver.name = "CompressionDriver"
	add_child(compression_driver)
	compression_driver.fast_forward_available.connect(_on_fast_forward_available)

	aed_station = AedStationScript.new()
	aed_station.name = "AedStation"
	add_child(aed_station)

	pad_station = PadStationScript.new()
	pad_station.name = "PadStation"
	add_child(pad_station)

	aed_voice = AedVoice.new()
	aed_voice.name = "AedVoice"
	add_child(aed_voice)

	# After compression_driver above: its `metronome_tick` is a local signal,
	# and CprCueAudio reaches it through this station in its own deferred pass.
	cue_audio = CprCueAudio.new()
	cue_audio.name = "CprCueAudio"
	add_child(cue_audio)

	# Last: shock_button.gd reaches CprStation.get_current().camera_rig from
	# its own call_deferred("_bind_camera_rig") — camera_rig is already
	# assigned above by the time that runs, and it registers its target with
	# interact_bridge only once SHOCK is entered, well after this.
	shock_button = ShockButtonScript.new()
	shock_button.name = "ShockButton"
	add_child(shock_button)

	breathing_check = BreathingCheckScript.new()
	breathing_check.name = "BreathingCheck"
	add_child(breathing_check)

	# Replaces the FpsArms plan (CPR_CONTRACT.md §9 seam 5) — a flat overlay
	# conveys hand placement and the press without a rig to keep in sync.
	hands = CprHands2DScript.new()
	hands.name = "CprHands2D"
	add_child(hands)

	# The hands' counterpart at the mouth: the cue that a hold is wanted during
	# the breathing check, and the fill that shows it running. Added after
	# `breathing_check`, which it reads its progress off.
	ear = CprEar2DScript.new()
	ear.name = "CprEar2D"
	add_child(ear)

	key_hint = CprKeyHintScript.new()
	key_hint.name = "CprKeyHint"
	add_child(key_hint)

	# From spawn, not from phase entry: Casualty_CPR_Posed is in the scene from
	# level load, and the trainee is walking around it long before the CPR
	# phase begins.
	_free_casualty_collision()

	_prompt_timer = Timer.new()
	_prompt_timer.name = "CprMessageTimer"
	_prompt_timer.wait_time = MESSAGE_REPEAT_SECONDS
	_prompt_timer.one_shot = false
	_prompt_timer.timeout.connect(_on_prompt_timer_timeout)
	add_child(_prompt_timer)


# --- public API ------------------------------------------------------------------

## Arms the phase and starts its clock, leaving the spine at
## STATE_PRIMARY_SURVEY. Idempotent — a second call while a run is already in
## progress is a no-op. See CPR_CONTRACT.md section 9, seam 1.
##
## It no longer enters a state. It used to enter EXPOSE_CHEST, which was state 0
## and did nothing but wait; EXPOSE_CHEST has moved to after the first
## compression set, and entering BREATHING_CHECK in its place would take the
## camera and start the 5 s hold the moment the extraction drag finished. See
## STATE_PRIMARY_SURVEY.
##
## Idempotency is now tracked by `_phase_entered` rather than by
## `current_state != -1`, because -1 is where an armed phase legitimately sits.
func enter_cpr_phase() -> void:
	if _phase_entered:
		return
	_phase_entered = true
	current_state = STATE_PRIMARY_SURVEY
	_reset_metrics()
	_awaiting_stand_up = false
	_awaiting_help_call = false
	compressions_armed = false
	# A retry after a debrief re-enters the phase with the ambulance still
	# flashing from the previous run otherwise.
	_set_emergency_lights(false)
	_phase_start_ms = Time.get_ticks_msec()
	Events.cpr_phase_entered.emit()


## True once enter_cpr_phase() has run, whether or not the spine has left the
## primary survey. Read by scripts/ui/casualty_action_menu.gd, which offers the
## "Check for breathing" pointer only once the station is armed.
func is_phase_entered() -> bool:
	return _phase_entered


## Playtest fix: once the casualty is down for CPR the trainee has to be able
## to stand over the chest, but Casualty_CPR_Posed carries an imported
## StaticBody3D (a ConvexPolygonShape3D hull of the whole body) on collision
## layer 1 "World" — the only layer Player's own collision_mask contains — so
## the body was a solid obstacle to walk around.
##
## Moving the hull to layer 3 "Casualty" drops it out of Player's mask while
## keeping it inside InteractionRay's mask (7 = World|Interactable|Casualty),
## so the trainee walks through the body but every raycast still hits it: the
## breathing-check aim test and the pad-ghost walk in cpr_interact_bridge.gd
## both keep working. Done in code, at phase entry rather than at build, so
## Done from _build() — the CPR mesh exists from level load, so it is
## walk-through for the whole exercise — and in code rather than authored, so a
## .blend reimport cannot drop it (CPR_CONTRACT.md §3).
func _free_casualty_collision() -> void:
	var root: Node = get_tree().current_scene
	if root == null:
		root = get_tree().root
	var mesh := CprGhost.find_node(root, CasualtyCpr.CASUALTY_CPR_MESH)
	if mesh == null:
		push_error("CprStation: no node named '%s'; casualty collision not handed over." % CasualtyCpr.CASUALTY_CPR_MESH)
		return
	for child in mesh.get_children():
		var body := child as PhysicsBody3D
		if body != null:
			body.collision_layer = 4   # "Casualty", per project.godot layer_names


## CPR_AGENTS.md, Agent L brief, task 1: the legacy CasualtyActions menu
## (scripts/ui/casualty_action_menu.gd, not a CPR agent file) stays open and
## holds input in menu mode until its "Stand up" button is pressed, and
## nothing closed it when the CPR phase took over. Its pre-CPR entries
## ("Check for a response", "Open the airway", "Expose the chest") are still
## the route into this phase and must keep working, which is why this is NOT
## called from enter_cpr_phase(): that fires at PRIMARY_SURVEY, right after
## the drag — before the trainee has opened the menu even once to reach
## "Expose the chest". Calling suppress() that early would black out the
## menu's entire pre-CPR route in. begin_breathing_check() (seam 2, below)
## fires only once the chest-expose swap has actually happened, which is the
## correct hand-over point: the menu's remaining entries
## ("Start chest compressions", "Attach the AED pads", "Stand clear for
## analysis", "Deliver the shock") are exactly the ones the CPR minigame now
## supersedes.
func _suppress_legacy_menu() -> void:
	if _legacy_menu == null:
		return
	if _legacy_menu.has_method("suppress"):
		_legacy_menu.suppress()
	else:
		push_error("CprStation: '%s' has no public suppress()/close() method; the legacy menu was not handed over. See CPR_AGENTS.md Agent L report." % LEGACY_MENU_NODE_NAME)


## The door into the spine: PRIMARY_SURVEY -> BREATHING_CHECK. Taken by the
## "Check for breathing" body pointer once the airway is open.
##
## Arms the phase first if nothing else has. That is the real fix for the
## PRIMARY_SURVEY ordering race in ARCHITECTURE.md §2 — the race was that
## `phase_changed` could reach PRIMARY_SURVEY before main.gd had instanced this
## station, leaving current_state at -1 forever and the camera never engaging.
## main.gd's second hook used to cover it off `step_completed(chest_exposed)`;
## that step now happens after the first compression set and is far too late, so
## the guard belongs here, at the one call every route into the spine goes
## through. main.gd still carries a backstop off `breathing_checked`.
func begin_breathing_check() -> void:
	if not _phase_entered:
		enter_cpr_phase()
	if current_state != STATE_PRIMARY_SURVEY:
		return
	_suppress_legacy_menu()
	_enter_state(STATE_BREATHING_CHECK)


## How long the casualty stays rolled while the airway is inspected. Long enough
## to read the finding, short enough that it is a look rather than a cutscene.
const AIRWAY_INSPECT_SECONDS := 3.0


## BREATHING_CHECK -> AIRWAY_INSPECT. Taken by the "Check the airway for a
## blockage" body pointer once the 5 s hold has answered.
##
## Client item 6: roll the casualty to check the airway for a blockage. The roll
## is a cold mesh swap to the posed recovery mesh, not an animation — Nadir,
## 3 Sep: "we dont need roll animation just pose well cold switch" — which is
## also what keeps CPR_CONTRACT.md §8's "never touch the casualty's
## AnimationPlayer" intact. Casualty.inspect_airway() owns the swap and the
## finding; this owns the dwell and the hand-off to the pulse check.
func begin_airway_inspect() -> void:
	if current_state != STATE_BREATHING_CHECK:
		return
	_enter_state(STATE_AIRWAY_INSPECT)

	var casualty := _casualty()
	if casualty != null:
		casualty.inspect_airway()

	if _airway_timer == null:
		_airway_timer = Timer.new()
		_airway_timer.name = "AirwayInspectTimer"
		_airway_timer.one_shot = true
		_airway_timer.timeout.connect(finish_airway_inspect)
		add_child(_airway_timer)
	_airway_timer.start(AIRWAY_INSPECT_SECONDS)


## Rolls the casualty back and moves on to the pulse check. Called by the dwell
## timer; public so the headless test can drive the beat without sleeping.
## Idempotent and state-guarded, so the timer firing after a reset or a debug
## jump cannot roll a casualty who is somewhere else entirely.
func finish_airway_inspect() -> void:
	if current_state != STATE_AIRWAY_INSPECT:
		return
	if _airway_timer != null:
		_airway_timer.stop()
	var casualty := _casualty()
	if casualty != null:
		casualty.end_airway_inspection()
	_enter_state(STATE_PULSE_CHECK)


## Completes the pulse check and hands the decision back to the trainee.
## Called by breathing_check.gd, which runs the hold itself — the pulse check is
## the same 5 s construction as the breathing check at a different place on the
## body, so it reuses that timer rather than growing a second one.
##
## Client item 7: the pulse check is the beat that licenses compressions. The
## finding is always "no pulse"; nothing here blocks compressions if the trainee
## skips it, exactly as nothing blocks them for skipping the breathing check —
## the debrief reports it.
func complete_pulse_check() -> void:
	if current_state != STATE_PULSE_CHECK:
		return
	Assessment.complete(&"pulse_checked")
	Events.center_message_requested.emit(
		"No pulse. Start chest compressions.", Tokens.DANGER, 4.0
	)


# --- recovery, injuries, handover (client item 8) -----------------------------
#
# The three beats after the shock, in order: RECOVERY_ROLL -> INJURY_SURVEY ->
# HANDOVER -> COMPLETE. Each is entered by the trainee taking a body pointer,
# not by arriving in the state — same principle as COMPRESSIONS_1 and
# COMPRESSIONS_2. The one exception is HANDOVER, which is the ambulance arriving
# and is therefore something that happens TO the trainee.

## The FLOOR for how long the siren runs before the debrief takes the screen.
## Long enough for the centre message to be read; short enough that the run does
## not end on a wait. The actual dwell is _handover_dwell(), which never cuts
## the cue short - see it for why this is a floor and not the answer.
const HANDOVER_SECONDS := 6.0

## The injury sites the survey offers, in the order the pills stack. The
## findings themselves live on Casualty (INJURY_SITES) — this is only the
## sequence.
const INJURY_SITES: Array[StringName] = [&"hands", &"head", &"legs"]

## The sites looked at during this visit to INJURY_SURVEY, as a set. Kept
## rather than counted so the survey is answered by the site list above and not
## by a literal three - add a fourth callout and the survey waits for it.
var _sites_surveyed: Dictionary = {}


## RECOVERY_ROLL -> INJURY_SURVEY. Taken by the "Roll into the recovery
## position" body pointer.
##
## Casualty.roll_to_recovery() owns the roll, the mesh swap and the step; this
## owns the hand-off. It refuses on a casualty who is not breathing and records
## a violation when it does, so the transition is conditional on the roll having
## actually happened rather than on the click.
func roll_to_recovery() -> void:
	if current_state != STATE_RECOVERY_ROLL:
		return
	var casualty := _casualty()
	if casualty == null:
		# Nothing to roll. Do not strand the run in a state with one pill that
		# cannot resolve — the survey is still worth doing.
		_enter_state(STATE_INJURY_SURVEY)
		return
	casualty.roll_to_recovery()
	# Read the casualty's own state, not `Assessment.is_complete`: the checklist
	# step can be pre-completed by a dev warp or an out-of-order route, and then
	# a refused roll would look like a successful one. State.RECOVERY is set by
	# roll_to_recovery() itself and only by it.
	if casualty.state != Casualty.State.RECOVERY:
		# It refused — the casualty is not in ROSC. The violation is already
		# recorded; leave the pill up rather than advancing past a beat that did
		# not happen.
		return
	_enter_state(STATE_INJURY_SURVEY)


## One look during the injury survey. Returns true if that site carried the
## finding, which is what it has always returned - the finding, not the end of
## the survey.
##
## THE SURVEY ENDS WHEN EVERY SITE HAS BEEN LOOKED AT, not when the burn is
## found. It used to end on the finding, and since the hands are the site that
## carries it, a trainee who went straight to the hands - the correct instinct
## for an electrical casualty - had the ambulance arrive with the head and the
## legs never looked at. The client's words are "check for any other injuries
## whilst help arrives": the burn is one of that survey's answers, not its
## terminator, and a survey that stops at the first positive is not a survey.
##
## The finding still speaks the moment it is found. That is Casualty's message
## and it is unchanged - the reward for knowing where the entry wound is is
## still immediate, it just no longer calls the ambulance.
func survey_injury(site: StringName) -> bool:
	if current_state != STATE_INJURY_SURVEY:
		return false
	var casualty := _casualty()
	if casualty == null:
		return false

	var found: bool = casualty.survey_injury(site)
	_sites_surveyed[site] = true
	if not _all_sites_surveyed():
		return found

	Assessment.complete(&"injuries_checked")
	_enter_state(STATE_HANDOVER)
	_begin_handover()
	return found


## Every site in INJURY_SITES looked at. An unknown site name recorded above is
## harmless here: this asks whether the list is covered, never how many looks
## were taken.
func _all_sites_surveyed() -> bool:
	for site in INJURY_SITES:
		if not _sites_surveyed.has(site):
			return false
	return true


## The ambulance arrives and the run ends. Nothing is asked of the trainee here
## — this is the one beat of the phase that happens to them rather than being
## taken — so it is a cue, a line, and a timer onto COMPLETE.
## The ambulance only comes if somebody called it.
##
## `send_for_help` is suppress_prompt and critical: nothing on screen ever asks
## for it, the trainee is expected to know, and skipping it fails the run. But
## the run still ENDED the same way - siren, lights, "hand over to the crew" -
## which is the one thing the exercise must not do. A trainee who never made
## the call watched an ambulance arrive anyway and had no reason to believe
## they had missed anything until the debrief told them so. The world agreed
## with the mistake.
##
## So the beat stalls instead. No cue, no lights, no dwell timer, no `handover`
## step: the casualty is in the recovery position and nobody is coming. The
## trainee gets the last chance they would get in the field - stand up, walk to
## the radio, make the call - and _on_help_called() then runs the real handover
## and records how late it was.
##
## Not a fail screen, and not a silent pass. The call is still worth making at
## this point precisely because it is the thing that ends the emergency.
func _begin_handover() -> void:
	if not Assessment.is_complete(&"send_for_help"):
		_await_help_call()
		return
	_arrive_ambulance()


## True from entering HANDOVER with no call made until the call is made. Drives
## the state message, the repeat prompt, and _on_help_called().
var _awaiting_help_call: bool = false

const NO_HELP_MESSAGE := "Nobody called 000. No ambulance is coming — call it now."

const NO_HELP_LATE_DETAIL := "Emergency services were not called until the casualty was already breathing and in the recovery position. In the field nobody would have been on the way for the whole of the resuscitation."


func _await_help_call() -> void:
	_awaiting_help_call = true
	# _enter_state() ran _apply_state_message() before _begin_handover() got to
	# decide whether an ambulance is coming at all, so the arrival card is
	# already on screen. Take it down: nobody called, and a card saying the
	# crew is here over the top of "nobody called 000" is the exact thing
	# _begin_handover() exists to prevent - the world agreeing with the mistake.
	if _centre_card != null:
		_centre_card.hide_card()
	# The radio is on the bench, so this beat cannot be worked from the anchor.
	# Same treatment as the AED fetch: hand the camera back and say so.
	if camera_rig != null:
		camera_rig.release()
	_awaiting_stand_up = false
	_message(NO_HELP_MESSAGE)
	if _prompt_timer != null:
		_prompt_timer.start(STAND_UP_HINT_SECONDS)


## The call landing during the stalled handover. Records how bad the delay was
## and lets the beat finish.
##
## `record_violation` on top of whatever lateness Assessment.complete() already
## found, because the two say different things: the time limit says the call
## missed its 10 s window, this says it missed the entire resuscitation. The
## step is still completed - the trainee did eventually do it, and the debrief
## should say so rather than pretending it never happened.
func _on_help_called() -> void:
	if not _awaiting_help_call:
		return
	_awaiting_help_call = false
	if _prompt_timer != null:
		_prompt_timer.stop()
	Assessment.record_violation(&"send_for_help", NO_HELP_LATE_DETAIL)
	_apply_state_message(STATE_HANDOVER)
	_arrive_ambulance()


## The middle-of-screen announcement for the handover. Built the first time it
## is asked for, for the same reason the lights are: a headless run drives the
## spine with no viewport to draw into.
var _centre_card: CentreCard = null

const HANDOVER_CARD_TITLE := "Ambulance arriving"
const HANDOVER_CARD_BODY := "Stay with the casualty and hand over to the crew."


func _show_handover_card() -> void:
	if _centre_card == null:
		_centre_card = CentreCard.build(self)
	if _centre_card != null:
		_centre_card.show_card(
			HANDOVER_CARD_TITLE, HANDOVER_CARD_BODY, _handover_dwell())


func _arrive_ambulance() -> void:
	# The resuscitation is over: the crew is here, the casualty is on his side
	# and breathing, and there is nothing left to do at knee height. Playtest:
	# "when ambulance starts arriving stand up automatically (tween)."
	#
	# release_smooth() rather than release() - the same tweened hand-back the
	# stand-clear and the AED fetch use, so the last shot of the run rises to
	# standing instead of cutting there. Unconditional: the stalled-handover
	# path has already released the camera to let the trainee walk to the radio,
	# and releasing a camera nobody holds is a no-op.
	_awaiting_stand_up = false
	if camera_rig != null:
		camera_rig.release_smooth()

	if cue_audio != null and cue_audio.has_method("play_ambulance"):
		cue_audio.play_ambulance()
	_set_emergency_lights(true)
	Assessment.complete(&"handover")
	if _handover_timer == null:
		_handover_timer = Timer.new()
		_handover_timer.name = "HandoverTimer"
		_handover_timer.one_shot = true
		_handover_timer.timeout.connect(finish_handover)
		add_child(_handover_timer)
	_handover_timer.start(_handover_dwell())


## The red/blue wash for the handover, built the first time it is asked for.
##
## Lazy rather than built in _ready(): every run reaches the handover, but a
## headless test run drives the spine without a viewport to draw into, and a
## CanvasLayer built at startup would be a node the tests carry for nothing.
var _lights: EmergencyLights = null


func _set_emergency_lights(on: bool) -> void:
	if _lights == null:
		if not on:
			return
		_lights = EmergencyLights.build(self)
	if _lights != null:
		_lights.set_running(on)


## The handover dwell: the floor above, or the length of the cue if the cue is
## longer.
##
## It used to be the bare constant, and docs/OVERNIGHT_PROGRESS.md recorded that
## 6.0 was "matched to the generated cue's length". It was not - the placeholder
## is 6.5 s. Measured in the running game: the player was still playing at
## +6.51 s and the master bus peak was still climbing at +6.2 s, having risen
## from -51 dB to -22.7 dB, while the timer fired at +6.0 s. The cue's envelope
## peaks on arrival, so the half second the debrief covered was the ambulance
## actually arriving - the one moment the beat exists to deliver.
##
## Reading the length rather than re-tuning the constant is also what makes
## replacing the placeholder with a real recording a drop-in.
func _handover_dwell() -> float:
	var cue := 0.0
	if cue_audio != null and cue_audio.has_method("ambulance_length"):
		cue = float(cue_audio.call("ambulance_length"))
	return maxf(HANDOVER_SECONDS, cue)


## HANDOVER -> COMPLETE, and the end of the phase. Public and state-guarded for
## the same reason finish_airway_inspect() is: the headless test drives the beat
## without sleeping out the dwell.
func finish_handover() -> void:
	if current_state != STATE_HANDOVER:
		return
	if _handover_timer != null:
		_handover_timer.stop()
	_enter_state(STATE_COMPLETE)
	_finish_phase()


## The Casualty node, found through its group rather than held as a reference —
## it lives outside the CPR file set and the station is instanced from main.gd
## with no wiring (CPR_CONTRACT.md §3).
func _casualty() -> Casualty:
	if get_tree() == null:
		return null
	return get_tree().get_first_node_in_group(&"casualty") as Casualty


## Enter the first compression set. This is the only way in — nothing else
## advances the spine to COMPRESSIONS_1.
##
## Taken by the "Start compressions" pointer, which is offered as soon as the
## chest is bare, whether or not breathing has been assessed. That is
## deliberate: DRSABCD puts the breathing check first, and a trainee who goes
## to compressions without it has made a real mistake that a real assessor
## would mark. Nothing here blocks it — `_time_to_breathing_check` stays 0 and
## the breathing step is never completed, so the debrief reports exactly what
## was skipped.
##
## Railing the order would teach it by making it impossible to get wrong, which
## is not the same as knowing it. Equally, finishing the breathing check does
## not start compressions on its own: the trainee takes the pointer either way.
func begin_compressions_early() -> void:
	if not _phase_entered:
		return
	if current_state >= STATE_COMPRESSIONS_1:
		return
	if current_state == STATE_AIRWAY_INSPECT:
		# The casualty is rolled on their side for the inspection, and the
		# "Start compressions" pointer is up during that beat like every other
		# one before the set. Compressions on a body lying on its side is not a
		# thing the world can show, and finish_airway_inspect() would bail on
		# its state guard once we had left, leaving them rolled for the rest of
		# the run. So the roll is undone rather than the choice refused — the
		# skipped pulse check is still recorded, which is the part that matters.
		if _airway_timer != null:
			_airway_timer.stop()
		var rolled := _casualty()
		if rolled != null:
			rolled.end_airway_inspection()
	_close_skipped_assessments()
	_enter_state(STATE_COMPRESSIONS_1)


## The assessments between the response check and the first compression set,
## in the order the spine offers them. Each one is skippable - the pointer that
## starts compressions is up throughout - and skipping one is a real mistake the
## debrief is supposed to report.
const PRE_COMPRESSION_ASSESSMENTS := [
	&"breathing_checked", &"airway_inspected", &"pulse_checked",
]

const SKIPPED_ASSESSMENT_REASON := "Compressions were started before this assessment was made."


## Closes whichever of those assessments the trainee has gone past without
## making, at the moment they go past it.
##
## The comment in begin_compressions_early() has always said "the skipped pulse
## check is still recorded". It was not. Nothing closed the step, so it sat open
## for the rest of the run: absent from the debrief's own account of what went
## wrong, and - because `chest_exposed` requires it - quietly flagging the
## correctly-performed chest exposure as out of order instead. Seen end to end
## in a full playtest run, which finished with an amber "! Expose the chest" the
## trainee had done nothing wrong to earn.
##
## `fail`, not a silent skip: the step happened to nobody, it scores nothing,
## and the trainee should read about it in the debrief. It is idempotent and
## refuses steps already resolved, so a trainee who made the assessment keeps
## their completion.
func _close_skipped_assessments() -> void:
	for step_id: StringName in PRE_COMPRESSION_ASSESSMENTS:
		if not Assessment.is_resolved(step_id):
			Assessment.fail(step_id, SKIPPED_ASSESSMENT_REASON)


## Single source of truth for "is the trainee down at the casualty".
##
## The floating panel, the 2D hands and the body pointers each used to decide
## this for themselves, and each got it wrong in a different state — most
## visibly, standing up to reach the radio mid-breathing-check left the
## "Observing..." panel and the pills hanging over the room. They are three
## views of one fact, so they read one predicate.
##
## The camera rig is that fact: it is `active` exactly while the trainee is at
## an anchor, whether they were put there by the pointer sequence, by a state
## transition, or by toggling [C] back down. `move_started` and `released` are
## the change notifications that go with it.
func trainee_at_anchor() -> bool:
	return camera_rig != null and camera_rig.active


## Releases the camera and clears state without emitting `cpr_completed`.
## For an abandoned/reset run (e.g. a fail screen restart) — a normal run
## reaches COMPLETE through `_finish_phase()` instead.
func reset() -> void:
	current_state = STATE_PRIMARY_SURVEY
	_phase_entered = false
	compressions_armed = false
	if _centre_card != null:
		_centre_card.hide_card()
	_sites_surveyed.clear()
	if _airway_timer != null:
		_airway_timer.stop()
	if _handover_timer != null:
		_handover_timer.stop()
	if camera_rig != null:
		camera_rig.release()
	_reset_metrics()


## True once COMPLETE has been reached (cpr_completed already emitted).
func is_complete() -> bool:
	return current_state == STATE_COMPLETE


## Dev-menu / debug helper: force a transition, bypassing the Events gating
## that a real playthrough would go through. Starts the phase first if it
## has not begun. Metrics for states skipped this way stay at their
## defaults, so a `cpr_completed` reached by jumping will under-report.
func debug_jump_to_state(state: int) -> void:
	if not STATE_NAMES.has(state):
		push_error("CprStation.debug_jump_to_state: %d is not a valid state." % state)
		return
	if not _phase_entered:
		enter_cpr_phase()
	_enter_state(state)


# --- state machine -----------------------------------------------------------------

func _enter_state(new_state: int) -> void:
	var previous := current_state
	current_state = new_state
	if new_state != STATE_COMPRESSIONS_1 and new_state != STATE_COMPRESSIONS_2:
		_fast_forward_offer_up = false
	if new_state == STATE_INJURY_SURVEY:
		# Fresh pills, fresh set of looks. The state is re-enterable through
		# debug_jump_to_state, and a survey half taken under an earlier visit
		# must not let one click of the new one call the ambulance.
		_sites_surveyed.clear()
	_apply_camera(new_state)
	_apply_state_message(new_state)
	Events.cpr_state_changed.emit(previous, new_state)


func _apply_state_message(state: int) -> void:
	if _prompt_timer != null:
		_prompt_timer.stop()
	if not STATE_MESSAGES.has(state):
		return
	if state == STATE_HANDOVER and _awaiting_help_call:
		# Not the closing beat at all yet - see _begin_handover(). The line that
		# belongs here is the one naming what is missing, and _await_help_call()
		# has already put it up.
		return
	if state == STATE_HANDOVER:
		# The closing beat is a siren and a line, and the line is the only thing
		# on screen that names it - no pill, nothing to click, nothing else
		# changes. It holds for as long as the ambulance takes to arrive.
		#
		# Playtest: "make the 'ambulance coming' a center screen card." It was
		# the HUD's transient feedback pill, which is the furniture every wrong
		# click and every nudge in the run uses, tucked above the bottom edge -
		# so the end of the exercise announced itself in the same voice as
		# "the circuit is still live". A card in the middle of the frame is the
		# only thing on screen that has never meant anything else.
		_show_handover_card()
		return
	_message(STATE_MESSAGES[state])
	if _prompt_timer == null:
		return
	if STAND_UP_STATES.has(state):
		# Follow the goal with the key that gets you there, sooner than the
		# ordinary repeat — being stuck on your knees is a dead end otherwise.
		_prompt_timer.start(STAND_UP_HINT_SECONDS)
	elif REPEAT_STATES.has(state):
		_prompt_timer.start()


func _message(text: String) -> void:
	Events.center_message_requested.emit(text, MESSAGE_COLOR, MESSAGE_SECONDS)


func _on_prompt_timer_timeout() -> void:
	# While the trainee is still on their knees, the repeat says HOW to get up
	# rather than restating the goal — the goal is not the part they are stuck
	# on.
	if _awaiting_help_call:
		# Alternates goal and mechanism the same way the stand-up hint does:
		# the trainee on their knees beside the casualty is stuck on getting up
		# and across the room, not on understanding what is being asked.
		_message(_stand_up_prompt() if _message_was_goal else NO_HELP_MESSAGE)
		_message_was_goal = not _message_was_goal
		return
	if _awaiting_stand_up:
		_message(_stand_up_prompt())
		return
	if not REPEAT_STATES.has(current_state):
		_prompt_timer.stop()
		return
	_message(STATE_MESSAGES[current_state])


## Reused for both compression sets — offer only counts while the station is
## actually sitting in the state the driver offered it for.
func _on_fast_forward_available() -> void:
	if current_state != STATE_COMPRESSIONS_1 and current_state != STATE_COMPRESSIONS_2:
		return
	_fast_forward_offer_up = true


## Mirrors Player._unhandled_input's own "interact" action (CPR_CONTRACT.md
## §4.0) — deliberately not the compression input (left mouse / Space), which
## drives reps and would fire the skip on a normal rep.
func _unhandled_input(event: InputEvent) -> void:
	if Events.is_ui_blocking():
		return

	if event.is_action_pressed(&"crouch") and _handle_stance_key():
		get_viewport().set_input_as_handled()
		return

	if not _fast_forward_offer_up:
		return
	if not event.is_action_pressed(&"interact"):
		return
	_fast_forward_offer_up = false
	if compression_driver != null:
		compression_driver.accept_fast_forward()


## Two states no longer move the camera on entry — the trainee has to stand up
## first, deliberately, the way they would at a real casualty:
##
##   AED_FETCH  you cannot walk off to the cabinet from your knees. The camera
##              stays at the kneel anchor until the trainee stands, and only
##              then is it released for free movement.
##   SHOCK      standing up IS the stand-clear (CPR_CONTRACT.md §4.3: "the
##              pull-back to standing height is the stand-clear, so there is no
##              separate confirm action"). Doing it automatically meant the
##              trainee never performed it.
##
## Every other state is unchanged: anchored states move immediately, free
## states release immediately.
func _apply_camera(state: int) -> void:
	if camera_rig == null or _cpr_rig == null:
		return
	if STAND_UP_STATES.has(state):
		_awaiting_stand_up = true
		return
	_awaiting_stand_up = false
	var anchor := _camera_anchor(state)
	if anchor != null:
		camera_rig.look_yaw_limit_deg = _yaw_limit_for(state)
		camera_rig.move_to(anchor)
	else:
		camera_rig.release()


## The anchor for a state, with the one beat that has two of them.
##
## COMPRESSIONS_2 is entered on the far side of the shock and does not start
## compressing: it asks whether there are signs of life first, and only
## compresses if the answer is no. The kneel anchor is right for the second
## half and wrong for the first - half a metre over the sternum looking down at
## bare chest, with the mouth pill riding the top edge of the frame, which is
## exactly the playtest complaint ("looks at chest while pills are higher").
##
## So the state gets the decision anchor until the trainee takes "Start
## compressions", and arm_compressions() swaps it for the kneel. Every other
## state has one anchor and comes straight off the rig.
func _camera_anchor(state: int) -> Marker3D:
	if state == STATE_COMPRESSIONS_2 and not compressions_armed:
		return _cpr_rig.anchor_decision
	return _cpr_rig.anchor_for_state(state)


## Takes the "Start compressions" pointer: arms the minigame and, post-shock,
## drops the camera from the decision anchor onto the compression one.
##
## The camera move IS the receipt. _apply_camera() only runs on state entry, and
## the post-shock beat resumes compressions without changing state, so arming
## had to re-apply it or the trainee would have compressed from the decision
## shot. It also reads correctly: answering the question moves you into
## position for the work.
##
## Safe in every other state - COMPRESSIONS_1 already holds the kneel anchor, so
## re-applying is a no-op move to the pose the camera is in.
func arm_compressions() -> void:
	compressions_armed = true
	_apply_camera(current_state)


## How far either side of the anchor''s own forward the trainee may look, in
## this state.
##
## The rig''s 110 degrees is a hard case, not a default: it is what SHOCK needs
## so the deployed AED can be found from Anchor_Shock without standing up. Every
## other anchored beat inherited it, and on the rolled anchor that meant a
## trainee working the injury survey could swing 110 degrees off a shot that is
## already oblique and end up looking at the back wall - "I could look all the
## way behind me", from the playtest. Nothing in the survey is behind them.
##
## The rolled beats get the tight clamp because everything they are asked to
## touch is inside one frame now (see CprRig.rolled_pos): the head, the hands
## and the feet are all in shot at the anchor''s own forward, so look is for
## small adjustments rather than for finding things.
const ROLLED_LOOK_YAW_LIMIT := 45.0

const ROLLED_STATES := [
	STATE_AIRWAY_INSPECT, STATE_RECOVERY_ROLL, STATE_INJURY_SURVEY, STATE_HANDOVER,
]


func _yaw_limit_for(state: int) -> float:
	if ROLLED_STATES.has(state):
		return ROLLED_LOOK_YAW_LIMIT
	return CprCameraRig.DEFAULT_LOOK_YAW_LIMIT


## Performs whatever the state was waiting to do once the trainee stands.
## Both stand-up states hand the camera back to the player rather than moving
## it to another anchor, and both do it tweened.
##
## AED_FETCH obviously needs free movement. SHOCK was originally a tween to
## Anchor_Shock, but that left the trainee standing in a fixed pose with
## clamped look and no way to turn to the AED — the stand-clear worked, the
## shock was unreachable. Standing back to the player's own camera is the same
## pull-back to standing height the contract asks for, and it leaves the AED
## reachable through the ordinary crosshair like every other CPR interaction.
## shock_button.arm() is then called explicitly, since there is no longer a
## camera landing for it to react to.
func _stand_up() -> void:
	if not _awaiting_stand_up or camera_rig == null:
		return
	_awaiting_stand_up = false
	if current_state == STATE_SHOCK and shock_button != null:
		camera_rig.released.connect(_on_stood_up_for_shock, CONNECT_ONE_SHOT)
	camera_rig.release_smooth()


## The crouch key, once the trainee is already on their feet.
##
## SHOCK does NOT toggle - see STANCE_TOGGLE_STATES. It used to, and the claim
## that stood here, that "the stand-clear already happened and is not un-done by
## kneeling back down to press the button", was simply not true of the code:
## ShockButton._on_activate() reads `trainee_at_anchor()` at the moment of press
## and fires the fatal violation. Following this docstring ended the run.
##
## The toggle covers BREATHING_CHECK and both compression states. The
## trainee has business away from the body during them — the two-way radio on
## the bench is the one that bit: help is called after the response check, and
## from the kneel there was no way to get to your feet before AED_FETCH, a good
## two minutes later. Kneeling again returns to that state's own anchor.
##
## AED_FETCH deliberately does not toggle: the trainee walks across the room in
## that beat, and snapping them back to the casualty from wherever they had got
## to would be a teleport, not a stance change.
##
## Returns true if the key was used, so the caller knows whether to swallow it.
func _handle_stance_key() -> bool:
	if _awaiting_stand_up:
		_stand_up()
		return true
	if not STANCE_TOGGLE_STATES.has(current_state):
		return false
	if camera_rig == null or _cpr_rig == null:
		return false
	if camera_rig.active:
		camera_rig.release_smooth()
		return true
	var anchor := _cpr_rig.anchor_for_state(current_state)
	if anchor == null:
		return false
	camera_rig.move_to(anchor)
	return true


func _on_stood_up_for_shock() -> void:
	# Guard the state: a phase reset or a debug jump could land the release
	# somewhere else entirely between the tween starting and finishing.
	if current_state != STATE_SHOCK:
		return
	if shock_button != null and shock_button.has_method("arm"):
		shock_button.arm()


## The prompt names whatever key `crouch` is actually bound to, rather than
## hard-coding one — the action is otherwise unused while the CPR camera holds
## an anchor, since Player is frozen for the duration.
func _stand_up_prompt() -> String:
	return "Press %s to stand up" % key_name_for(&"crouch")


## Printable name of an action's first key binding. Shared with
## cpr_key_hint.gd so the corner chip and the centre prompts can never disagree
## about which key it is.
##
## Deliberately not InputEvent.as_text(): that renders a physical binding as
## "C (Physical)", which is engine bookkeeping, not something to put in front of
## a trainee.
static func key_name_for(action: StringName) -> String:
	for event in InputMap.action_get_events(action):
		var key := event as InputEventKey
		if key == null:
			continue
		var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		if code != KEY_NONE:
			return OS.get_keycode_string(code)
	# `interact` is bound to the left mouse button, not a key, so the key loop
	# above finds nothing and the old fallback printed the raw action name —
	# "hold interact at the mouth". Mouse bindings get a real name.
	for event in InputMap.action_get_events(action):
		var button := event as InputEventMouseButton
		if button == null:
			continue
		match button.button_index:
			MOUSE_BUTTON_LEFT: return "Left Click"
			MOUSE_BUTTON_RIGHT: return "Right Click"
			MOUSE_BUTTON_MIDDLE: return "Middle Click"
			_: return "Mouse %d" % button.button_index
	return String(action)


# --- Events reactions ----------------------------------------------------------------
# Each handler ignores the fact unless the station is in the state it belongs
# to, so a stray or replayed signal can't double-advance the spine.

## Records the check and stops there. It used to call _enter_state(
## COMPRESSIONS_1) directly, which meant finishing the hold at the mouth threw
## the trainee straight into the compression beat — camera swung to the kneel
## anchor, panel up, metronome running — with no decision in between.
##
## The spine now waits on the "Start compressions" pointer, the same one that
## drives it when the breathing check is skipped entirely. Both routes into
## COMPRESSIONS_1 go through begin_compressions_early(), so starting
## compressions is always something the trainee chose.
func _on_breathing_checked(_breathing: bool) -> void:
	if current_state != STATE_BREATHING_CHECK:
		return
	_time_to_breathing_check = _elapsed_seconds()
	# Points at the next assessment, not at compressions: the airway inspection
	# and the pulse check now sit between the two, and the pulse check is what
	# licenses the compressions.
	Events.center_message_requested.emit(
		"No breathing. Check the airway for a blockage.", Tokens.ATTENTION, 4.0
	)


func _on_compression_delivered(depth: float, rate: float, index: int) -> void:
	if current_state != STATE_COMPRESSIONS_1 and current_state != STATE_COMPRESSIONS_2:
		return
	if _time_to_first_compression < 0.0:
		_time_to_first_compression = _elapsed_seconds()
	_compression_reps += 1
	# Milestones are per set, off the driver's own 0-based rep index, not off
	# the cumulative metric: the second set is now a full 30 and reports its
	# progress the same way the first does, but `_compression_reps` is already
	# past 30 by then and would never match.
	if COMPRESSION_MILESTONES.has(index + 1):
		_message("%d compressions" % (index + 1))
	if depth >= 0.75:
		_in_depth_reps += 1
	if rate >= 100.0 and rate <= 120.0:
		_in_rate_reps += 1


## Set 1 no longer hands straight to AED_FETCH. The client walked their
## "no need to open the shirt" note back to "compressions first, then open the
## shirt for the AED" (docs/OVERNIGHT_PLAN.md §1 item 5), so the shirt comes off
## between the two. Casualty.attach_pads() already refused without
## `chest_exposed`; that guard now does real work.
func _on_compression_set_completed(_count: int, assisted: bool) -> void:
	if assisted:
		_assisted = true
	if current_state == STATE_COMPRESSIONS_1:
		# EXPOSE_CHEST's only exit is `step_completed(chest_exposed)`, and
		# Assessment.complete() is silent on a step that is already complete
		# (assessment.gd:109). So a run that got the shirt open early — the
		# [F10] warps do exactly that, and nothing stops a future route doing
		# the same — would enter a state it could never leave. Skip it instead.
		if _chest_already_exposed():
			_enter_state(STATE_AED_FETCH)
		else:
			_enter_state(STATE_EXPOSE_CHEST)
	elif current_state == STATE_COMPRESSIONS_2:
		# Client item 8: the run no longer ends at the second set. Return of
		# spontaneous circulation, then the recovery position, the injury survey
		# and the handover — three beats that used to be cut (PROJECT_STATUS.md
		# §1 said not to re-add the recovery position without asking; this is the
		# asking and the answer was yes).
		_enter_state(STATE_RECOVERY_ROLL)
		var casualty := _casualty()
		if casualty != null:
			# Wired, not rewritten: _achieve_rosc() already sets State.ROSC,
			# completes `signs_of_life` and moves SimState to RECOVERY.
			casualty.achieve_rosc()


## True when the shirt is already open, by either measure — the casualty's own
## flag or the checklist step. They can disagree: a dev warp completes the step
## directly, and Casualty.expose_chest() sets the flag before completing it.
func _chest_already_exposed() -> bool:
	if Assessment.is_complete(&"chest_exposed"):
		return true
	var casualty := _casualty()
	return casualty != null and casualty.chest_exposed


## EXPOSE_CHEST's exit. The shirt is opened by the "Open the shirt" body pointer
## calling Casualty.expose_chest(), which completes the step — there is no CPR
## fact on the bus for it, so the checklist step is what this listens to.
func _on_step_completed(step_id: StringName, _elapsed: float) -> void:
	if step_id == &"send_for_help":
		_on_help_called()
		return
	if step_id != &"chest_exposed":
		return
	if current_state != STATE_EXPOSE_CHEST:
		return
	_enter_state(STATE_AED_FETCH)


func _on_aed_picked_up() -> void:
	if current_state != STATE_AED_FETCH:
		return
	_enter_state(STATE_AED_DEPLOY)


func _on_aed_placed() -> void:
	if current_state != STATE_AED_DEPLOY:
		return
	_pads_placed_count = 0
	_enter_state(STATE_PAD_PLACEMENT)


func _on_aed_pad_placed(_slot: int, correct: bool, _site_name: String) -> void:
	if current_state != STATE_PAD_PLACEMENT:
		return
	if correct:
		_pads_correct += 1
	else:
		_pad_errors += 1
	_pads_placed_count += 1
	if _pads_placed_count >= PAD_TARGET:
		_enter_state(STATE_SHOCK)
	else:
		# CPR_CONTRACT.md §4.4: never say whether the site was right — only
		# that a pad went down. The error surfaces in the debrief.
		_message("Pad %d of %d attached" % [_pads_placed_count, PAD_TARGET])


func _on_aed_shock_delivered() -> void:
	if current_state != STATE_SHOCK:
		return
	_time_to_shock = _elapsed_seconds()
	# Hand the decision back to the body pointers: post-shock compressions are
	# resumed by taking the pill, not by arriving in the state. See
	# `compressions_armed` and scripts/ui/casualty_action_menu.gd.
	compressions_armed = false
	_enter_state(STATE_COMPRESSIONS_2)


# --- metrics -------------------------------------------------------------------------

func _elapsed_seconds() -> float:
	return float(Time.get_ticks_msec() - _phase_start_ms) / 1000.0


func _reset_metrics() -> void:
	_phase_start_ms = 0
	_compression_reps = 0
	_in_depth_reps = 0
	_in_rate_reps = 0
	_time_to_breathing_check = 0.0
	_time_to_first_compression = -1.0
	_time_to_shock = 0.0
	_pad_errors = 0
	_pads_correct = 0
	_pads_placed_count = 0
	_assisted = false


func _finish_phase() -> void:
	if camera_rig != null:
		camera_rig.release()
	var pct_in_depth := 0.0
	var pct_in_rate := 0.0
	if _compression_reps > 0:
		pct_in_depth = float(_in_depth_reps) / float(_compression_reps)
		pct_in_rate = float(_in_rate_reps) / float(_compression_reps)
	var metrics := {
		"total_compressions": _compression_reps,
		"pct_in_depth": pct_in_depth,
		"pct_in_rate": pct_in_rate,
		"time_to_breathing_check": _time_to_breathing_check,
		"time_to_first_compression": maxf(_time_to_first_compression, 0.0),
		"time_to_shock": _time_to_shock,
		"pad_errors": _pad_errors,
		"pads_correct": _pads_correct,
		"assisted": _assisted,
	}
	Events.cpr_completed.emit(metrics)


# =============================================================================
# CPR_CONTRACT.md section 9 — integration seams owned by the human, not
# guessed at here. How each maps onto this station:
#
# 1. Instancing CprStation and calling enter_cpr_phase() — see the class
#    docstring above for the exact call shape. Nothing in main.tscn/main.gd
#    does this yet.
#
# 2. Calling CprStation.begin_breathing_check() when the chest-expose swap
#    happens — this station only exposes the method; nothing marks "chest
#    exposed" as an Events fact for it to react to on its own.
#
# 3. Wiring `cpr_completed` metrics into Assessment and the debrief — this
#    station only emits the signal with a populated dictionary (see
#    _finish_phase() above); it does not touch Assessment itself.
#
# Seams 4-5 (audio assets, FpsArms) do not touch this file at all.
# =============================================================================
