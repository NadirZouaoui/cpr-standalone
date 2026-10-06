@tool
class_name CprRig
extends Node3D

## Camera and UI anchors for the CPR phase, driven off the casualty's chest bone.
##
## Instanced ONCE in main.tscn at the scene root. Every frame it snaps itself onto a
## "chest frame" derived from the skeleton, so the anchors follow the body wherever the
## drag left it — nothing to hand-place in world space.
##
## THE CHEST FRAME
##   origin  = the chest bone's world position
##   -Z      = horizontal direction from the hips toward the head
##   +Y      = world up
##   +X      = the remaining axis (one of the casualty's sides — flip the sign in the
##             offsets below if an anchor lands on the wrong side)
##
## Only bone ORIGINS are read, never bone bases. That is deliberate: the Mixamo armature
## carries scale (0.01, 0.01, -0.01), a negative determinant, and anything derived from
## its basis comes out mirrored. Origins are immune to that.
##
## The AED drop location is NOT here — it is a real duplicate mesh authored in Blender at
## "ControlRoom/AED Defibrilator CPR". aed_station.gd hides it, ghosts it, and places it.
##
## TWEAKING
##   Select this node in main.tscn. Every anchor is a position + rotation pair in the
##   inspector, in metres and degrees, relative to the chest frame. Editor gizmos draw a
##   wireframe view frustum at each camera anchor: the pyramid opens along the direction
##   the trainee will be looking, and the small tick on one edge marks UP, so roll is
##   visible too. Panel markers draw a flat card facing the same way they will billboard.
##
## SHARED / FROZEN (structure) — see CPR_CONTRACT.md section 7. Offsets are yours to edit.

# --- skeleton binding --------------------------------------------------------
@export_group("Binding")
## Direct path first; if it misses, a recursive search for the first Skeleton3D runs.
@export var skeleton_path: NodePath = ^"ControlRoom/Armature/Skeleton3D"
## Bone name candidates, tried in order.
@export var chest_bone_names: PackedStringArray = [
	"mixamorig:Spine2", "mixamorig:Spine1", "mixamorig:Spine", "Spine2", "Spine",
]
@export var head_bone_names: PackedStringArray = [
	"mixamorig:Head", "mixamorig:Neck", "Head", "Neck",
]
@export var hips_bone_names: PackedStringArray = [
	"mixamorig:Hips", "Hips", "mixamorig:Spine",
]
## The injury-survey sites are bound to real bones rather than to chest-frame
## offsets - see the Body pointers group for why. Both sides are resolved and
## the more exposed of the two is used - see _exposed_bone() - which is the one
## the trainee can actually look at once the casualty is on their side.
@export var hand_bone_names: PackedStringArray = [
	"mixamorig:LeftHand", "mixamorig:RightHand", "LeftHand", "RightHand",
]
@export var foot_bone_names: PackedStringArray = [
	"mixamorig:LeftFoot", "mixamorig:RightFoot", "LeftFoot", "RightFoot",
]
## Off = freeze the rig where it is. Useful if the skeleton is mid-animation.
@export var follow_skeleton: bool = true
## Manual yaw override in degrees, used when the hips/head bones can't be resolved.
@export var fallback_yaw_degrees: float = 0.0

# --- editor gizmos -----------------------------------------------------------
@export_group("Editor gizmos")
## Draw wireframe frustums at the camera anchors. Editor only; never runs in game.
@export var show_gizmos: bool = true:
	set(v):
		show_gizmos = v
		_gizmos_dirty = true
## How far the frustum pyramid extends, in metres.
@export_range(0.1, 5.0, 0.05) var gizmo_length: float = 0.9:
	set(v):
		gizmo_length = v
		_gizmos_dirty = true
## Frustum opening angle. Match your camera's FOV to see roughly the real framing.
@export_range(20.0, 110.0, 1.0) var gizmo_fov_deg: float = 70.0:
	set(v):
		gizmo_fov_deg = v
		_gizmos_dirty = true
## Draw the mouse-look clamp as extra rays at the yaw limits.
@export var gizmo_show_look_limits: bool = true:
	set(v):
		gizmo_show_look_limits = v
		_gizmos_dirty = true
@export_range(0.0, 90.0, 1.0) var gizmo_yaw_limit_deg: float = 60.0:
	set(v):
		gizmo_yaw_limit_deg = v
		_gizmos_dirty = true

const GIZMO_COLORS := {
	"Anchor_Head": Color(0.35, 0.85, 1.00),
	"Anchor_HeadClose": Color(0.20, 0.65, 0.95),
	"Anchor_Decision": Color(0.95, 0.55, 0.75),
	"Anchor_Kneel": Color(0.45, 1.00, 0.55),
	"Anchor_PadSide": Color(1.00, 0.75, 0.30),
	"Anchor_Shock": Color(1.00, 0.45, 0.45),
	"Anchor_Rolled": Color(0.80, 0.60, 1.00),
}
const PANEL_COLOR := Color(0.75, 0.70, 1.00)
## Body-pointer anchors.
const POINTER_COLOR := Color(1.00, 0.45, 0.85)

