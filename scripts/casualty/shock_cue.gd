class_name ShockCue
extends Node
## Everything about the incident at the breaker that is *not* clinical state:
## whether the worker is in the room yet, and the arc at the panel.
##
## WHAT CHANGED AND WHY. This node used to play the LVR_* clips itself, on its
## own timer, on the same AnimationPlayer that Casualty was already driving.
## Both started the idle; both started the shock, 0.25 s apart; the second
## call restarted a lead-in the first had already begun. Neither knew the
## other had fired, so `_fired` and `state` disagreed for the rest of the run.
##
## Casualty now owns the AnimationPlayer outright and this owns the staging.
## The two are joined by `Events.casualty_state_changed` rather than by one
## calling into the other, which means the arc is tied to the worker's actual
## condition instead of to a timer that happens to agree with it. The sparks
## stop on the frame the state becomes COLLAPSING - the frame the hook lands -
## with nothing needing to remember to call release().
##
## Every node reference here is a NodePath rather than a typed node export.
## Exported Node references need an explicit `node_paths=PackedStringArray(...)`
## on the node line, which the editor writes but a hand-authored .tscn does
## not. NodePaths need no such thing, so this scene can be edited as text.

## The worker's clinical state machine. Asked to start the shock when a clue
## triggers this cue; otherwise only listened to.
@export var casualty_path: NodePath = ^"../Casualty"

## Sparks, flicker and noise at the panel.
@export var arc_fx_path: NodePath

## The imported armature. Hidden while the exercise is still in its
## pre-exercise phases, so the room is genuinely empty behind the kit check
## rather than containing a man standing motionless at a live panel.
@export var rig_path: NodePath = ^"../ControlRoom/Armature"

@export_group("Trigger")
## Hold the reveal until the exercise proper starts. The kit check runs
## first and is untimed, so without this the trainee sees the casualty
## through the quiz.
##
## Casualty has the matching flag and owns the timing of the shock itself;
## this one only decides when the body appears.
@export var wait_for_exercise_start: bool = true

## Hand the reveal to someone else entirely. With this set, the rig stays
## hidden and no phase is watched: the room contains no worker until another
## node calls arm(). BreakerPanel is that node - the trainee has to name the
## hazard, open the board and sign the isolation point before the man who is
## about to be electrocuted is allowed to walk into the scene.
##
## Takes precedence over `wait_for_exercise_start`, which only knows about
## the preamble boundary and would arm the moment the kit check closed.
@export var armed_externally: bool = false

var _armed: bool = false
var _arc: ArcFx = null
var _rig: Node3D = null
var _casualty: Casualty = null


func _ready() -> void:
	_casualty = get_node_or_null(casualty_path) as Casualty
	if _casualty == null:
		_casualty = get_tree().get_first_node_in_group(&"casualty") as Casualty
	if _casualty == null:
		push_warning("ShockCue: no Casualty at '%s'; the cue can stage but not trigger"
			% casualty_path)

	_arc = get_node_or_null(arc_fx_path) as ArcFx
	if _arc == null and not arc_fx_path.is_empty():
		push_warning("ShockCue: arc_fx_path does not point at an ArcFx node")

	_rig = get_node_or_null(rig_path) as Node3D
	if _rig == null and not rig_path.is_empty():
		push_warning("ShockCue: rig_path does not point at a Node3D")

	Events.casualty_state_changed.connect(_on_casualty_state_changed)

	# Someone else owns the reveal: stay empty and wait to be told.
	if armed_externally:
		_set_rig_visible(false)
		_warmup_rig()
		return

	if wait_for_exercise_start and SimState.is_preamble():
		_set_rig_visible(false)
		_warmup_rig()
		Events.phase_changed.connect(_on_phase_changed)
		return

	arm()


## Draw the hidden rig once, out of sight, so its first real appearance does
## not hitch. The web export compiles a material's shaders (and the skinning
## pass) the first time it is drawn, which stalled the frame the worker walked
## in. Showing him for a frame in place would flash a man into the empty room -
## the kit brief only dims the scene, and that frame is the slow one - so he is
## drawn far below the floor instead, with culling defeated so the draw call
## really happens. The floor hides him; the GPU still has to build the shaders.
func _warmup_rig() -> void:
	if _rig == null:
		return
	var home := _rig.global_transform
	var meshes := _rig.find_children("*", "MeshInstance3D", true, false)
	var saved_aabbs: Array[AABB] = []
	for m: MeshInstance3D in meshes:
		saved_aabbs.append(m.custom_aabb)
		m.custom_aabb = AABB(Vector3(-1e4, -1e4, -1e4), Vector3(2e4, 2e4, 2e4))
	_rig.global_position.y -= 20.0
	_set_rig_visible(true)
	await RenderingServer.frame_post_draw
	for i in meshes.size():
		if is_instance_valid(meshes[i]):
			(meshes[i] as MeshInstance3D).custom_aabb = saved_aabbs[i]
	if not is_instance_valid(_rig):
		return
	_rig.global_transform = home
	# arm() may have landed while this was waiting; it owns visibility then.
	_set_rig_visible(_armed)


## Put the casualty in the room. Split out of _ready so the pre-exercise
## phases can hold the scene back without this node needing to know what
## those phases are for.
func arm() -> void:
	if _armed:
		return
	_armed = true
	_set_rig_visible(true)


func _on_phase_changed(_previous: int, _current: int) -> void:
	if SimState.is_preamble():
		return
	Events.phase_changed.disconnect(_on_phase_changed)
	arm()


func _set_rig_visible(value: bool) -> void:
	if _rig != null:
		_rig.visible = value


# =============================================================================
# Arc
# =============================================================================
## The arc is a function of the worker's state, not of the clock. IN_CONTACT
## is the only state it burns in; everything downstream of the rescue kills
## it, including the states reached by a debug jump straight to DOWN.
##
## Both calls are idempotent, so a state that is re-entered cannot restack
## the burst or double-fade the buzz.
func _on_casualty_state_changed(state: int) -> void:
	if _arc == null:
		return
	if state == Casualty.State.IN_CONTACT:
		_arc.start()
	else:
		_arc.stop()


# =============================================================================
# External hooks
# =============================================================================
## Start the incident. This is the seam the clue plugs into once the trainee
## interaction that reveals the hazard has been designed: have it call
## trigger() and nothing else here needs to change.
##
## Idempotent by way of Casualty.begin_shock(), which ignores a second call
## while already IN_CONTACT.
func trigger() -> void:
	if _casualty == null:
		push_warning("ShockCue: nothing to trigger")
		return
	if not _armed:
		arm()
	_casualty.begin_shock()


## Contact is broken. Normally unnecessary - the state change does this - but
## kept for anything that kills the arc without moving the casualty on, such
## as isolating the supply at the board before the rescue.
func release() -> void:
	if _arc != null:
		_arc.stop()


## Lets a reset or a retry re-stage the cue. Puts the casualty back out of
## the room if the exercise has been wound back to its preamble, so a soft
## retry replays the same reveal a fresh run gets.
func reset() -> void:
	_armed = false
	if _arc != null:
		_arc.stop()

	if armed_externally:
		_set_rig_visible(false)
		return

	if wait_for_exercise_start and SimState.is_preamble():
		_set_rig_visible(false)
		if not Events.phase_changed.is_connected(_on_phase_changed):
			Events.phase_changed.connect(_on_phase_changed)
	else:
		arm()
