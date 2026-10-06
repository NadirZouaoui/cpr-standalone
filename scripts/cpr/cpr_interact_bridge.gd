class_name CprInteractBridge
extends Node

## Routes crosshair hover/interact to CPR ghost targets and cabinet-style
## objects, replacing Godot's built-in Area3D mouse picking everywhere in the
## CPR phase.
##
## OWNERSHIP: Agent G · Input bridge. See CPR_CONTRACT.md section 7 and
## CPR_AGENTS.md's Agent G brief.
##
## THE PROBLEM (CPR_CONTRACT.md §4.0): the game runs Input.MOUSE_MODE_CAPTURED
## with no visible cursor, so Godot's own Area3D camera picking
## (mouse_entered/exited/input_event) fires at a stale screen position instead
## of the crosshair. It is especially useless during an anchored CPR state:
## CprCameraRig.move_to() freezes Player (Player.is_frozen = true), and
## Player._set_frozen() also flips InteractionRay.active to false and clears
## it — so nothing routed through the normal Interactable path runs at all
## while the camera holds an anchor.
##
## THE FIX: reuse the project's existing crosshair interactor — Player's own
## InteractionRay (scripts/interaction/interaction_ray.gd), reached via the
## "player" group Player already adds itself to in its own _ready(). That
## node wraps a RayCast3D whose built-in `enabled` property nothing ever
## touches (only the script's own unrelated `active` export gates its
## Interactable resolution) — so `get_collider()`/`is_colliding()` stay live
## every physics frame no matter what Player or the CPR camera are doing.
## This bridge reads that one already-running raycast instead of building a
## second, parallel one, and reuses the exact same raycast length (1.6 m)
## and collision_mask (7, i.e. layers World/Interactable/Casualty) that
## scenes/player/player.tscn already authors on it.
##
## Registered targets are anything shaped like GhostTarget: a `mesh`
## (MeshInstance3D) plus `set_hovered(bool)` and `activate()` methods.
## GhostTarget itself self-registers (see ghost_target.gd) whenever it is
## built with `build_area = false`, which is now the default — so
## pad_station.gd and the AED_DEPLOYED ghost in aed_station.gd need no
## changes to pick this up. aed_station.gd's cabinet (never a GhostTarget)
## registers a small adapter object built to the same shape.
##
## Colliders are built here at runtime from each target's mesh AABB, padded
## ~10 mm, as a StaticBody3D on collision_layer 2 ("Interactable" per
## project.godot's layer_names) with collision_mask 0 — matching the
## StaticBody3D convention every other runtime-built hitbox in this project
## already uses (see isolation_sign_anchor.gd), and landing on the same layer
## InteractionRay's collision_mask (7) already includes. Never authored into
## main.tscn.
##
## Exposes a static accessor, following CprStation._current's pattern, so
## other CPR scripts can register without holding a node reference.

## Collider padding, metres — matches GhostTarget's own COLLIDER_PAD_METRES.
const COLLIDER_PAD_METRES := 0.010

## First instance to reach _ready() wins — CprStation._current's pattern.
static var _current: CprInteractBridge = null

var _ray: InteractionRay = null

## target (Object, duck-typed: mesh / set_hovered / activate) -> StaticBody3D
var _bodies_by_target: Dictionary = {}
## StaticBody3D -> target, for the reverse lookup on a raycast hit.
var _targets_by_body: Dictionary = {}

var _hovered: Object = null
## Last text this bridge put on the prompt chip. InteractionRay writes to the
## same chip and clears it to "" whenever it resolves no Interactable — which
## is every time the crosshair moves onto a ghost — so the bridge re-asserts
## its own line whenever the ray's focus changes underneath it.
var _prompt_text: String = ""
var _last_ray_current: Object = null


func _ready() -> void:
	_current = self
	# Playtest fix (see _set_hovered_target): InteractionRay also emits
	# focus_changed from its own _physics_process, and it emits null whenever
	# it resolves no Interactable — which is every frame the crosshair is on a
	# CPR ghost, since ghosts are not Interactables. Running last means this
	# node's emit is the one the HUD sees, rather than the result depending on
	# tree order.
	process_physics_priority = 10
	# Player (and its InteractionRay) may not have finished entering the
	# tree relative to this node yet — same call_deferred caution every
	# other CPR binder takes.
	call_deferred("_build")


