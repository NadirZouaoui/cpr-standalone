class_name DecisionOption
extends Resource
## One button on a decision point: something the trainee could physically go
## and do next, plus what taking it means for the grade.
##
## A decision chooses an intent and never performs the act. `intent` is routed
## by decision_screen.gd's dispatch table; nothing here calls into the world.
## See DECISION_POINTS.md section 2.

## Stable identifier, written to the transcript.
@export var id: StringName = &""

## The button face.
@export var label: String = ""

## One line under the label: why you would pick this.
@export_multiline var detail: String = ""

## Routed by the controller's dispatch table. See DECISION_POINTS.md 4.3.
@export var intent: StringName = &""

## Whether this is the right call at this moment. Exactly one option should
## normally be correct - the timeout path presents the first correct option's
## routing so the run continues.
@export var correct: bool = false

## Recorded through Assessment.record_violation() when a wrong option is taken.
@export_multiline var violation_reason: String = ""

## Shown briefly after the pick, right or wrong.
@export_multiline var feedback: String = ""
