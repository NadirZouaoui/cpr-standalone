extends Node
## Ordering harness for AedVoice — drives the Events sequence a real run
## produces, in the real order, and prints each line as it starts.
##
## Exists because two ordering faults got through reasoning alone: lines
## outrunning the trainee, and a line arriving after its own beat had been
## retired (CprStation advances the state synchronously ahead of this node's
## own handler for the same signal). Both are invisible to the CPR headless
## regression, which never listens to the voice.
##
##   "/c/Program Files/Godot.exe" --headless --path . tools/check_aed_voice.tscn


var _voice: AedVoice
var _t0: int = 0


func _ready() -> void:
	_t0 = Time.get_ticks_msec()
	_voice = AedVoice.new()
	add_child(_voice)
	_voice.line_started.connect(_on_line)
	_voice.went_quiet.connect(func(): _log("-- quiet --"))
	_run()


func _log(text: String) -> void:
	print("%6.2fs  %s" % [(Time.get_ticks_msec() - _t0) / 1000.0, text])


func _on_line(id: StringName, text: String) -> void:
	_log("%-18s %s" % [id, text])


func _run() -> void:
	Events.cpr_phase_entered.emit()
	await _wait(0.5)

	_log("[trainee places the AED]")
	Events.aed_placed.emit()
	Events.cpr_state_changed.emit(CprStation.STATE_AED_DEPLOY, CprStation.STATE_PAD_PLACEMENT)

	# A slow trainee, so the nag has room to fire: nothing happens for a while
	# after the opening instruction, then the first pad, then another wait.
	await _wait(22.0)
	_log("[pad 1]")
	Events.aed_pad_placed.emit(0, true, "PadSite_Correct_Upper")

	await _wait(20.0)
	_log("[pad 2 — CprStation advances to SHOCK before this node sees the pad]")
	Events.cpr_state_changed.emit(CprStation.STATE_PAD_PLACEMENT, CprStation.STATE_SHOCK)
	Events.aed_pad_placed.emit(1, true, "PadSite_Correct_Lower")

	# The trainee stands in response to the "stand clear" line, not ahead of it.
	await _wait(12.0)
	_log("[trainee stands up]")
	Events.stand_clear_confirmed.emit()

	await _wait(2.0)
	_log("[shock]")
	Events.aed_shock_delivered.emit()
	Events.cpr_state_changed.emit(CprStation.STATE_SHOCK, CprStation.STATE_COMPRESSIONS_2)

	await _wait(10.0)
	get_tree().quit()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
