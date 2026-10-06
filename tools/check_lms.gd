extends Node
## Asserts the SCORM 1.2 reporting contract: which elements the exercise writes,
## what it writes into them, and that the values survive the trip through
## JavaScriptBridge intact.
##
##   & "C:\Program Files\Godot.exe" --headless --path <project> res://tools/check_lms.tscn
##
## WHY THIS EXISTS
##
## The Web export shipped once with no SCORM_API_wrapper.js in the package at
## all. Because scorm_shell.html guards on `typeof pipwerks !== 'undefined'`,
## the course ran, played perfectly, and told the LMS absolutely nothing. That
## failure is invisible from inside the game: every Lms call is a no-op outside
## the browser by design, so a detached run looks identical whether the bridge
## is sound or missing entirely.
##
## What can be checked headlessly is the half that lives in GDScript - the
## element names, the vocabulary, the ordering, and the encoding. Lms.sent
## mirrors every write, so this plays the real reporting path and reads it back.
##
## What CANNOT be checked here is the JavaScript half: that pipwerks finds the
## LMS API and that LMSSetValue actually lands. That needs a browser and a mock
## API object - see tools/scorm_test_harness.html.
##
## Run fidelity is not this file's job. check_run_order plays the exercise
## through the real station and casualty; here the steps are completed directly,
## because the reporting layer does not care how the assessment got its numbers.

## Every element scripts/core/lms.gd is allowed to write, with the SCORM 1.2
## data model's answer for each. Anything outside this set is either read-only
## (cmi.core.student_id), not in 1.2 at all (cmi.completion_status - that is
## 2004), or simply misspelled, and all three fail the same silent way: the LMS
## rejects the write, the wrapper traces it to a console nobody is reading, and
## the course reports nothing.
const WRITABLE := {
	"cmi.core.lesson_status": "RW, vocabulary below",
	"cmi.core.score.raw": "RW, CMIDecimal 0-100",
	"cmi.core.score.min": "RW, CMIDecimal",
	"cmi.core.score.max": "RW, CMIDecimal",
	"cmi.core.exit": "W, vocabulary: time-out | suspend | logout | (empty)",
	"cmi.comments": "RW, CMIString 4096",
	"cmi.suspend_data": "RW, CMIString 4096",
}

const STATUS_VOCAB := [
	"passed", "completed", "failed", "incomplete", "browsed", "not attempted",
]

const EXIT_VOCAB := ["time-out", "suspend", "logout", ""]

## SCORM 1.2 caps cmi.comments and cmi.suspend_data at 4096. lms.gd trims to
## 4000 to leave room for an LMS that counts bytes rather than characters.
const FIELD_CAP := 4000

## Quotes would close the string literal lms.gd builds, the newline would end
## the statement, the backslash would start an escape, and the rest are there
## because a transcript carries whatever the client's step descriptions carry.
const NASTY := "Casualty said \"don't move\" — 50 % done\nline two \\ back & <tag> ✓ naïve"

var _failures: int = 0


func _ready() -> void:
	Assessment.reset()
	SimState.reset()

	_check_detached()
	_check_encoding()
	_check_clean_run_report()
	_check_transcript_cap()
	_check_incomplete_and_exit()
	await _check_crash_trail()

	_finish()


## The premise the whole class rests on: headless, every call is a no-op that
## still records. If is_available() ever returned true here, this file would be
## asserting against a bridge that was not running.
func _check_detached() -> void:
	print("\nDetached behaviour")
	_ok(not Lms.is_available(), "is_available() is false outside the browser")


