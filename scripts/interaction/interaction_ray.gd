class_name InteractionRay
extends RayCast3D
## Finds the Interactable under the reticle and routes activation to it.
##
## Split out of the player so movement code and interaction code stay
## independent - and so the scripted CPR camera can borrow the same ray
## without dragging a CharacterBody3D along.

## How far up the parent chain to look for an Interactable from a collider.
const SEARCH_DEPTH := 6

@export var active: bool = true

var current: Interactable = null

## Last text put on the bus. The prompt has to be re-read every frame - a
## stateful interactable changes its own text without the focus changing, and
## the casualty's changes four times over the course of the exercise - but
## re-emitting an unchanged string 60 times a second made every listener
## rebuild its label for nothing. Compare, then emit.
var _prompt: String = ""

## Press this in game to dump what the ray is actually looking at, from
## wherever the trainee happens to be standing. Reading the running game
## from outside is not possible and reproducing a position by description
## has already cost several wrong guesses, so the game reports on itself.
@export var probe_key: Key = KEY_F9


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == probe_key:
		_probe()


## Appends, so several presses from several spots build a picture in one
## file rather than each one erasing the last.
func _probe() -> void:
	var out: PackedStringArray = []
	out.append("===== probe %.1fs =====" % (Time.get_ticks_msec() / 1000.0))
	out.append("eye      %s" % global_position)
	out.append("forward  %s" % (-global_transform.basis.z))
	out.append("reach    %.2f m   active=%s enabled=%s mask=%d"
		% [target_position.length(), active, enabled, collision_mask])

	# Everything along the ray, not just the first thing - the point is to
	# see what is getting in the way, if anything is.
	var from := global_position
	var to := global_position + (global_transform.basis * target_position)
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	var found := false
	for i in 8:
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.collision_mask = collision_mask
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break
		found = true
		var body := hit["collider"] as CollisionObject3D
		out.append("  [%d] %-38s layer=%-3d dist %.3f"
			% [i, _chain(body), body.collision_layer if body != null else -1,
			from.distance_to(hit["position"])])
		out.append("       interactables here: %s" % _names(body))
		exclude.append(hit["rid"])
	if not found:
		out.append("  ray hits NOTHING - past the end of its reach")

	out.append("resolved %s" % (current.id if current != null else &"NONE"))
	if current != null:
		out.append("  can_interact=%s prompt='%s'"
			% [current.can_interact(), current.prompt_text()])

	# Where the panel is from here, whether or not the ray found it.
	var door := get_tree().current_scene.get_node_or_null(
		"ControlRoom/Breaker_002"
	) as Node3D
	if door != null:
		var centre := door.global_transform * (
			(door as MeshInstance3D).mesh.get_aabb().get_center()
			if door is MeshInstance3D and (door as MeshInstance3D).mesh != null
			else Vector3.ZERO
		)
		var to_door := centre - global_position
		out.append("door centre %s" % centre)
		out.append("  distance %.3f m, off-axis %.1f deg, hitbox=%s"
			% [to_door.length(),
			rad_to_deg((-global_transform.basis.z).angle_to(to_door)),
			door.get_node_or_null("PanelHitbox") != null])

	var text := "\n".join(out) + "\n\n"
	var path := "user://interaction_probe.txt"
	var f := FileAccess.open(path, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(path, FileAccess.WRITE)
	else:
		f.seek_end()
	f.store_string(text)
	f.close()
	print(text)
	Events.center_message_requested.emit("Probe written", Tokens.SCENE_TEXT, 1.5)


func _chain(node: Node) -> String:
	if node == null:
		return "<null>"
	var parts: PackedStringArray = []
	var walk := node
	for i in 3:
		if walk == null:
			break
		parts.append(String(walk.name))
		walk = walk.get_parent()
	return "/".join(parts)


func _names(node: Node) -> String:
	if node == null:
		return "-"
	var parts: PackedStringArray = []
	var walk := node
	for _i in SEARCH_DEPTH:
		if walk == null:
			break
		for candidate in _interactables_at(walk):
			parts.append("%s(can=%s)" % [candidate.id, candidate.can_interact()])
		walk = walk.get_parent()
	return "-" if parts.is_empty() else ", ".join(parts)


func _physics_process(_delta: float) -> void:
	if not active:
		_set_current(null)
		return
	_set_current(_resolve(get_collider() if is_colliding() else null))


func _resolve(collider: Object) -> Interactable:
	if collider == null or not (collider is Node):
		return null

	# Colliders usually sit under the mesh, with the Interactable as a
	# sibling or a child of the same body. Check children first, then walk up.
	#
	# A mesh can carry more than one: the bench props are a kit item to name
	# during the preamble and a tool to pick up after it. An available one
	# always wins over an unavailable one, so which affordance the trainee
	# gets is decided by the phase rather than by the order two unrelated
	# binder nodes happened to run in.
	var node := collider as Node
	var fallback: Interactable = null

	for _i in SEARCH_DEPTH:
		if node == null:
			break
		for candidate in _interactables_at(node):
			if candidate.can_interact():
				return candidate
			if fallback == null:
				fallback = candidate
		node = node.get_parent()

	return fallback


## The node itself, then its direct children. Deeper than that is the next
## level's job, so the walk stays breadth-first up the parent chain.
func _interactables_at(node: Node) -> Array[Interactable]:
	var out: Array[Interactable] = []
	if node is Interactable:
		out.append(node)
	for child in node.get_children():
		if child is Interactable:
			out.append(child)
	return out


func _set_current(next: Interactable) -> void:
	if next == current:
		if current != null:
			_emit_prompt(current.prompt_text())
		return

	if current != null:
		current.unhighlight()

	current = next if (next != null and next.can_interact()) else null

	if current != null:
		current.highlight()
		_emit_prompt(current.prompt_text())
	else:
		_emit_prompt("")
	Events.focus_changed.emit(current)


func _emit_prompt(text: String) -> void:
	if text == _prompt:
		return
	_prompt = text
	Events.prompt_requested.emit(text)


## Called by the player on the interact action.
func activate(from_position: Vector3) -> bool:
	if current == null:
		return false
	current.interact(from_position)
	return true


func clear() -> void:
	_set_current(null)
