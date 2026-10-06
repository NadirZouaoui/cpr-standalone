class_name Interactable
extends Node3D
## Base contract for anything the player can look at and activate.
##
## Attach as a child of the StaticBody3D that carries the collider, or
## directly to a mesh. The highlight target is auto-detected from the
## parent chain if not set.
##
## Subclasses override `_on_interact()` and optionally `can_interact()`.
## They should NOT reach for the scene root - emit through Events instead.

const GROUP := &"interactable"

@export_group("Identity")
## Stable id used by procedure steps and grading. Renaming the node in
## Blender must never change this.
@export var id: StringName = &""

## Shown on the reticle prompt. Falls back to the node name.
@export var display_name: String = ""

## Verb shown before the name, e.g. "Open" -> "Open Cabinet Door".
@export var verb: String = "Use"

@export_group("Availability")
@export var enabled: bool = true

## When set, the prompt is shown but activating it reports this refusal
## instead of running the interaction.
@export var disabled_reason: String = ""

@export_group("Highlight")
@export var mesh_to_highlight: GeometryInstance3D
@export var highlight_color: Color = Color("f9e30026")
@export var outline_thickness: float = 0.02

var _highlight_material: StandardMaterial3D
var _is_highlighted: bool = false


func _ready() -> void:
	add_to_group(GROUP)

	if id == &"":
		push_warning("Interactable '%s' has no id; grading cannot reference it." % name)

	if mesh_to_highlight == null:
		mesh_to_highlight = _find_highlight_target()

	_highlight_material = StandardMaterial3D.new()
	_highlight_material.albedo_color = highlight_color
	_highlight_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_highlight_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_highlight_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_highlight_material.grow = true
	_highlight_material.grow_amount = outline_thickness

	_ready_impl()


## Subclass hook - runs after the base is initialised.
func _ready_impl() -> void:
	pass


func _find_highlight_target() -> GeometryInstance3D:
	var node: Node = get_parent()
	for _i in 3:
		if node == null:
			break
		if node is GeometryInstance3D:
			return node
		node = node.get_parent()
	# Fall back to a mesh sibling or child.
	for child in get_children():
		if child is GeometryInstance3D:
			return child
	return null


# =============================================================================
# Focus
# =============================================================================
func highlight() -> void:
	if _is_highlighted or mesh_to_highlight == null:
		return
	_is_highlighted = true
	mesh_to_highlight.material_overlay = _highlight_material


func unhighlight() -> void:
	if not _is_highlighted or mesh_to_highlight == null:
		return
	_is_highlighted = false
	mesh_to_highlight.material_overlay = null


## The name shown to the player. `name` is a StringName, so it is converted
## explicitly rather than left to a Variant-typed ternary.
func label() -> String:
	return display_name if display_name != "" else String(name)


## Text for the reticle. Override for state-dependent prompts
## ("Open Door" vs "Close Door").
func prompt_text() -> String:
	return "%s %s" % [verb, label()]


# =============================================================================
# Activation
# =============================================================================
## Override to gate on simulation state. Returning false hides the prompt.
func can_interact() -> bool:
	return enabled


func interact(from_position: Vector3 = Vector3.ZERO) -> void:
	if not can_interact():
		return
	if disabled_reason != "":
		Events.center_message_requested.emit(disabled_reason, Tokens.WARNING, 2.5)
		return
	Events.interacted.emit(self, from_position)
	_on_interact(from_position)


## Subclass hook - the actual behaviour.
func _on_interact(_from_position: Vector3) -> void:
	pass
