class_name KitManifest
extends Resource
## The bench contents, the wording and the wrong answers for the kit check.
##
## Mirrors ProcedureList: one resource holds the whole exercise, so the
## wording, the item set and the distractor names are all editable in the
## inspector without touching the interaction or UI code.

@export var title: String = "Identify the Low Voltage Rescue Kit"

## Shown on the opening brief under the title. One instruction, because there
## is one interaction: naming an object is what claims it as kit, and leaving
## one alone is what says it is not.
@export_multiline var instruction: String = ""

## Shown on the card that closes the phase. Must stay neutral - it is the
## same text whether the trainee named everything correctly or nothing.
@export_multiline var closing_note: String = ""

@export var items: Array[KitItem] = []

@export_group("Questions")
## Buttons per naming menu: the asked object's own true title plus this many
## minus one drawn from `name_distractors`.
@export_range(2, 8) var choices_per_question: int = 4

## Heading on the naming menu.
@export var question: String = "Identify this item"

## The wrong answers, and the only source of them. LV rescue and CPR equipment
## that is plausible for the bag and is NOWHERE in the room: the menu used to
## draw its distractors from the manifest itself, which meant a trainee could
## solve every question by looking round the bench for the other names.
##
## Data rather than code so the client can re-author them without a build -
## the same reasoning the hazard lists are resources for.
@export var name_distractors: PackedStringArray = PackedStringArray()

@export_group("Rules")
## Checklist step the check completes. Always completed, with a quality
## factor rather than a pass or a fail - KitBench.quality() is where that is
## worked out and argued.
@export var step_id: StringName = &"kit_identified"


## How many items actually belong in the kit. The denominator in the
## transcript summary; nothing on screen ever shows it, because a count of
## how many are left to find is a count the trainee could watch.
func kit_size() -> int:
	var n := 0
	for item in items:
		if item != null and item.in_kit:
			n += 1
	return n


## Every in-kit name. Not the choice pool - the wrong answers all come from
## `name_distractors` now - just the answer key in one list, for anything that
## needs to talk about what is in the bag.
func kit_titles() -> Array[String]:
	var out: Array[String] = []
	for item in items:
		if item != null and item.in_kit:
			out.append(item.title)
	return out


func find(id: StringName) -> KitItem:
	for item in items:
		if item != null and item.id == id:
			return item
	return null


## Catches a manifest edited into an unanswerable state. Checked at startup
## rather than trusted, because a duplicate title or a short distractor pool
## would make a question unanswerable in a way that looks like a UI bug from
## the trainee's side.
func validate() -> String:
	if items.is_empty():
		return "no items"
	if kit_size() == 0:
		return "no item is marked in_kit"
	if kit_size() == items.size():
		return "every item is marked in_kit"

	var ids := {}
	var titles := {}
	for item in items:
		if item == null or item.id == &"":
			return "an item has no id"
		if ids.has(item.id):
			return "duplicate item id '%s'" % item.id
		ids[item.id] = true
		if item.title == "":
			return "item '%s' has no title" % item.id
		if titles.has(item.title):
			return "two items are both called '%s'" % item.title
		titles[item.title] = true

	var wanted := choices_per_question - 1
	if name_distractors.size() < wanted:
		return "only %d name distractor(s) for %d wrong choice(s)" % [
			name_distractors.size(), wanted
		]
	var seen := {}
	for label in name_distractors:
		if label == "":
			return "a name distractor is empty"
		if seen.has(label):
			return "duplicate name distractor '%s'" % label
		seen[label] = true
		# A distractor that is also a bench object's real name puts that name
		# back in the pool, which is the leak the pool was moved out of the
		# manifest to close.
		if titles.has(label):
			return "name distractor '%s' is also a bench object's title" % label
	return ""
