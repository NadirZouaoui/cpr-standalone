extends Node
## What the rescuer is wearing and holding.
##
## Separate from SimState because this is the rescuer's own condition rather
## than the exercise's progress, and separate from Assessment because the
## fatal-contact rule needs to consult it in real time, before any grading
## decision is made.

## Item currently in hand, or &"" for empty-handed.
var held_item: StringName = &""

## PPE items donned. Keys are item ids; a complete set is required before
## approaching the hazard.
var ppe_worn: Dictionary = {}

## Items taken from the room and kept on the person: not PPE, so they are
## nothing to do with the hazard gate, and not the held item, so picking up
## the hook does not put them down. The torch is the only one today. Keys are
## item ids.
var stowed: Dictionary = {}

## Everything that must be worn before the hazard zone is safe to enter.
const REQUIRED_PPE: Array[StringName] = [&"insulated_gloves", &"safety_boots", &"long_sleeves"]

## PPE the rescuer arrives already wearing, seeded at startup.
##
## The room only contains gloves. Boots and sleeves are site dress worn
## before entering a switchroom at all, not something picked up off a bench,
## and there are no objects for them - so `is_ppe_complete()` could never
## return true, `ppe_donned` could never be completed, and `ppe_donned` is a
## critical step. Every run failed on it, and `crook_retrieved` (which
## requires it) was logged as out-of-order on top.
##
## Seeding them keeps the checklist honest about what full PPE means while
## matching what the room actually offers. If boots or sleeves ever become
## pickups, delete them from here and the gate tightens by itself.
const STARTING_PPE: Array[StringName] = [&"safety_boots", &"long_sleeves"]

## Items that make it safe to contact an energised casualty.
const INSULATED_ITEMS: Array[StringName] = [&"rescue_crook"]

## PPE that must also be on before the hook is trustworthy. Gloves are the
## last line of defence if the hook is wet, cracked or wrongly gripped, so a
## bare-handed grab on an insulated hook is still a fatal contact.
const CONTACT_PPE: Array[StringName] = [&"insulated_gloves"]


func _ready() -> void:
	_seed_starting_ppe()


func _seed_starting_ppe() -> void:
	for item in STARTING_PPE:
		ppe_worn[item] = true


func equip(item_id: StringName) -> void:
	held_item = item_id


func drop() -> void:
	held_item = &""


## Take an item onto the person for good. There is no un-stow: a torch in a
## pocket stays in the pocket, and nothing in the exercise asks for it back.
func stow(item_id: StringName) -> void:
	stowed[item_id] = true


func has_stowed(item_id: StringName) -> bool:
	return stowed.has(item_id)


func is_holding(item_id: StringName) -> bool:
	return held_item == item_id


## True when the held item can safely break contact with a live conductor.
func is_holding_insulated() -> bool:
	return held_item in INSULATED_ITEMS


func has_contact_ppe() -> bool:
	for item in CONTACT_PPE:
		if not ppe_worn.has(item):
			return false
	return true


## The full gate: insulated hook in hand AND insulated gloves on. Anything
## else that reaches the casualty is a fatal contact.
func can_break_contact() -> bool:
	return is_holding_insulated() and has_contact_ppe()


## Why the gate failed, phrased for the fatality message. Empty when it did
## not fail.
func unsafe_contact_reason() -> String:
	var no_hook := not is_holding_insulated()
	var no_gloves := not has_contact_ppe()
	if no_hook and no_gloves:
		return "with no insulated gloves and no rescue hook"
	if no_gloves:
		return "without insulated gloves"
	if held_item == &"":
		return "bare-handed"
	return "using something other than the insulated rescue hook"


func don_ppe(item_id: StringName) -> void:
	ppe_worn[item_id] = true
	if is_ppe_complete():
		Assessment.complete(&"ppe_donned")


func is_ppe_complete() -> bool:
	for item in REQUIRED_PPE:
		if not ppe_worn.has(item):
			return false
	return true


func missing_ppe() -> Array[StringName]:
	var out: Array[StringName] = []
	for item in REQUIRED_PPE:
		if not ppe_worn.has(item):
			out.append(item)
	return out


func reset() -> void:
	held_item = &""
	ppe_worn.clear()
	stowed.clear()
	_seed_starting_ppe()
