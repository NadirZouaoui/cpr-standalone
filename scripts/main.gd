extends Node3D
## Walkable base scene. Nothing but the environment, the player, and enough
## lighting to see. The simulation systems exist but are not wired in yet.

## Spawned rather than authored into main.tscn: the room is rebuilt on every
## .blend reimport and the editor has dropped properties out of that file
## before, so anything the exercise cannot run without is created in code.
const PauseMenuScript := preload("res://scripts/ui/pause_menu.gd")
const DevMenuScript := preload("res://scripts/ui/dev_menu.gd")
const MeshProbeScript := preload("res://scripts/debug/mesh_probe.gd")
const FreeCameraScript := preload("res://scripts/debug/free_camera.gd")
const DebriefScreenScript := preload("res://scripts/ui/debrief_screen.gd")
const ChoiceCardScript := preload("res://scripts/ui/choice_card_3d.gd")
const ReviewPanelScript := preload("res://scripts/ui/review_panel_3d.gd")
const ExtractionPointersScript := preload("res://scripts/ui/extraction_pointers.gd")
const HelpGuideScript := preload("res://scripts/ui/help_guide.gd")
const ControlsTutorialScript := preload("res://scripts/ui/controls_tutorial.gd")
const EdgeIndicatorsScript := preload("res://scripts/ui/edge_indicators.gd")
const CasualtyPillScript := preload("res://scripts/ui/casualty_pill.gd")

## CPR phase integration — CPR_CONTRACT.md section 9's seams, none of which
## belong to any CPR agent's file set. CprStation itself is frozen territory
## (Agent E) and is not wired into main.tscn, so this is the "entry script"
## every CPR brief points at instancing it once. See CPR_AGENTS.md, Agent I.
var _cpr_station: CprStation = null

## The clothed worker, as the .blend names it - the body the trainee watches
## collapse and then drags clear. `Casualty_CPR_Posed` is the other one.
const WORKER_MESH := "Boots1_002"


func _ready() -> void:
	# Before anything draws: the checklist tick and the debrief marks have no
	# glyph in the engine's own face, and only the web export shows it.
	Tokens.install_symbol_fallback()
	_spawn_pause_menu()
	_spawn_dev_menu()
	_spawn_mesh_probe()
	_spawn_free_camera()
	_spawn_debrief_screen()
	_spawn_help_card()
	_spawn_review_panel()
	_spawn_cpr_station()
	_spawn_extraction_pointers()
	_spawn_edge_indicators()
	_spawn_casualty_pill()
	_spawn_help_guide()
	_spawn_controls_tutorial()
	_repair_casualty_mesh()


## The casualty carries mesh defects that only show in the engine: coincident
## duplicate faces (one on each body's Teeth surface, which z-fights into the
## dark spot on the open mouth) and vertex normals on the body that light the
## shoulders as dark smudges. The clothing's shading is a separate problem,
## fixed at import in scripts/import/casualty_clothing_shading.gd.
##
## casualty_cpr.gd already carried the geometry half of this, but only ran it
## when the compressions phase built it - so every earlier beat of the exercise
## showed the broken mesh, and the casualty is in plain sight from the moment
## the trainee turns round. Running it here means what is on screen is the
## repaired mesh from the first frame; casualty_cpr.gd calling it again later
## finds the work already done.
##
## tools/check_casualty_geometry.tscn is the regression check.
func _repair_casualty_mesh() -> void:
	var posed := CprGhost.find_node(self, CasualtyCpr.CASUALTY_CPR_MESH) as MeshInstance3D
	if posed == null:
		push_error("Main: no node named '%s'; casualty mesh not repaired." % CasualtyCpr.CASUALTY_CPR_MESH)
	else:
		CasualtyCpr.repair_mesh(posed)

	# The clothed worker - the body the trainee watches collapse and drags clear
	# - is a second mesh carrying the same defects: the metal clothing that puts
	# the black patch under each arm, two doubled faces on its teeth, and a
	# handful of inverted normals. It is skinned and animated, so it is repaired
	# in place rather than split: nothing here touches positions or weights.
	var worker := CprGhost.find_node(self, WORKER_MESH) as MeshInstance3D
	if worker == null:
		push_error("Main: no node named '%s'; worker mesh not repaired." % WORKER_MESH)
		return
	CasualtyMeshRepair.repair(worker)