# --- anchors -----------------------------------------------------------------
# Position in metres, rotation in degrees, both relative to the chest frame.

@export_group("Anchor · Breathing check")
## Also the pose the primary-survey pointer sequence is worked from - clicking
## the casualty drops the trainee onto this anchor (casualty_action_menu.gd), so
## it is the first close look at the body the exercise gives and the one every
## early pill is read from.
##
## Pulled back along its own view axis from the (0, 0.50, 0) / (-30, 0, 0) that
## main.tscn carried. Measured at those values: the camera sat 0.58 m from the
## mouth and 0.41 m from the sternum, which put the mouth 71% of the way down
## the frame and the CHEST MARKER OFF THE BOTTOM EDGE ENTIRELY, at 117%. So
## "Start compressions" and "Check the casualty is not on fire" were both
## clamped into the bottom margin with their leader lines running off frame -
## which is what a trainee sees as two pills piled in the corner pointing at
## nothing.
##
## It is also half of why the pills were hard to click. A perspective camera
## projects an off-axis point at `f * tan(angle)`, so the further a pill sits
## from the centre of the frame the faster it travels for a given mouse
## movement, and at 0.4 m everything is off-axis. See CAPTURE_RADIUS in
## casualty_pointers.gd for the other half.
##
## Measured at these values: 1.47 m to the mouth, 1.25 m to the sternum, mouth
## at 55% down the frame and sternum at 65%, both centred horizontally, whole
## upper body in shot. Still a kneel beside the casualty, not a wide shot.
##
## BROUGHT IN AGAIN. Playtest: "anchor too far." At (0, 0.95, 0.78) / -32 the
## measurements above still hold, and they are the problem: 1.47 m to the mouth
## is a shot of a casualty on a floor rather than a rescuer kneeling at one.
## The three survey markers also projected only 9 percentage points of frame
## height apart (mouth 55%, chest 64.6%, belly 73.4%), which is barely more
## than a pill height - so every frame the layout solver had to stack them off
## one another, and that stacking is what the second half of the same playtest
## note ("start compressions keeps dancing up and down") was watching.
##
## Measured at (0, 0.72, 0.42) / -36: mouth 50.9%, chest 65.7%, belly 80.6%,
## and 1.05 m to the mouth. Half the frame is casualty, and the three pills sit
## roughly 96 px apart at 1152x648 - past STACK_GAP + a pill height, so on this
## shot the solver has nothing to resolve at all.
@export var head_pos := Vector3(0.0, 0.72, 0.42)
@export var head_rot := Vector3(-36.0, 0.0, 0.0)

@export_group("Anchor · Head, close")
## The second half of the primary survey, and the two holds after it.
##
## head_pos above frames the whole upper body, which is what the survey's first
## question needs: is this casualty on fire, are they responsive, and the pills
## for both sit at opposite ends of the torso. Once the response check is
## answered, every remaining question is at the head - open the airway, look
## listen and feel at the mouth, two fingers to the side of the neck - and a
## shot framed for the torso is the wrong shot for all three. The trainee was
## being asked to work at the mouth from a distance that made the mouth a
## detail.
##
## So the survey zooms in when the response check lands, rather than being
## framed once for the whole of it. Same pose, closer and a little steeper:
## it reads as leaning in, which is what the trainee is being asked to do.
##
## Brought in twice. The first pass settled at (0, 0.78, 0.34) / -44 and was
## still too far off on the playtest - the frame had the whole upper body in it
## when the only thing being worked was the face. At (0, 0.62, 0.16) / -46 the
## head and shoulders fill the shot: mouth 44% down the frame, chest still in
## at 68% so the "Open the shirt" pill has somewhere to point.
##
## BROUGHT IN A THIRD TIME. Playtest: "zoom to the head while checking breath."
## (0, 0.62, 0.16) / -46 put the mouth 44% down the frame at 0.78 m, which is a
## head in a shot rather than a head filling one - and the two beats this
## anchor really exists for, the breathing hold and the pulse hold, are both
## worked at features a few centimetres across.
##
## At (0, 0.46, -0.04) / -52: mouth 37.3% at 0.53 m, the neck point 52.2%, and
## the sternum still in frame at 80% so "Start compressions" - the pill that is
## how the trainee leaves both holds - has somewhere to point and room to sit
## above the HUD band. Any closer and the chest goes under it.
@export var head_close_pos := Vector3(0.0, 0.46, -0.04)
@export var head_close_rot := Vector3(-52.0, 0.0, 0.0)

@export_group("Anchor · Compressions")
@export var kneel_pos := Vector3(0.55, 0.75, 0.05)
@export var kneel_rot := Vector3(-45.0, -90.0, 0.0)

