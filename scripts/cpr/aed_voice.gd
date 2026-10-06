class_name AedVoice
extends Node3D

## Station D · AED voice prompts — CPR_CONTRACT.md §9 seam 4 ("Audio assets:
## AED voice lines, metronome sample, negative tone").
##
## The *assets* are the human's to record; this is the machine that plays them.
## Everything here is asset-optional: a line whose .ogg/.wav is missing still
## occupies its slot in the queue for FALLBACK_SECONDS, so the sequencing,
## the gating and (if enabled) the subtitles behave identically whether or not
## a single sound file exists yet. Drop the files into AUDIO_DIR with the
## filenames listed in LINES and they start playing — no code change.
##
## WHY A QUEUE. A real AED never talks over itself: it says one thing, finishes
## it, then says the next. Several of our triggers land within a few hundred
## milliseconds of each other (the AED is placed and PAD_PLACEMENT is entered;
## the SHOCK camera move lands while the analyse/charge patter is still
## running), so every request goes through `_queue`, and the next line starts
## only when the previous one has actually finished.
##
## WHY IT IS A Node3D. The AED is a physical object in the room and the trainee
## walks away from it during AED_FETCH; the prompts have to come from the unit,
## not from inside their head. The player follows the deployed mesh
## ("AED Defibrilator CPR") when it can be resolved, and falls back to
## non-positional playback otherwise so a bad bind is quiet-but-working rather
## than silent.
##
## Never touches the CPR state machine and never gates anything — it only
## listens to Events. Instanced by cpr_station.gd like every other station
## node; needs no scene-authored wiring (CPR_CONTRACT.md §8).
##
## OWNED BY AGENT D · AED — see CPR_CONTRACT.md section 7.

# CPR state ids come from CprStation.STATE_* — never a local copy of the number.
# The spine was renumbered on 3 Sep 2026 (docs/OVERNIGHT_PLAN.md §2) and every
# duplicated integer here was a silent breakage waiting to happen.

const AED_DEPLOYED_NODE_NAME := "AED Defibrilator CPR"  # exact, per CPR_CONTRACT.md §3

const AUDIO_DIR := "res://audio/aed/"
## Tried in order for each line id, so a placeholder .wav can be dropped in
## before the final .ogg exists.
const AUDIO_EXTENSIONS := ["ogg", "wav", "mp3"]

## How long a line holds the queue when its file is missing. Long enough that
## the ordering still reads as speech-paced while the assets are outstanding.
const FALLBACK_SECONDS := 2.2
## Silence between lines. A real unit leaves a beat; back-to-back lines read as
## one run-on sentence.
const GAP_SECONDS := 0.35

## Longer pauses after specific lines, where the silence is doing work rather
## than merely separating two sentences. A line not listed here gets
## GAP_SECONDS.
const PAUSE_AFTER := {
	# The unit is analysing during this silence. Coming straight back with
	# "Shock advised." makes it sound like it decided before it looked — and
	# this is the beat where the trainee must not be touching the patient, so
	# the pause is also the window they have just been told to keep clear.
	&"analysing": 2.5,
}

## How long the unit waits before repeating an unanswered instruction, measured
## from the end of the previous prompt. Real units nag; a single instruction
## followed by silence leaves a trainee who missed it with nothing.
const NAG_SECONDS := 8.0

## Preferred bus, if the project ever grows one. No default_bus_layout.tres
## exists today, so this resolves to Master — see _resolve_bus().
const PREFERRED_BUS := "Voice"

const UNIT_DB := 2.0
## Speech has to stay intelligible across the switchroom, so it attenuates far
## more gently than ArcFx's inverse-distance falloff.
const MAX_DISTANCE := 25.0

