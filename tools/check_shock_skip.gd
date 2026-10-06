extends Node
## Verifies the ShockEnter dead-lead-in skip without instantiating the whole
## main scene (that hangs headless): builds a minimal Casualty, hands it the
## blend's AnimationPlayer, and runs the real measurement + play/seek path.

func _ready() -> void:
	var packed: PackedScene = load("res://LVR CPR.blend")
	if packed == null:
		print("FAILED to load LVR CPR.blend")
		get_tree().quit()
		return
	var room: Node = packed.instantiate()
	var player := _find_player(room)
	if player == null:
		print("FAILED: no AnimationPlayer in the blend")
		room.free()
		get_tree().quit()
		return

	var casualty_script := load("res://scripts/casualty/casualty.gd")
	var casualty: Casualty = casualty_script.new()
	add_child(casualty)
	casualty.animation_player = player

	var skip: float = casualty.shock_enter_start
	print("shock_enter skip = %.3fs" % skip)

	# Exercise the real handoff: play the clip and seek to the measured point.
	player.play(&"LVR_ShockEnter")
	if skip > 0.0:
		player.seek(skip, true)
	print("after seek: pos=%.3f playing=%s" % [player.current_animation_position, player.is_playing()])
	var length: float = player.get_animation(&"LVR_ShockEnter").length
	print("clip length = %.3fs (skipped = %.1f%% of the lead-in)" % [length, 100.0 * skip / length])

	casualty.free()
	room.free()
	get_tree().quit()


func _find_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var hit := _find_player(c)
		if hit != null:
			return hit
	return null
