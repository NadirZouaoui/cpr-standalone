class_name ToolRack
extends Node
## Attaches PickupItem behaviour to meshes that came out of Blender.
##
## The room is an imported .blend, so its node tree is rebuilt wholesale on
## every reimport - anything wired in the editor would be lost, and any
## exported NodePath into it would go stale. So the binding is done in code
## at startup instead, keyed on Blender object names.
##
## Consequence worth knowing: renaming an object in Blender silently breaks
## its binding. `_ready` pushes a warning listing anything it could not
## find, so a rename shows up on the first run rather than in a play test.
##
## The table lives here rather than in a .tres because the ids have to agree
## with Rescuer.REQUIRED_PPE and the procedure list, which are also code.
## Move it to a resource if a designer ever needs to edit it.

## The imported room. NodePath rather than a Node export, because a
## hand-written .tscn needs `node_paths=PackedStringArray(...)` for Node
## references and silently drops them otherwise.
@export var room_path: NodePath = ^"../ControlRoom"

## Turn off to leave the room inert while testing something else.
@export var enabled: bool = true

## Bench tools are gripped at the low end of their long axis and pointed
## forward and slightly up.
const DEFAULT_ANCHOR := Vector3(0.5, 0.0, 0.5)
const DEFAULT_AIM := Vector3(0.0, 0.25, -0.97)

## Blender object carrying the emergency-call interaction.
const RADIO_NODE := "Radio1"
## preload rather than the class_name: a freshly added script is not in the
## global class cache until the editor rescans, and this must work from a
## headless run too.
const EMERGENCY_RADIO := preload("res://scripts/interaction/emergency_radio.gd")

## Blender object name -> interaction. Keys not listed are left alone.
##
## node     Blender object name, exactly as it arrives in Godot.
## id       Rescuer / grading id. Stable; never rename to match the mesh.
## name     Shown on the reticle.
## ppe      Worn and accumulated rather than held.
## hold     Carried in the HandSlot as a view model.
## anchor   Handle position in normalised bounds space, 0-1 per axis.
## aim      Camera-space direction for the far end; -Z is into the screen.
## roll     Spin about the aim axis, degrees. The only by-eye value.
## step     Procedure step completed on pickup, or &"" for none.
const TOOLS: Array[Dictionary] = [
	# --- The one that matters: the insulated LVR rescue hook --------------
	# Grip is the ribbed end, which sits at the +X +Z corner in world space
	# and therefore at local (0, -, 0) once the node's rotation is undone.
	# Aimed up and left so the hook end reads against the centre of screen.
	{
		"node": "Hook",
		"id": &"rescue_crook",
		"name": "Rescue Crook",
		"hold": true,
		"anchor": Vector3(0.0, 0.5, 0.0),
		"aim": Vector3(-0.35, 0.45, -0.82),
		"roll": -90.0,
		"step": &"crook_retrieved",
		"offset": Vector3(-0.05, 0.025, 0.2),
	},

	# --- PPE --------------------------------------------------------------
	{
		"node": "Gloves",
		"id": &"insulated_gloves",
		"name": "LV Insulated Gloves",
		"ppe": true,
	},

	# --- Kit --------------------------------------------------------------
	# Compact objects read better gripped near their centre than by an end.
	{
		"node": "Rescue kit bag",
		"id": &"rescue_kit_bag",
		"name": "LV Rescue Bag",
		"hold": true,
		"anchor": Vector3(0.5, 0.5, 0.5),
	},
	{
		"node": "Fire blanket",
		"id": &"fire_blanket",
		"name": "Fire Blanket",
		"hold": true,
		"anchor": Vector3(0.5, 0.5, 0.5),
	},
	{
		"node": "Burns_dressings",
		"id": &"burns_dressings",
		"name": "Bandage Dressing",
		"hold": true,
		"anchor": Vector3(0.5, 0.5, 0.5),
	},
	{
		"node": "Isolate here",
		"id": &"isolation_sign",
		"name": "Danger Isolate Sign",
		"hold": true,
		"anchor": Vector3(0.5, 0.5, 0.5),
		# Measured from the mesh UVs, not assumed: the sign is a flat plaque
		# in its own XZ plane, readable face up (+Y), text up +Z, text right
		# -X. X=-90 stands it up but leaves the readable face pointing away
		# from the camera, so the player sees the mirrored back; the extra
		# Y=180 turns the face to the camera with the text upright. Roll only
		# pinwheels a plaque in the screen plane, so it cannot do this.
		"hold_rot": Vector3(-90.0, 180.0, 0.0),
	},
	{
		"node": "Flashlight",
		"id": &"flashlight",
		"name": "Torch",
		# Stowed, not held. Taking the torch IS the step - there is no on/off
		# and no light. The client asked to "turn on the torche so you can see
		# when the power goes out"; the blackout is not modelled and will not
		# be, so the torch is a precaution to sort out before the work starts,
		# and it should behave like the gloves: on the person once taken, and
		# still there after the trainee picks up the hook. Held in the hand it
		# floated in front of the camera like the isolation sign and the next
		# pickup put it back on the bench. It is not PPE either - it guards
		# against nothing electrical and must stay out of the PPE gate.
		"stow": true,
		"step": &"torch_taken",
	},

	# --- Bench tools. Present so the trainee can pick the wrong thing. ----
	{"node": "Wrench", "id": &"wrench", "name": "Adjustable Wrench", "hold": true},
	{"node": "Pliers1", "id": &"pliers", "name": "Pliers", "hold": true},
	{"node": "Hammer", "id": &"hammer", "name": "Claw Hammer", "hold": true},
	{"node": "SD1", "id": &"screwdriver_flat", "name": "Flat Screwdriver", "hold": true},
	{"node": "SD2", "id": &"screwdriver_phillips", "name": "Phillips Screwdriver", "hold": true},
	{"node": "Level1", "id": &"spirit_level", "name": "Spirit Level", "hold": true},
	{"node": "Pen1", "id": &"marker_pen", "name": "Marker Pen", "hold": true},
	{"node": "Roulette1", "id": &"tape_measure", "name": "Tape Measure", "hold": true},
	{
		"node": "Electric_hammerdrill1",
		"id": &"hammer_drill",
		"name": "Hammer Drill",
		"hold": true,
	},
]