## Every line the unit can say. `text` is the exact wording to record — generic
## and non-manufacturer, flat unhurried delivery (CPR_HANDOFF.md §5).
## `file` is the basename expected under AUDIO_DIR.
##
## Ten lines, matching the handoff's estimate.
const LINES := {
	&"unit_on": {
		"file": "aed_unit_on",
		"text": "Unit ready. Stay calm and follow the spoken instructions.",
	},
	&"attach_pads": {
		"file": "aed_attach_pads",
		"text": "Attach the pads to the patient's bare chest.",
	},
	&"attach_second_pad": {
		"file": "aed_attach_second_pad",
		"text": "Attach the second pad.",
	},
	&"pads_attached": {
		"file": "aed_pads_attached",
		"text": "Pads attached.",
	},
	&"analysing": {
		"file": "aed_analysing",
		"text": "Analysing heart rhythm. Do not touch the patient.",
	},
	&"shock_advised": {
		"file": "aed_shock_advised",
		"text": "Shock advised.",
	},
	&"charging": {
		"file": "aed_charging",
		"text": "Charging.",
	},
	&"stand_clear": {
		"file": "aed_stand_clear",
		"text": "Stand clear. Press the flashing button to deliver the shock.",
	},
	&"shock_delivered": {
		"file": "aed_shock_delivered",
		"text": "Shock delivered.",
	},
	&"resume_cpr": {
		"file": "aed_resume_cpr",
		"text": "Begin CPR. Continue chest compressions.",
	},
}

## Emitted as each line starts, with its recorded wording. The floating panel
## (CPR_CONTRACT.md §6: "current AED instruction line") or a subtitle strip can
## connect to this; nothing is required to. Carries the text rather than the id
## so a reader needs no table of its own.
signal line_started(id: StringName, text: String)
## The queue drained — nothing is speaking and nothing is pending.
signal went_quiet()
## A line reached its end (or was superseded — see `_supersede`). ShockButton
## waits on this for `charging` before it will let the trainee press the
## button; see `has_finished()`.
signal line_finished(id: StringName)

## Off by default: the panel owns on-screen text and duplicating every line in
## the centre message would fight it. Flip on for accessibility passes or when
## testing without recorded audio.
@export var subtitles: bool = false


var _player: AudioStreamPlayer3D = null
var _timer: Timer = null
var _aed_mesh: Node3D = null

var _queue: Array[StringName] = []
var _current: StringName = &""
## Which line ids have been said this run — the "say it once" gate for prompts
## whose trigger can fire more than once (re-entering a state via
## debug_jump_to_state, a second pad landing on an already-full chest).
var _said: Dictionary = {}
## Cached ResourceLoader results, including the misses: a line with no file is
## looked up once per run, not once per utterance.
var _streams: Dictionary = {}
var _warned_missing: Dictionary = {}
## Line ids that have finished this run. Read through `has_finished()` by
## anything that must not run ahead of the unit's own patter.
var _finished: Dictionary = {}
## Line ids that have BEGUN this run. Separate from `_said`, which is stamped
## when a line is queued: a caller waiting to act with the unit's voice — the
## pad ghosts appearing as it says "attach pads" — needs the moment it actually
## starts speaking, not the moment it got in line.
var _started: Dictionary = {}
## Current CPR state, for the nag's "still in this beat?" test. Starts at the
## spine's named idle rather than a bare -1 — see aed_station.gd for why the
## `var` initialiser is safe where a `const` one would not be.
var _state: int = CprStation.STATE_PRIMARY_SURVEY
## Pads stuck on the casualty so far — the nag stops at two.
var _pads_placed: int = 0
var _nag_timer: Timer = null


func _ready() -> void:
	_player = AudioStreamPlayer3D.new()
	_player.name = "AedVoicePlayer"
	_player.bus = _resolve_bus()
	_player.volume_db = UNIT_DB
	_player.max_distance = MAX_DISTANCE
	_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_LOGARITHMIC
	_player.finished.connect(_on_player_finished)
	add_child(_player)

	# One shared timer covers both the inter-line gap and the stand-in duration
	# of a line whose asset is missing — they are the same thing to the queue.
	_timer = Timer.new()
	_timer.name = "AedVoiceTimer"
	_timer.one_shot = true
	_timer.timeout.connect(_on_timer_timeout)
	add_child(_timer)

	_nag_timer = Timer.new()
	_nag_timer.name = "AedVoiceNagTimer"
	_nag_timer.one_shot = true
	_nag_timer.timeout.connect(_on_nag_timeout)
	add_child(_nag_timer)

	Events.cpr_phase_entered.connect(_on_cpr_phase_entered)
	Events.cpr_state_changed.connect(_on_cpr_state_changed)
	Events.aed_placed.connect(_on_aed_placed)
	Events.aed_pad_placed.connect(_on_aed_pad_placed)
	Events.stand_clear_confirmed.connect(_on_stand_clear_confirmed)
	Events.aed_shock_delivered.connect(_on_aed_shock_delivered)
	Events.cpr_completed.connect(_on_cpr_completed)

	# Same caution as every other station node: the ControlRoom .blend instance
	# may still be settling on the frame this enters the tree.
	call_deferred("_bind_aed")