func _spawn_pause_menu() -> void:
	if has_node("PauseMenu"):
		return
	var menu := CanvasLayer.new()
	menu.name = "PauseMenu"
	menu.set_script(PauseMenuScript)
	add_child(menu)


# --- The help decision -------------------------------------------------------
## The one choice card of the run: the casualty has been found unresponsive,
## and the trainee must say what comes first. This is the gotcha that replaces
## the radio's old repeating nag - the card is the only thing that ever points
## at the radio, and picking "Perform CPR" is recorded, never blocked. The
## radio stays usable whatever they pick, and `send_for_help` is graded
## whenever the call actually goes out.
## Playtest: "we're told 'the casualty is not breathing' before we do breath
## check, should be 'casualty unresponsive'." The card fires on `check_response`
## completing, which is exactly one finding earlier than the old wording claimed
## - the airway has not been opened and the look-listen-feel hold has not been
## held, so the game was announcing a result the trainee is about to be asked to
## find. Unresponsiveness is what they have actually established at this point,
## and it is on its own enough to make the call.
const HELP_HEADING := "The casualty is unresponsive. What do you do first?"
const HELP_CHOICES: PackedStringArray = ["Call for help", "Perform CPR"]

## Fires once per run. Moot once the call has gone out: a trainee who used the
## radio before the response check never sees the question.
var _help_card: Node3D = null
var _help_card_spent: bool = false


func _spawn_help_card() -> void:
	if has_node("HelpCard"):
		return
	_help_card = ChoiceCardScript.new()
	_help_card.name = "HelpCard"
	add_child(_help_card)
	_help_card.choice_made.connect(_on_help_choice)
	Events.step_completed.connect(_on_help_card_trigger)


func _on_help_card_trigger(step_id: StringName, _elapsed: float) -> void:
	if _help_card == null:
		return

	# The radio answered while the card was up: the question is over either way.
	#
	# This runs BEFORE the `_help_card_spent` guard, and that ordering is the
	# whole point. Opening the card sets `spent`, so while this branch sat under
	# the guard it could never fire on the case its own comment describes - the
	# card would still be on screen with `choice_hold` still raised, which stands
	# every casualty pill down. A trainee who answered "call for help" by walking
	# to the radio and using it, instead of by clicking the pill that only points
	# at the radio, was left with the question hanging and no body pointer to
	# open the airway, start compressions or roll the casualty over: a stuck run,
	# entered by doing the right thing. Reproduced in game.
	if step_id == &"send_for_help":
		_help_card_spent = true
		if _help_card.is_open:
			_help_card.close()
		# Unconditional: the hold is this function's to release, and leaving it
		# raised is the failure above. Lowering one that was never raised is free.
		_set_choice_hold(false)
		return

	if _help_card_spent:
		return
	if step_id != &"check_response":
		return
	if Assessment.is_complete(&"send_for_help"):
		return
	_help_card_spent = true
	_set_choice_hold(true)
	_help_card.open_in_view(HELP_HEADING, HELP_CHOICES)


## The card scores nothing of its own. It used to complete a `prioritised_help`
## step, which put a second row in the debrief saying the same thing as
## "Send for help - call 000" five seconds later - the decision and the call
## graded twice over. `send_for_help` already carries the whole weight of this,
## including its 10 s limit, so the right answer here just points at the radio
## and the wrong one is recorded against the step it actually harms.
func _on_help_choice(index: int, _label: String) -> void:
	_set_choice_hold(false)
	if index == 0:
		Events.center_message_requested.emit(
			"The two-way radio is on the bench.", Tokens.ATTENTION, 3.0)
	else:
		Assessment.record_violation(&"send_for_help", "CPR started before help was called")
		Events.log_action(&"primary_survey", "Chose to perform CPR first", &"warning",
			"The call for help goes out first - one rescuer cannot run the resuscitation alone.")


