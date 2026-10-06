class_name KitBench
extends Node
## Owns the kit check: what is on the bench, what the trainee has claimed as
## rescue kit, and what that claim is worth.
##
## **One interaction, not two.** Clicking a bench object brings the naming
## menu straight up, and naming it is what claims it as kit. Clicking an
## object that is already claimed takes the claim back. Anything never clicked
## is an object the trainee is saying is NOT in the bag - which is half of
## what is being tested, and the reason there is no "not in the kit" entry on
## the menu: an option like that would put the answer key's own question in
## front of the trainee every time they looked at a spanner.
##
## [Enter] reads their list back to them on the shared review card
## (review_panel_3d.gd, raised over the Events bus and tagged `kit_review`).
## Correct returns to the bench with every claim exactly as they left it;
## Confirm grades the whole thing as the `kit_identified` step and ends the
## check.
##
## **Nothing tells the trainee they got a name wrong.** The menu used to
## strike the pill out in red and take a second answer on the spot; that was
## the one verdict in the whole exercise given at the time, and the review
## card has replaced the job it was doing. A trainee who wants to change an
## answer clicks the object again, which takes the claim back, and names it
## afresh - so the correction is theirs to spot, which is the same rule every
## other beat in this exercise follows.
##
## **The settled answer is what scores**, and a re-naming is still recorded as
## a correction: `_first_answers` keeps whatever they said the first time, so
## the transcript can still say "answered X, corrected to Y" for the debrief
## and the LMS.
##
## Binds a KitInspectItem onto each named mesh in the imported room, the same
## way ToolRack binds PickupItems - the .blend subtree is rebuilt on every
## reimport, so anything wired in the editor would be lost and any exported
## NodePath into it would go stale.
##
## Renaming an object in Blender silently breaks its binding, so `_ready`
## pushes a warning listing anything it could not find. That shows up on the
## first run rather than in a play test.
##
## No UI here at all. This decides *what* is asked and *whether* the answer
## was right; kit_check.gd, kit_identify_panel.gd and review_panel_3d.gd
## decide what that looks like on screen and in the world.

## The imported room. NodePath rather than a Node export, because a
## hand-written .tscn needs `node_paths=PackedStringArray(...)` for Node
## references and silently drops them otherwise.
@export var room_path: NodePath = ^"../ControlRoom"

## Leave empty to load the default manifest.
@export var manifest: KitManifest

## Off skips the phase entirely - the exercise starts in the room, as it did
## before this was added. Useful when iterating on the animation.
@export var enabled: bool = true

@export_group("Beacon")
## The same floating arrow the breaker panel puts over the cabinet door, over
## the bench for the naming task.
##
## The kit check is the first thing a trainee ever does and it is the one task
## with nothing in the room announcing itself: the cabinet has a door that is
## obviously shut and obviously openable, while the bench is a table with
## objects on it that look like scenery until you happen to put the crosshair
## on one. Trainees stood in the switchroom not knowing the exercise had
## started. The cabinet's arrow is already the vocabulary for "your objective
## is here", so the bench gets it too rather than a tutorial line.
@export var show_beacon: bool = true
## Above the mean top of the bench objects - see review_anchor(), which is the
## same point the review card hangs off. Clear of the tallest thing on the
## bench without floating free of it.
@export var beacon_offset: Vector3 = Vector3(0.0, 0.42, 0.0)

const DEFAULT_MANIFEST := "res://resources/kit/lvr_kit.tres"

## Our own tag on the shared review card. The hazard assessment raises the
## same card with its own contexts, so every handler here filters on this and
## ignores anything else that comes back.
const REVIEW_CONTEXT := &"kit_review"

## The review card's own words, authored here because the card is a pure view
## and writes none of its own copy. Neutral by construction: it reads the
## trainee's list back and says nothing about any line on it.
const REVIEW_HEADING := "You have named these as LV rescue kit"
const REVIEW_EMPTY_LINE := "You have not named anything as rescue kit."
## Phrased as the two things the trainee can do, not as a judgement - see the
## same pair on HazardList. "Correct" read as "this is correct".
const REVIEW_CORRECT := "Go back and change"
const REVIEW_CONFIRM := "Submit answer"

enum Stage { NAMING, REVIEW, DONE }

