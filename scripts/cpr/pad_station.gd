extends Node

## Station D · Pad placement — CPR_CONTRACT.md §4 "Pad placement — the puzzle"
##
## All five PadSite_* meshes (CPR_CONTRACT.md §3) are found by prefix and
## wrapped in GhostTarget — the shared/frozen ghost machinery, not anything
## reimplemented here. When PAD_PLACEMENT begins, all five are revealed as
## ghosts at once. GhostTarget/CprGhost already do the hover recolour and the
## "click clears the override so the authored material shows" placement.
##
## Wrong sites are accepted exactly like correct ones: no colour difference,
## no re-prompt, no judgement made here. Correctness is read once, off the
## node name (`Correct` per CPR_CONTRACT.md §3), and only ever carried in the
## emitted signal for Assessment to score later — it never changes what the
## trainee sees.
##
## This station never advances the CPR state machine — it only reports via
## Events. CPR_CONTRACT.md §4 says two placements end the state regardless of
## correctness; that transition belongs to cpr_station.gd (Agent E), which is
## expected to be listening to aed_pad_placed and to fire the next
## cpr_state_changed itself. When that arrives, this station tears down
## whatever ghosts are still up.
##
## Add this node anywhere in the tree (e.g. as a child the CPR station
## instances at runtime); it needs no scene-authored wiring.
##
## OWNED BY AGENT D · AED — see CPR_CONTRACT.md section 7.

# CPR state ids come from CprStation.STATE_* — never a local copy of the number.
# The spine was renumbered on 3 Sep 2026 (docs/OVERNIGHT_PLAN.md §2) and every
# duplicated integer here was a silent breakage waiting to happen.

# --- node naming (CPR_CONTRACT.md section 3) -----------------------------------
const PAD_SITE_PREFIX := "PadSite_"
const CORRECT_MARKER := "Correct"

# --- mechanics (CPR_CONTRACT.md section 4: "Two placements end the state") ------
const PAD_TARGET := 2

## The sites appear WITH the unit's instruction, not ahead of it. Entering
## PAD_PLACEMENT used to reveal all five ghosts (and the panel's "0 / 2") the
## instant the AED was down, while the unit was still saying "Unit ready" —
## the trainee was being shown where to put pads before being told to place
## any. Same interlock ShockButton uses for `charging`, one line earlier.
const VOICE_PADS_LINE := &"attach_pads"
## Audio must never be able to stall the exercise: if the line has not started
## by now — no AedVoice in the tree, a missing asset, a wedged queue — reveal
## anyway. Comfortably longer than the unit_on line that precedes it.
const VOICE_WAIT_TIMEOUT_S := 8.0

## Emitted when the sites actually go up, which is the same instant the panel's
## pad counter should. Local rather than an Events fact: it is a presentation
## beat, not something the spine or the assessment cares about.
signal pads_revealed()

var _targets: Array[GhostTarget] = []
var _placed_count: int = 0
var _active: bool = false
## True between entering PAD_PLACEMENT and the ghosts actually going up.
var _waiting_for_voice: bool = false
var _voice: AedVoice = null
var _voice_timeout: Timer = null


func _ready() -> void:
	Events.cpr_state_changed.connect(_on_cpr_state_changed)
	Events.cpr_phase_entered.connect(_on_cpr_phase_entered)
	# Scene population (ControlRoom's .blend instance, the casualty drag
	# target) may still be settling on the frame this node enters the tree —
	# same caution CprRig's own binder takes.
	call_deferred("_build_targets")


# --- construction --------------------------------------------------------------

func _build_targets() -> void:
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		scene_root = get_tree().root

	var meshes := CprGhost.find_nodes_with_prefix(scene_root, PAD_SITE_PREFIX)
	if meshes.is_empty():
		push_error("PadStation: no nodes found with prefix '%s'." % PAD_SITE_PREFIX)
		return

	for m in meshes:
		var mesh := m as MeshInstance3D
		if mesh == null:
			push_error("PadStation: '%s' matched the pad prefix but is not a MeshInstance3D." % m.name)
			continue
		var target := GhostTarget.new(mesh, CprGhost.idle_material(), CprGhost.hover_material())
		target.data = {"correct": String(mesh.name).contains(CORRECT_MARKER)}
		target.hovered_changed.connect(_on_pad_hovered_changed)
		target.activated.connect(_on_pad_activated)
		_targets.append(target)