## The transport. lms.gd hands JavaScript
##
##     pipwerks.SCORM.set('<key>', decodeURIComponent('<value.uri_encode()>'));
##
## so the payload is only safe if uri_encode() leaves nothing that can break out
## of a single-quoted JS string literal, and only correct if decodeURIComponent
## is its exact inverse. Godot's uri_decode() is that inverse, which is what is
## asserted here; that it matches the BROWSER's decodeURIComponent is checked in
## tools/scorm_test_harness.html, because only a browser can answer it.
func _check_encoding() -> void:
	print("\nuri_encode round-trip")
	var encoded := NASTY.uri_encode()

	# Percent-encoding emits only unreserved characters and %XX, so there is no
	# quote, no backslash and no newline left to terminate the literal early.
	var re := RegEx.create_from_string("^[A-Za-z0-9\\-_.~%]*$")
	_ok(re.search(encoded) != null,
		"encoded payload is confined to [A-Za-z0-9-_.~%%] (%d chars)" % encoded.length())
	_ok(not encoded.contains("'"), "no apostrophe survives encoding")
	_ok(not encoded.contains("\n"), "no newline survives encoding")
	_ok(not encoded.contains("\\"), "no backslash survives encoding")

	var decoded := encoded.uri_decode()
	_ok(decoded == NASTY, "decode(encode(s)) == s, quotes, newline and non-ASCII intact")
	if decoded != NASTY:
		print("    expected: %s" % NASTY)
		print("    got:      %s" % decoded)

	# The em dash, the tick and the diaeresis are multi-byte in UTF-8 and are
	# the ones an LMS mangles when something encodes per-character instead.
	_ok(encoded.contains("%E2%80%94"), "em dash encodes as its UTF-8 bytes (%E2%80%94)")

	# Printed so the exact bytes Godot puts on the wire can be pasted into
	# tools/scorm_test_harness.html, which checks them against the browser's
	# own decodeURIComponent. Regenerate that constant if NASTY changes.
	print("  info   encoded: %s" % encoded)


## A full pass reported through the real entry point.
func _check_clean_run_report() -> void:
	print("\nA passing run's report")
	Assessment.reset()
	SimState.reset()
	Lms.sent.clear()

	for id in Assessment.order:
		Assessment.complete(id)
	# Through the real signal, so the nasty characters reach the transcript the
	# way a step description would rather than being pasted in afterwards.
	Events.action_logged.emit(&"test", NASTY, &"ok", "detail — ✓")

	var passed := Assessment.is_passed()
	var score := Assessment.score_percent()
	_ok(passed, "completing every step passes (%d%%)" % score)

	Lms.report_result(passed, score, Assessment.transcript_as_text())

	_ok_keys()
	_ok(Lms.sent.get("cmi.core.lesson_status", "") == "passed",
		"lesson_status = passed")
	_ok(Lms.sent.get("cmi.core.score.raw", "") == str(score),
		"score.raw = %d" % score)
	_ok(Lms.sent.get("cmi.core.score.min", "") == "0", "score.min = 0")
	_ok(Lms.sent.get("cmi.core.score.max", "") == "100", "score.max = 100")

	var raw := int(Lms.sent.get("cmi.core.score.raw", "-1"))
	_ok(raw >= 0 and raw <= 100, "score.raw is within min..max")

	var comments: String = Lms.sent.get("cmi.comments", "")
	_ok(comments.contains("don't move"),
		"the transcript reaches cmi.comments with its apostrophe")
	_ok(comments.contains("✓"), "and with its non-ASCII intact")

	# lesson_status must be on the wire before the session ends, or the LMS
	# keeps whatever init() set - "incomplete" - and the pass is lost.
	var keys: Array = Lms.sent.keys()
	_ok(keys.has("cmi.core.lesson_status"), "lesson_status is set before any quit")


## The 4096 cap is the one place a long run can silently lose its report: an
## over-length CMIString is a 405 from the LMS and the whole element is dropped,
## not truncated for you.
func _check_transcript_cap() -> void:
	print("\nOver-length fields are trimmed, not dropped")
	Lms.sent.clear()
	var huge := "x".repeat(9000)

	Lms.report_result(true, 100, huge)
	var comments: String = Lms.sent.get("cmi.comments", "")
	_ok(comments.length() <= FIELD_CAP,
		"cmi.comments trimmed to %d (was 9000)" % comments.length())

	Lms.save_progress(huge)
	var suspend: String = Lms.sent.get("cmi.suspend_data", "")
	_ok(suspend.length() <= FIELD_CAP,
		"cmi.suspend_data trimmed to %d (was 9000)" % suspend.length())

	# The tail is kept because that is where the failures that ended the
	# exercise are; a head-truncated transcript debriefs the wrong half.
	Lms.sent.clear()
	Lms.report_result(true, 100, "HEAD" + "x".repeat(9000) + "TAIL")
	var trimmed: String = Lms.sent.get("cmi.comments", "")
	_ok(trimmed.ends_with("TAIL"), "the trimmed transcript keeps its tail")
	_ok(not trimmed.begins_with("HEAD"), "and drops its head")


