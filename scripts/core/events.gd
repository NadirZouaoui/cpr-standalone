extends Node
## Global signal bus.
##
## Nothing in this project should reach across the tree with
## get_tree().current_scene.find_child() or has_method() probing.
## Emit here, connect here.

# --- Interaction ---------------------------------------------------------
## Raycast started/stopped pointing at something interactable.
signal focus_changed(interactable: Node)
## Player activated whatever they were looking at.
signal interacted(interactable: Node, from_position: Vector3)
## Something wants a line of text on the reticle prompt. "" clears it.
signal prompt_requested(text: String)

# --- Simulation phase ----------------------------------------------------
signal phase_changed(previous: int, current: int)

# --- Procedure / assessment ---------------------------------------------
## A checklist step was satisfied. `step_id` matches a ProcedureStep.id.
signal step_completed(step_id: StringName, elapsed: float)
## A checklist step was attempted out of order or performed wrongly.
signal step_violated(step_id: StringName, reason: String)
## A checklist step was resolved as failed and will never be completed.
## Distinct from `step_violated`, which is a mark against a step the trainee
## may still finish - this one closes it.
signal step_failed(step_id: StringName, reason: String)
## Any gradable event, correct or not. Assessment logs these verbatim.
signal action_logged(category: StringName, message: String, status: StringName, detail: String)

# --- Kit identification --------------------------------------------------
## KitInspectItem -> KitBench. The trainee clicked a bench object. The object
## itself has no idea what that means; the bench decides what a click does -
## on an unclaimed object it raises the naming menu, on a claimed one it takes
## the claim back.
signal kit_item_inspected(item_id: StringName)
## KitBench -> UI. A claim was made or withdrawn. Carries no judgement on it:
## `claimed` is what the trainee did, not whether they were right.
signal kit_selection_toggled(item_id: StringName, claimed: bool)
## KitBench -> UI. The check moved between its stages. Values are
## KitBench.Stage - NAMING, REVIEW, DONE.
signal kit_stage_changed(stage: int)
## KitBench -> UI (the diegetic naming menu). Here is the object to name and
## the answers to offer, already shuffled. The panel renders them and nothing
## more - it does not know which one is right.
signal kit_question_requested(item_id: StringName, choices: PackedStringArray)
## Panel -> KitBench. The choice they aimed at and picked, by label.
signal kit_answer_submitted(item_id: StringName, choice: String)
## KitBench -> UI. The answer was accepted and the object is claimed, so the
## menu can close. Carries no verdict on purpose, and now there are no
## exceptions anywhere in the check: the trainee is told nothing about the
## name they gave or about whether the object belongs in the bag until the
## debrief. `kit_answer_rejected`, which told them a first name was wrong on
## the spot, is retired - the review card is where a claim gets corrected.
signal kit_answer_recorded(item_id: StringName)
## KitBench -> UI. The bench is done. No pass flag - showing one here would
## be the feedback this phase is deliberately withholding.
signal kit_check_finished()

# --- Hazard assessment ---------------------------------------------------
## An interactable asks for a hazard pass to be put up - the breaker door for
## pass 1, the busbars for pass 2. HazardAssessment decides whether it may be,
## which is where the `panel_opened` gate on pass 2 actually lives.
signal hazard_assessment_requested(step_id: StringName)
## HazardAssessment -> UI (the diegetic hazard panel). Here is the pass to put
## up, where to hang it, and the lines to offer, in authoring order. The panel
## renders them and nothing more - it never sees an id or an answer key.
signal hazard_question_requested(step_id: StringName, heading: String, options: PackedStringArray, submit_label: String, anchor: Vector3)
## Panel -> HazardAssessment. The ticked set, as indices into the options the
## panel was opened with, ascending.
signal hazard_answer_submitted(step_id: StringName, picks: PackedInt32Array)
## HazardAssessment -> UI. The trainee chose Correct on the review card, so the
## pass goes back up with `picks` re-ticked exactly as they left them. The panel
## clears its ticks when it is opened, so it cannot simply be reopened - and
## re-reading their own list off a blank panel is not a correction.
##
## There used to be a `hazard_answer_marked` here, which told the panel which
## lines were wrong so it could tint them amber and red. It is gone. Marking the
## lines is what made grading the correction dishonest - once the wrong ones are
## named, fixing them costs nothing - and the marks were the only reason the
## first attempt had to be the graded one.
signal hazard_panel_resumed(step_id: StringName, picks: PackedInt32Array)
## HazardAssessment -> UI. The pass is closed and graded. `quality` is the
## SETTLED set's score - what the trainee confirmed on the review card, not
## what they first submitted; `corrected` says whether they went back at all.
signal hazard_answer_recorded(step_id: StringName, quality: float, corrected: bool)

