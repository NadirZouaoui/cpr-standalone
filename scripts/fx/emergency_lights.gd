class_name EmergencyLights
extends CanvasLayer
## The red-and-blue wash that says the ambulance is outside.

## The handover beat is the one moment in the run where something arrives that
## the trainee did not do, and until now the only sign of it was the siren on
## the audio bus. A run played muted - a classroom, a shared office, a SCORM
## player with its volume down - reached the end of the exercise with nothing
## on screen to mark it, and the debrief appeared out of a beat that looked
## identical to the one before it.
##
## Lights rather than a room light: the casualty is indoors, the ambulance is
## not, and the geometry it would have to shine through is an imported .blend
## whose node subtree is rebuilt on every reimport (ARCHITECTURE.md section 1).
## A screen wash needs nothing from the room, reads at every camera anchor
## including the rolled ones, and is the same effect the trainee has actually
## seen on a street: colour sweeping across everything from somewhere off to
## the side.
##
## Two edge gradients, left and right, in counter-phase - one is at full while
## the other is out - which is what a two-bar light bar does. Deliberately not
## a full-screen tint: the trainee is still working (the injury survey and the
## handover both happen under this) and tinting the casualty would fight the
## body pointers for the middle of the frame. The middle stays clean.
##
## Pure presentation, and additive: nothing here blocks input, and the layer
## sits under the HUD so pills and cards are never washed.

## Under everything the trainee reads. The HUD and the pointers own the layers
## above; this is scenery.
const LAYER := -1

## A full sweep of the bar, in seconds. Real light bars run faster than this;
## the flash has to live behind a debrief that people read, so it is slowed to
## where it is unmistakably there and not where it is a strobe. Anything near
## 3 Hz is photosensitivity territory and this is a training product.
const PERIOD := 1.6

## How far in from each edge the wash reaches, as a fraction of screen width.
const SPREAD := 0.34

## Peak alpha at the very edge of the screen, falling linearly to nothing at
## SPREAD. Measured against the handover shot: below about 0.4 the wash is not
## reliably visible over a lit concrete floor, which is most of what the frame
## is at that point in the run.
const PEAK_ALPHA := 0.55

## Seconds to fade the whole effect in, so the ambulance arrives rather than
## being switched on.
const FADE_SECONDS := 0.9

const RED := Color(0.95, 0.13, 0.16)
const BLUE := Color(0.16, 0.35, 1.0)

var _canvas: Control = null
var _on: bool = false
var _started_ms: int = 0
var _phase: float = 0.0


## Built by whoever owns the beat, with `owner = null` so it is never
## serialised into a scene file.
static func build(parent: Node, node_name: String = "EmergencyLights") -> EmergencyLights:
	if parent == null:
		return null
	var lights := EmergencyLights.new()
	lights.name = node_name
	lights.layer = LAYER
	parent.add_child(lights)
	lights.owner = null
	return lights


func _ready() -> void:
	_canvas = Control.new()
	_canvas.name = "Wash"
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_wash)
	add_child(_canvas)
	_canvas.owner = null
	visible = false
	set_process(false)


## Turns the bar on or off. Idempotent: called from the handover beat, which
## can be re-entered by a test driving the spine directly.
func set_running(on: bool) -> void:
	if on == _on:
		return
	_on = on
	visible = on
	set_process(on)
	if on:
		_started_ms = Time.get_ticks_msec()
		_phase = 0.0
	if _canvas != null:
		_canvas.queue_redraw()


func _process(_delta: float) -> void:
	# Ticks rather than accumulated deltas, like every other timed thing in the
	# project: frame pacing inside a WebGL2 canvas is not something to build a
	# phase on (CLAUDE.md).
	var elapsed := float(Time.get_ticks_msec() - _started_ms) / 1000.0
	_phase = fposmod(elapsed / PERIOD, 1.0)
	if _canvas != null:
		_canvas.queue_redraw()


func _draw_wash() -> void:
	if _canvas == null:
		return
	var size := _canvas.size
	if size.x <= 0.0 or size.y <= 0.0:
		return

	var elapsed := float(Time.get_ticks_msec() - _started_ms) / 1000.0
	var fade: float = clampf(elapsed / FADE_SECONDS, 0.0, 1.0)

	# Counter-phase sines, squared so each bar sits dark for most of the cycle
	# and spikes rather than cross-fading. A light bar is a sequence of flashes,
	# not a colour wheel.
	var left := pow(maxf(sin(_phase * TAU), 0.0), 2.0)
	var right := pow(maxf(sin(_phase * TAU + PI), 0.0), 2.0)

	_draw_edge(size, RED, left * fade, true)
	_draw_edge(size, BLUE, right * fade, false)


## One edge gradient, as a single quad with per-vertex colour.
##
## draw_polygon() interpolates the colours across the triangles it builds, so
## the ramp is genuinely smooth. The first version stepped it as 24 hard-edged
## draw_rect() bands and the steps were plainly visible on screen as vertical
## stripes - a wash with seams in it reads as a rendering fault, not as a light.
func _draw_edge(size: Vector2, tint: Color, strength: float, from_left: bool) -> void:
	if strength <= 0.001:
		return
	var lit := tint
	lit.a = PEAK_ALPHA * strength
	var gone := tint
	gone.a = 0.0
	var width: float = size.x * SPREAD
	var inner: float = width if from_left else size.x - width
	var outer: float = 0.0 if from_left else size.x
	var points := PackedVector2Array([
		Vector2(outer, 0.0),
		Vector2(inner, 0.0),
		Vector2(inner, size.y),
		Vector2(outer, size.y),
	])
	_canvas.draw_polygon(points, PackedColorArray([lit, gone, gone, lit]))