## The casualty pill menu stands down while the card owns the screen, so there
## is exactly one live direction at a time.
func _set_choice_hold(on: bool) -> void:
	var menu := get_node_or_null("CasualtyActions")
	if menu != null and menu.has_method("set_choice_hold"):
		menu.set_choice_hold(on)


## The success half of the ending. FailScreen is authored into main.tscn, but
## that file is frozen, so the debrief is spawned here alongside the other
## code-added screens. It must exist before CprStation, because it listens
## for `cpr_completed`.
## The review-and-confirm card, spawned once and shared by the kit check and
## the hazard assessment - the two callers are never up at the same time (the
## kit check is preamble, the hazards are in-exercise) and the panel is keyed
## on the caller's own context tag, so one is enough.
##
## Spawned here rather than by either caller for exactly that reason: whichever
## of them built it would own it, and the other would be reaching across the
## tree for a node it does not own. Parented to Main rather than to
## get_tree().current_scene, which under a headless tool scene is the *tool* -
## a panel parented there outlives every reboot and keeps answering the bus.
func _spawn_review_panel() -> void:
	var panel: CanvasLayer = ReviewPanelScript.new()
	panel.name = "ReviewPanel"
	panel.owner = null
	add_child(panel)


func _spawn_debrief_screen() -> void:
	if has_node("DebriefScreen"):
		return
	var screen := CanvasLayer.new()
	screen.name = "DebriefScreen"
	screen.set_script(DebriefScreenScript)
	add_child(screen)


## [F10] jump-to-stage menu. Debug builds only - see DevMenu for the gate.
func _spawn_dev_menu() -> void:
	if has_node("DevMenu"):
		return
	var menu := CanvasLayer.new()
	menu.name = "DevMenu"
	menu.set_script(DevMenuScript)
	add_child(menu)

## [F8] reports the render triangle under the crosshair, and whether anything
## is z-fighting with it. Debug builds only - see MeshProbe for the gate.
func _spawn_mesh_probe() -> void:
	if has_node("MeshProbe"):
		return
	var probe := Node.new()
	probe.name = "MeshProbe"
	probe.set_script(MeshProbeScript)
	add_child(probe)


## Fly-through inspection camera, toggled from the [F10] menu. Debug builds
## only - see FreeCamera for the gate.
func _spawn_free_camera() -> void:
	if has_node("FreeCamera"):
		return
	var cam := Node.new()
	cam.name = "FreeCamera"
	cam.set_script(FreeCameraScript)
	add_child(cam)


## The extraction beat's two signposts - the casualty and the breaker. Spawned
## here rather than placed in main.tscn for the same reason everything else on
## this list is: the scene is frozen, and a node added in code with owner left
## null is never serialised into it (ARCHITECTURE.md §1).
##
## It owns nothing but its own pills; the phase gate those pills describe lives
## in Casualty._try_leave_extraction().
func _spawn_extraction_pointers() -> void:
	if has_node("ExtractionPointers"):
		return
	var pills := Node.new()
	pills.name = "ExtractionPointers"
	pills.set_script(ExtractionPointersScript)
	add_child(pills)
	pills.owner = null


## Screen-edge arrows to the yellow beacons and the live pills when they are
## out of view. See edge_indicators.gd.
func _spawn_edge_indicators() -> void:
	if has_node("EdgeIndicators"):
		return
	var layer := CanvasLayer.new()
	layer.name = "EdgeIndicators"
	layer.set_script(EdgeIndicatorsScript)
	add_child(layer)
	layer.owner = null


## The "Interact with casualty" pill. See casualty_pill.gd.
func _spawn_casualty_pill() -> void:
	if has_node("CasualtyPill"):
		return
	var pill := Node.new()
	pill.name = "CasualtyPill"
	pill.set_script(CasualtyPillScript)
	add_child(pill)
	pill.owner = null