func _exit_tree() -> void:
	if _current == self:
		_current = null
	for body in _targets_by_body.keys():
		if is_instance_valid(body):
			body.queue_free()
	_bodies_by_target.clear()
	_targets_by_body.clear()
	_hovered = null


static func get_current() -> CprInteractBridge:
	return _current


## Register a clickable target. `target` must expose:
##   var mesh: MeshInstance3D
##   func set_hovered(is_hovered: bool) -> void
##   func activate() -> void
## GhostTarget already satisfies this shape (see ghost_target.gd). Anything
## else — e.g. aed_station.gd's cabinet adapter — just needs to match it.
## Safe to call again for an already-registered target (no-op).
static func register(target: Object) -> void:
	if _current != null:
		_current._register(target)


## Drop a target and free its collider. Safe to call on an unregistered
## target.
static func unregister(target: Object) -> void:
	if _current != null:
		_current._unregister(target)


## Enable or disable a registered target's collider without rebuilding it —
## the runtime equivalent of the old Area3D.input_ray_pickable toggle.
static func set_enabled(target: Object, enabled: bool) -> void:
	if _current != null:
		_current._set_enabled(target, enabled)


func _build() -> void:
	var player := get_tree().get_first_node_in_group(&"player") as Player
	if player == null:
		push_error("CprInteractBridge: no node in group 'player' found; hover/click will not work.")
		return
	_ray = player.interaction_ray
	if _ray == null:
		push_error("CprInteractBridge: Player has no InteractionRay assigned; hover/click will not work.")


## The static posed body, and the group the live skinned body's root carries.
## Both count as "the casualty" for crosshair purposes.
const CASUALTY_MESH_NAME := "Casualty_CPR_Posed"
const CASUALTY_GROUP := &"casualty"


## Is the crosshair on the casualty?
##
## The one test every on-body beat should use. It accepts EITHER of the two
## bodies the exercise puts on the floor: the static posed mesh
## (`Casualty_CPR_Posed`) and the live skinned body, which is whatever collider
## hangs under the node in the `casualty` group.
##
## Accepting both is not belt-and-braces, it is the bug fix. The posed mesh is
## hidden for the whole first half of the CPR phase — the reorder of 3 Sep put
## BREATHING_CHECK and COMPRESSIONS_1 before EXPOSE_CHEST, so the clothed
## skinned body is what is on screen — and its collider is a single coarse
## ConvexPolygonShape3D whose surface the breathing-check anchor's own ray
## misses, while the accurate skinned collider under it is hit. Asking only for
## the posed mesh therefore returned false at the authored `Anchor_Head` pose
## with the crosshair squarely on the casualty, and both the breathing check and
## every compression rep refused with "Aim at the casualty's mouth/chest".
## Measured in game on 4 Sep 2026; see docs/PLAYTEST_2026-09-04_pass3.md.
static func crosshair_on_casualty(depth: int = 6) -> bool:
	return crosshair_on_node_named(CASUALTY_MESH_NAME, depth, CASUALTY_GROUP)


## Is the crosshair on a node named `node_name` (or on a descendant of one)?
##
## `group` is an OR, not an AND: a collider whose chain carries either the name
## or the group counts. Pass &"" to test the name alone.
##
## Walks every collider along the ray, nearest first, for the same reason
## _first_registered_target() does — once the pad ghosts are up they sit in
## front of the casualty, and aiming at the chest must still read as "on the
## casualty".
static func crosshair_on_node_named(
	node_name: String, depth: int = 6, group: StringName = &""
) -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return true
	var player := tree.get_first_node_in_group(&"player") as Player
	if player == null or player.interaction_ray == null:
		# Cannot tell — never block the trainee on a lookup failure.
		return true
	var ray := player.interaction_ray
	var space := ray.get_world_3d().direct_space_state
	var from := ray.global_position
	var to := from + (ray.global_transform.basis * ray.target_position)
	var exclude: Array[RID] = []

	for _i in depth:
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = ray.collision_mask
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return false
		var walk: Node = hit.get("collider") as Node
		for _j in depth:
			if walk == null:
				break
			if String(walk.name) == node_name:
				return true
			if group != &"" and walk.is_in_group(group):
				return true
			walk = walk.get_parent()
		exclude.append(hit["rid"])

	return false