## item id -> {
##     "correct":      bool,   THE GRADE. Whether the settled answer was right.
##     "choice":       String, the first label they ever gave this object.
##     "corrected":    bool,   true when they re-named it after a retraction.
##     "final_choice": String, what they settled on - == "choice" when they
##                             got it first time.
## }
##
## An entry existing IS the claim: the trainee has said this object is rescue
## kit. Taking the claim back erases the entry, so this dictionary is the one
## record of what they are pointing at, in the order they pointed at it.
##
## Both attempts are kept on purpose. The debrief and the SCORM comments have
## to be able to say "answered X, corrected to Y" even though it is the
## correction that scores.
var answers: Dictionary = {}

## The stage the check is in. NAMING from bind until [Enter]; REVIEW while the
## card is up; DONE once confirmed, or once the exercise has started.
var stage: int = Stage.NAMING

var _items: Dictionary = {}       ## item id -> KitInspectItem
var _asking: StringName = &""     ## the id the naming menu is currently putting to the trainee
var _active: bool = false

## item id -> the FIRST label the trainee ever gave that object, kept even
## after they take the claim back. Taking a claim back erases the answer, so
## without this a trainee who re-named an object would read as having got it
## right first time and the "correction noted" the client asked for would be
## lost with the retraction.
var _first_answers: Dictionary = {}

var _beacon: ObjectiveBeacon = null
## Set by the first claim, and never cleared: taking a claim back does not
## un-find the bench. See _refresh_beacon().
var _touched: bool = false


func _ready() -> void:
	if not enabled:
		return

	if manifest == null:
		manifest = load(DEFAULT_MANIFEST) as KitManifest
	if manifest == null:
		push_error("KitBench: no KitManifest at '%s'" % DEFAULT_MANIFEST)
		return

	var problem := manifest.validate()
	if problem != "":
		push_error("KitBench: manifest is unusable - %s" % problem)
		return

	# A reloaded scene mid-exercise must not put the bench back into
	# inspection mode behind a casualty who is already on the floor.
	if not SimState.is_preamble():
		return

	_bind_all()
	_set_bench_live(true)
	# After _bind_all: the arrow is placed off the bound objects' own bounds,
	# so there is nothing to place it over until they exist.
	_build_beacon()

	stage = Stage.NAMING
	_active = true
	Events.kit_stage_changed.emit.call_deferred(stage)
	# Deferred with the stage for the same reason it is: the room's transforms
	# are still settling on the frame this node enters the tree, and an arrow
	# positioned now lands somewhere near the world origin.
	_refresh_beacon.call_deferred()

	Events.kit_item_inspected.connect(_on_item_inspected)
	Events.kit_answer_submitted.connect(_on_answer_submitted)
	Events.review_answered.connect(_on_review_answered)
	Events.simulation_started.connect(_on_simulation_started)
	# The naming menu and the review card are blocking screens, and the arrow
	# hangs behind them rather than over them.
	Events.ui_opened.connect(func(_n): _refresh_beacon())
	Events.ui_closed.connect(func(_n): _refresh_beacon())


func _unhandled_input(event: InputEvent) -> void:
	if not _active or stage != Stage.NAMING:
		return
	# A naming menu is up and owns [Enter]. The review is what happens after
	# it closes, never over the top of it.
	if _asking != &"":
		return
	if not event.is_action_pressed(&"ui_accept"):
		return
	# The brief and the closing card also listen for keyboard activation via
	# their focused buttons; while any blocking screen is up, [Enter] is its.
	if Events.is_ui_blocking():
		return
	get_viewport().set_input_as_handled()
	_request_review()


# =============================================================================
# Binding
# =============================================================================
func _bind_all() -> void:
	var room := get_node_or_null(room_path)
	if room == null:
		push_error("KitBench: no room at '%s'." % room_path)
		return

	var missing: Array[String] = []
	for item in manifest.items:
		if item == null or item.node == "":
			continue
		if not _bind(room, item):
			missing.append(item.node)

	if not missing.is_empty():
		push_warning(
			"KitBench: %d object(s) not found in the room - renamed in Blender? %s"
			% [missing.size(), ", ".join(missing)]
		)


func _bind(room: Node, item: KitItem) -> bool:
	var mesh := room.get_node_or_null(NodePath(item.node)) as Node3D
	if mesh == null:
		# The cabinet and a few props sit deeper in the .blend subtree than a
		# direct child lookup reaches. CprGhost's recursive search is the
		# established way into the rebuilt room.
		mesh = CprGhost.find_node(room, item.node) as Node3D
	if mesh == null:
		return false

	var inspect := KitInspectItem.new()
	# Not "Interact" - ToolRack already put one of those here, and two nodes
	# cannot share a name under the same parent.
	inspect.name = "KitInspect"
	inspect.id = item.id
	inspect.item_id = item.id
	inspect.display_name = item.title
	mesh.add_child(inspect)
	_items[item.id] = inspect

	# Same treatment ToolRack gives its props: interactable without leaving
	# the world layer, so they still behave like solid objects.
	for body in _bodies(mesh):
		body.collision_layer |= 2

	return true


