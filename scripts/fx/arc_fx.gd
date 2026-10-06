class_name ArcFx
extends Node3D
## Arc flash at the MCCB: sparks, light flicker and sound.
##
## Self-contained. Drop one Node3D with this script at the breaker face,
## point its -Z at the room (sparks spray along local -Z), and call
## `start()` / `stop()`. Everything else - particle meshes, materials,
## light, audio players - is built in `_ready()`, so there is nothing to
## wire in the .tscn and no exported NodePaths to hand-write.
##
## The two audio streams are the only things you assign in the inspector.

## Crack of the arc. Retriggered for as long as the arc runs, so this can be
## the whole soundtrack if you have no separate buzz.
@export var zap_sound: AudioStream

## Optional bed under the zaps: a seamless buzz held until release.
@export var buzz_sound: AudioStream

@export_group("Sparks")
## Spray half-angle in degrees. Low = a tight jet, high = a shower.
@export_range(0.0, 90.0) var spread_degrees: float = 35.0
## Sparks in the initial burst.
@export var burst_amount: int = 96
## Sparks per lifetime while the arc is sustained.
@export var sustain_amount: int = 40
## Metres per second off the breaker face.
@export var spark_speed: float = 3.0
@export var spark_lifetime: float = 0.55

@export_group("Light")
@export var flash_energy: float = 6.0
@export var sustain_energy: float = 1.6
@export var light_range: float = 4.0
@export var arc_color: Color = Color(0.75, 0.85, 1.0)

@export_group("Audio")
@export_range(-40.0, 12.0) var zap_db: float = 0.0
@export_range(-40.0, 12.0) var buzz_db: float = -6.0
## Keep firing the zap until `stop()`. Off = a single crack at contact.
@export var zap_repeat: bool = true
## Silence between zaps, randomised in this range. Set both to 0.0 for a
## gapless stutter; a small spread stops it sounding metronomic.
@export var zap_gap_min: float = 0.05
@export var zap_gap_max: float = 0.35
## Each repeat is pitched slightly off so the ear does not hear one sample
## looping. 1.0 disables the variation.
@export_range(1.0, 1.5) var zap_pitch_spread: float = 1.12
## Metres. Beyond this the arc is inaudible.
@export var audio_max_distance: float = 18.0
## Seconds to fade the buzz out on stop(), so the rescue does not click.
@export var buzz_fade_out: float = 0.35

var _burst: GPUParticles3D
var _sustain: GPUParticles3D
var _light: OmniLight3D
var _zap: AudioStreamPlayer3D
var _buzz: AudioStreamPlayer3D
var _active: bool = false
var _flicker_time: float = 0.0
var _zap_wait: float = 0.0
var _fade_tween: Tween


func _ready() -> void:
	_build()
	set_process(false)
	_warmup()


## Same reason the light is never switched off: the web export builds the
## particle shaders on first use, which stalled the frame of contact. One
## spark from each emitter at load builds them while the trainee is still on
## the opening card, and one spark at the panel is invisible.
func _warmup() -> void:
	for p: GPUParticles3D in [_burst, _sustain]:
		p.amount_ratio = 1.0 / p.amount
		p.emitting = true
	await RenderingServer.frame_post_draw
	for p: GPUParticles3D in [_burst, _sustain]:
		p.amount_ratio = 1.0
		if not _active:
			p.emitting = false


func _build() -> void:
	_burst = _make_emitter("SparkBurst", burst_amount, true)
	_sustain = _make_emitter("SparkSustain", sustain_amount, false)

	_light = OmniLight3D.new()
	_light.name = "ArcLight"
	_light.light_color = arc_color
	_light.light_energy = 0.0
	_light.omni_range = light_range
	# The flash is a fill light, not a shadow caster - shadows on a mobile-
	# grade web export cost more than the flicker is worth.
	_light.shadow_enabled = false
	# Left visible at zero energy rather than toggled. The web renderer lights
	# each object with an extra pass per omni light, and switching a light on
	# for the first time compiled that pass for every material in range - the
	# hitch on the frame of contact. Present from the start, it compiles
	# during load instead.
	add_child(_light)

	_zap = _make_player("ArcZap", zap_sound, zap_db, false)
	_buzz = _make_player("ArcBuzz", buzz_sound, buzz_db, true)


