class_name ProcedureStep
extends Resource
## One checklist item in the LVR / DRSABCD procedure.
##
## Steps are data, not code. Reordering the procedure, adding a step, or
## changing what counts as critical should never require touching the grader.

## Stable identifier. Referenced by `requires` and emitted in signals.
@export var id: StringName = &""

## Shown on the HUD checklist.
@export var title: String = ""

## Longer text shown in the debrief when this step is failed or skipped.
@export_multiline var prompt: String = ""

## Grouping for the debrief breakdown, e.g. &"danger", &"isolation", &"cpr".
@export var category: StringName = &"general"

## Steps that must already be complete. Doing this step first is an
## out-of-order violation, which is scored but does not block progress -
## trainees should see the consequence of their real sequence, not be railroaded.
@export var requires: Array[StringName] = []

## Points contributed when completed correctly.
@export var weight: int = 5

## A critical step failed or skipped fails the whole assessment regardless
## of points. Danger check and proving-dead are the obvious candidates.
@export var critical: bool = false

@export_group("Gating")
## Earliest SimState.Phase at which this step should be offered on the HUD.
## -1 leaves it ungated.
##
## Prerequisites answer "what must already be done"; this answers "has the
## exercise reached the point where this makes sense". PPE is the case that
## forced it: it depends on nothing but seeing the hazard, yet offering it
## while the worker is still safely fiddling at the panel tells the trainee
## something is about to go wrong.
##
## Typed as int rather than SimState.Phase because SimState is an autoload
## and this is a Resource - the enum is not reachable at load time. Values
## follow SimState.Phase: 0 KIT_CHECK, 1 BRIEFING, 2 SCENE_SAFETY,
## 3 BREAK_CONTACT, 4 EXTRACTION, 5 PRIMARY_SURVEY, 6 RESUSCITATION,
## 7 RECOVERY, 8 DEBRIEF.
##
## Display only. Completing a gated step early is still recorded and still
## scored - the gate hides the hint, it does not railroad the trainee.
@export var min_phase: int = -1

@export_group("Display")
## When set, the HUD names this step by the referenced step's title instead of
## its own - the gotcha mechanism. A step whose prompt is deliberately
## withheld points at the step the trainee *should* be worrying about, so the
## screen keeps saying one thing while the grading still expects the hidden
## one. Chain resolution stops at the first step without its own `display_as`.
@export var display_as: StringName = &""

## The step exists and is graded, but the HUD never offers it. The trainee is
## meant to recall it on their own; skipping it costs exactly what it would
## cost in the field.
@export var suppress_prompt: bool = false

## Draw the step pill in danger red, flashing. Reserved for the one moment
## where seconds of delay are the injury itself.
@export var urgent: bool = false

@export_group("Timing")
## Seconds allowed after all prerequisites are met. 0 disables the window.
## Used for "send for help within 10s of finding no response" style rules.
@export var time_limit: float = 0.0

## Shown when the step is completed but outside `time_limit`.
@export_multiline var late_detail: String = ""


func has_time_limit() -> bool:
	return time_limit > 0.0
