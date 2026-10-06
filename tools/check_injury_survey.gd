extends Node
## The ambulance waits for the whole injury survey, not for the burn.
##
##   & "C:\Program Files\Godot.exe" --headless --path <project> res://tools/check_injury_survey.tscn
##
## WHY THIS EXISTS
##
## `CprStation.survey_injury()` used to complete `injuries_checked` and jump to
## HANDOVER the moment the site carrying the finding was checked - and that site
## is the hands, which is where an electrical casualty's entry wound is and
## therefore the first place a trainee who knows the trade looks. Going straight
## to it ended the run with the head and the legs never surveyed: the siren, the
## handover and the debrief, off one click. Reproduced on screen.
##
## The client's words are "check for any other injuries whilst help arrives".
## The burn is one of that survey's answers, not its terminator, and the whole
## point of the beat - stated in Casualty.INJURY_SITES' own comment - is that
## two clear sites are what make looking at the hands mean anything. A survey
## that stops at the first positive finding is not a survey.
##
## WHAT IS ASSERTED, and why the third one matters as much as the other two:
##
##   1. The finding site FIRST completes nothing and advances nothing. This is
##      the regression itself.
##   2. All three sites, in either order, complete `injuries_checked` and reach
##      HANDOVER on the last look. A gate that never opens would strand the run
##      one beat from the end, which is worse than what it replaced.
##   3. The finding still speaks AT ITS OWN SITE, not at the end. That immediacy
##      is the reward for knowing where to look and it is the thing most easily
##      lost when a completion is moved to the end of a loop - so it is asserted
##      by the words themselves, read out of Casualty.INJURY_SITES rather than
##      copied here, where a reworded finding would silently stop being checked.
##
## The site list is read from CprStation.INJURY_SITES, not written out here. A
## fourth site added to the callouts must make this check demand a fourth look
## rather than pass on three.
##
## Overlaps `scripts/cpr/cpr_headless_test.gd` on one case: that suite already
## walks head, legs, hands - the order in which the old code happened to behave
## correctly, which is exactly why it never caught this. Kept there and repeated
## here because it is the control the other order is read against.

const MAIN := preload("res://main.tscn")

var _failures: int = 0

## Every centre message since the last _clear_messages(), in order. The finding
## has to be found in the batch its own look produced, not merely somewhere in
## the run.
var _messages: PackedStringArray = PackedStringArray()

var _station: CprStation = null


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	# Let ControlRoom's .blend instance settle before anything binds to it.
	await get_tree().process_frame
	await get_tree().process_frame

	_station = CprStation.new()
	_station.name = "CprStation"
	add_child(_station)
	# Let every call_deferred("_build") binder in the CPR file set resolve.
	await get_tree().process_frame
	await get_tree().process_frame

	Events.center_message_requested.connect(
		func(text: String, _c: Color, _d: float) -> void: _messages.append(text))

	# survey_injury() reports through the casualty, so a scene without one would
	# make every assertion below vacuously true.
	var casualty := get_tree().get_first_node_in_group(&"casualty") as Casualty
	if not _ok(casualty != null, "the casualty is in the scene"):
		return _finish()

	var finding := _finding_site()
	if not _ok(finding != &"", "one site carries the finding"):
		return _finish()
	print("  the finding is at '%s'" % finding)

	# The finding first. This is the order that used to end the run in one look.
	print("\nThe finding first")
	await _survey(_ordered(finding, true), finding)

	# The finding last - the order cpr_headless_test already walks, kept as the
	# control. Both orders must land in the same place.
	print("\nThe finding last")
	await _survey(_ordered(finding, false), finding)

	_finish()


## One whole survey, taken in `order`. Asserts that nothing completes and
## nothing advances until the last site, that the finding speaks at its own
## site, and that the last look reaches HANDOVER.
func _survey(order: Array[StringName], finding: StringName) -> void:
	Assessment.reset()
	_station.reset()
	_station.debug_jump_to_state(CprStation.STATE_INJURY_SURVEY)
	# The handover refuses to summon an ambulance nobody called for, so this
	# run makes the call the way a trainee would before the survey begins.
	# Without it the station stalls at HANDOVER and the last assertion below
	# would be testing the help gate rather than the survey.
	Assessment.complete(&"send_for_help")
	await get_tree().process_frame
	if not _ok(_station.current_state == CprStation.STATE_INJURY_SURVEY,
			"the station is in INJURY_SURVEY"):
		return

	var finding_text: String = Casualty.INJURY_SITES[finding]["message"]

	for i in order.size():
		var site: StringName = order[i]
		var last: bool = i == order.size() - 1

		_messages = PackedStringArray()
		var found: bool = _station.survey_injury(site)
		await get_tree().process_frame

		_ok(found == (site == finding),
			"'%s' reports the finding: %s" % [site, found])
		# Assertion 3, both halves: at its own site the finding speaks, and
		# nowhere else does it.
		_ok(_messages.has(finding_text) == (site == finding),
			"the burn is announced at '%s': %s" % [site, _messages.has(finding_text)])

		if not last:
			_ok(not Assessment.is_complete(&"injuries_checked"),
				"after '%s', %d of %d looked at - injuries_checked waits"
				% [site, i + 1, order.size()])
			_ok(_station.current_state == CprStation.STATE_INJURY_SURVEY,
				"after '%s' the station is still in INJURY_SURVEY" % site)
			_ok(not Assessment.is_complete(&"handover"),
				"after '%s' the ambulance has not been called" % site)
			continue

		_ok(Assessment.is_complete(&"injuries_checked"),
			"the last look ('%s') completes injuries_checked" % site)
		_ok(_station.current_state == CprStation.STATE_HANDOVER,
			"the last look advances to HANDOVER")
		_ok(Assessment.is_complete(&"handover"), "handover completes")


## The site list with the finding at the front or at the back, built from
## CprStation.INJURY_SITES so a fourth site is surveyed rather than ignored.
func _ordered(finding: StringName, finding_first: bool) -> Array[StringName]:
	var rest: Array[StringName] = []
	for site in CprStation.INJURY_SITES:
		if site != finding:
			rest.append(site)
	if finding_first:
		rest.push_front(finding)
	else:
		rest.append(finding)
	return rest


## Which site carries the finding, read out of Casualty.INJURY_SITES rather
## than assumed. If the content ever moves to another site this check follows it
## instead of quietly testing the wrong one.
func _finding_site() -> StringName:
	for site in CprStation.INJURY_SITES:
		var entry: Dictionary = Casualty.INJURY_SITES.get(site, {})
		if bool(entry.get("finding", false)):
			return site
	return &""


func _ok(condition: bool, label: String) -> bool:
	if condition:
		print("  pass   %s" % label)
	else:
		_failures += 1
		print("  FAIL   %s" % label)
	return condition


func _finish() -> void:
	if _failures == 0:
		print("\ncheck_injury_survey: all assertions passed.")
		get_tree().quit()
		return
	printerr("\ncheck_injury_survey: %d assertion(s) FAILED." % _failures)
	get_tree().quit(1)
