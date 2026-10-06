class_name HazardList
extends Resource
## One pass of the hazard assessment: the lines offered, the checklist step
## they grade, and the wording around them.
##
## Mirrors KitManifest. Two of these ship - `hazards_pass1.tres`, read from the
## floor with the board shut, and `hazards_pass2.tres`, read once the board is
## open - because the busbars cannot honestly be named before the door is off
## them (docs/OVERNIGHT_PLAN.md section 5, Task 4).
##
## **Every line in both files is invented.** The client supplied no hazard
## content; it was authored during the overnight run and verified against the
## room's mesh inventory rather than against anything they said. One entry has
## since been deleted outright on Nadir's instruction - the lighting hazard,
## which described a blackout the simulation does not model. Nothing here
## may be shown to them as though it were theirs. `review_notes()` exists so
## the handover report can print the outstanding questions instead of
## pretending there are none.

## Shown as the panel's heading.
@export var heading: String = "Which hazards are present?"

## Checklist step this pass grades. Completed with a quality factor rather
## than pass/fail: `Assessment.complete(step_id, quality)`.
@export var step_id: StringName = &""

## The step that must already be complete before this pass may be answered at
## all. Empty means no gate. Pass 2 sets `panel_opened`, which is the entire
## reason the assessment is split in two.
@export var requires_step: StringName = &""

## Shown when the trainee reaches the panel before `requires_step` is done.
@export_multiline var locked_message: String = ""

@export var items: Array[HazardItem] = []

@export_group("Copy")
## The pill that submits the ticked set. Sits at the bottom of the stack, and
## submits to the REVIEW CARD rather than to the grader - the pass is not
## closed until the trainee confirms it there.
@export var submit_label: String = "Submit assessment"

## The review card's own words. Authored here rather than in the panel for the
## same reason the lines themselves are: the client can reword any of it
## without a rebuild.
##
## All of it must stay neutral. The card reads the trainee's ticked set back to
## them and says nothing whatever about it - which is exactly what makes
## grading the correction honest, where the old marked-up retry could not be.
@export var review_heading: String = "You have reported these hazards"

## Shown as the single line when nothing at all was ticked, so the card is
## never raised empty.
@export var review_empty_line: String = "You have not reported any hazards."

## The two pills at the foot of the review card: back to the list, or lock it
## in. Neither is styled as the right one and neither may read as one.
##
## They are phrased as the two things the trainee can DO, not as a judgement.
## "Correct" and "Confirm" were both a C-word of the same length in the same
## pill and read as the same button; worse, "Correct" can be heard as "this is
## correct", which is the one thing this card must never say.
@export var review_correct_label: String = "Go back and change"
@export var review_confirm_label: String = "Submit answer"


## How many entries are genuinely hazards. The denominator of the quality
## factor, and the number the panel can honestly tell the trainee to look for.
func real_count() -> int:
	var n := 0
	for item in items:
		if item != null and item.is_real:
			n += 1
	return n


func find(id: StringName) -> HazardItem:
	for item in items:
		if item != null and item.id == id:
			return item
	return null


## Scramble the order the lines are offered in. Called once per run, before
## anything reads the list.
##
## Authoring order puts every real hazard first and the distractors after them,
## because that is how the answer key is easiest to WRITE - and it is also how
## the answer is easiest to READ. Playtest: "the hazards list is ordered, real
## hazards then fake." A trainee who notices that can tick the top of the stack
## and score full marks without reading a word of it.
##
## The shuffle is of `items` itself, so a row index means the same thing to the
## panel, to the grader and to the review card, exactly as it did before. The
## answer key travels with the entry; nothing anywhere keys off a position.
##
## In memory only. The .tres on disk keeps its authoring order, which is the
## order the client edits and the handover report prints.
##
## ONCE per run, not per opening. The stack must not reorder itself between the
## first attempt and the correction - the trainee would have to re-read all of
## it to find the pill they just ticked.
func shuffle_items() -> void:
	items.shuffle()


## Labels in the order the panel shows them - the run's shuffled order, set by
## shuffle_items() at startup.
func labels() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for item in items:
		if item != null:
			out.append(item.label)
	return out


## Every entry still carrying an open question, as "id - note" lines. The
## handover report prints this; nothing in the runtime reads it.
func review_notes() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for item in items:
		if item != null and item.needs_review:
			out.append("%s - %s" % [item.id, item.review_note])
	return out


## Catches a list edited into an ungradable state. Checked at startup rather
## than trusted: a pass with no real hazards would divide by zero, and a pass
## with no distractors would score full marks for ticking everything.
func validate() -> String:
	if items.is_empty():
		return "no items"
	if step_id == &"":
		return "no step_id"
	if real_count() == 0:
		return "no item is marked is_real - the quality factor would divide by zero"
	if real_count() == items.size():
		return "every item is marked is_real - ticking everything would score full marks"

	var ids := {}
	var labels_seen := {}
	for item in items:
		if item == null or item.id == &"":
			return "an item has no id"
		if ids.has(item.id):
			return "duplicate item id '%s'" % item.id
		ids[item.id] = true
		if item.label == "":
			return "item '%s' has no label" % item.id
		if labels_seen.has(item.label):
			return "two items are both worded '%s'" % item.label
		labels_seen[item.label] = true
	return ""


## The quality factor for a ticked set, as CPR_CONTRACT.md's existing scale:
## (hits - false positives) / real count, floored at 0 and capped at 1.
##
## This grades the SETTLED set - the one the trainee confirmed on the review
## card - not their first submission. Nothing marks a wrong line any more, so
## correcting is no longer free and no longer has to be worth nothing.
##
## Lives here rather than in the controller so the arithmetic is testable
## without booting a scene, and so it sits next to the answer key it reads.
##
## Ticking everything does NOT score full marks - that is the point of the
## distractors. Ticking nothing scores zero. The step is still *completed*
## either way: the trainee did carry out an assessment, they just carried out
## a poor one, and Assessment.complete's own doc comment is explicit that a
## quality-0.0 completion is a completion.
func quality_for(ticked: Array) -> float:
	var real := real_count()
	if real <= 0:
		return 0.0
	var hits := 0
	var false_positives := 0
	for id in ticked:
		var item := find(id)
		if item == null:
			continue
		if item.is_real:
			hits += 1
		else:
			false_positives += 1
	return clampf(float(hits - false_positives) / float(real), 0.0, 1.0)
