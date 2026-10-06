extends Node

## Brute force: show one top-level node at a time, screenshot each.
## The shot(s) containing the lone orange glove name the duplicate's node.

const ROOM := preload("res://LVR CPR.blend")

var _cam: Camera3D

func _ready() -> void:
	var room := ROOM.instantiate()
	add_child(room)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	sun.light_energy = 1.2
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.3, 0.3, 0.35)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.7)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	_cam = Camera3D.new()
	add_child(_cam)
	await get_tree().process_frame
	await get_tree().physics_frame

	var gloves := room.get_node("Gloves") as MeshInstance3D
	var c: Vector3 = gloves.global_transform * gloves.mesh.get_aabb().get_center()
	_cam.global_position = c + Vector3(0.0, 0.28, 0.38)
	_cam.look_at(c, Vector3.UP)
	print("cam=%s looking at %s" % [_cam.global_position, c])

	var tops := room.get_children()
	for top in tops:
		for other in tops:
			other.visible = other == top
		await RenderingServer.frame_post_draw
		var nm := String(top.name).replace(" ", "_").replace("/", "_")
		get_viewport().get_texture().get_image().save_png(
			ProjectSettings.globalize_path("res://tools/out_only_%s.png" % nm))
		print("shot only_%s" % nm)
	get_tree().quit()
