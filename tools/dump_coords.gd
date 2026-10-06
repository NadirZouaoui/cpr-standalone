extends Node
## Throwaway: prints imported world positions so the Blender -> Godot axis
## mapping can be measured rather than assumed.

const MAIN := preload("res://main.tscn")


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	await get_tree().process_frame

	var room: Node = main.get_node_or_null("ControlRoom")
	print("ControlRoom transform: ", (room as Node3D).global_transform)
	for name in ["Rescue kit bag", "Hook", "Gloves", "Fire blanket", "Burns_dressings",
		"Flashlight", "Isolate here"]:
		var mesh: Node3D = room.get_node_or_null(NodePath(name))
		if mesh != null:
			print("%-18s %s" % [name, mesh.global_position])

	var door: Node3D = room.get_node_or_null("Control room/LowPolyDoor 03_002")
	print("door               ", door.global_position if door != null else "not found")
	var player: Node3D = main.get_node_or_null("Player")
	print("player             ", player.global_position)

	get_tree().quit(0)