func _make_emitter(node_name: String, amount: int, one_shot: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = node_name
	p.amount = maxi(1, amount)
	p.lifetime = spark_lifetime
	p.one_shot = one_shot
	p.emitting = false
	p.explosiveness = 1.0 if one_shot else 0.0
	p.local_coords = false
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	p.process_material = _make_process_material(one_shot)
	p.draw_pass_1 = _make_spark_mesh()
	add_child(p)
	return p


func _make_process_material(one_shot: bool) -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.03
	# Sparks leave along the node's local -Z, so aiming the node aims the FX.
	m.direction = Vector3(0.0, 0.0, -1.0)
	m.spread = spread_degrees
	m.initial_velocity_min = spark_speed * (0.7 if one_shot else 0.4)
	m.initial_velocity_max = spark_speed * (1.6 if one_shot else 1.0)
	m.gravity = Vector3(0.0, -9.8, 0.0)
	m.damping_min = 1.0
	m.damping_max = 3.0
	m.scale_min = 0.4
	m.scale_max = 1.0
	# Sparks cool as they fall: white-hot to orange to out.
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.25, 0.7, 1.0])
	grad.colors = PackedColorArray([
		Color(1.6, 1.6, 1.5, 1.0),
		Color(1.4, 0.9, 0.35, 1.0),
		Color(1.0, 0.35, 0.05, 1.0),
		Color(0.4, 0.1, 0.0, 0.0),
	])
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	m.color_ramp = ramp
	# Streak: sparks stretch along their velocity so they read as lines.
	var curve := CurveXYZTexture.new()
	var flat := Curve.new()
	flat.add_point(Vector2(0.0, 1.0))
	flat.add_point(Vector2(1.0, 0.2))
	var long := Curve.new()
	long.max_value = 6.0
	long.add_point(Vector2(0.0, 4.0))
	long.add_point(Vector2(1.0, 1.0))
	curve.curve_x = flat
	curve.curve_y = flat
	curve.curve_z = long
	m.scale_curve = curve
	return m


func _make_spark_mesh() -> Mesh:
	var q := QuadMesh.new()
	q.size = Vector2(0.006, 0.006)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.disable_receive_shadows = true
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	q.material = mat
	return q


func _make_player(node_name: String, stream: AudioStream, db: float, looping: bool) -> AudioStreamPlayer3D:
	var a := AudioStreamPlayer3D.new()
	a.name = node_name
	a.stream = stream
	a.volume_db = db
	a.max_distance = audio_max_distance
	a.unit_size = 4.0
	a.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	if looping and stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	add_child(a)
	return a


## Fire the arc. Idempotent - a second call while running does nothing, so a
## cue that double-fires cannot restack the burst.
func start() -> void:
	if _active:
		return
	_active = true
	_flicker_time = 0.0
	_zap_wait = 0.0

	_burst.restart()
	_burst.emitting = true
	_sustain.emitting = true

	_light.light_energy = flash_energy

	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	if _zap.stream != null:
		_zap.pitch_scale = 1.0
		_zap.play()
	if _buzz.stream != null:
		_buzz.volume_db = buzz_db
		_buzz.play()

	set_process(true)


## Cut the arc - call this the moment the rescue breaks contact.
func stop() -> void:
	if not _active:
		return
	_active = false
	_sustain.emitting = false
	_burst.emitting = false
	set_process(false)
	_light.light_energy = 0.0

	if _zap.playing:
		_zap.stop()

	if _buzz.playing:
		if _fade_tween != null and _fade_tween.is_valid():
			_fade_tween.kill()
		_fade_tween = create_tween()
		_fade_tween.tween_property(_buzz, "volume_db", -60.0, buzz_fade_out)
		_fade_tween.tween_callback(_buzz.stop)


func is_active() -> bool:
	return _active


func _process(delta: float) -> void:
	# Two out-of-phase sines plus jitter: reads as mains-frequency flicker
	# without needing a noise texture.
	_flicker_time += delta
	var t := _flicker_time
	var wobble := 0.55 + 0.25 * sin(t * 47.0) + 0.20 * sin(t * 13.3) + randf() * 0.25
	# The opening flash decays into the sustained level over ~0.2 s.
	var settle: float = clampf(t / 0.2, 0.0, 1.0)
	var base: float = lerpf(flash_energy, sustain_energy, settle)
	_light.light_energy = base * wobble

	_tick_zap(delta)


## Keeps the crack going for the whole contact. Rather than looping the
## stream - which would tick audibly at the seam - each pass waits a random
## gap after the last one finishes and replays at a slightly different pitch.
func _tick_zap(delta: float) -> void:
	if not zap_repeat or _zap.stream == null or _zap.playing:
		return
	_zap_wait -= delta
	if _zap_wait > 0.0:
		return
	_zap_wait = randf_range(zap_gap_min, maxf(zap_gap_min, zap_gap_max))
	_zap.pitch_scale = randf_range(1.0 / zap_pitch_spread, zap_pitch_spread)
	_zap.play()
