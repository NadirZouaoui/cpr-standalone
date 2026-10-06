class_name CprCueAudio
extends Node

## The CPR phase's two non-diegetic sounds — CPR_CONTRACT.md §9 seam 4, the
## remainder of it once AedVoice took the spoken prompts.
##
##   metronome  — 110/min, fixed, for the duration of a compression set.
##                CPR_CONTRACT.md §4.2: it "never varies — it is the teaching
##                mechanism", so this only plays what CompressionDriver's
##                `metronome_tick` already emits and never times anything
##                itself.
##   breathing  — the result tone at the end of the 5 s hold.
##
## BOTH ARE NON-POSITIONAL (AudioStreamPlayer, not ...3D), deliberately, and
## that is the whole reason they live here rather than in AedVoice. The AED is
## an object in the room and its prompts come from it; these two have no source
## in the room at all. The metronome is a teaching aid laid over the scene, and
## the result tone is the sim telling the trainee what they just observed. Give
## either one a position and it becomes something in the switchroom making a
## noise, which is a different — and wrong — claim.
##
## The result tone is NOT an error sound. It fires when the trainee has done
## exactly the right thing and the answer came back grave. CPR_CONTRACT.md §4.4
## forbids a negative tone for wrong pad sites, so a sound with the shape of a
## "wrong" sting here would be misread as one, appearing as it does nowhere
## else in the phase. See tools/gen_breathing_negative.py for the spec the
## placeholder was built to.
##
## Asset-optional in the same way AedVoice is: a missing file warns once and
## the node stays silent. Nothing here gates or times anything.

const METRONOME_PATH := "res://audio/aed/metronome_tick.wav"
const BREATHING_NEGATIVE_PATH := "res://audio/cues/breathing_negative.wav"
## The HANDOVER beat's approaching siren. A third non-positional cue, and the
## one that needs the most defending: an ambulance IS a thing in the world, so
## by the rule above it ought to be an AudioStreamPlayer3D. It is not, because
## the thing making the noise is outside a building that has no outside — there
## is no exterior modelled and no door to place it at, so any position chosen
## would be a lie about where the vehicle is. Heard through the walls, from no
## particular direction, is the honest reading.
##
## PLACEHOLDER ASSET. Synthesised by tools/gen_ambulance_arrive.py; see that
## file's docstring for what a real recording has to do.
const AMBULANCE_ARRIVE_PATH := "res://audio/cues/ambulance_arrive.wav"

## Under the voice lines: it runs continuously for 30 reps and has to stay
## somewhere the trainee can follow without it dominating.
const METRONOME_DB := -9.0
## Quieter still, and sitting inside the ambience duck the breathing check
## already applies.
const BREATHING_NEGATIVE_DB := -12.0

## Polyphony rather than one player: at 110/min ticks are 545 ms apart and the
## sample may ring longer, in which case restarting one player clips its own
## tail.
const METRONOME_VOICES := 3

## The cue already carries its own approach envelope, so it needs no ducking or
## fade here — only enough headroom to sit under the centre message the trainee
## is reading at the same moment.
const AMBULANCE_ARRIVE_DB := -8.0


var _metronome: Array[AudioStreamPlayer] = []
var _metronome_next: int = 0
var _breathing: AudioStreamPlayer = null
var _ambulance: AudioStreamPlayer = null


func _ready() -> void:
	var metronome_stream := _load(METRONOME_PATH)
	if metronome_stream != null:
		for i in METRONOME_VOICES:
			var p := AudioStreamPlayer.new()
			p.name = "Metronome%d" % i
			p.stream = metronome_stream
			p.volume_db = METRONOME_DB
			add_child(p)
			_metronome.append(p)

	var breathing_stream := _load(BREATHING_NEGATIVE_PATH)
	if breathing_stream != null:
		_breathing = AudioStreamPlayer.new()
		_breathing.name = "BreathingResult"
		_breathing.stream = breathing_stream
		_breathing.volume_db = BREATHING_NEGATIVE_DB
		add_child(_breathing)

	var ambulance_stream := _load(AMBULANCE_ARRIVE_PATH)
	if ambulance_stream != null:
		_ambulance = AudioStreamPlayer.new()
		_ambulance.name = "AmbulanceArrive"
		_ambulance.stream = ambulance_stream
		_ambulance.volume_db = AMBULANCE_ARRIVE_DB
		add_child(_ambulance)

	Events.breathing_checked.connect(_on_breathing_checked)
	# CompressionDriver's tick is a local signal, not an Events one (see its
	# own note on why), so it has to be reached through the station. It is
	# built in the same _build() pass as this node, hence the deferred hookup.
	call_deferred("_connect_metronome")


func _load(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		push_warning("CprCueAudio: no audio file at %s; that cue will be silent." % path)
		return null
	return ResourceLoader.load(path) as AudioStream


func _connect_metronome() -> void:
	var station := CprStation.get_current()
	if station == null or station.compression_driver == null:
		push_warning("CprCueAudio: no CompressionDriver reachable; the metronome will be silent.")
		return
	if not station.compression_driver.metronome_tick.is_connected(_on_metronome_tick):
		station.compression_driver.metronome_tick.connect(_on_metronome_tick)


func _on_metronome_tick() -> void:
	if _metronome.is_empty():
		return
	_metronome[_metronome_next].play()
	_metronome_next = (_metronome_next + 1) % _metronome.size()


## Only the "not breathing" answer gets a tone. A breathing casualty is not a
## case this sim produces (CPR_CONTRACT.md §4.1 — the chest never rises), but
## the signal carries the flag, so it is honoured rather than assumed.
func _on_breathing_checked(breathing: bool) -> void:
	if breathing or _breathing == null:
		return
	_breathing.play()


## The HANDOVER beat, called by CprStation rather than driven off an Events
## fact. Deliberate: the other two cues react to things several systems care
## about, and this one is a single hand-off from the one place that knows the
## beat has arrived. Adding a bus signal for a single caller is not what the bus
## is for.
##
## Silent and harmless when the asset is missing — the beat's centre message and
## its dwell run either way, which is the asset-optional contract AedVoice sets
## (CPR_CONTRACT.md §9 seam 4).
func play_ambulance() -> void:
	if _ambulance == null:
		return
	_ambulance.play()


## How long the ambulance cue runs, in seconds, or 0.0 when the asset is
## absent. CprStation takes the longer of this and its own floor for the
## handover dwell, so swapping the placeholder for a real recording of a
## different length needs no code change - which is the note
## docs/OVERNIGHT_PROGRESS.md left for whoever does the swap.
func ambulance_length() -> float:
	if _ambulance == null or _ambulance.stream == null:
		return 0.0
	return _ambulance.stream.get_length()
