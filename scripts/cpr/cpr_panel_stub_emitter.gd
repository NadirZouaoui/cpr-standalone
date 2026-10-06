extends Node

## Standalone test harness for CprPanel3D — fires the Events signals the panel
## listens to, on a timer, cycling through the CPR states.
##
## Not part of CPR_CONTRACT.md section 7 file ownership; this is throwaway test
## scaffolding for Agent B only. Run `CprPanelTestHarness.tscn` directly (F6) —
## it does not depend on main.tscn, the casualty, or any other agent's work.
##
## Also builds a minimal fake Skeleton3D (three named bones) at _ready() so
## CprRig has something real to bind to and the panel actually tracks anchors
## instead of sitting frozen at the origin.

const STATE_LABELS := {
	0: "EXPOSE_CHEST", 1: "BREATHING_CHECK", 2: "COMPRESSIONS_1", 3: "AED_FETCH",
	4: "AED_DEPLOY", 5: "PAD_PLACEMENT", 6: "SHOCK", 7: "COMPRESSIONS_2", 8: "COMPLETE",
}


func _ready() -> void:
	_build_fake_skeleton()
	_run()


func _build_fake_skeleton() -> void:
	var skel := Skeleton3D.new()
	skel.name = "FakeSkeleton3D"

	var hips := skel.add_bone("mixamorig:Hips")
	skel.set_bone_rest(hips, Transform3D(Basis(), Vector3(0.0, 1.0, 0.0)))

	var spine2 := skel.add_bone("mixamorig:Spine2")
	skel.set_bone_rest(spine2, Transform3D(Basis(), Vector3(0.0, 1.25, 0.0)))

	var head := skel.add_bone("mixamorig:Head")
	skel.set_bone_rest(head, Transform3D(Basis(), Vector3(0.0, 1.65, 0.0)))

	get_tree().current_scene.add_child(skel)
	skel.reset_bone_poses()


func _enter_state(from: int, to: int) -> void:
	print("[stub] state -> %s" % STATE_LABELS.get(to, str(to)))
	Events.cpr_state_changed.emit(from, to)


func _run_compressions() -> void:
	for i in range(10):
		var depth := 0.5 + (0.4 * (i % 4) / 3.0)
		var rate := 95.0 + float(i * 3)
		Events.compression_delivered.emit(depth, rate, i)
		await get_tree().create_timer(0.3).timeout
	Events.compression_set_completed.emit(10, false)
	await get_tree().create_timer(0.5).timeout


func _run_pads() -> void:
	Events.aed_pad_hovered.emit("PadSite_Correct_Upper")
	await get_tree().create_timer(0.8).timeout
	Events.aed_pad_placed.emit(0, true, "PadSite_Correct_Upper")
	await get_tree().create_timer(0.6).timeout

	Events.aed_pad_hovered.emit("PadSite_Wrong_02")
	await get_tree().create_timer(0.8).timeout
	Events.aed_pad_placed.emit(1, false, "PadSite_Wrong_02")
	await get_tree().create_timer(0.6).timeout


func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	Events.cpr_phase_entered.emit()
	await get_tree().create_timer(0.5).timeout

	_enter_state(0, 1)
	await get_tree().create_timer(3.5).timeout
	Events.breathing_checked.emit(true)
	await get_tree().create_timer(0.3).timeout

	_enter_state(1, 2)
	await _run_compressions()

	_enter_state(2, 3)
	await get_tree().create_timer(0.5).timeout
	Events.aed_picked_up.emit()
	await get_tree().create_timer(0.8).timeout

	_enter_state(3, 4)
	await get_tree().create_timer(0.5).timeout
	Events.aed_placed.emit()
	await get_tree().create_timer(0.8).timeout

	_enter_state(4, 5)
	await _run_pads()

	_enter_state(5, 6)
	await get_tree().create_timer(1.5).timeout
	Events.stand_clear_confirmed.emit()
	await get_tree().create_timer(2.5).timeout
	Events.aed_shock_delivered.emit()
	await get_tree().create_timer(0.5).timeout

	_enter_state(6, 7)
	await _run_compressions()

	_enter_state(7, 8)
	Events.cpr_completed.emit({
		"total_compressions": 20, "pct_in_depth": 0.8, "pct_in_rate": 0.7,
		"time_to_breathing_check": 3.5, "time_to_first_compression": 4.0,
		"time_to_shock": 30.0, "pad_errors": 1, "pads_correct": 1, "assisted": false,
	})

	await get_tree().create_timer(2.0).timeout
	_run()