@export_group("Anchor · Pad placement")
@export var pad_side_pos := Vector3(-0.55, 0.85, 0.05)
@export var pad_side_rot := Vector3(-40.0, 90.0, 0.0)

@export_group("Anchor · Rolled onto their side")
## The casualty is on their side for four beats - the airway inspection, the
## recovery roll, the injury survey and the handover - and the head anchor
## cannot serve them.
##
## head_pos sits 0.5 m above the chest looking 30 degrees down the body, which
## frames a supine casualty and nothing else. Rolled, the head drops to the
## bottom edge of the frame and the feet end up BEHIND the camera; measured at
## the injury survey, the head bone projected to 88% of the way down the screen
## and the foot bone did not project at all. Two thirds of the frame was empty
## floor, and the survey asks the trainee to look at three sites they could not
## see. It had never been rendered.
##
## Higher and steeper than the head anchor, because a body on its side is a
## short deep shape rather than a long flat one, and pushed toward the feet so
## the whole run from head to boots is in frame.
##
## MOVED OFF THE TOP-DOWN. The note that used to stand here recorded the head
## at 26% down the frame, the hand at 24% and the foot at 91%. Re-measured
## against the same pose it describes, the foot was at 109% - off the bottom
## edge - while the head and the hand were 1% apart vertically and 12% apart
## horizontally, effectively stacked on each other. Two of the three survey
## pills came out in a pile and the third was pinned to the opposite margin,
## and the playtest note for it was "pills are too far apart".
##
## The cause is the shape of the shot, not the numbers. A body on its side is a
## long horizontal object, and (0, 1.5, 0.35) / -80 degrees looked almost
## straight down its length: 1.56 m of casualty had to fit down the SHORT axis
## of a 16:9 frame while the three sites separated by only a few degrees of arc
## near the lens. It also meant the trainee was looking at the floor, which is
## what made the clamped look feel like it went round behind them - there is no
## horizon in a top-down shot to tell you which way you are facing.
##
## This is a three-quarter view from the casualty''s front, on the side their
## hands are on, standing off far enough to take the whole body in. The long
## axis now runs across the long axis of the frame, where there is room for it.
##
## Tuned live against the recovery pose, one candidate at a time, reading back
## the projected position of each survey site. The first pass at it fixed the
## geometry and not the distance: head 29% across / 46% down, hand 24% / 63%,
## upper foot 61% / 53% - three separated sites, but all of them crowded into
## the left half of the frame with the bottom right corner nothing but floor,
## and the playtest note for that was "body too far away".
##
## Brought in from 1.90 m to 1.45 m and re-centred, and the tilt taken back to
## -36 degrees. Less tilt is the wrong instinct here and the measurements say
## so: at -23 degrees the body sank to 65-95% down the frame and the lower hand
## went under the HUD band, because the camera is above the casualty and
## flattening it pushes them toward the bottom edge rather than lifting them.
##
## Settled at head 39% across / 52% down, chest 44% / 47%, hand 35% / 74%,
## upper foot 77% / 60%. The body spans most of the frame width, sits on the
## middle, and the three survey pills stack down the centre without a leader
## line crossing the casualty.
##
## Shared by the airway inspection, the recovery roll, the injury survey and the
## handover - every beat with the casualty on their side.
@export var rolled_pos := Vector3(-1.45, 1.10, 0.05)
@export var rolled_rot := Vector3(-36.0, -90.0, 0.0)

@export_group("Anchor · Shock")
@export var shock_pos := Vector3(-1.20, 1.50, 0.0)
@export var shock_rot := Vector3(-35.0, 90.0, 0.0)

@export_group("Anchor · Post-shock decision")
## The beat between the shock landing and compressions resuming.
##
## COMPRESSIONS_2 used to take anchor_kneel the moment the state was entered,
## which is right for compressing and wrong for the question that comes first.
## The kneel anchor is half a metre above the sternum looking almost straight
## down (see main.tscn), so the two pills the beat offers - "Check for signs of
## life" at the mouth and "Start compressions" at the chest - came out with the
## mouth marker near the top edge of the frame and both pills stacked above the
## casualty''s collarbones, over a shot that was nothing but bare chest.
##
## The beat is a decision, and a decision needs to see what it is deciding
## about: the casualty''s face and their chest, in one frame. That is the same
## shot the primary survey opens with, for the same reason, so this sits in the
## same place. It is a separate anchor rather than a reuse of anchor_head
## because the casualty has pads, wires and an AED beside them by now, and the
## framing may want to move for that without dragging the survey along with it.
##
## CprStation._apply_camera() picks this one while `compressions_armed` is
## false, and CprStation.arm_compressions() moves to the kneel anchor the
## instant the trainee takes the pill. The camera change IS the receipt for
## having chosen.
@export var decision_pos := Vector3(0.0, 0.95, 0.78)
@export var decision_rot := Vector3(-32.0, 0.0, 0.0)

