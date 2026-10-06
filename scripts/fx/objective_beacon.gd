class_name ObjectiveBeacon
extends Node3D
## The floating arrow that says "the thing you are being asked to do is here".
##
## Lifted out of breaker_panel.gd, which authored the only one in the game: a
## bobbing, slowly spinning cone pointing tip-down at an objective, unshaded and
## emissive so it reads against the room's own lighting at any angle. That one
## works and trainees follow it, so the kit bench gets the same object rather
## than a second thing that looks nearly like it.
##
## Pure presentation. It knows where it is and whether it is up; it knows
## nothing about what it is pointing at or why. Whoever builds it owns the
## sequence and moves it - see BreakerPanel._refresh_beacon_target() for the
## non-trivial case, where the objective moves twice while the arrow is up.
##
## Built in code and added with `owner = null` like everything else here, so it
## is never serialised into a scene file and survives a .blend reimport
## (ARCHITECTURE.md section 1).

## Tip-down at the objective. Not exported: every caller wants the same arrow,
## and the one that did not - a smaller or larger one - would be better served
## by scaling the node.
const CONE_RADIUS := 0.075
const CONE_HEIGHT := 0.2
const CONE_SEGMENTS := 12

@export var color: Color = Tokens.ATTENTION
@export var bob: float = 0.06
@export var spin_speed: float = 1.1

var _cone: MeshInstance3D = null
var _t: float = 0.0


## `parent` rather than the caller adding this itself, because the two things
## that have to happen on the way in - `owner = null` and starting hidden - are
## both easy to forget and neither fails loudly.
static func build(parent: Node, beacon_name: String = "ObjectiveBeacon", edge_label: String = "") -> ObjectiveBeacon:
	if parent == null:
		return null
	var beacon := ObjectiveBeacon.new()
	beacon.name = beacon_name
	beacon.set_meta(&"edge_label", edge_label)
	parent.add_child(beacon)
	beacon.owner = null
	return beacon


func _ready() -> void:
	# While it is shown and out of view, edge_indicators.gd draws an arrow to it
	# from the side of the screen. Client, 23 Sep: "like in video games".
	add_to_group(&"edge_target")

	_cone = MeshInstance3D.new()
	_cone.name = "Pointer"

	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = CONE_RADIUS
	mesh.height = CONE_HEIGHT
	mesh.radial_segments = CONE_SEGMENTS
	mesh.rings = 1
	_cone.mesh = mesh
	# Tip down, at the thing it is pointing at.
	_cone.rotation_degrees = Vector3(180.0, 0.0, 0.0)

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.5
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cone.material_override = material
	_cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	add_child(_cone)
	_cone.owner = null
	set_process(visible)


## Up or down. Processing stops with it - a hidden arrow that is still spinning
## is work done for nobody.
func show_beacon(on: bool) -> void:
	visible = on
	set_process(on)


func _process(delta: float) -> void:
	_t += delta
	rotate_y(delta * spin_speed)
	if _cone != null:
		_cone.position.y = sin(_t * 2.4) * bob