## Master unless the project grows a dedicated speech bus. Naming a bus that
## does not exist makes the player silent with only an engine warning, so this
## checks rather than assumes.
func _resolve_bus() -> StringName:
	if AudioServer.get_bus_index(PREFERRED_BUS) >= 0:
		return PREFERRED_BUS
	return &"Master"


func _bind_aed() -> void:
	var root: Node = get_tree().current_scene
	if root == null:
		root = get_tree().root
	_aed_mesh = CprGhost.find_node(root, AED_DEPLOYED_NODE_NAME) as Node3D
	if _aed_mesh == null:
		push_warning("AedVoice: no node named '%s' found; voice prompts will play non-positionally." % AED_DEPLOYED_NODE_NAME)
		return
	global_position = _aed_mesh.global_position


# --- public API ------------------------------------------------------------------

## Adds a line to the back of the queue. Unknown ids are ignored (with an
## error) rather than silently swallowed.
##
## A line whose beat is already closed is dropped, not queued. Every line is
## one-shot per run, so "already finished" and "no longer wanted" are the same
## condition — and the trigger for a line does not reliably arrive before the
## state change that retires it. CprStation is connected to `aed_pad_placed`
## ahead of this node (it is built first), so on the second pad it advances to
## SHOCK synchronously and this node sees the state change *first*: the pad
## beat is retired, and "Pads attached." then arrives to be queued behind
## "Charging.". `_supersede` cannot help there — it only cleans what is
## already queued — so the guard belongs here, at the point of entry.
func say(id: StringName) -> void:
	if not LINES.has(id):
		push_error("AedVoice: unknown line id '%s'." % id)
		return
	if _finished.has(id):
		return
	_queue.append(id)
	_advance_if_idle()


## `say()` that does nothing if this line has already been spoken during the
## current CPR run. Used for every prompt whose trigger can legitimately fire
## twice.
func say_once(id: StringName) -> void:
	if _said.has(id):
		return
	_said[id] = true
	say(id)


## Says a line the trainee has already heard. The once-guards exist to stop a
## repeated *trigger* producing a repeated line; a deliberate re-prompt is a
## different intent, so it clears them rather than working around them.
##
## Note this also clears `_started`/`_finished` for that id, so anything gating
## on has_started()/has_finished() sees it briefly go false again. Harmless for
## the pad gate (it has already opened by the time a nag can fire) but worth
## knowing before hanging a new gate off a nagged line.
func say_again(id: StringName) -> void:
	if not LINES.has(id):
		push_error("AedVoice: unknown line id '%s'." % id)
		return
	_said.erase(id)
	_started.erase(id)
	_finished.erase(id)
	say(id)


## Cuts the current line and empties the queue — for leaving the AED beat, or
## for the end of the run.
func stop_all() -> void:
	if _nag_timer != null:
		_nag_timer.stop()
	_queue.clear()
	_current = &""
	if _player != null:
		_player.stop()
	if _timer != null:
		_timer.stop()


func is_speaking() -> bool:
	return _current != &"" or not _queue.is_empty()


## Has this line already been said in full this run? A line that was dropped or
## cut short counts as finished: the caller is asking "has the unit got past
## this point", and it has.
func has_finished(id: StringName) -> bool:
	return _finished.has(id)


## Has this line begun this run? The counterpart to has_finished(), for
## anything that should appear WITH a line rather than after it.
func has_started(id: StringName) -> bool:
	return _started.has(id)