# --- state -----------------------------------------------------------------------

func _on_cpr_phase_entered() -> void:
	_teardown()


func _on_cpr_state_changed(_from: int, to: int) -> void:
	if to == CprStation.STATE_PAD_PLACEMENT:
		_enter_pad_placement()
	elif _active or _waiting_for_voice:
		_teardown()


## Arms the beat but shows nothing yet. The reveal happens in _reveal(), when
## the unit starts telling the trainee to attach the pads.
func _enter_pad_placement() -> void:
	_placed_count = 0
	for target in _targets:
		target.is_placed = false

	_bind_voice()
	if _voice == null or _voice.has_started(VOICE_PADS_LINE):
		# No voice in the tree, or the line already went by (re-entering the
		# state via debug_jump_to_state): nothing to wait for.
		_reveal()
		return

	_waiting_for_voice = true
	_start_voice_timeout()


func _bind_voice() -> void:
	if _voice != null:
		return
	var station := CprStation.get_current()
	_voice = station.aed_voice if station != null else null
	if _voice != null:
		_voice.line_started.connect(_on_voice_line_started)


func _start_voice_timeout() -> void:
	if _voice_timeout == null:
		_voice_timeout = Timer.new()
		_voice_timeout.name = "PadVoiceTimeout"
		_voice_timeout.one_shot = true
		_voice_timeout.timeout.connect(_on_voice_timeout)
		add_child(_voice_timeout)
	_voice_timeout.start(VOICE_WAIT_TIMEOUT_S)


func _on_voice_line_started(id: StringName, _text: String) -> void:
	if id != VOICE_PADS_LINE or not _waiting_for_voice:
		return
	_reveal()


func _on_voice_timeout() -> void:
	if not _waiting_for_voice:
		return
	push_warning(
		"PadStation: '%s' never started after %.0f s; revealing the pad sites anyway."
		% [VOICE_PADS_LINE, VOICE_WAIT_TIMEOUT_S]
	)
	_reveal()


func _reveal() -> void:
	_waiting_for_voice = false
	if _voice_timeout != null:
		_voice_timeout.stop()
	_active = true
	for target in _targets:
		target.show_ghost()
	_refresh_prompts()
	pads_revealed.emit()


## Whether the sites are actually up. The panel reads this on entry, in case
## the reveal already happened before it got a chance to connect.
func is_revealed() -> bool:
	return _active


## Every unplaced site offers the same line — which pad is going down, never
## which site is right. CPR_CONTRACT.md §4.4: the trainee commits without being
## told, and a per-site tooltip would give the answer away.
func _refresh_prompts() -> void:
	var text := ""
	if _active and _placed_count < PAD_TARGET:
		text = "Place pad %d of %d" % [_placed_count + 1, PAD_TARGET]
	for target in _targets:
		target.prompt = "" if target.is_placed else text


func _teardown() -> void:
	_active = false
	_waiting_for_voice = false
	if _voice_timeout != null:
		_voice_timeout.stop()
	for target in _targets:
		target.prompt = ""
		target.dismiss()


# --- clicks ------------------------------------------------------------------

func _on_pad_hovered_changed(target: GhostTarget, is_hovered: bool) -> void:
	if not _active or not is_hovered:
		return
	# CPR_CONTRACT.md §4: never surface which site is under the cursor beyond
	# the recolour GhostTarget already did — but the contract's own event bus
	# (§2) carries the site name for anything downstream (e.g. logging) that
	# wants it. The floating panel (Agent B) explicitly does not read it.
	Events.aed_pad_hovered.emit(target.site_name)


func _on_pad_activated(target: GhostTarget) -> void:
	if not _active or _placed_count >= PAD_TARGET:
		return
	target.place()
	_placed_count += 1
	_refresh_prompts()
	var correct: bool = target.data.get("correct", false)
	Events.aed_pad_placed.emit(_placed_count - 1, correct, target.site_name)


func _exit_tree() -> void:
	for target in _targets:
		target.free_target()
