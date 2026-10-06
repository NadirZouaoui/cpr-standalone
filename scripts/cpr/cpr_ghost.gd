class_name CprGhost
extends RefCounted

## Ghost material factory for the CPR phase.
##
## Pad sites and the AED drop location are real meshes authored in Blender, conformed
## to the surface they sit on. They start hidden; when a station needs them it shows
## them with a translucent override from here, then clears the override to "place" them.
##
## SHARED / FROZEN — see CPR_CONTRACT.md section 7. Do not edit without agreement.

# --- palette -----------------------------------------------------------------
# The CPR phase used its own cool blue/cyan/green set, which read as a
# different product from the rest of the game — every other affordance in the
# sim highlights in Tokens.ATTENTION gold. Consolidated onto that: same hue
# throughout, with brightness and alpha carrying the state instead of hue.
const COLOR_IDLE  := Tokens.ATTENTION                  # "available"
const COLOR_HOVER := Color(1.00, 0.87, 0.55)           # brighter — "under the crosshair"
const COLOR_DROP  := Tokens.ATTENTION                  # the AED drop location

const ALPHA_IDLE  := 0.30
const ALPHA_HOVER := 0.58

## Conformed duplicates sit exactly on the skin, so they z-fight badly. `grow` pushes
## the ghost shell out along its normals by this much. 1.5 mm is enough on this model
## without the ghost visibly floating.
const GROW_METRES := 0.0015

# --- material cache ----------------------------------------------------------
# Materials are shared across every ghost. Do not mutate a returned material —
# swap to a different one instead.
static var _cache: Dictionary = {}


## Returns a cached unshaded translucent material.
static func material(color: Color, alpha: float) -> StandardMaterial3D:
	var key := "%.3f_%.3f_%.3f_%.3f" % [color.r, color.g, color.b, alpha]
	if _cache.has(key):
		return _cache[key]

	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	m.cull_mode = BaseMaterial3D.CULL_BACK
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.grow = true
	m.grow_amount = GROW_METRES
	# Keep ghosts drawn after opaque geometry so the alpha sorts predictably.
	m.render_priority = 1
	_cache[key] = m
	return m


static func idle_material() -> StandardMaterial3D:
	return material(COLOR_IDLE, ALPHA_IDLE)


static func hover_material() -> StandardMaterial3D:
	return material(COLOR_HOVER, ALPHA_HOVER)


static func drop_material(hovered: bool = false) -> StandardMaterial3D:
	return material(COLOR_DROP, ALPHA_HOVER if hovered else ALPHA_IDLE)


# --- convenience -------------------------------------------------------------

## Show `mesh` as a ghost.
static func show_as_ghost(mesh: MeshInstance3D, mat: StandardMaterial3D) -> void:
	if mesh == null:
		return
	mesh.material_override = mat
	mesh.visible = true


## Clear the override so the mesh renders with its authored material. This is what
## "placing" a pad looks like — same mesh, real material.
static func place(mesh: MeshInstance3D) -> void:
	if mesh == null:
		return
	mesh.material_override = null
	mesh.visible = true


## Hide and clear. Safe to call on a mesh that was never ghosted.
static func hide_ghost(mesh: MeshInstance3D) -> void:
	if mesh == null:
		return
	mesh.material_override = null
	mesh.visible = false


# --- node lookup -------------------------------------------------------------

## Recursive find-by-name. The project's binder doctrine: resolve nodes at `_ready()`
## rather than trusting editor-wired NodePaths, which `.blend` reimports have dropped.
## Returns null if not found — callers must `push_error` and disable themselves.
static func find_node(root: Node, node_name: String) -> Node:
	if root == null:
		return null
	if root.name == node_name:
		return root
	for child in root.get_children():
		var hit := find_node(child, node_name)
		if hit != null:
			return hit
	return null


## Every descendant whose name begins with `prefix`, sorted by name for stable order.
static func find_nodes_with_prefix(root: Node, prefix: String) -> Array:
	var out: Array = []
	_collect_prefix(root, prefix, out)
	out.sort_custom(func(a, b): return String(a.name) < String(b.name))
	return out


static func _collect_prefix(node: Node, prefix: String, out: Array) -> void:
	if node == null:
		return
	if String(node.name).begins_with(prefix):
		out.append(node)
	for child in node.get_children():
		_collect_prefix(child, prefix, out)
