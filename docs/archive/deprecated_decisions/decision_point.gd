class_name DecisionPoint
extends Resource
## A blocking question asked at a real branch in the procedure. Authored as a
## resource so a new branch is a .tres and a dispatch-table line, not a rewrite.
##
## Same shape and spirit as ProcedureStep: decisions are data, not code.
## See DECISION_POINTS.md section 3.

enum Trigger {
	## Fires on Events.step_completed with `trigger_value` as the step id.
	STEP_COMPLETED,
	## Fires on Events.cpr_state_changed arriving at `trigger_state`.
	CPR_STATE,
	## Fires on Events.phase_changed arriving at `trigger_state`.
	PHASE,
}

## Stable identifier.
@export var id: StringName = &""

## The question.
@export var title: String = ""

## Optional context paragraph under the question.
@export_multiline var body: String = ""

## Transcript grouping, as on ProcedureStep.
@export var category: StringName = &"general"

## Assessment step this decision itself completes. Empty means the decision is
## logged and graded but carries no points of its own.
@export var step_id: StringName = &""

@export_group("Trigger")
@export var trigger_kind: Trigger = Trigger.STEP_COMPLETED

## Step id, for STEP_COMPLETED. Ignored by the other kinds.
@export var trigger_value: StringName = &""

## CprStation state constant or SimState.Phase, for CPR_STATE / PHASE. Split
## from `trigger_value` because a StringName cannot hold either enum, and both
## autoloads are out of reach from a Resource at load time.
@export var trigger_state: int = -1

## Steps that must already be complete, or the decision does not fire.
@export var requires: Array[StringName] = []

## Steps that, if complete, make the question moot - it is dropped, not queued.
@export var unless: Array[StringName] = []

@export_group("Content")
## Two to four. The order shown is the order authored.
@export var options: Array[DecisionOption] = []

@export_group("Grading")
## 0 leaves the decision untimed. Otherwise, running out records the decision
## as hesitated - a warning, no violation - and routes the correct option.
@export var time_limit: float = 0.0

## Points contributed when `step_id` is set and the pick is correct. Mirrors
## the weight on the matching ProcedureStep; the step resource is what scores.
@export var weight: int = 5


func matches(kind: Trigger, step: StringName, state: int) -> bool:
	if trigger_kind != kind:
		return false
	if kind == Trigger.STEP_COMPLETED:
		return trigger_value == step
	return trigger_state == state


## The option routed when the timer runs out. First correct one, else the
## first authored - a decision with no correct answer still has to continue.
func default_option() -> DecisionOption:
	for option in options:
		if option != null and option.correct:
			return option
	return options[0] if not options.is_empty() else null