## [H] Help: the standing chip, the what-to-do-now card and the guide arrow,
## plus the idle nudge. Client feedback 23 Sep 2026 - a tester stalled after the
## drag with the only live direction off screen. See help_guide.gd.
func _spawn_help_guide() -> void:
	if has_node("HelpGuide"):
		return
	var guide := CanvasLayer.new()
	guide.name = "HelpGuide"
	guide.set_script(HelpGuideScript)
	add_child(guide)
	guide.owner = null


## "How to play": one card per interaction, run once after the opening brief.
## See controls_tutorial.gd.
func _spawn_controls_tutorial() -> void:
	if has_node("ControlsTutorial"):
		return
	var tutorial := CanvasLayer.new()
	tutorial.name = "ControlsTutorial"
	tutorial.set_script(ControlsTutorialScript)
	add_child(tutorial)
	tutorial.owner = null


## Seam 1 (CPR_CONTRACT.md section 9): instance CprStation once. Entering the
## phase itself is deferred to Events.phase_changed reaching PRIMARY_SURVEY
## (see _on_phase_changed) rather than happening here — the station has to
## exist before that phase arrives, but must not start the spine before it.
func _spawn_cpr_station() -> void:
	if has_node("CprStation"):
		return
	_cpr_station = CprStation.new()
	_cpr_station.name = "CprStation"
	add_child(_cpr_station)
	Events.phase_changed.connect(_on_phase_changed)
	Events.step_completed.connect(_on_step_completed)
	Events.breathing_checked.connect(_on_breathing_checked)
	Events.cpr_completed.connect(_on_cpr_completed)


## Seam 1's other half: whatever precedes SimState.Phase.RESUSCITATION must
## start the CPR spine, because Casualty.start_compressions() — the only code
## that reaches RESUSCITATION today — fires after compressions have already
## begun, far too late for EXPOSE_CHEST and BREATHING_CHECK to run.
## PRIMARY_SURVEY is the phase the casualty enters the instant the drag
## finishes (Casualty.drag_to_safety()), which is the earliest point the CPR
## camera/interact bridge could possibly be needed. enter_cpr_phase() is
## idempotent, so a re-entrant phase_changed can't restart the spine.
func _on_phase_changed(_previous: int, current: int) -> void:
	if current == SimState.Phase.PRIMARY_SURVEY and _cpr_station != null:
		_cpr_station.enter_cpr_phase()
	if current > SimState.Phase.SCENE_SAFETY:
		_close_torch_window()


## `torch_taken` gates nothing and can be skipped; what it must not do is sit
## at the head of the checklist for the rest of the run when it is.
##
## Assessment.next_step() returns the first *unresolved* available step in list
## order, and both the objective pill and the checklist card read it. An
## optional step with no prerequisites and nothing to close it therefore
## becomes the answer to "what should I be doing" permanently the moment it is
## skipped, hiding every real objective behind it - which is exactly the fault
## docs/PLAYTEST_2026-09-04_pass2.md section 3 records "Perform the CPR set"
## causing for the whole second half of a run.
##
## Leaving SCENE_SAFETY is the honest moment to close it: the client's own
## words put the torch with the gloves, "before the work commences", and by
## BREAK_CONTACT the work has commenced. Failing it costs its 4 marks and puts
## it in the debrief, which is all it was ever meant to cost.
func _close_torch_window() -> void:
	if Assessment.steps.has(&"torch_taken") and not Assessment.is_resolved(&"torch_taken"):
		Assessment.fail(&"torch_taken",
			"The torch was never taken. It is a precaution to sort out before the "
			+ "work starts, alongside the gloves - once the incident is running "
			+ "there is no going back to the bench for it.")


