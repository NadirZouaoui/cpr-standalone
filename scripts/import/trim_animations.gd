@tool
extends RefCounted
## Drops the .blend's working actions from the imported scene and declares the
## loop modes of the four that ship.
##
## WHY. The .blend holds ten actions. Five are the deliverables; the rest are
## the pipeline:
##
##   LVR_Master        219 f  the uncut bake the four motion clips are cut from
##   Shock_Retargeted  219 f  the retarget source, and the source of truth
##   Shock             215 f  the original Mixamo-side action
##   TGT_Hand*Action     3 f  IK target helpers, on two Empties
##
## All of them are kept in the .blend deliberately - lvr_rebuild.py needs
## Shock_Retargeted to recut the clips, and clearing its fake user would lose
## it. None of them is wanted at runtime.
##
## WHAT ACTUALLY REACHES THE IMPORTER. Two gates, and both have to be passed
## for a clip to arrive - this was measured on 3 Sep 2026 by exporting the
## .blend through Blender's own glTF exporter with Godot's import parameters
## and reading the animation list out of the .gltf, not inferred.
##
##   1. BLENDER. The exporter runs in ACTIONS mode (blender/animation/
##      group_tracks in LVR CPR.blend.import). In that mode it writes the
##      armature's ACTIVE action plus every action sitting on an NLA strip -
##      and nothing else. The four shipping clips are each stashed on their own
##      NLA track on the Armature OBJECT's animation data; LVR_Master and
##      Shock_Retargeted are stashed nowhere and so never leave Blender at all.
##      Shock is on the armature DATA's animation data rather than the object's,
##      which is likewise not a place the exporter looks. Authoring a new clip
##      therefore means authoring an action AND stashing it as an NLA strip; an
##      unstashed action is silently absent from the export.
##
##   2. HERE. What does survive the exporter still has to be named in CLIPS
##      below, or it is removed from the imported scene. TGT_Hand*Action do
##      reach the .gltf (one translation channel each) and are dropped here.
##
## The scene importer has no per-action filter, so the second gate lives in
## this script. The .blend stays authoritative and the web build stays lean.
##
## LOOP MODES. glTF has no way to say "this clip loops", so the alternative is
## every caller mutating the imported Animation at runtime - a write to a
## shared resource that each new caller has to remember to repeat. Declaring it
## once at import is the whole story instead, and it means a clip's loop
## behaviour is a property of the clip rather than of whoever played it last.
##
## NAMES. Depending on how the exporter groups tracks, actions can arrive
## prefixed with the object that held them ("Armature|LVR_Fall"). The prefix is
## stripped so that the names in the inspector are the names in the design doc.

## Clip name -> does it loop. Anything not listed is removed from the export.
##
## Keep this in step with the exports on Casualty: these are the same four
## names, and a rename in Blender has to land in both places.
const CLIPS := {
	"LVR_Fiddle": true,      ## Idle at the breaker, held until the shock.
	"LVR_ShockEnter": false, ## One-shot lead-in.
	"LVR_ShockHold": true,   ## Tetany, looped until the rescue.
	"LVR_Fall": false,       ## Hip-first collapse. Ends on the floor pose.
	"LVR_Recovery": false,   ## Two-frame hold: the recovery position, posed.
}


static func apply(scene: Node) -> void:
	var players: Array[AnimationPlayer] = _players(scene)
	if players.is_empty():
		# Not fatal - the room can be reimported without the character while
		# the animation is being reworked.
		push_warning("trim_animations: no AnimationPlayer in the imported scene")
		return

	var kept: Dictionary = {}
	var dropped: PackedStringArray = []

	for player in players:
		_trim(player, kept, dropped)

	for wanted in CLIPS:
		if not kept.has(wanted):
			push_warning("trim_animations: '%s' is not in the .blend export" % wanted)

	if dropped.size() > 0:
		print("trim_animations: kept %d clip(s), dropped %d: %s"
			% [kept.size(), dropped.size(), ", ".join(dropped)])


static func _trim(player: AnimationPlayer, kept: Dictionary, dropped: PackedStringArray) -> void:
	for library_name in player.get_animation_library_list():
		var library: AnimationLibrary = player.get_animation_library(library_name)
		if library == null:
			continue

		# Snapshot: the list is mutated inside the loop. AnimationLibrary
		# hands back Array[StringName] here, unlike AnimationMixer, which
		# hands back a PackedStringArray - so both are typed explicitly.
		var names: Array[StringName] = library.get_animation_list()
		var remove: Array[StringName] = []

		for name in names:
			var bare: String = _bare(String(name))
			if not CLIPS.has(bare):
				remove.append(name)
				dropped.append(bare)
				continue

			var anim: Animation = library.get_animation(name)
			if anim != null:
				anim.loop_mode = (Animation.LOOP_LINEAR if CLIPS[bare]
					else Animation.LOOP_NONE)

			if name != bare and not library.has_animation(bare):
				library.rename_animation(name, bare)
			kept[bare] = true

		for name in remove:
			library.remove_animation(name)

	# An autoplay pointing at a removed clip is a hard error on instantiation,
	# not a warning, so it has to be cleared rather than left to fail loudly.
	# Nothing autoplays here by design: ShockCue and Casualty decide when the
	# worker starts moving, and that is after the kit check.
	if player.autoplay != "" and not player.has_animation(player.autoplay):
		player.autoplay = ""


## "Armature|LVR_Fall" and "LVR_Fall" are the same clip. Match on the tail.
static func _bare(name: String) -> String:
	var cut: int = name.rfind("|")
	return name.substr(cut + 1) if cut >= 0 else name


static func _players(node: Node) -> Array[AnimationPlayer]:
	var out: Array[AnimationPlayer] = []
	var stack: Array[Node] = [node]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is AnimationPlayer:
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out