@export_group("Floating UI positions")
@export var panel_head_pos := Vector3(0.0, 0.55, -0.25)
## Tuned live at the kneeling anchor. The compression camera is close to
## top-down, so a card placed high (y ~0.5) ends up level with the lens and
## projects off the top of the screen, while lowering y to reach the frame
## drops it into the chest. The answer is a low, sideways offset: x pushes it
## screen-right past the ribs, z brings it down the screen toward the feet.
@export var panel_kneel_pos := Vector3(0.15, 0.20, 0.09)
## Deliberately close to panel_kneel_pos: the pad camera settles nearly
## top-down like the compression one, so the card reads best in the same
## place, lifted a little toward the head to clear the pad sites. Tuned live
## against the settled anchor — the rig keeps aiming for a beat after the
## move, so a value measured mid-tween is wrong by a long way.
@export var panel_pad_side_pos := Vector3(0.21, 0.08, 0.0)
@export var panel_shock_pos := Vector3(-0.70, 0.90, 0.10)

@export_group("Body pointers")
## Anchor points for the floating contextual callouts (see
## scripts/ui/casualty_pointers.gd). Both are in the chest frame, like every
## other offset here, so they follow the body wherever it is posed.
##
## The mouth point is what "check for a response" and the airway steps point
## at; it sits at the head end, forward of the chest origin (-Z) and up.
@export var point_mouth_pos := Vector3(0.0, 0.10, -0.42)
## The sternum: where the shirt is opened and the compressions land.
@export var point_chest_pos := Vector3(0.0, 0.12, 0.02)
## The belly, a little down the body from the sternum (+Z is toward the feet).
##
## Its own point rather than a second user of the chest one. "Check the
## casualty is not on fire" and "Start compressions" were both hanging off the
## sternum, which read as one pill stacked on another and gave the crosshair two
## overlapping targets at the same spot; the fire check is a look over the whole
## body anyway, so it reads better lower. Kept clear of the chest point by more
## than a pill height so the two never restack.
@export var point_belly_pos := Vector3(0.0, 0.11, 0.0)

## The side of the neck, where two fingers find a carotid pulse.
##
## Between the mouth (-0.42) and the sternum (0.02) and off to one side, so
## the cue for the pulse hold cannot be mistaken for the cue for the breathing
## hold. Its own point for the same reason the belly is: two holds at the same
## marker are two holds the trainee cannot tell apart.
@export var point_neck_pos := Vector3(0.055, 0.11, -0.30)

## The three injury-survey anchors (client item 8, docs/OVERNIGHT_PLAN.md §5
## Task 6). These are BONE-BOUND, not chest-frame offsets, and the values below
## are only a nudge applied on top of the bone origin.
##
## They were authored headless as estimated chest-frame offsets, flagged as such,
## and left to be nudged in the editor. Nudging cannot fix them. The injury
## survey only ever runs with the casualty rolled into the recovery position,
## and a fixed offset from the chest cannot describe where a limb ends up once
## the body is on its side. Rendered for the first time, all three leader lines
## pointed at bare concrete: "Check the head and neck" at a dot a metre clear of
## the head, "Check the hands" off in empty floor.
##
## A bone origin is right in any pose with nothing to tune, which is the same
## reasoning that puts the chest frame on bones (see the note at the top - only
## origins, never bases; the Mixamo armature carries a negative scale and
## anything derived from a basis comes out mirrored). If a bone cannot be
## resolved the marker falls back to the offset alone, which is the old
## behaviour rather than every pointer stacked on the rig origin.
##
## The hand is the one that matters: the entry burn is at the contact point, so
## this is the anchor the finding hangs off.
@export var point_hand_pos := Vector3(0.0, 0.0, 0.0)
## The head end, distinct from the mouth point: this is "head and neck", a
## survey site, not the airway.
@export var point_head_pos := Vector3(0.0, 0.0, 0.0)
## Down the body, at the feet.
@export var point_legs_pos := Vector3(0.0, 0.0, 0.0)

# --- runtime -----------------------------------------------------------------
var anchor_head: Marker3D
var anchor_head_close: Marker3D
var anchor_decision: Marker3D
var anchor_kneel: Marker3D
var anchor_pad_side: Marker3D
var anchor_shock: Marker3D
var anchor_rolled: Marker3D
var panel_head: Marker3D
var panel_kneel: Marker3D
var panel_pad_side: Marker3D
var panel_shock: Marker3D
var point_mouth: Marker3D
var point_chest: Marker3D
var point_belly: Marker3D
var point_neck: Marker3D
var point_hand: Marker3D
var point_head: Marker3D
var point_legs: Marker3D