func _bodies(root: Node) -> Array[CollisionObject3D]:
	var out: Array[CollisionObject3D] = []
	if root is CollisionObject3D:
		out.append(root)
	for child in root.get_children():
		out.append_array(_bodies(child))
	return out


## The crosshair offers a bench object only while the trainee is working the
## bench. The naming menu and the review card are picked with that same
## crosshair and that same button, so an object left live behind either of
## them is activated by the interaction ray before the panel ever sees the
## click.
func _set_bench_live(live: bool) -> void:
	for inspect in _items.values():
		(inspect as KitInspectItem).naming_active = live


# =============================================================================
# The bench - claiming and un-claiming
# =============================================================================
## A click on a bench object. On an unclaimed one it raises the naming menu,
## and naming it is what claims it. On one already claimed it takes the claim
## back - the only way to change your mind, and the reason the old sweep's
## toggle idiom survives the merge into a single interaction.
func _on_item_inspected(item_id: StringName) -> void:
	if not _active or stage != Stage.NAMING:
		return
	# One question at a time. The menu is modal in everything but name.
	if _asking != &"":
		return
	var item := manifest.find(item_id)
	if item == null:
		push_warning("KitBench: no manifest entry for '%s'" % item_id)
		return
	if not _items.has(item_id):
		return

	if answers.has(item_id):
		_unclaim(item)
	else:
		_ask(item)


func _ask(item: KitItem) -> void:
	_asking = item.id
	(_items[item.id] as KitInspectItem).set_marked(true)
	_set_bench_live(false)
	Events.kit_question_requested.emit(item.id, _choices_for(item))


## Retraction, logged where it happens. Without this line the transcript would
## still carry "Identified the Torch" for an object the trainee thought better
## of, and the debrief would be reporting a claim that was withdrawn.
func _unclaim(item: KitItem) -> void:
	answers.erase(item.id)
	(_items[item.id] as KitInspectItem).set_claimed(false)
	Events.log_action(&"preparation", "Took back the claim on %s" % item.title,
		&"info", "No longer named as rescue kit.")
	Events.kit_selection_toggled.emit(item.id, false)


## The trainee has already decided this object is kit gear by clicking it, so
## there is no reject option: the question is genuinely "what is this called".
## The asked object's own true title is always in the list - that is what
## makes a wrongly claimed wrench answerable - and every wrong answer comes
## from the manifest's distractor pool, which is equipment that is nowhere in
## the room. Drawing them from the manifest itself, as this used to, let the
## whole menu be solved by reading the labels off the bench.
func _choices_for(item: KitItem) -> PackedStringArray:
	var pool: Array[String] = []
	for label in manifest.name_distractors:
		if label != item.title:
			pool.append(label)
	pool.shuffle()

	var names: Array[String] = []
	var wanted := maxi(manifest.choices_per_question - 1, 0)
	for candidate in pool:
		if names.size() >= wanted:
			break
		names.append(candidate)
	names.append(item.title)
	names.shuffle()

	return PackedStringArray(names)


func _on_answer_submitted(item_id: StringName, choice: String) -> void:
	if not _active or stage != Stage.NAMING:
		return
	if item_id != _asking:
		return
	var item := manifest.find(item_id)
	if item == null:
		return

	var correct := choice == item.title

	# The answer stands, right or wrong, and the trainee is told nothing. The
	# only correction is the one they go looking for: click the object again to
	# take the claim back, then name it afresh.
	var first_choice: String = choice
	if _first_answers.has(item_id):
		first_choice = String(_first_answers[item_id])
	else:
		_first_answers[item_id] = choice

	answers[item_id] = {
		"correct": correct,
		"choice": first_choice,
		"corrected": first_choice != choice,
		"final_choice": choice,
	}
	_asking = &""

	(_items[item_id] as KitInspectItem).set_claimed(true)
	_set_bench_live(true)

	# The rationale rides along in the detail field so the teaching text
	# survives into the LMS comments rather than dying with the manifest.
	# A re-naming carries both answers in one line, in the order they were
	# given, because that is what the debrief and the LMS have to be able to
	# say about it.
	var headline := "Identified %s" % item.title
	var detail := ""
	if answers[item_id]["corrected"]:
		headline = ("Misidentified %s, then corrected it" if correct
			else "Misidentified %s twice") % item.title
		detail = "Answered: %s, corrected to: %s. %s" % [
			answers[item_id]["choice"], choice, item.rationale]
	elif not correct:
		headline = "Misidentified %s" % item.title
		detail = "Answered: %s. %s" % [choice, item.rationale]
	Events.log_action(&"preparation", headline, &"ok" if correct else &"error", detail)

	Events.kit_answer_recorded.emit(item_id)
	Events.kit_selection_toggled.emit(item_id, true)

	if not _touched:
		_touched = true
		_refresh_beacon()