func _ready() -> void:
	if not enabled:
		return

	var room := get_node_or_null(room_path)
	if room == null:
		push_error("ToolRack: no room at '%s'." % room_path)
		return

	var missing: Array[String] = []
	for entry in TOOLS:
		if not _bind(room, entry):
			missing.append(entry["node"])

	_bind_radio(room)

	if not missing.is_empty():
		push_warning(
			"ToolRack: %d object(s) not found in the room - renamed in Blender? %s"
			% [missing.size(), ", ".join(missing)]
		)


## The radio is not a pickup. It is the "send for help" step: using it places
## the 000 call and dispatches someone for the AED (see emergency_radio.gd).
## Bound here rather than in the .tscn for the same reimport reason as the
## tools above.
func _bind_radio(room: Node) -> void:
	var mesh := room.get_node_or_null(NodePath(RADIO_NODE)) as Node3D
	if mesh == null:
		push_warning("ToolRack: no '%s' in the room - the trainee cannot call for help." % RADIO_NODE)
		return
	var radio := EMERGENCY_RADIO.new()
	radio.name = "Interact"
	# Set before add_child: Interactable._ready() warns on a missing id, and
	# _ready_impl() runs after that check.
	radio.id = &"emergency_radio"
	radio.display_name = "Two-way Radio"
	mesh.add_child(radio)
	for body in _bodies(mesh):
		body.collision_layer |= 2


func _bind(room: Node, entry: Dictionary) -> bool:
	var mesh := room.get_node_or_null(NodePath(entry["node"])) as Node3D
	if mesh == null:
		return false

	var item := PickupItem.new()
	item.name = "Interact"
	item.id = entry["id"]
	item.item_id = entry["id"]
	item.display_name = entry.get("name", entry["node"])
	item.is_ppe = entry.get("ppe", false)
	item.is_stowed = entry.get("stow", false)
	item.holdable = entry.get("hold", false)
	item.grip_anchor = entry.get("anchor", DEFAULT_ANCHOR)
	item.aim_direction = entry.get("aim", DEFAULT_AIM)
	item.roll_degrees = entry.get("roll", 0.0)
	item.grip_offset = entry.get("offset", Vector3.ZERO)
	item.hold_rotation_deg = entry.get("hold_rot", Vector3.ZERO)
	item.step_on_pickup = entry.get("step", &"")
	# PPE and stowed items disappear onto the person; a held tool stays
	# visible in hand.
	item.hide_on_pickup = item.is_ppe or item.is_stowed

	mesh.add_child(item)

	# Mark the collider as interactable without taking it out of the world
	# layer, so the props still behave like solid objects.
	for body in _bodies(mesh):
		body.collision_layer |= 2

	return true


func _bodies(root: Node) -> Array[CollisionObject3D]:
	var out: Array[CollisionObject3D] = []
	if root is CollisionObject3D:
		out.append(root)
	for child in root.get_children():
		out.append_array(_bodies(child))
	return out