# --- Review and confirm --------------------------------------------------
## One shared panel serves both the kit check and the hazard assessment: the
## trainee submits, is shown their own answer read back to them, and either
## goes back to change it or locks it in. The client asked for exactly that in
## both places - "if incorrect should be able to correct at that stage with
## the correction noted" for the bag, and the same shape for the hazards - so
## it is built once and used twice (review_panel_3d.gd).
##
## **Nothing on that card says which picks are right or wrong.** The panel
## never sees an answer key and the controller never sends it one; the whole
## card is neutral, and the verdict stays where every other verdict in this
## exercise lives, in the debrief. The kit check's per-item "that is not what
## this is called" is a separate beat and is untouched by this.
##
## Controller -> panel. `context` is the caller's own tag, echoed back on the
## answer so two callers can share one panel without either one guessing;
## `lines` is the answer read back, already worded by the caller.
signal review_requested(context: StringName, heading: String, lines: PackedStringArray, correct_label: String, confirm_label: String, anchor: Vector3)
## Panel -> controller. `confirmed` false is Correct (go back and change it),
## true is Confirm (lock it in and score it). The panel is down either way.
signal review_answered(context: StringName, confirmed: bool)

# --- Casualty ------------------------------------------------------------
signal casualty_state_changed(state: int)
## The rescuer knelt at the casualty; the action menu should open.
signal casualty_actions_requested(casualty: Node)

# --- Electrical ----------------------------------------------------------
signal supply_isolated(source_id: StringName)
signal supply_restored(source_id: StringName)

# --- Session -------------------------------------------------------------
signal simulation_started()
signal simulation_finished(passed: bool, score: int)
## Fatal safety violation - rescuer became a second casualty.
signal fatal_violation(reason: String)

# --- UI ------------------------------------------------------------------
signal ui_opened(ui_name: StringName)
signal ui_closed(ui_name: StringName)
signal center_message_requested(text: String, color: Color, duration: float)


## Which blocking UIs are currently up. Replaces the substation project's
## habit of scanning CanvasLayer names for "pause"/"intro"/"end".
var open_uis: Dictionary = {}


func open_ui(ui_name: StringName) -> void:
	open_uis[ui_name] = true
	ui_opened.emit(ui_name)


func close_ui(ui_name: StringName) -> void:
	open_uis.erase(ui_name)
	ui_closed.emit(ui_name)


func is_ui_blocking() -> bool:
	return not open_uis.is_empty()


func log_action(category: StringName, message: String, status: StringName = &"info", detail: String = "") -> void:
	action_logged.emit(category, message, status, detail)


signal cpr_phase_entered()
signal breathing_checked(breathing: bool)
signal compression_delivered(depth: float, rate: float, index: int)
signal compression_set_completed(count: int, assisted: bool)
signal aed_picked_up()
signal aed_placed()
signal aed_pad_hovered(site_name: String)
signal aed_pad_placed(slot: int, correct: bool, site_name: String)
signal stand_clear_confirmed()
signal aed_shock_delivered()
signal cpr_state_changed(from: int, to: int)
signal cpr_completed(metrics: Dictionary)
