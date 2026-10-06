class_name KitItem
extends Resource
## One object on the bench in the kit identification check.
##
## Data, not code, for the same reason ProcedureStep is: the client will want
## to add, remove and reword these without a build. `in_kit` is the answer
## key - everything else is presentation.

## Stable identifier. Matches the ToolRack / Rescuer id where the item is
## also pickable once the exercise starts, so the two systems agree on what
## a thing is called even though they bind it for different reasons.
@export var id: StringName = &""

## Node name in the imported room, exactly as it arrives in Godot. Godot
## strips the `-col` / `-convcol` import suffixes, so "Hook-convcol" in
## Blender is "Hook" here. Must resolve: an entry with no mesh behind it is
## still a judgement in the grading and the trainee has no way to make it, so
## KitBench warns about every one it cannot bind.
@export var node: String = ""

## The correct answer for this object, whether or not it belongs in the bag.
##
## Every object is answerable by its own real name: the trainee has already
## said this one is kit by clicking it, so the menu asks what it is called,
## not whether it belongs. "Claw Hammer" is the right name for an object that
## is still not kit, and the two judgements are scored separately.
@export var title: String = ""

## One line under the title. Authoring notes for whoever edits the manifest -
## nothing on screen draws it, and the review card is deliberately the
## trainee's own words rather than ours.
@export var description: String = ""

## THE ANSWER KEY. True when this belongs in the low voltage rescue kit.
@export var in_kit: bool = false

## Carried into the transcript and the LMS comments beside whatever the
## trainee did with this object, right or wrong. This is where the teaching
## actually happens, so it should say *why*, not restate the answer.
@export_multiline var rationale: String = ""

## Optional artwork, unused by the current screens. Kept so an illustrated
## debrief can be authored without re-editing every item.
@export var icon: Texture2D
