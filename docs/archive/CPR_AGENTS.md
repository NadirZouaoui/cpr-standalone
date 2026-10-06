# CPR Phase — Work Log

Historical record of how the CPR phase was built, kept for the reasoning in each brief
rather than as a set of assignments. The agent/ownership workflow it describes is
retired: there are no per-file permissions and nothing is frozen.

## Before you write anything

1. Read `CPR_CONTRACT.md` in the project root, in full.
2. Obey the standing rules in `CPR_CONTRACT.md` §8, and the input model in §4.0.
3. Use the helpers in `cpr_ghost.gd`, `ghost_target.gd` and `cpr_interact_bridge.gd`
   rather than writing a second way to do the same thing.

The briefs below record what each piece of work found and why it was done that way.
Read whichever ones touch the code you are changing.

Project path: `D:\Nadir\Documents\Work\Freelance\HV Exercices Simulations\LVR CPR\lvr-cpr`

### Status board

| Area | Files | State |
|---|---|---|
| A · Camera | `cpr_camera_rig.gd` | complete |
| B · UI | `cpr_panel_3d.gd`, `CprPanel.tscn`, stub emitter | complete |
| C · Compressions | `compression_driver.gd`, `casualty_cpr.gd` | complete |
| D · AED | `aed_station.gd`, `pad_station.gd` | complete |
| E · Station | `cpr_station.gd`, `cpr_headless_test.gd/.tscn` | complete |
| G · Input bridge | `cpr_interact_bridge.gd`, `ghost_target.gd` | complete |
| H · Shock | `shock_button.gd` | complete |
| I · Integration | `main.gd` seams, `Assessment` wiring | complete |
| K · Playtest fixes | panel instancing, hover clear | complete |
| **L · Menu handover** | see below | **run this first** |
| J · Cleanup | see below | run after L |

All of the below is complete; the briefs are kept for their reasoning.

---

## Agent L · Menu handover, stuck breathing check, camera freedom

Second playtest. The diegetic panel now appears and the camera anchors work. Three
defects, and the first is probably the cause of the second.

### Task 1 — the legacy casualty menu never hands over (blocking)

The old screen-space casualty menu — a panel titled "Casualty" listing "Check for a
response", "Check the airway and breathing", "Open the airway - full head tilt",
"Expose the chest", "Start chest compressions", "Attach the AED pads", "Stand clear for
analysis", "Deliver the shock", "Roll into the recovery position", "Stand up" — is
still open and still in control after the CPR phase begins.

Observed: choosing "Expose the chest" correctly starts the CPR phase and the diegetic
panel appears, but the old menu stays up. The trainee has to press "Stand up" in the
old menu before anything responds. While that menu is open the player is held in menu
mode, so **no CPR input reaches anything.**

Find what owns that menu (start from `Events.casualty_actions_requested`). Then, from
`cpr_station.gd`, close it and stop it reopening for the rest of the phase — via
whatever public close/suppress path it already offers.

Do not delete the menu or its entries. The pre-CPR entries ("Check for a response",
"Open the airway", "Expose the chest") are still the route *into* the phase and must
keep working. Only the CPR-and-later entries are superseded.

If the menu's owner had no public way to be closed or suppressed, one was added —
`suppress()` on `casualty_action_menu.gd`, resolved by name from `CprStation`.
Do not reach into it and mutate state from outside.

### Task 2 — breathing check never completes

The panel shows "Observing…" with the arc part-filled and stays there forever.

Most likely a consequence of Task 1: the hold input never arrives because the menu owns
input. **Fix Task 1 first, then re-test before changing anything here.**

If it still hangs, diagnose properly. Check in this order:
1. Does the hold-to-observe read an input action that actually exists in the project's
   InputMap? Print it and confirm.
2. Is it reading input in `_unhandled_input` while something upstream is consuming the
   event?
3. Does the completion path emit `Events.breathing_checked(false)` unconditionally, or
   is it gated behind a condition that never becomes true?

Report the actual cause. Do not "fix" it by shortening the timer or auto-completing.

### Task 3 — mouse-look clamp is too tight

±30° yaw and −45°/+15° pitch is too restrictive in play; the trainee cannot comfortably
look over the casualty.

