extends Node
## SCORM 1.2 bridge.
##
## Every call is a no-op outside the browser, so the whole exercise can be
## run and graded from the Godot editor without an LMS attached. The
## substation project inlined JavaScriptBridge.eval() calls throughout its
## manager; keeping them behind one interface makes the exercise testable.

## Mirrors what was sent, for debugging and for the editor-run case.
var sent: Dictionary = {}

var _available: bool = false


func _ready() -> void:
	_available = OS.has_feature("web")
	if _available:
		# The SCORM session itself is opened by scorm_shell.html before the
		# engine boots, so by now init() has either found an LMS API or it
		# has not. Probe the live connection rather than the mere presence of
		# the wrapper: the wrapper is there whenever the file loaded, so the
		# old `typeof pipwerks` test also passed when the course was opened
		# straight from a web server with no LMS around it, and every later
		# write went into the wrapper's "API connection is inactive" branch
		# while is_available() still claimed the LMS was listening.
		# eval() returns Variant, so the type is annotated explicitly.
		var probe: Variant = JavaScriptBridge.eval(
			"typeof pipwerks !== 'undefined' && pipwerks.SCORM.connection.isActive === true", true)
		_available = bool(probe)
	if not _available:
		print_rich("[color=gray]LMS: running detached, SCORM calls will be logged only.[/color]")


func is_available() -> bool:
	return _available


func set_value(key: String, value: String) -> void:
	sent[key] = value
	if not _available:
		print("LMS (detached) %s = %s" % [key, value])
		return
	var js := "pipwerks.SCORM.set('%s', decodeURIComponent('%s'));" % [key, value.uri_encode()]
	JavaScriptBridge.eval(js)


func commit() -> void:
	if _available:
		JavaScriptBridge.eval("pipwerks.SCORM.save();")


## Fired once, at the debrief.
func report_result(passed: bool, score_percent: int, transcript: String) -> void:
	set_value("cmi.core.lesson_status", "passed" if passed else "failed")
	set_value("cmi.core.score.raw", str(score_percent))
	set_value("cmi.core.score.min", "0")
	set_value("cmi.core.score.max", "100")

	# cmi.comments is capped at 4096 chars in SCORM 1.2. Keep the tail,
	# which is where the failures that ended the exercise will be.
	var comments := transcript
	if comments.length() > 4000:
		comments = comments.right(4000)
	set_value("cmi.comments", comments)
	commit()


## The crash trail. Driven by assessment.gd, which re-sends it as the record
## changes, so a browser that dies mid-exercise leaves behind how far the
## trainee got instead of an attempt that reads as never opened.
##
## Note the LMS is only obliged to keep cmi.suspend_data when the attempt ends
## with cmi.core.exit = "suspend", and every exit path here sets it to "" - a
## finished run is finished. That is the right trade: on a clean exit the
## verdict and the transcript have already gone out through report_result(),
## and it is precisely the unclean exit, where nothing else was sent, that
## leaves no exit status behind for the LMS to act on.
func save_progress(data: String) -> void:
	var payload := data
	if payload.length() > 4000:
		payload = payload.right(4000)
	set_value("cmi.suspend_data", payload)
	commit()


## Ends the SCORM session. The shell owns the session clock and writes
## cmi.core.session_time on the way through, so the exit paths do not have to
## agree on a duration between them - see scorm_shell.html. The fallback is for
## the course being served through some other shell, where a bare quit is still
## better than an abandoned session.
func quit_session() -> void:
	if _available:
		JavaScriptBridge.eval(
			"typeof lvrScormFinish === 'function' ? lvrScormFinish() : pipwerks.SCORM.quit();")
