class_name DecisionList
extends Resource
## Every decision point in the exercise, the way ProcedureList collects steps.
##
## Adding a branch is an entry here plus one dispatch-table line. Not frozen.

@export var decisions: Array[DecisionPoint] = []


func find(id: StringName) -> DecisionPoint:
	for decision in decisions:
		if decision != null and decision.id == id:
			return decision
	return null