# =============================================================================
# Review and confirm
# =============================================================================
## The claims, in the order they were made. Claim order rather than manifest
## order on purpose: manifest order puts the whole kit first and the bench
## tools after it, so re-sorting the read-back into it would quietly cluster a
## trainee's right answers at the top of their own list.
func claims() -> Array[StringName]:
	var out: Array[StringName] = []
	for id in answers:
		out.append(id)
	return out


## What the trainee claimed, in the words THEY claimed it with - never the
## true titles. That is the whole point of reading it back: a trainee who
## called the crook a "Hooking Pole" sees "Hooking Pole" on the card and can
## go and fix it.
func review_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	for id in answers:
		lines.append(String(answers[id]["final_choice"]))
	if lines.is_empty():
		lines.append(REVIEW_EMPTY_LINE)
	return lines


## Where the review card hangs. Derived from the bench objects themselves,
## because their transforms come out of the .blend and nothing in this project
## may hold a world coordinate for them (ARCHITECTURE.md section 1). The mean
## of every bound object's bounding-box top puts it over the middle of the
## bench at about the height of the things on it; the card lifts itself
## further by its own stack height from there, which is what carries it up to
## reading height.
func review_anchor() -> Vector3:
	var tops: Array[Vector3] = []
	for inspect in _items.values():
		var ki := inspect as KitInspectItem
		var mesh := ki.mesh_to_highlight
		if mesh == null:
			tops.append(ki.global_position)
			continue
		var aabb := mesh.get_aabb()
		tops.append(mesh.to_global(
			aabb.get_center() + Vector3(0.0, aabb.size.y * 0.5, 0.0)))

	if tops.is_empty():
		return Vector3.ZERO

	var centre := Vector3.ZERO
	for point in tops:
		centre += point
	return centre / float(tops.size())


func _request_review() -> void:
	if stage != Stage.NAMING:
		return
	stage = Stage.REVIEW
	_set_bench_live(false)
	_refresh_beacon()
	Events.kit_stage_changed.emit(stage)
	Events.review_requested.emit(REVIEW_CONTEXT, REVIEW_HEADING, review_lines(),
		REVIEW_CORRECT, REVIEW_CONFIRM, review_anchor())


## Correct puts the trainee back in front of the bench with every claim
## exactly as they left it - nothing here clears anything, and the card can be
## raised again as often as they like. Confirm is the only thing that grades.
func _on_review_answered(context: StringName, confirmed: bool) -> void:
	if context != REVIEW_CONTEXT:
		return
	if not _active or stage != Stage.REVIEW:
		return
	if confirmed:
		_finish()
		return
	stage = Stage.NAMING
	_set_bench_live(true)
	_refresh_beacon()
	Events.kit_stage_changed.emit(stage)


# =============================================================================
# Beacon
# =============================================================================
## Parented to the room rather than to a bench object, for the reason every
## binding in this file is done in code: the .blend subtree is rebuilt on every
## reimport and anything hanging off one of its nodes goes with it.
func _build_beacon() -> void:
	if not show_beacon or _items.is_empty():
		return
	var room := get_node_or_null(room_path) as Node3D
	if room == null:
		return
	_beacon = ObjectiveBeacon.build(room, "KitBenchBeacon", "Kit bench")
	if _beacon != null:
		_beacon.show_beacon(false)


## Up only while there is naming left to do AND the trainee has not started.
## Down for the naming menu and the review card - both are blocking screens the
## arrow would hang behind, and the card hangs off review_anchor() itself, which
## is the point this is floating over.
##
## Playtest: "remove yellow arrows once trainee interacts with kit/panel." The
## arrow answers one question - where do I go - and the first claim is proof it
## has been answered. Left up for the whole sweep it stops being an instruction
## and becomes decoration over the thing the trainee is already working on.
func _refresh_beacon() -> void:
	if _beacon == null:
		return
	var wanted := _active and stage == Stage.NAMING and not _touched 		and not Events.is_ui_blocking()
	if wanted:
		_beacon.global_position = review_anchor() + beacon_offset
	_beacon.show_beacon(wanted)