In `cpr_camera_rig.gd`, replace the hard-coded clamp constants with `@export` floats so
the human can tune them in the inspector without another agent round:

```gdscript
@export var look_yaw_limit_deg: float = 60.0
@export var look_pitch_min_deg: float = -70.0
@export var look_pitch_max_deg: float = 35.0
```

Keep the existing clamping behaviour and keep yaw rotating around `Vector3.UP` — widen
the limits and expose them, change nothing else about how look works.

### Task 4 — prove it

Re-run `res://scripts/cpr/cpr_headless_test.tscn` headless and report the exit code. It
must still pass. Do not edit the test.

### Report

- What owns the legacy casualty menu, and how you closed it.
- The real cause of the stuck breathing check.
- Whether any part of the fix needed a file you could not touch.
- The headless test's exit code.
- What the human should check in-game, in order.

---

## Agent J · Cleanup

Four small defects in a phase that already ran end to end.

### Task 1 — the three missing assessment steps (blocking)

`main.gd` already calls `Assessment.complete()` / `fail()` for `breathing_checked`,
`cpr_performed` and `aed_used`, but those ids do not exist in
`lvr_cpr_procedure.tres`, so all three are silent no-ops that emit a `push_warning`.

Add three `sub_resource` entries following the existing `s00`../`s23` pattern exactly,
and add their names to the `[resource] steps = Array[...]` list:

| id | category | requires | weight | critical |
|---|---|---|---|---|
| `breathing_checked` | `resuscitation` | `drag_to_safe_area` | 8 | false |
| `cpr_performed` | `resuscitation` | `breathing_checked` | 15 | true |
| `aed_used` | `resuscitation` | `cpr_performed` | 15 | false |

**Then retire the superseded granular steps** — `compressions_started`, `pads_placed`,
`clear_for_analysis`, `shock_delivered`, `compressions_resumed`. They predate the CPR
minigame and describe the menu-driven flow that Agent L has now superseded.

**Before removing any of them, grep the whole project for that id string.** Remove only
the ones with no live emitter. Report any that still have one and leave those alone.

Mind the project's `.tres` trap: any node line using an exported `Node` reference needs
an explicit `node_paths=PackedStringArray("property_name")`. Verify the file parses by
booting the main scene, not by `--check-only`.

### Task 2 — collider naming collision (one line)

`cpr_interact_bridge.gd`, in `_register()`:

```gdscript
body.name = "%s_BridgeBody" % mesh.name      # replace
body.name = "BridgeBody_%s" % mesh.name      # with
```

Runtime colliders are parented under each pad mesh, so the old name also begins with
`PadSite_` and `CprGhost.find_nodes_with_prefix()` picks them up — five `push_error`s
per run from `PadStation._build_targets()`. `pad_station.gd` already guards correctly.
Do not touch `pad_station.gd`.

### Task 3 — nobody offers the fast-forward

`CompressionDriver.fast_forward_available` is emitted and `accept_fast_forward()`
exists, but nothing connects them, so the trainee must hand-deliver every rep.

- `cpr_station.gd` connects to `fast_forward_available`, and on the `interact` action
  while the offer is up, calls `accept_fast_forward()`.
- `cpr_panel_3d.gd` shows a prompt on the compression panel while the offer is up, and
  clears it on acceptance or on leaving the state.

Use the `interact` action, **not** the compression input — compressions are left mouse
button and Space, and reusing either would fire the skip on a normal rep.

The offer is not a past-tense fact, so it stays a local signal. Add nothing to
`events.gd`.

### Task 4 — second set is too long

`REP_TARGET` is a single const used by both sets, so `COMPRESSIONS_2` asks for 30 reps
after the shock. The design calls for ~10. Make the target per-state: 30 for
`STATE_COMPRESSIONS_1`, 10 for `STATE_COMPRESSIONS_2`, resolved in `_start_set()`.

Keep the fast-forward streak at 10 — with a 10-rep second set it then never triggers
there, which is correct.

### Task 5 — prove it

Run `res://scripts/cpr/cpr_headless_test.tscn` headless and report the exit code. Two
warning families must be gone: the three `Assessment: unknown step` warnings and the
five `PadStation: ... not a MeshInstance3D` errors. Do not edit the test.