var skeleton: Skeleton3D = null
var chest_idx: int = -1
var head_idx: int = -1
var hips_idx: int = -1
## Every match, not just the first: the injury sites use the higher of a pair.
var hand_indices: PackedInt32Array = PackedInt32Array()
var foot_indices: PackedInt32Array = PackedInt32Array()
var bound: bool = false

var _gizmos_dirty: bool = true


func _ready() -> void:
	_build_markers()
	_bind_skeleton()
	set_process(true)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() and _gizmos_dirty:
		_rebuild_gizmos()
		_gizmos_dirty = false

	if not follow_skeleton:
		return
	if bound and not is_instance_valid(skeleton):
		bound = false
		skeleton = null
		chest_idx = -1
		head_idx = -1
		hips_idx = -1
		hand_indices = PackedInt32Array()
		foot_indices = PackedInt32Array()
	if not bound:
		# Editor scenes take a moment to populate; keep retrying cheaply.
		_bind_skeleton()
		if not bound:
			return
	global_transform = _chest_frame()
	_apply_offsets()


# --- markers -----------------------------------------------------------------
# Created in code with no owner, so they are never serialised into the .tscn and a
# reimport can't drop them.

func _build_markers() -> void:
	anchor_head       = _make_marker("Anchor_Head", 0.15)
	anchor_head_close = _make_marker("Anchor_HeadClose", 0.15)
	anchor_decision   = _make_marker("Anchor_Decision", 0.15)
	anchor_kneel    = _make_marker("Anchor_Kneel", 0.15)
	anchor_pad_side = _make_marker("Anchor_PadSide", 0.15)
	anchor_shock    = _make_marker("Anchor_Shock", 0.15)
	anchor_rolled   = _make_marker("Anchor_Rolled", 0.15)
	panel_head      = _make_marker("Panel_Head", 0.08)
	panel_kneel     = _make_marker("Panel_Kneel", 0.08)
	panel_pad_side  = _make_marker("Panel_PadSide", 0.08)
	panel_shock     = _make_marker("Panel_Shock", 0.08)
	point_mouth     = _make_marker("Point_Mouth", 0.05)
	point_chest     = _make_marker("Point_Chest", 0.05)
	point_belly     = _make_marker("Point_Belly", 0.05)
	point_neck      = _make_marker("Point_Neck", 0.05)
	point_hand      = _make_marker("Point_Hand", 0.05)
	point_head      = _make_marker("Point_Head", 0.05)
	point_legs      = _make_marker("Point_Legs", 0.05)
	_apply_offsets()
	_gizmos_dirty = true


func _make_marker(marker_name: String, extents: float) -> Marker3D:
	var existing := get_node_or_null(marker_name)
	if existing is Marker3D:
		return existing
	var m := Marker3D.new()
	m.name = marker_name
	m.gizmo_extents = extents
	add_child(m)
	m.owner = null
	return m


func _apply_offsets() -> void:
	_set_local(anchor_head, _vec(head_pos), _vec(head_rot))
	_set_local(anchor_head_close, _vec(head_close_pos), _vec(head_close_rot))
	_set_local(anchor_decision, _vec(decision_pos), _vec(decision_rot))
	_set_local(anchor_kneel, _vec(kneel_pos), _vec(kneel_rot))
	_set_local(anchor_pad_side, _vec(pad_side_pos), _vec(pad_side_rot))
	_set_local(anchor_shock, _vec(shock_pos), _vec(shock_rot))
	_set_local(anchor_rolled, _vec(rolled_pos), _vec(rolled_rot))
	_set_local(panel_head, _vec(panel_head_pos), Vector3.ZERO)
	_set_local(panel_kneel, _vec(panel_kneel_pos), Vector3.ZERO)
	_set_local(panel_pad_side, _vec(panel_pad_side_pos), Vector3.ZERO)
	_set_local(panel_shock, _vec(panel_shock_pos), Vector3.ZERO)
	_set_local(point_mouth, _vec(point_mouth_pos), Vector3.ZERO)
	_set_local(point_chest, _vec(point_chest_pos), Vector3.ZERO)
	_set_local(point_belly, _vec(point_belly_pos), Vector3.ZERO)
	_set_local(point_neck, _vec(point_neck_pos), Vector3.ZERO)
	# Bone-bound, so they are right in the recovery pose as well as supine.
	_set_at_bone(point_hand, _exposed_bone(hand_indices), _vec(point_hand_pos))
	_set_at_bone(point_head, head_idx, _vec(point_head_pos))
	_set_at_bone(point_legs, _exposed_bone(foot_indices), _vec(point_legs_pos))


## This is a @tool script, so the editor holds a live instance of it. Hot-
## reloading after adding an exported variable adds the member to that instance
## but does NOT re-run its initialiser, so it reads as Nil until the scene is
## reopened — and _process() calls _apply_offsets() every frame in the editor,
## which then fails to convert Nil to Vector3. Reading every offset through
## here means adding the next anchor cannot spam the output the same way.
func _vec(value: Variant) -> Vector3:
	return value if value is Vector3 else Vector3.ZERO


