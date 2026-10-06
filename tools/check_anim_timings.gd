extends SceneTree
## Dumps the LVR_* clips' lengths and, for each, the per-0.1s motion energy of
## the position/rotation tracks - so a dead (motionless) lead-in shows up as a
## run of zero deltas where the worker visibly stands still.

func _init() -> void:
	var packed: PackedScene = load("res://LVR CPR.blend")
	if packed == null:
		print("FAILED to load LVR CPR.blend")
		quit()
		return
	var room: Node = packed.instantiate()
	_scan(room)
	room.free()
	quit()


func _scan(n: Node) -> void:
	if n is AnimationPlayer:
		_dump(n as AnimationPlayer)
	for c in n.get_children():
		_scan(c)


func _dump(player: AnimationPlayer) -> void:
	var lines: Array[String] = []
	for anim_name in player.get_animation_list():
		var bare := String(anim_name)
		if not bare.begins_with("LVR_"):
			continue
		var anim := player.get_animation(anim_name)
		lines.append("=== %s  length=%.3fs fps=%.1f tracks=%d" % [bare, anim.length, anim.step, anim.get_track_count()])
		# Motion energy: max per-track value delta over each 0.1 s window.
		var window := 0.1
		var t := 0.0
		while t < anim.length:
			var e := _window_energy(anim, t, minf(t + window, anim.length))
			lines.append("  %.2f-%.2fs  max_delta=%.4f%s" % [t, t + window, e, "   <-- STILL" if e < 0.001 else ""])
			t += window
	var out := ProjectSettings.globalize_path("res://tools/out_anim_timings.txt")
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines))
		f.close()
	print("WROTE ", out)
	print("\n".join(lines))


func _window_energy(anim: Animation, from: float, to: float) -> float:
	var worst := 0.0
	for i in anim.get_track_count():
		var path := anim.track_get_path(i)
		# Only body-motion tracks; skip blend shapes (mouth) which are quiet anyway.
		if String(path).contains("Mouth"):
			continue
		var kt := anim.track_get_key_count(i)
		if kt < 2:
			continue
		var prev_v: Variant = null
		var prev_t := -1.0
		for k in kt:
			var t := anim.track_get_key_time(i, k)
			if t < from - 0.0001:
				prev_v = anim.track_get_key_value(i, k)
				prev_t = t
				continue
			if t > to + 0.0001:
				break
			var v: Variant = anim.track_get_key_value(i, k)
			if prev_v != null:
				var d := _delta(prev_v, v, prev_t, t, from, to)
				worst = maxf(worst, d)
			prev_v = v
			prev_t = t
	return worst


func _delta(a: Variant, b: Variant, ta: float, tb: float, from: float, to: float) -> float:
	# The keys may straddle the window; scale the delta to the window's span.
	if ta < from:
		ta = from
	if tb > to:
		tb = to
	if tb <= ta:
		return 0.0
	var full := absf(tb - ta) if (tb - ta) > 0.0 else 0.0001
	var frac := (tb - ta) / maxf(absf(tb - ta), 0.0001)
	var span := maxf(absf(tb - ta), 0.0001)
	# Interpolated endpoints are overkill; just compare raw keys scaled to how
	# much of the window they cover.
	frac = span / span
	frac = 1.0
	if a is Vector3 and b is Vector3:
		return (b as Vector3).distance_to(a as Vector3) * frac
	if a is Quaternion and b is Quaternion:
		return (b as Quaternion).angle_to(a as Quaternion) * frac
	if a is float and b is float:
		return absf(b as float - a as float) * frac
	if a is Transform3D and b is Transform3D:
		return ((b as Transform3D).origin.distance_to((a as Transform3D).origin)) * frac
	return 0.0