## Marks a line done and tells anything waiting on it. Called for a line that
## played out, one that was cut mid-sentence, and one that was dropped from the
## queue unplayed — all three mean the same thing to a waiter.
func _mark_finished(id: StringName) -> void:
	if id == &"" or _finished.has(id):
		return
	_finished[id] = true
	line_finished.emit(id)


## Retires a whole beat's worth of lines that the trainee has overtaken: drops
## them from the queue, and cuts the one currently speaking if it belongs to
## that beat too.
##
## Cutting mid-sentence is deliberate, and it is what changed once the real
## recordings landed. The lines total nearly half a minute — `aed_unit_on` and
## `aed_attach_pads` alone are 9.4 s — so a trainee working at any pace at all
## outruns the queue, and a unit still saying "attach the pads" while the rhythm
## is being analysed is worse than one that stops talking about the last beat
## the moment the next begins. Real units interrupt themselves the same way.
func _supersede(ids: Array) -> void:
	if not _queue.is_empty():
		var kept: Array[StringName] = []
		for queued in _queue:
			if ids.has(queued):
				_mark_finished(queued)
			else:
				kept.append(queued)
		_queue = kept
	if _current != &"" and ids.has(_current):
		var cut := _current
		_current = &""
		_player.stop()
		_mark_finished(cut)
		# Straight into the next line rather than through the usual gap: the
		# pause after a cut-off sentence is what would read as a fault.
		_timer.stop()
		_play_next()
	# Close the whole beat, including lines that were never queued. The trigger
	# for a line does not reliably arrive before the state change that retires
	# it — see the note on `say()` — so retiring only what is currently in
	# flight leaves the stragglers free to queue themselves afterwards, which
	# is how "Pads attached." ended up behind "Charging.".
	for id in ids:
		_mark_finished(id)


# --- queue -----------------------------------------------------------------------

func _advance_if_idle() -> void:
	if _current != &"" or (_timer != null and not _timer.is_stopped()):
		return
	_play_next()


func _play_next() -> void:
	if _queue.is_empty():
		_current = &""
		went_quiet.emit()
		_schedule_nag()
		return

	var id: StringName = _queue.pop_front()
	_current = id
	var text: String = LINES[id]["text"]

	# The AED can be picked up and put down between lines, so the emitter
	# position is refreshed per utterance rather than only at bind time.
	if _aed_mesh != null and is_instance_valid(_aed_mesh):
		global_position = _aed_mesh.global_position

	_started[id] = true
	line_started.emit(id, text)
	if subtitles:
		Events.center_message_requested.emit(text, Tokens.SCENE_TEXT_MUTED, FALLBACK_SECONDS)
	Events.log_action(&"aed", "AED voice prompt", &"info", text)

	var stream := _stream_for(id)
	if stream == null:
		# Asset outstanding: hold the slot so the rest of the sequence still
		# lands in the right order and at a believable pace.
		_timer.start(FALLBACK_SECONDS)
		return
	_player.stream = stream
	_player.play()


func _on_player_finished() -> void:
	if _current == &"":
		return
	var done: StringName = _current
	_mark_finished(done)
	_current = &""
	_timer.start(PAUSE_AFTER.get(done, GAP_SECONDS))


## Serves both jobs of the timer: a missing line's stand-in duration (in which
## case `_current` is still set and its slot is now over) and the gap between
## two real lines.
func _on_timer_timeout() -> void:
	_mark_finished(_current)
	_current = &""
	_play_next()


func _stream_for(id: StringName) -> AudioStream:
	if _streams.has(id):
		return _streams[id]
	var stream: AudioStream = null
	var base: String = AUDIO_DIR + String(LINES[id]["file"]) + "."
	for ext in AUDIO_EXTENSIONS:
		var path: String = base + str(ext)
		if ResourceLoader.exists(path):
			stream = ResourceLoader.load(path) as AudioStream
			if stream != null:
				break
	_streams[id] = stream
	if stream == null and not _warned_missing.has(id):
		_warned_missing[id] = true
		push_warning("AedVoice: no audio file for line '%s' (expected %s{%s}). Playing silently at %.1f s. Wording to record: \"%s\"" % [
			id, base, ", ".join(AUDIO_EXTENSIONS), FALLBACK_SECONDS, LINES[id]["text"],
		])
	return stream