## Park a marker on a bone, plus a nudge expressed in the chest frame. Falls
## back to the nudge alone as a plain chest-frame offset when the bone is not
## resolved, so a renamed armature degrades to the old behaviour rather than
## stacking every pointer on the rig origin.
func _set_at_bone(m: Marker3D, bone_idx: int, nudge: Vector3) -> void:
	if m == null:
		return
	if bone_idx < 0 or skeleton == null or not bound:
		_set_local(m, nudge, Vector3.ZERO)
		return
	m.global_position = _bone_origin(bone_idx) + (global_transform.basis * nudge)
	m.rotation = Vector3.ZERO


func _set_local(m: Marker3D, pos: Vector3, rot_deg: Vector3) -> void:
	if m == null:
		return
	m.transform = Transform3D(
		Basis.from_euler(Vector3(
			deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z)
		)),
		pos
	)


# --- editor gizmos -----------------------------------------------------------
# Wireframe frustums drawn as children of each anchor. Editor only, owner = null, so
# they are never saved and never exist at runtime.

func _rebuild_gizmos() -> void:
	for m in [anchor_head, anchor_head_close, anchor_decision, anchor_kneel,
			anchor_pad_side, anchor_shock, anchor_rolled,
			panel_head, panel_kneel, panel_pad_side, panel_shock,
			point_mouth, point_chest, point_belly, point_neck, point_hand, point_head,
			point_legs]:
		if m == null:
			continue
		var old: Node = m.get_node_or_null("Gizmo")
		if old != null:
			old.free()
	if not show_gizmos:
		return

	for m in [anchor_head, anchor_head_close, anchor_decision, anchor_kneel,
			anchor_pad_side, anchor_shock, anchor_rolled]:
		if m == null:
			continue
		_attach_mesh(m, _frustum_mesh(GIZMO_COLORS.get(String(m.name), Color.WHITE)))
	for m in [panel_head, panel_kneel, panel_pad_side, panel_shock]:
		if m == null:
			continue
		_attach_mesh(m, _panel_card_mesh(PANEL_COLOR))
	# Pointer anchors get a cross rather than a card: they mark a spot on the
	# body, and a card gizmo would read as another floating panel.
	for m in [point_mouth, point_chest, point_belly, point_neck, point_hand,
			point_head, point_legs]:
		if m == null:
			continue
		_attach_mesh(m, _cross_mesh(POINTER_COLOR))


func _attach_mesh(parent: Marker3D, mesh: ImmediateMesh) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Gizmo"
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true          # visible through the casualty while tuning
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	parent.add_child(mi)
	mi.owner = null


## Pyramid opening along -Z (the look direction), with an UP tick so roll is legible.
func _frustum_mesh(col: Color) -> ImmediateMesh:
	var d := gizmo_length
	var h := d * tan(deg_to_rad(gizmo_fov_deg * 0.5))
	var w := h * 1.6                                   # roughly 16:10
	var apex := Vector3.ZERO
	var tl := Vector3(-w,  h, -d)
	var tr := Vector3( w,  h, -d)
	var br := Vector3( w, -h, -d)
	var bl := Vector3(-w, -h, -d)

	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_set_color(col)

	for corner in [tl, tr, br, bl]:
		_line(im, apex, corner)
	_line(im, tl, tr)
	_line(im, tr, br)
	_line(im, br, bl)
	_line(im, bl, tl)

	# UP tick — a little roof over the top edge.
	var peak := Vector3(0.0, h + h * 0.45, -d)
	im.surface_set_color(col.lightened(0.35))
	_line(im, tl, peak)
	_line(im, tr, peak)

	# Centre ray, so the aim point is unambiguous.
	im.surface_set_color(col.lightened(0.5))
	_line(im, apex, Vector3(0.0, 0.0, -d * 1.15))

	if gizmo_show_look_limits and gizmo_yaw_limit_deg > 0.0:
		im.surface_set_color(Color(col.r, col.g, col.b, 0.35))
		for s in [-1.0, 1.0]:
			var a: float = deg_to_rad(gizmo_yaw_limit_deg) * float(s)
			_line(im, apex, Vector3(sin(a), 0.0, -cos(a)) * d * 1.15)

	im.surface_end()
	return im


## A flat card facing -Z, showing where the floating panel will sit.
func _panel_card_mesh(col: Color) -> ImmediateMesh:
	var w := 0.11
	var h := 0.08
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_set_color(col)
	var a := Vector3(-w,  h, 0.0)
	var b := Vector3( w,  h, 0.0)
	var c := Vector3( w, -h, 0.0)
	var e := Vector3(-w, -h, 0.0)
	_line(im, a, b); _line(im, b, c); _line(im, c, e); _line(im, e, a)
	_line(im, a, c); _line(im, b, e)
	im.surface_end()
	return im