func _register(target: Object) -> void:
	if target == null:
		push_error("CprInteractBridge: attempted to register a null target.")
		return
	if _bodies_by_target.has(target):
		return

	var mesh: MeshInstance3D = target.mesh
	if mesh == null:
		push_error("CprInteractBridge: target has no mesh to build a collider from.")
		return

	var shape := CollisionShape3D.new()
	# Playtest fix: the padded-AABB box was hopeless for the pad sites. Their
	# meshes carry the electrode *and its lead cable*, so the AABB spans the
	# whole run of the cable — measured 9.6 x 2.1 x 4.0 local units on
	# PadSite_Wrong_01, i.e. a ~0.6 x 0.13 x 0.25 m world box centred ~0.28 m
	# away from where the pad actually renders. All five boxes overlapped each
	# other and none of them sat on its own pad, so the crosshair could never
	# resolve the site the trainee was looking at.
	#
	# A trimesh built straight off the mesh resource is exact by construction
	# and costs nothing here (five small meshes, built once). Concave shapes
	# are static-only, which is exactly what these are. Fall back to the old
	# padded box if the mesh has no surfaces to build from.
	var concave: ConcavePolygonShape3D = null
	if mesh.mesh != null and mesh.mesh.get_surface_count() > 0:
		concave = mesh.mesh.create_trimesh_shape()
	if concave != null and not concave.get_faces().is_empty():
		shape.shape = concave
	else:
		var aabb: AABB = mesh.get_aabb()
		var box := BoxShape3D.new()
		box.size = aabb.size + Vector3.ONE * (COLLIDER_PAD_METRES * 2.0)
		shape.shape = box
		shape.position = aabb.get_center()

	var body := StaticBody3D.new()
	# Deliberately NOT "<mesh.name>_BridgeBody": every station that resolves its
	# targets with CprGhost.find_nodes_with_prefix() (pad_station.gd's
	# "PadSite_" scan is the case that actually hit this) walks the whole
	# subtree, and a mesh-name-prefixed child collider matches that same
	# prefix and gets "found" as a bogus MeshInstance3D candidate. A fixed
	# name that can never start with a station's own prefix sidesteps that
	# regardless of build order; uniqueness isn't needed since this is a
	# child of `mesh`, not a sibling shared across meshes.
	body.name = "BridgeBody"
	body.collision_layer = 2   # "Interactable", per project.godot layer_names
	body.collision_mask = 0
	body.add_child(shape)
	mesh.add_child(body)

	_bodies_by_target[target] = body
	_targets_by_body[body] = target


func _unregister(target: Object) -> void:
	if _hovered == target:
		_clear_hover()
	if not _bodies_by_target.has(target):
		return
	var body: StaticBody3D = _bodies_by_target[target]
	_targets_by_body.erase(body)
	if is_instance_valid(body):
		body.queue_free()
	_bodies_by_target.erase(target)


func _set_enabled(target: Object, enabled: bool) -> void:
	if not _bodies_by_target.has(target):
		return
	var body: StaticBody3D = _bodies_by_target[target]
	if is_instance_valid(body):
		body.collision_layer = 2 if enabled else 0
	if not enabled and _hovered == target:
		_clear_hover()


## How many colliders deep to look for a registered target before giving up.
## Matches InteractionRay._probe()'s own 8-hit walk.
const MAX_RAY_HITS := 8


func _physics_process(_delta: float) -> void:
	if _ray == null:
		return
	if Events.is_ui_blocking():
		_clear_hover()
		return
	_set_hovered_target(_first_registered_target())

	# The ray just changed what it thinks is focused, which means it also just
	# overwrote the prompt chip. Put ours back.
	if _ray.current != _last_ray_current:
		_last_ray_current = _ray.current
		if _hovered != null:
			_prompt_text = ""
			_emit_prompt()