## What the pause menu does: a trainee who walks out mid-exercise still owes the
## LMS a status, and cmi.core.exit decides whether the LMS offers to resume.
func _check_incomplete_and_exit() -> void:
	print("\nWalking away mid-exercise")
	Lms.sent.clear()
	Lms.set_value("cmi.core.lesson_status", "incomplete")
	Lms.set_value("cmi.core.exit", "")

	_ok_keys()
	_ok(STATUS_VOCAB.has(Lms.sent.get("cmi.core.lesson_status", "")),
		"lesson_status is in the 1.2 vocabulary")
	_ok(EXIT_VOCAB.has(Lms.sent.get("cmi.core.exit", "!")),
		"cmi.core.exit is in the 1.2 vocabulary (empty = finished, do not resume)")


## The crash trail. Nothing used to reach the LMS until the debrief, so a
## browser that died at minute 22 of a 23-minute run left an attempt that read
## as never opened; assessment.gd now pushes the transcript out as it grows.
##
## Driving it here means telling the bridge it is attached. Headless that
## changes nothing about what is sent - JavaScriptBridge.eval() has nowhere to
## go and set_value() still only records into Lms.sent - but it is what brings
## the trail's own guards to life, and those guards are the thing under test.
func _check_crash_trail() -> void:
	print("
The crash trail")
	Assessment.reset()
	SimState.reset()
	Lms.sent.clear()

	var timer: Timer = Assessment._trail_timer
	if not _ok(timer != null, "assessment.gd built a flush timer"):
		return
	_ok(timer.process_mode == Node.PROCESS_MODE_ALWAYS,
		"the timer keeps running while the tree is paused - the pause menu is "
		+ "where a trainee wanders off")

	Lms._available = true
	# So the test does not sit through TRAIL_INTERVAL twice over.
	timer.wait_time = 0.2

	Events.simulation_started.emit()
	_ok(Lms.sent.get("cmi.core.lesson_status", "") == "incomplete",
		"the attempt is claimed as incomplete the moment the exercise starts")
	_ok(not timer.is_stopped(), "and the flush timer is running")

	Events.action_logged.emit(&"test", "Something the trainee did", &"ok", "")
	await timer.timeout
	var trail: String = Lms.sent.get("cmi.suspend_data", "")
	_ok(trail != "", "the transcript reaches cmi.suspend_data")
	_ok(trail.contains("Something the trainee did"), "and carries what was logged")

	# Each flush is an LMSCommit, which on a real LMS is a network round trip.
	# A tick with nothing new must not spend one.
	Lms.sent.erase("cmi.suspend_data")
	await timer.timeout
	_ok(not Lms.sent.has("cmi.suspend_data"), "an unchanged transcript is not re-sent")

	# The verdict has gone out by then and report_result() committed it.
	Events.simulation_finished.emit(true, 100)
	_ok(timer.is_stopped(), "the verdict stops the trail")

	_ok_keys()

	Lms._available = false
	timer.wait_time = Assessment.TRAIL_INTERVAL


## Every element written so far is one the SCORM 1.2 data model lets an SCO set.
func _ok_keys() -> void:
	var bad: Array[String] = []
	for k in Lms.sent.keys():
		if not WRITABLE.has(k):
			bad.append(String(k))
	_ok(bad.is_empty(), "every element written is writable in SCORM 1.2%s" % [
		"" if bad.is_empty() else " - not: " + ", ".join(bad)])


func _ok(condition: bool, label: String) -> bool:
	if condition:
		print("  pass   %s" % label)
	else:
		_failures += 1
		print("  FAIL   %s" % label)
	return condition


func _finish() -> void:
	if _failures == 0:
		print("\ncheck_lms: all assertions passed.")
		get_tree().quit()
		return
	printerr("\ncheck_lms: %d assertion(s) FAILED." % _failures)
	get_tree().quit(1)