# =============================================================================
# Grading
# =============================================================================
## Settled names that were wrong, over the claims the trainee made. The
## correction counts: this reads the settled answer, not the first attempt.
func errors() -> int:
	var n := 0
	for id in answers:
		if not answers[id]["correct"]:
			n += 1
	return n


## Every manifest entry is a judgement, including the ones the trainee made by
## leaving an object alone: a kit item claimed is right, a kit item left alone
## is wrong, a bench tool left alone is right, a bench tool claimed is wrong.
## Correct judgements over the whole manifest.
func selection_accuracy() -> float:
	var judgements := 0
	var right := 0
	for item in manifest.items:
		if item == null:
			continue
		judgements += 1
		if item.in_kit == answers.has(item.id):
			right += 1
	if judgements == 0:
		return 0.0
	return float(right) / float(judgements)


## Settled names that were right, over the number of objects named. An empty
## set is 0.0 rather than 1.0: there is nothing to be accurate about, and
## perfect marks for naming nothing would pay for doing nothing.
func naming_accuracy() -> float:
	if answers.is_empty():
		return 0.0
	return float(answers.size() - errors()) / float(answers.size())


## THE GRADE, and an INVENTED one - the client specified neither this formula
## nor any other. Half of it is what the trainee decided is in the bag, half
## is whether they know what those things are called. Two skills, weighted the
## same, because the brief treats them as one act.
##
## The step is always COMPLETED, never failed. `Assessment.fail()` closes a
## step as never done and records a violation against it, which is the wrong
## account of a trainee who did the check and got some of it wrong;
## `Assessment.complete()` at quality 0.0 is still a completion and still
## earns nothing, which is exactly this case (assessment.gd, `complete()`).
## There is also no threshold left to fail against - the old `allowed_errors`
## went with the merge, and a merged step that scores continuously has no
## honest cliff in it.
func quality() -> float:
	return 0.5 * selection_accuracy() + 0.5 * naming_accuracy()


func _finish() -> void:
	if stage == Stage.DONE:
		return
	stage = Stage.DONE
	_set_bench_live(false)
	_refresh_beacon()
	for inspect in _items.values():
		(inspect as KitInspectItem).set_marked(false)

	# The answer key, applied once, and only into the transcript - the trainee
	# finds out how they did in the debrief, with the rest of the exercise,
	# not at the moment they confirm.
	var missed: Array[String] = []
	var wrongly: Array[String] = []
	var misnamed: Array[String] = []
	for item in manifest.items:
		if item == null:
			continue
		if answers.has(item.id):
			if not item.in_kit:
				wrongly.append(item.title)
				Events.log_action(&"preparation", "Wrongly included %s" % item.title,
					&"error", "Named as rescue kit. %s" % item.rationale)
			if not answers[item.id]["correct"]:
				misnamed.append(item.title)
		elif item.in_kit:
			missed.append(item.title)
			Events.log_action(&"preparation", "Missed %s" % item.title, &"error",
				"Never named as rescue kit. %s" % item.rationale)

	var clean := missed.is_empty() and wrongly.is_empty() and misnamed.is_empty()
	Events.log_action(&"preparation",
		"Kit check confirmed: %d of %d kit items named, %d tool(s) wrongly included, %d misnamed"
			% [manifest.kit_size() - missed.size(), manifest.kit_size(),
				wrongly.size(), misnamed.size()],
		&"ok" if clean else &"error",
		"Missed: %s. Wrongly included: %s. Misnamed: %s." % [
			", ".join(missed) if not missed.is_empty() else "none",
			", ".join(wrongly) if not wrongly.is_empty() else "none",
			", ".join(misnamed) if not misnamed.is_empty() else "none",
		])

	Assessment.complete(manifest.step_id, quality())

	Events.kit_stage_changed.emit(stage)
	Events.kit_check_finished.emit()


## The exercise proper has begun, whatever way it was reached - a DevMenu
## warp calls begin_exercise directly with the check still live. Stand down
## quietly: drop the marks so nothing keeps glowing over a CPR phase.
func _on_simulation_started() -> void:
	_active = false
	stage = Stage.DONE
	_asking = &""
	_set_bench_live(false)
	# The arrow only re-decides on a UI change; the exercise starting is not
	# one, and a stale arrow over the bench now draws an edge marker too.
	_refresh_beacon()
	for inspect in _items.values():
		(inspect as KitInspectItem).set_marked(false)
