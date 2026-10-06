extends Node

## Visual probe for the kit-check highlight (post-fix).
##
##   & "C:\Program Files\Godot.exe" --path <project> res://tools/highlight_probe.tscn
##
## Instances the room, applies ghost materials with the same per-mesh scale
## conversion KitInspectItem now uses, frames the bench, and saves screenshots
## to tools/out_*.png.

const ROOM := preload("res://LVR CPR.blend")
const THICKNESS := 0.005

## Kit items get the green "marked" ghost.
const MARKED := ["Rescue kit bag", "Hook", "Gloves", "Fire blanket",
	"Burns_dressings", "Flashlight", "Isolate here", "AED Defibrilator Cabinet"]


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
	e.background_color = Color(0.5, 0.5, 0.55)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.7)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)

	await get_tree().process_frame
	await get_tree().physics_frame

	for nm in MARKED:
		var mesh := _find(room, nm) as MeshInstance3D
		if mesh == null:
			print("MISSING %s" % nm)
			continue
		var mat := _ghost(Color(0.24, 0.85, 0.38, 0.42))
		mat.grow_amount = _local_thickness(mesh)
		mesh.material_overlay = mat

	var bench := _find(room, "Aged Sideboard") as MeshInstance3D
	var bench_top: Vector3 = bench.global_position + Vector3(0.1, 1.03, 0.68)
	var cam := Camera3D.new()
	add_child(cam)
	# Stand where the trainee stands: across the bench, looking down.
	cam.global_position = bench_top + Vector3(-0.1, 1.25, 1.55)
	cam.look_at(bench_top, Vector3.UP)
	cam.fov = 65.0

	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://tools/out_fixed_overview.png"))

	# Half-bench close-ups, still at a natural angle.
	for offset: Vector3 in [Vector3(-0.55, 0, 0.1), Vector3(0.5, 0, 0.1)]:
		var target := bench_top + offset
		cam.global_position = target + Vector3(-0.05, 0.75, 0.85)
		cam.look_at(target, Vector3.UP)
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(
			ProjectSettings.globalize_path("res://tools/out_fixed_half_%s.png" %
				("left" if offset.x < 0 else "right")))
	print("done")
	get_tree().quit()


func _ghost(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.grow = true
	m.grow_amount = THICKNESS
	return m


## Mirrors KitInspectItem._local_ghost_thickness().
func _local_thickness(mesh: MeshInstance3D) -> float:
	var b := mesh.global_transform.basis
	var mean_scale := (b.x.length() + b.y.length() + b.z.length()) / 3.0
	return THICKNESS / maxf(mean_scale, 0.0001)


func _world_centre(mesh: MeshInstance3D) -> Vector3:
	return mesh.global_transform * mesh.mesh.get_aabb().get_center()


func _find(n: Node, target: String) -> Node:
	if String(n.name) == target:
		return n
	for c in n.get_children():
		var r := _find(c, target)
		if r != null:
			return r
	return null