## Seam 2, halved — and re-pointed. This is the backstop that guarantees the CPR
## phase has started even if the PRIMARY_SURVEY `phase_changed` landed before
## _spawn_cpr_station() ran; losing that race left current_state at -1 and the
## CPR camera never engaged (ARCHITECTURE.md §2). enter_cpr_phase() is idempotent,
## so a second call is free.
##
## It used to hang off `chest_exposed`. That step now happens AFTER the first
## compression set (the client asked for compressions with the shirt on, then the
## shirt open for the pads), which is far too late to be a safety net for a phase
## whose first beat is the breathing check — and firing enter_cpr_phase() that
## late, on a run where the phase somehow had not started, would have reset the
## metrics mid-procedure. Re-pointed at `breathing_checked` rather than deleted,
## because the phase_changed hook is the one that loses the race and something
## has to cover it.
##
## The real fix for that race is in CprStation.begin_breathing_check(), which now
## arms the phase itself if nothing else has: the "Check for breathing" body
## pointer is the door into the spine, so it is the honest place for the guard.
## This hook is the belt to that pair of braces.
##
## What it does not do is start the breathing check. That used to fire off
## `chest_exposed`, which forced the trainee to open the shirt before the airway
## could be assessed — the wrong way round for DRSABCD. The "Check for breathing"
## body pointer (scripts/ui/casualty_action_menu.gd) owns that trigger.
func _on_step_completed(step_id: StringName, _elapsed: float) -> void:
	if step_id == &"breathing_checked" and _cpr_station != null:
		_cpr_station.enter_cpr_phase()


## CPR_CONTRACT.md section 5: `breathing_checked` scores full/zero on its own
## and fires long before `cpr_completed` does (BREATHING_CHECK is the second
## CPR state; cpr_completed is the last), so it is graded straight off
## Events.breathing_checked rather than waiting for the whole spine to
## finish. An aborted hold re-prompts without emitting (CPR_CONTRACT.md
## §4.1), so every real emission earns the step.
func _on_breathing_checked(_breathing: bool) -> void:
	Assessment.complete(&"breathing_checked")


## CPR_CONTRACT.md section 5's other two steps, both graded once the whole
## spine finishes, and both now scored the way that section actually asks for:
## `cpr_performed` scaled by `pct_in_depth`, `aed_used` halved per incorrect
## pad site. Assessment.complete() takes a quality factor for exactly this.
##
## Before that existed the pair could only be marked done or failed, so the
## real performance went to the transcript and the score saw none of it - a
## set of forty compressions at 0% in depth scored the same fifteen points as
## forty good ones, which is the one thing a CPR trainer must not do. The
## transcript lines below are unchanged; they now explain a number the score
## already reflects rather than standing in for it.
func _on_cpr_completed(metrics: Dictionary) -> void:
	var pct_in_depth: float = metrics.get("pct_in_depth", 0.0)
	Assessment.complete(&"cpr_performed", pct_in_depth)
	Events.log_action(&"resuscitation",
		"Compression quality",
		&"ok" if pct_in_depth >= 0.75 else &"warning",
		"%.0f%% of compressions in depth, %.0f%% in rate over %d rep(s).%s" % [
			pct_in_depth * 100.0,
			metrics.get("pct_in_rate", 0.0) * 100.0,
			metrics.get("total_compressions", 0),
			" Fast-forward was used." if metrics.get("assisted", false) else "",
		]
	)

	# "Halved per incorrect pad site" (CPR_CONTRACT.md section 5), which lands
	# on zero at two wrong pads - the case the contract calls out explicitly.
	# Completed rather than failed even then: the AED was deployed and the
	# shock was delivered, so the step happened and satisfies what follows it.
	# It just earns nothing, and the contract is equally explicit that this is
	# never a fatal violation - that is reserved for the rescuer dying.
	var pad_errors: int = metrics.get("pad_errors", 0)
	Assessment.complete(&"aed_used", pow(0.5, float(pad_errors)) if pad_errors < 2 else 0.0)
	Events.log_action(&"resuscitation",
		"Pad placement",
		&"ok" if pad_errors == 0 else &"warning",
		"%d of 2 pads placed correctly." % int(metrics.get("pads_correct", 0))
	)


# Escape used to toggle the pointer lock here so an editor run was escapable.
# The pause menu owns that key now and releases the pointer itself by opening
# a blocking UI, so the two must not both answer it.
