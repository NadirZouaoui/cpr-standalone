extends Node
## Regression check for inverted shading.
##
## Puts an OmniLight3D at the camera position and photographs every mesh in
## LVR CPR.blend one at a time. A light co-located with the camera must
## illuminate every visible surface, so anything that comes back near-black has
## normals pointing away from the viewer - the signature of the mirrored
## transform problem that scripts/import/fix_mirrored_meshes.gd corrects.
##
## Run it after touching the .blend, the import settings, or the import script:
##     godot --path <project> res://tools/check_shading.tscn
##
## Genuinely dark materials (screens, black plastic) can trip the threshold, so
## treat SUSPECT as "go and look", not as a failure.

const LIT_THRESHOLD := 0.05

var root: Node
var cam: Camera3D
var light: OmniLight3D


func _ready() -> void:
	get_window().size = Vector2i(384, 384)
	root = (load("res://LVR CPR.blend") as PackedScene).instantiate()
	add_child(root)
	await get_tree().process_frame

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_energy = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	add_child(we)

	cam = Camera3D.new()
	cam.near = 0.01
	add_child(cam)
	cam.current = true

	light = OmniLight3D.new()
	light.light_energy = 6.0
	light.omni_range = 500.0
	light.shadow_enabled = false
	add_child(light)

	var meshes: Array[MeshInstance3D] = []
	_gather(root, meshes)

	print("=== SHADING CHECK (%d meshes) ===" % meshes.size())
	var suspects: PackedStringArray = []
	for mi in meshes:
		var result: Dictionary = await _check(mi)
		if result.is_empty():
			continue
		var flag: String = "ok"
		if result["lum"] < LIT_THRESHOLD:
			flag = "SUSPECT"
			suspects.append(String(mi.name))
		print("  %-28s det=%+9.4f  px=%6d  lum=%.4f  %s" % [
			String(mi.name), result["det"], result["px"], result["lum"], flag])

	if suspects.is_empty():
		print("=== all meshes light up ===")
	else:
		print("=== %d suspect(s): %s ===" % [suspects.size(), ", ".join(suspects)])
	get_tree().quit()


func _gather(n: Node, into: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		into.append(n)
	for c in n.get_children():
		_gather(c, into)


func _check(mi: MeshInstance3D) -> Dictionary:
	_solo(mi)

	var centre := Vector3.ZERO
	var radius := 1.0
	if mi.skin != null:
		var skel: Skeleton3D = mi.get_node_or_null(mi.skeleton)
		if skel == null:
			return {}
		var lo := Vector3.INF
		var hi := -Vector3.INF
		for i in skel.get_bone_count():
			var p: Vector3 = (skel.global_transform * skel.get_bone_global_pose(i)).origin
			lo = lo.min(p)
			hi = hi.max(p)
		centre = (lo + hi) * 0.5
		radius = (hi - lo).length() * 0.5
	else:
		var ab: AABB = mi.global_transform * mi.get_aabb()
		centre = ab.get_center()
		radius = ab.size.length() * 0.5
	if radius < 0.0001:
		return {}

	cam.global_position = centre + Vector3(0.7, 0.4, 0.7).normalized() * radius * 1.9
	cam.look_at(centre, Vector3.UP)
	light.global_position = cam.global_position

	# Silhouette, so the lit result can be normalised by visible area.
	var mask := StandardMaterial3D.new()
	mask.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mask.albedo_color = Color.WHITE
	mi.material_override = mask
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var px: int = 0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			if img.get_pixel(x, y).get_luminance() > 0.2:
				px += 1
	if px < 20:
		return {}

	mi.material_override = null
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	img = get_viewport().get_texture().get_image()
	var sum: float = 0.0
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			sum += img.get_pixel(x, y).get_luminance()

	return {
		"det": mi.global_transform.basis.determinant(),
		"px": px,
		"lum": sum / float(px),
	}


func _solo(keep: MeshInstance3D) -> void:
	_set_vis(root, keep)


func _set_vis(n: Node, keep: MeshInstance3D) -> void:
	if n is VisualInstance3D:
		(n as VisualInstance3D).visible = (n == keep)
	for c in n.get_children():
		_set_vis(c, keep)