## A small three-axis cross, for anchors that mark a point rather than a pose.
func _cross_mesh(col: Color) -> ImmediateMesh:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_set_color(col)
	var r := 0.05
	_line(im, Vector3(-r, 0.0, 0.0), Vector3(r, 0.0, 0.0))
	_line(im, Vector3(0.0, -r, 0.0), Vector3(0.0, r, 0.0))
	_line(im, Vector3(0.0, 0.0, -r), Vector3(0.0, 0.0, r))
	im.surface_end()
	return im


func _line(im: ImmediateMesh, a: Vector3, b: Vector3) -> void:
	im.surface_add_vertex(a)
	im.surface_add_vertex(b)


# --- skeleton ----------------------------------------------------------------

func _bind_skeleton() -> void:
	skeleton = get_node_or_null(skeleton_path) as Skeleton3D
	if skeleton == null:
		var root: Node = get_tree().edited_scene_root if Engine.is_editor_hint() else get_tree().current_scene
		if root == null:
			root = get_parent()
		skeleton = _find_skeleton(root)
	if skeleton == null:
		return

	chest_idx = _find_bone(chest_bone_names)
	head_idx = _find_bone(head_bone_names)
	hips_idx = _find_bone(hips_bone_names)
	hand_indices = _find_bones(hand_bone_names)
	foot_indices = _find_bones(foot_bone_names)

	if chest_idx < 0:
		push_error("CprRig: no chest bone found. Tried %s" % [chest_bone_names])
		return
	bound = true


func _find_skeleton(node: Node) -> Skeleton3D:
	if node == null:
		return null
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var hit := _find_skeleton(c)
		if hit != null:
			return hit
	return null


func _find_bone(candidates: PackedStringArray) -> int:
	for n in candidates:
		var i := _match_bone(n)
		if i >= 0:
			return i
	return -1


## Every candidate that resolves, not just the first. The injury sites are
## left/right pairs and want both, so the visible one can be picked per frame.
func _find_bones(candidates: PackedStringArray) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for n in candidates:
		var i := _match_bone(n)
		if i >= 0 and not out.has(i):
			out.append(i)
	return out


## find_bone(), then the same lookup with ":" and "_" treated as the same
## character.
##
## The importer sanitises the colon in Mixamo bone names, so the .blend ships
## "mixamorig:LeftHand" and Godot holds "mixamorig_LeftHand". Every list in this
## file was written in the colon form and main.tscn overrides three of them with
## the underscore form, which is why the two that were NOT overridden - the new
## hand and foot lists - resolved to nothing and quietly dropped their markers
## on the rig origin. Both leader lines then pointed at the same spot in mid-air.
##
## A whole-name compare rather than a suffix match: "LeftHand" is a prefix of
## "LeftHandIndex1", and a survey pill on a fingertip would be worse than one
## that failed loudly.
func _match_bone(wanted: String) -> int:
	var direct := skeleton.find_bone(wanted)
	if direct >= 0:
		return direct
	var norm := wanted.replace(":", "_")
	if norm != wanted:
		var swapped := skeleton.find_bone(norm)
		if swapped >= 0:
			return swapped
	for i in skeleton.get_bone_count():
		if skeleton.get_bone_name(i).replace(":", "_") == norm:
			return i
	return -1


## The most exposed of a set of bones, or -1 if none resolved: the one furthest
## from the chest, which is the limb held out away from the body rather than
## folded into it.
##
## Height was tried first and picks the wrong one. In the recovery position the
## upper arm is bent with the hand tucked under the cheek, so it wins on height
## while being the hand you cannot see - the leader line landed on the shoulder,
## a few pixels from the head pill's own dot, and the two read as pointing at
## the same thing. Distance picks the arm laid out on the floor with the palm
## open, which is the one the trainee is being asked to look at. Supine, the
## arms are roughly symmetric and either answer is fine.
func _exposed_bone(indices: PackedInt32Array) -> int:
	if chest_idx < 0:
		return indices[0] if indices.size() > 0 else -1
	var chest := _bone_origin(chest_idx)
	var best := -1
	var best_d := -INF
	for i in indices:
		var d := _bone_origin(i).distance_squared_to(chest)
		if d > best_d:
			best_d = d
			best = i
	return best


## World-space position of a bone. Origin only — see the note at the top about the
## armature's negative scale.
func _bone_origin(idx: int) -> Vector3:
	return (skeleton.global_transform * skeleton.get_bone_global_pose(idx)).origin


