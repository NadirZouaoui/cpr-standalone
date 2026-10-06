@tool
extends RefCounted
## Rebuilds Blender's procedural alpha-gradient materials as Godot shaders.
##
## Blender can drive Alpha from a node graph - Cube.008 uses
## Texture Coordinate > Generated -> Separate XYZ -> Map Range -> Alpha to fade a
## black box out along one axis. glTF has no way to express that, so the
## material arrives in Godot as flat opaque black.
##
## Rather than hard-coding object names here, the objects opt in from Blender.
## Add an object custom property named godot_alpha_fade holding JSON:
##
##     {"axis": "Y", "from": 0.0, "to": 0.13}
##
## where axis is the Blender local axis the Generated coordinate is separated
## on, and from/to are the Map Range From Min / From Max. Custom properties ride
## through glTF as node extras (blender/nodes/custom_properties must stay on in
## the .blend import settings), so this keeps the .blend the source of truth.
##
## Blender is Z-up and glTF is Y-up, so the axes are remapped on the way in:
## Blender X -> Godot X, Blender Y -> Godot -Z, Blender Z -> Godot Y.

const SHADER_PATH := "res://resources/shaders/alpha_fade.gdshader"
const META_KEY := "godot_alpha_fade"

const AXIS_MAP := {
	"X": Vector3(1.0, 0.0, 0.0),
	"Y": Vector3(0.0, 0.0, -1.0),
	"Z": Vector3(0.0, 1.0, 0.0),
}


static func apply(scene: Node) -> void:
	var shader: Shader = load(SHADER_PATH)
	if shader == null:
		push_error("alpha_fade_materials: missing %s" % SHADER_PATH)
		return

	var done: PackedStringArray = []
	for mi in _mesh_instances(scene):
		var config: Dictionary = _read_config(mi)
		if config.is_empty():
			continue
		if _build(mi, shader, config):
			done.append(String(mi.name))

	if done.size() > 0:
		print("alpha_fade_materials: applied to %s" % ", ".join(done))


static func _mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array[Node] = [node]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out


## Blender custom properties arrive under a single "extras" metadata dictionary.
static func _read_config(mi: MeshInstance3D) -> Dictionary:
	if not mi.has_meta("extras"):
		return {}
	var extras: Variant = mi.get_meta("extras")
	if not (extras is Dictionary) or not (extras as Dictionary).has(META_KEY):
		return {}

	var raw: Variant = (extras as Dictionary)[META_KEY]
	var parsed: Variant = JSON.parse_string(str(raw))
	if not (parsed is Dictionary):
		push_warning("alpha_fade_materials: '%s' has unparseable %s: %s"
			% [mi.name, META_KEY, raw])
		return {}

	var config: Dictionary = parsed
	var axis: String = str(config.get("axis", "Z")).to_upper()
	if not AXIS_MAP.has(axis):
		push_warning("alpha_fade_materials: '%s' has unknown axis '%s'" % [mi.name, axis])
		return {}

	return {
		"axis": AXIS_MAP[axis],
		"from": float(config.get("from", 0.0)),
		"to": float(config.get("to", 1.0)),
	}


static func _build(mi: MeshInstance3D, shader: Shader, config: Dictionary) -> bool:
	var aabb: AABB = mi.mesh.get_aabb()
	var axis: Vector3 = config["axis"]

	# Extent of the bounding box projected onto the gradient axis, which is what
	# Blender normalises Generated coordinates by.
	var lo: float = INF
	var hi: float = -INF
	for i in 8:
		var d: float = aabb.get_endpoint(i).dot(axis)
		lo = minf(lo, d)
		hi = maxf(hi, d)
	if hi - lo < 0.000001:
		push_warning("alpha_fade_materials: '%s' is flat along the gradient axis" % mi.name)
		return false

	for s in mi.mesh.get_surface_count():
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.resource_name = "%s_alpha_fade_%d" % [mi.name, s]

		# Carry the Principled values across so the look is unchanged apart
		# from the alpha.
		var source: Material = mi.mesh.surface_get_material(s)
		if source is BaseMaterial3D:
			var b: BaseMaterial3D = source
			mat.set_shader_parameter("albedo", b.albedo_color)
			mat.set_shader_parameter("roughness", b.roughness)
			mat.set_shader_parameter("metallic", b.metallic)

		mat.set_shader_parameter("grad_axis", axis)
		mat.set_shader_parameter("grad_min", lo)
		mat.set_shader_parameter("grad_extent", hi - lo)
		mat.set_shader_parameter("from_min", config["from"])
		mat.set_shader_parameter("from_max", config["to"])

		mi.set_surface_override_material(s, mat)

	return true
