@tool
extends EditorScenePostImport
## Entry point for LVR CPR.blend post-import fixes.
##
## Each step lives in its own file and exposes a static apply(scene). Add new
## steps here rather than growing one script - these run on every reimport, so
## anything the .blend cannot express through glTF gets rebuilt automatically
## and the .blend stays the single source of truth.
##
## Order matters in one place: TrimAnimations runs first, so the mesh steps are
## not walking a scene that still carries three full-length working actions.
## Everything after it is independent.

const TrimAnimations := preload("res://scripts/import/trim_animations.gd")
const FixMirroredMeshes := preload("res://scripts/import/fix_mirrored_meshes.gd")
const AlphaFadeMaterials := preload("res://scripts/import/alpha_fade_materials.gd")
const CasualtyClothingShading := preload("res://scripts/import/casualty_clothing_shading.gd")


func _post_import(scene: Node) -> Object:
	TrimAnimations.apply(scene)
	FixMirroredMeshes.apply(scene)
	AlphaFadeMaterials.apply(scene)
	# After FixMirroredMeshes: both rebuild meshes, and this one must smooth the
	# normals of the meshes that step leaves behind, not the ones it replaces.
	CasualtyClothingShading.apply(scene)
	return scene
