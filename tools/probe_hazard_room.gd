extends SceneTree
## Evidence probe for the PROVISIONAL hazard content authored in Task 4.
##
##   & "C:\Program Files\Godot\Godot_v4.7.2-stable_win64_console.exe" \
##       --headless --path <project> --script res://tools/probe_hazard_room.gd
##
## The client did not supply the hazard list; it was invented from the room's
## contents (docs/OVERNIGHT_PLAN.md risk 3). No entry may be offered to a
## trainee as an assessment until it has been checked against what is actually
## modelled, so this enumerates every mesh in the imported room and then
## reports, per keyword, whether the thing an entry names exists at all.
##
## Headless on purpose, and it renders nothing: Godot's headless display
## server has no rendering device, so `get_viewport().get_texture()` comes
## back empty and a screenshot is not available on this path. The mesh
## inventory is the stronger evidence anyway - "is it in the room" is a fact,
## not something to squint at in a PNG.
##
## Note it instantiates the .blend WITHOUT adding it to the tree, so global
## transforms are unavailable here (they read as identity and Godot logs an
## error for each one). Presence, not position, is what this answers.

const ROOM := "res://LVR CPR.blend"

## What each authored hazard entry claims is in the room. Keyword match
## against the mesh names, case-insensitive.
const CLAIMS := {
	"switchboard / breaker board": ["breaker"],
	"point of isolation, marked": ["isolate", "label", "tag", "lock"],
	"the worker": ["boots1", "casualty"],
	"metal hand tools": ["wrench", "plier", "hammer", "sd1", "sd2", "spanner"],
	"lighting fed from the board": ["light", "lamp", "fluor", "strip"],
	"torch": ["flashlight", "torch"],
	"ladder": ["ladder"],
	"overhead pipework": ["pipe"],
	"water / wet floor": ["water", "wet", "puddle", "spill", "drain"],
	"busbars": ["busbar"],
	"barrier / insulating mat": ["mat", "barrier", "cone", "tape", "screen"],
	"rodent damage / wiring": ["rodent", "rat", "mouse", "cable", "wiring", "chew"],
}


func _init() -> void:
	var packed: PackedScene = load(ROOM)
	if packed == null:
		printerr("probe_hazard_room: could not load %s" % ROOM)
		quit(1)
		return
	var room: Node = packed.instantiate()

	var names: Array[String] = []
	_walk(room, names)

	print("=== %d meshes in the room ===" % names.size())
	for n in names:
		print("  %s" % n)

	print("\n=== what each hazard entry claims, against the inventory ===")
	for claim in CLAIMS:
		var hits: Array[String] = []
		for needle in CLAIMS[claim]:
			for n in names:
				if n.to_lower().contains(needle) and not hits.has(n):
					hits.append(n)
		print("  %-30s %s" % [
			claim,
			("PRESENT  " + ", ".join(hits)) if not hits.is_empty() else "ABSENT"])

	room.free()
	quit(0)


func _walk(n: Node, out: Array[String]) -> void:
	if n is MeshInstance3D:
		out.append(String(n.name))
	for c in n.get_children():
		_walk(c, out)
