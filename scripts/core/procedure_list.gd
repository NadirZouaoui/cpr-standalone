class_name ProcedureList
extends Resource
## The full ordered checklist for an exercise.
##
## One resource holds every step, so the client can reorder, reweight or
## rewrite the whole procedure in the Godot inspector without touching a
## single line of code.

## Display and evaluation order. Prerequisites are declared per step, so
## this array's order only drives the HUD checklist and debrief layout.
@export var steps: Array[ProcedureStep] = []

## Percentage needed to pass, before critical-step and fatal checks.
@export_range(0, 100) var pass_mark: int = 80


func find(id: StringName) -> ProcedureStep:
	for step in steps:
		if step.id == id:
			return step
	return null