# --- triggers --------------------------------------------------------------------

## Powering on is modelled as the unit being set down beside the casualty:
## there is no separate power switch in this sim, and a silent AED sitting on
## the floor gives the trainee nothing to follow.
# --- nag -------------------------------------------------------------------------

## Armed only when the unit has run out of things to say and the trainee still
## has a pad to place. Timed from the end of the last prompt rather than off a
## free-running clock, so a long line is never followed straight away by a
## repeat of itself.
func _schedule_nag() -> void:
	if _nag_timer == null:
		return
	if _state != CprStation.STATE_PAD_PLACEMENT or _pads_placed >= 2:
		_nag_timer.stop()
		return
	_nag_timer.start(NAG_SECONDS)


func _on_nag_timeout() -> void:
	if _state != CprStation.STATE_PAD_PLACEMENT or _pads_placed >= 2 or is_speaking():
		return
	# The outstanding instruction, not the opening one: after the first pad,
	# what they have not done is the second.
	say_again(&"attach_second_pad" if _pads_placed == 1 else &"attach_pads")


# --- triggers --------------------------------------------------------------------

func _on_aed_placed() -> void:
	say_once(&"unit_on")
	say_once(&"attach_pads")


func _on_aed_pad_placed(slot: int, _correct: bool, _site_name: String) -> void:
	_pads_placed = maxi(_pads_placed, slot + 1)
	if _pads_placed >= 2 and _nag_timer != null:
		_nag_timer.stop()
	# Correctness is deliberately not voiced — CPR_CONTRACT.md §4.4: wrong
	# sites are accepted silently and surface only in the debrief.
	if slot == 0:
		say_once(&"attach_second_pad")
	else:
		say_once(&"pads_attached")


const PAD_BEAT_LINES := [&"unit_on", &"attach_pads", &"attach_second_pad", &"pads_attached"]
const SHOCK_BEAT_LINES := [&"analysing", &"shock_advised", &"charging", &"stand_clear"]


## Standing up is the trainee's response to the unit, not its cue to speak —
## `stand_clear` is queued with the rest of the charge sequence on entering
## SHOCK (see _on_cpr_state_changed). This remains only as a safety net for a
## route into stand-clear that skipped that sequence, e.g. a debug jump.
## say_once refuses it in the normal case, where it has already been said.
func _on_stand_clear_confirmed() -> void:
	say_once(&"stand_clear")


func _on_aed_shock_delivered() -> void:
	# The rhythm has been analysed, the charge has been delivered: anything
	# still queued from those beats is now describing the past.
	_supersede(PAD_BEAT_LINES)
	_supersede(SHOCK_BEAT_LINES)
	say_once(&"shock_delivered")
	say_once(&"resume_cpr")


func _on_cpr_state_changed(_from: int, to: int) -> void:
	_state = to
	if to != CprStation.STATE_PAD_PLACEMENT and _nag_timer != null:
		_nag_timer.stop()
	match to:
		CprStation.STATE_PAD_PLACEMENT:
			# Covers a jump straight into pad placement (debug_jump_to_state),
			# where `aed_placed` never fired. say_once keeps the normal route
			# from repeating itself.
			say_once(&"unit_on")
			say_once(&"attach_pads")
		CprStation.STATE_SHOCK:
			# Pads are on; nothing left to say about attaching them.
			_supersede(PAD_BEAT_LINES)
			say_once(&"analysing")
			say_once(&"shock_advised")
			say_once(&"charging")
			# Last of the charge sequence, and the prompt that makes the
			# trainee stand: it has to come *before* they stand up, not after.
			# By the time it plays, `charging` has finished, so ShockButton's
			# interlock is satisfied and the button goes live the moment they
			# are clear — which is exactly what the line tells them to expect.
			say_once(&"stand_clear")


func _on_cpr_phase_entered() -> void:
	stop_all()
	_said.clear()
	_started.clear()
	_finished.clear()
	_state = CprStation.STATE_PRIMARY_SURVEY
	_pads_placed = 0


func _on_cpr_completed(_metrics: Dictionary) -> void:
	stop_all()