func _chest_frame() -> Transform3D:
	var origin := _bone_origin(chest_idx)
	var forward := Vector3.FORWARD

	if head_idx >= 0 and hips_idx >= 0:
		var spine_dir := _bone_origin(head_idx) - _bone_origin(hips_idx)
		spine_dir.y = 0.0
		if spine_dir.length() > 0.02:
			forward = spine_dir.normalized()
		else:
			forward = Basis(Vector3.UP, deg_to_rad(fallback_yaw_degrees)) * Vector3.FORWARD
	else:
		forward = Basis(Vector3.UP, deg_to_rad(fallback_yaw_degrees)) * Vector3.FORWARD

	return Transform3D(Basis.looking_at(forward, Vector3.UP), origin)


# --- lookup ------------------------------------------------------------------

## Camera pose for a CPR state. Null for states with no anchor.
##
## Written as if/elif against CprStation's own constants rather than as a match
## on integer literals. The literals were exactly the hazard the 3 Sep 2026
## renumber (docs/OVERNIGHT_PLAN.md §2, risk 4) was warned about: every state id
## moved, and a table of bare numbers would have kept parsing and quietly aimed
## the camera at the wrong beat.
##
## Five anchors serve nine anchored states. The pulse check shares the head
## anchor with the breathing check - both are holds worked at the casualty's
## head, supine - and EXPOSE_CHEST shares the kneel anchor with the compressions
## that bracket it, so opening the shirt does not move the trainee.
##
## The four beats where the casualty is ON THEIR SIDE take anchor_rolled. They
## used to take the head anchor too, on the reasoning that "everything the
## trainee is asked to look at is up that end". That is true of the airway
## inspection and false of the other three, and it was wrong about the framing
## in all four: rolled, the head drops to the bottom edge and the feet fall
## behind the camera. See rolled_pos.
func anchor_for_state(state: int) -> Marker3D:
	if state == CprStation.STATE_BREATHING_CHECK: return anchor_head_close
	if state == CprStation.STATE_AIRWAY_INSPECT: return anchor_rolled
	if state == CprStation.STATE_PULSE_CHECK: return anchor_head_close
	if state == CprStation.STATE_COMPRESSIONS_1: return anchor_kneel
	if state == CprStation.STATE_EXPOSE_CHEST: return anchor_kneel
	if state == CprStation.STATE_PAD_PLACEMENT: return anchor_pad_side
	if state == CprStation.STATE_SHOCK: return anchor_shock
	if state == CprStation.STATE_COMPRESSIONS_2: return anchor_kneel
	if state == CprStation.STATE_RECOVERY_ROLL: return anchor_rolled
	if state == CprStation.STATE_INJURY_SURVEY: return anchor_rolled
	if state == CprStation.STATE_HANDOVER: return anchor_rolled
	return null


## The primary survey''s camera, which moves once part way through it.
##
## The survey is not a spine state - it runs at STATE_PRIMARY_SURVEY with the
## body pointers owning the screen - so it cannot ask anchor_for_state() for its
## pose. It asks for the one that matches how far through it the trainee is:
## the wide shot while the question is still "what is in front of me", the close
## one once the response check has narrowed everything that is left to the head.
##
## See head_close_pos.
func survey_anchor(response_checked: bool) -> Marker3D:
	return anchor_head_close if response_checked else anchor_head


## Anchor for a body-pointer callout. Keyed by name rather than by state: the
## pointers belong to the phase before the CPR spine starts, and which one is
## live is decided by what the trainee has done, not by a state number.
func pointer_marker(id: StringName) -> Marker3D:
	match id:
		&"mouth": return point_mouth
		&"chest": return point_chest
		&"belly": return point_belly
		&"neck": return point_neck
		# The injury survey's three sites. Named, not numbered, for the same
		# reason the two above are: which one is live is decided by what the
		# trainee has looked at, not by a state.
		&"hand": return point_hand
		&"head": return point_head
		&"legs": return point_legs
		_:
			push_warning("CprRig: no body pointer named '%s'" % id)
			return null


## Same story as anchor_for_state(): CprStation's constants, never the numbers.
## PULSE_CHECK used to return `panel_head` here and it was a bug you could see:
## the panel has no pulse content, so it faded in at head height still carrying
## the breathing check's "Observing..." arc - half a screen tall, clipped off
## the top, describing a hold the trainee had already finished.
##
## It belongs with AIRWAY_INSPECT rather than with the states below. Both are
## holds at the body, and the breathing check already settled how those are
## presented: the ear at the mouth carries the cue and the progress, and a card
## floating at head height saying the name of the mechanic competes with it.
## Returning null is what turns the panel off - see CprPanel3D._reposition_for_state.
func panel_for_state(state: int) -> Marker3D:
	if state == CprStation.STATE_BREATHING_CHECK: return panel_head
	if state == CprStation.STATE_COMPRESSIONS_1: return panel_kneel
	if state == CprStation.STATE_PAD_PLACEMENT: return panel_pad_side
	if state == CprStation.STATE_SHOCK: return panel_shock
	if state == CprStation.STATE_COMPRESSIONS_2: return panel_kneel
	return null
