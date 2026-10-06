extends Node
## Headless regression check for `resources/procedures/lvr_cpr_procedure.tres`.
##
##   & "C:\Program Files\Godot.exe" --headless --path <project> res://tools/check_procedure_order.tscn
##
## This is the contract every later task codes against (docs/OVERNIGHT_PLAN.md §2).
## It does not touch the scene tree - `Assessment` is an autoload and has already
## loaded the procedure by the time `_ready()` runs here - so it is cheap enough
## to run after every change to the resource.
##
## Checks, in order:
##   1. every `requires` id names a step that actually exists in the resource
##   2. the requires graph has no cycles
##   3. the critical-step weights sum below 100 (so no single critical miss can
##      make the run unpassable on points alone, on top of failing it outright)
##   4. completing every step once, in the resource's own array order, is a
##      valid happy path (no step is asked to complete before its own
##      prerequisites) and clears `pass_mark`
##   5. the bottom-centre step pill never names a beat the trainee is not in
##
## Exits non-zero on any failed assertion.

var _failures: int = 0


func _ready() -> void:
	_check_dangling_requires()
	_check_no_cycles()
	_check_critical_weight()
	_check_happy_path()
	_check_step_pill()

	if _failures == 0:
		print("\ncheck_procedure_order: all assertions passed.")
	else:
		printerr("\ncheck_procedure_order: %d assertion(s) FAILED." % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _ok(condition: bool, label: String) -> void:
	if condition:
		print("  pass   %s" % label)
	else:
		_failures += 1
		print("  FAIL   %s" % label)


func _section(title: String) -> void:
	print("\n%s" % title)


# =============================================================================
# 1. Dangling requires
# =============================================================================
func _check_dangling_requires() -> void:
	_section("Requires resolve to real steps")
	var dangling: Array[String] = []
	for id in Assessment.order:
		var step: ProcedureStep = Assessment.steps[id]
		for req in step.requires:
			if not Assessment.steps.has(req):
				dangling.append("%s -> %s" % [id, req])
	_ok(dangling.is_empty(), "no dangling requires %s" % ", ".join(dangling))


# =============================================================================
# 2. No cycles
# =============================================================================
func _check_no_cycles() -> void:
	_section("No cycles in the requires graph")
	var state: Dictionary = {}  # id -> 0 unvisited, 1 in-progress, 2 done
	var cycle_found := false
	var cycle_path := ""

	for id in Assessment.order:
		if state.get(id, 0) == 0:
			var path: Array[StringName] = []
			if _visit(id, state, path):
				cycle_found = true
				cycle_path = ", ".join(path.map(func(s): return String(s)))
				break

	_ok(not cycle_found, "cycle detected: %s" % cycle_path)


func _visit(id: StringName, state: Dictionary, path: Array[StringName]) -> bool:
	state[id] = 1
	path.append(id)
	var step: ProcedureStep = Assessment.steps.get(id)
	if step != null:
		for req in step.requires:
			if not Assessment.steps.has(req):
				continue  # reported separately by _check_dangling_requires
			var req_state: int = state.get(req, 0)
			if req_state == 1:
				path.append(req)
				return true
			if req_state == 0 and _visit(req, state, path):
				return true
	path.remove_at(path.size() - 1)
	state[id] = 2
	return false


# =============================================================================
# 3. Critical weight sum
# =============================================================================
func _check_critical_weight() -> void:
	_section("Critical-step weights")
	var total := 0
	for id in Assessment.order:
		var step: ProcedureStep = Assessment.steps[id]
		if step.critical:
			total += step.weight
	print("  info   critical weight sum = %d" % total)
	_ok(total < 100, "critical weights sum below 100 (%d)" % total)


# =============================================================================
# 4. Happy path
# =============================================================================
func _check_happy_path() -> void:
	_section("Happy path, resource array order")
	Assessment.reset()

	var out_of_order_ids: Array[String] = []
	for id in Assessment.order:
		var step: ProcedureStep = Assessment.steps[id]
		var missing := step.requires.filter(func(r): return not Assessment.is_complete(r))
		if not missing.is_empty():
			out_of_order_ids.append(String(id))
		Assessment.complete(id)

	_ok(out_of_order_ids.is_empty(),
		"array order satisfies every step's own requires %s" % ", ".join(out_of_order_ids))

	for id in Assessment.order:
		_ok(Assessment.is_complete(id), "'%s' completed on the happy path" % id)

	_ok(Assessment.failed_critical().is_empty(),
		"no critical step reads as failed/out-of-order: %s" %
		", ".join(Assessment.failed_critical().map(func(s): return String(s))))

	var pct := Assessment.score_percent()
	var mark: int = Assessment.procedure.pass_mark if Assessment.procedure != null else 80
	print("  info   score_percent = %d, pass_mark = %d" % [pct, mark])
	_ok(pct >= mark, "happy path clears pass_mark (%d%% >= %d%%)" % [pct, mark])
	_ok(Assessment.is_passed(), "Assessment.is_passed() true on the happy path")

	Assessment.reset()


# =============================================================================
# 5. What the step pill says, beat by beat
# =============================================================================
## `display_as` is the gotcha mechanism: a step whose own name would give the
## answer away points at the goal of the beat it sits in, and the HUD says that
## instead. It is only honest while the redirect stays inside its own beat.
##
## `ppe_donned` carried `display_as = contact_broken` left over from when PPE
## sat inside the break-contact window. Moving it to the front of the procedure
## - gloves on before work commences - left the redirect pointing five steps
## downstream, so the first pill of the run, straight out of the kit check with
## the worker still safely at the panel, was a flashing red "Break contact with
## the live hazard". Every gate was correct; only the sentence was wrong, which
## is why nothing else caught it.
##
## The invariant is `category`: a redirect speaks for the beat it is in, so its
## target must share that beat. Transitive reachability is not enough - almost
## everything in a linear procedure is downstream of almost everything else.
func _check_step_pill() -> void:
	_section("Step pill names the beat the trainee is in")
	Assessment.reset()

	for id in Assessment.order:
		var step: ProcedureStep = Assessment.steps[id]
		if step.display_as == &"":
			continue
		if not Assessment.steps.has(step.display_as):
			continue  # reported by _check_dangling_requires
		var shown: ProcedureStep = _display_step(id)
		_ok(shown.category == step.category,
			"'%s' (%s) redirects to '%s' (%s) - same beat" % [
				id, step.category, shown.id, shown.category])

	# The urgent treatment is danger-red and flashing, reserved for the one beat
	# where seconds of delay are the injury. Walk the happy path and assert it
	# never appears while the trainee's actual next job is somewhere else.
	Assessment.reset()
	SimState.begin_exercise()
	var urgent_beat: StringName = &"break_contact"
	var wrong: Array[String] = []
	for id in Assessment.order:
		var next := Assessment.next_step()
		if next != &"":
			var step: ProcedureStep = Assessment.steps[next]
			var shown: ProcedureStep = _display_step(next)
			if shown.urgent and step.category != urgent_beat:
				wrong.append("%s -> \"%s\"" % [next, shown.title])
		Assessment.complete(id)
	_ok(wrong.is_empty(),
		"the urgent pill only ever flashes during the break-contact beat %s"
			% ", ".join(wrong))

	Assessment.reset()
	SimState.reset()

	# The same sentence, from the other direction: walk the procedure with the
	# phase machine held at SCENE_SAFETY - the worker upright at the panel, the
	# trainee free to prepare - and assert nothing on screen ever claims the
	# casualty is in contact with a live conductor.
	#
	# The playtest that forced this: fetching the crook early is legal and
	# sensible, and it made `contact_broken` the next available step while the
	# worker was still working. Checklist row and pill both went danger-red
	# before anything had happened, and the category invariant above could not
	# see it - both steps genuinely are the break-contact beat.
	Assessment.reset()
	SimState.begin_exercise()
	var early: Array[String] = []
	for id in Assessment.order:
		var next := Assessment.next_step()
		if next != &"":
			var shown: ProcedureStep = _display_step(next)
			if shown.urgent:
				early.append("%s -> \"%s\"" % [next, shown.title])
		Assessment.complete(id)
	_ok(early.is_empty(),
		"nothing flashes the break-contact beat while the phase is still scene safety %s"
			% ", ".join(early))

	Assessment.reset()
	SimState.reset()


## The HUD's own resolution (scripts/ui/hud.gd::_display_step), duplicated here
## rather than reached into, so the check fails if the HUD changes shape.
func _display_step(id: StringName) -> ProcedureStep:
	var step: ProcedureStep = Assessment.steps[id]
	var hops := 0
	while step.display_as != &"" and Assessment.steps.has(step.display_as) and hops < 8:
		# Mirrors hud.gd's _display_step: a redirect never carries the HUD into
		# a step the phase has not reached.
		var next: ProcedureStep = Assessment.steps[step.display_as]
		if next.min_phase >= 0 and int(SimState.phase) < next.min_phase:
			break
		step = next
		hops += 1
	return step