## Walks every collider along the InteractionRay, nearest first, and returns
## the first one that belongs to a registered target.
##
## Playtest fix: reading `_ray.get_collider()` — the single nearest hit — meant
## the pad sites were unreachable. Casualty_CPR_Posed carries a
## ConvexPolygonShape3D hull of the whole body on collision layer 1, which
## InteractionRay's mask (7) includes, and the pads are conformed onto that
## body's skin 1.5 mm proud. The hull is the nearest hit essentially always, so
## the pads' own colliders were never the collider the bridge saw.
##
## Looking *past* non-target geometry is safe here because the ray is only
## 1.6 m long and every registered target is something the trainee is by
## definition standing over: there is no "click the pad through a wall" case
## at this reach, and the alternative (re-layering the casualty hull) would
## reach outside the CPR file set into the drag/extraction code.
func _first_registered_target() -> Object:
	var space := _ray.get_world_3d().direct_space_state
	var from := _ray.global_position
	var to := from + (_ray.global_transform.basis * _ray.target_position)
	var exclude: Array[RID] = []

	for _i in MAX_RAY_HITS:
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = _ray.collision_mask
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return null
		var body: Object = hit.get("collider")
		if _targets_by_body.has(body):
			return _targets_by_body[body]
		exclude.append(hit["rid"])

	return null


func _set_hovered_target(target: Object) -> void:
	if target == _hovered:
		return
	if _hovered != null and is_instance_valid(_hovered):
		_hovered.set_hovered(false)
	_hovered = target
	if _hovered != null:
		_hovered.set_hovered(true)
	_emit_focus()
	_emit_prompt()


## Playtest fix: the crosshair stayed white over every CPR target, while it
## turns Tokens.ATTENTION over ordinary props. HUD colours the reticle off
## Events.focus_changed, which only InteractionRay ever emitted — and it emits
## null for a CPR ghost, because a ghost is deliberately not an Interactable
## (CPR_CONTRACT.md §4.0 keeps the whole phase off that path).
##
## The signal is typed `focus_changed(interactable: Node)` and hud.gd only
## tests it against null, so the target's own mesh is passed: a real Node,
## and the most meaningful thing to name as "what the crosshair is on".
func _emit_focus() -> void:
	if _hovered == null:
		Events.focus_changed.emit(null)
		return
	var mesh: MeshInstance3D = _hovered.mesh
	Events.focus_changed.emit(mesh)


## Hover tooltip for CPR targets, on the same HUD chip ordinary interactables
## use. Targets carry their own line in a `prompt` property (GhostTarget has
## one; aed_station.gd's cabinet adapter matches it), read duck-typed so a
## target without one simply shows nothing.
func _emit_prompt() -> void:
	var text := ""
	if _hovered != null:
		var value: Variant = _hovered.get("prompt")
		if value is String:
			text = value
	if text == _prompt_text and _hovered == null:
		return
	_prompt_text = text
	Events.prompt_requested.emit(text)


func _clear_hover() -> void:
	_set_hovered_target(null)


## Called on every unhandled input, mirroring Player._unhandled_input's own
## "interact" action — same action name, so behaviour is consistent whether
## the trainee is free-roaming or the CPR camera has taken over. Deliberately
## does NOT check Player.is_frozen or Input.mouse_mode: freezing Player is
## exactly the condition under which this bridge needs to keep working
## (that's the bug it exists to route around), and CprCameraRig.move_to()
## also switches Input.mouse_mode to MOUSE_MODE_VISIBLE while it holds an
## anchor, so gating on MOUSE_MODE_CAPTURED the way Player does would break
## every anchored-state interaction this bridge is for.
func _unhandled_input(event: InputEvent) -> void:
	if Events.is_ui_blocking():
		return
	if not event.is_action_pressed(&"interact"):
		return
	if _hovered != null:
		_hovered.activate()
