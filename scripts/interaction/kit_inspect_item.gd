class_name KitInspectItem
extends Interactable
## A bench object during the kit identification phase.
##
## Deliberately thin: it knows its own id, whether the trainee has claimed it
## as rescue kit, and whether it is currently marked. Nothing about grading,
## choices or scoring. Clicking it tells KitBench; KitBench decides what that
## click means.
##
## Lives alongside the PickupItem on the same mesh rather than replacing it.
## The two never compete, because each is only available in one phase -
## naming things is the preamble, picking them up is the exercise - and
## InteractionRay prefers whichever of them currently reports available.

## Group every KitInspectItem joins, so the diegetic naming menu can find the
## mesh it should float above without KitBench handing it a reference.
const GROUP_KIT_INSPECT := &"kit_inspect"

## How far the ghost shell stands off the mesh, in world metres. Small on
## purpose: wide enough to clear the depth test, tight enough that the shell
## still reads as the object's own shape.
const GHOST_THICKNESS := 0.005

## Matches KitItem.id.
@export var item_id: StringName = &""

## True once the trainee has named this object as rescue kit. Not final:
## clicking a claimed object takes the claim back, which is the only way to
## say "not in the bag after all" - so a claimed object has to stay
## interactable, where an answered one used to stand itself down.
var claimed: bool = false

## Gating, driven by KitBench. False while the naming menu or the review card
## is up: both are picked with this same crosshair and this same button, so an
## object left live behind either of them swallows the click.
var naming_active: bool = false

var _hovered: bool = false
var _marked: bool = false
var _marked_material: StandardMaterial3D


func _ready_impl() -> void:
	if item_id == &"":
		push_warning("KitInspectItem '%s' has no item_id" % name)
	add_to_group(GROUP_KIT_INSPECT)

	# Same construction as the base hover material, but the colour that says
	# "you have claimed this one" rather than "you are looking at this one".
	_marked_material = StandardMaterial3D.new()
	_marked_material.albedo_color = Color(0.24, 0.85, 0.38, 0.42)
	_marked_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_marked_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marked_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_marked_material.grow = true
	_marked_material.grow_amount = outline_thickness

	# The base built the hover material with the raw outline_thickness before
	# this ran; both materials get the same scale-corrected thickness.
	var thickness := _local_ghost_thickness()
	if thickness > 0.0:
		_marked_material.grow_amount = thickness
		_highlight_material.grow_amount = thickness


## grow pushes vertices along their normals in mesh-local space, so the raw
## thickness is multiplied by whatever the node's scale happens to be. The
## bench props span that whole range: the bag sits at scale 1.0 and grew a
## 2 cm balloon, while the gloves sit at ~1% scale and their ghost collapsed
## to a fraction of a millimetre - so close to the surface that it loses the
## depth test and only patches of it show. Convert the wanted world distance
## into local units per mesh.
func _local_ghost_thickness() -> float:
	if mesh_to_highlight == null:
		return 0.0
	var basis := mesh_to_highlight.global_transform.basis
	var mean_scale := (basis.x.length() + basis.y.length() + basis.z.length()) / 3.0
	if mean_scale < 0.0001:
		return 0.0
	return GHOST_THICKNESS / mean_scale


func can_interact() -> bool:
	return enabled and naming_active and SimState.is_preamble()


## Says which of the two things a click will do, because there are only two
## and one of them is destructive. There is no third option and no menu entry
## for "not in the kit": leaving an object alone is how the trainee says that,
## and taking a claim back is how they change their mind about it.
func prompt_text() -> String:
	if not naming_active:
		return ""
	if claimed:
		return "Named as kit - click to take it back"
	return "In the LV rescue kit? Click to name it"


func _on_interact(_from_position: Vector3) -> void:
	Events.kit_item_inspected.emit(item_id)


## The base class owns the hover overlay directly; this item has two overlay
## states that share the one material_overlay slot, so it composes them here
## instead: the mark wins over the hover, so a selected item stays visibly
## claimed while the crosshair passes over it.
func highlight() -> void:
	_hovered = true
	_refresh_overlay()


func unhighlight() -> void:
	_hovered = false
	_refresh_overlay()


## KitBench marks an object while the menu is asking about it, and leaves it
## marked for as long as the claim on it stands.
func set_marked(marked: bool) -> void:
	_marked = marked
	_refresh_overlay()


## Called by KitBench when a naming lands, and again when the claim is taken
## back. The mark follows the claim, so the green shell on the bench is always
## the trainee's own current answer rather than a spent selection.
func set_claimed(value: bool) -> void:
	claimed = value
	set_marked(value)


func _refresh_overlay() -> void:
	if mesh_to_highlight == null:
		return
	if _marked:
		mesh_to_highlight.material_overlay = _marked_material
	elif _hovered:
		mesh_to_highlight.material_overlay = _highlight_material
	else:
		mesh_to_highlight.material_overlay = null
