# LVR CPR — UI / interaction handoff, 31 Aug 2026

Covers one session's work: the treatment card was replaced by **body-anchored contextual
pointers**, and the interaction flow around them was reworked. Read
`HANDOFF_2026-08-31.md` first for everything else — it is still current except where this
file contradicts it.

Companion document: `DECISION_POINTS.md` (designed this session, **not built**).

---

## 1. What the treatment flow is now

Interacting with the casualty drops the trainee onto the CPR phase's **first camera
anchor** (`CprRig.anchor_for_state(1)`, the head-side kneel) and raises glass **pills**
anchored to points on the body, each with a leader line to the part it concerns. The
trainee clicks the **pill**, not the body part. The four-row world-space card is gone.

Two tracks run independently, so the shirt does not have to wait on the airway work:

| pill | anchor | appears when |
|---|---|---|
| Check for a response | mouth | not yet done |
| Open the airway | mouth | response done, airway not open |
| Check for breathing | mouth | airway open, CPR spine still at EXPOSE_CHEST |
| Open the shirt | chest | response done, chest not exposed |
| Start compressions | chest | state COMPRESSIONS_1 and chest exposed |

Two pills hand over rather than acting: **Check for breathing** calls
`CprStation.begin_breathing_check()`, and **Start compressions** arms the minigame and
dismisses the pointers.

## 2. Files

| file | what changed |
|---|---|
| `scripts/ui/casualty_pointers.gd` | **new.** The renderer and picker. |
| `scripts/ui/casualty_action_menu.gd` | rewritten, 828 → 331 lines. Now the sequence controller. Node name and `suppress()` / `is_open()` kept — `main.tscn` is frozen and `CprStation` resolves it by name. |
| `scripts/cpr/cpr_rig.gd` | "Body pointers" export group + `Point_Mouth` / `Point_Chest` markers and `pointer_marker()`. `_vec()` guard on every offset. |
| `scripts/cpr/cpr_station.gd` | `compressions_armed`; `STANCE_TOGGLE_STATES`. |
| `scripts/cpr/cpr_hands_2d.gd` | hands hidden until compressions are armed. |
| `scripts/cpr/compression_driver.gd` | reps silently refused until armed. |
| `scripts/casualty/casualty.gd` | airway tween; mouth blend shape synced across the mesh swap. |
| `scripts/interaction/casualty_interactable.gd` | tooltip suppressed while the sequence is live. |
| `scripts/ui/hud.gd` | centre message → glass pill at the bottom of the screen. |
| `scripts/ui/dev_menu.gd` | new "Casualty dragged clear" warp; both CPR warps share `_warp_to_body_down()`. |
| `scripts/main.gd` | no longer starts the breathing check off `chest_exposed`. |
| `resources/procedures/lvr_cpr_procedure.tres` | "with a full head tilt" dropped from the airway step title. |

### Why the pointers are 2D

`casualty_pointers.gd` draws in screen space and anchors to world markers, the way
`cpr_hands_2d.gd` already does — **not** a billboarded SubViewport quad like the CPR
panel. Text stays crisp at any distance (the old card blurred when leaned into), leader
lines are a two-segment polyline, there is no per-callout viewport, and pills can be
nudged apart in screen space. That last one is correctness, not polish: two overlapping
pills under the crosshair is an ambiguous click.

Picking is the crosshair against each pill's own `Rect2` (+6 px), nearest-to-centre wins
ties. No `Area3D`, no colliders — CPR_CONTRACT.md §4.0 still holds throughout.

## 3. Ordering changes worth knowing

- **The breathing check is no longer triggered by exposing the chest.** `main.gd` used to
  call `begin_breathing_check()` on `step_completed(chest_exposed)`, which forced
  shirt-before-airway — the wrong way round for DRSABCD. The "Check for breathing" pill
  owns that trigger now. `main.gd` still calls `enter_cpr_phase()` there; that guards a
  real startup race and must stay.
- **Compressions are gated on the pill, not on the chest.** `CprStation.compressions_armed`
  is false until "Start compressions" is taken; the hands stay hidden and reps are refused
  silently until then. The spine reaches COMPRESSIONS_1 off the breathing check, which is
  now assessed at the mouth with the shirt still on, so the state arriving is *not* the
  trainee saying they are ready.
- **The shock disarms compressions again.** COMPRESSIONS_2 is entered with
  `compressions_armed` back to false, so the trainee lands on two pills — "Start
  compressions" at the chest and the "Check for signs of life" gotcha at the mouth —
  instead of being dropped into the minigame. Taking either retires the gotcha; only the
  compressions pill re-arms. The metronome stays silent while the pills are up.
- **`[C]` stands you up during BREATHING_CHECK and both compression states** now
  (`STANCE_TOGGLE_STATES`), so the radio is reachable mid-procedure. AED_FETCH still does
  not toggle, deliberately.

## 4. Traps this session paid for

- **`suppress()` must not tear the sequence down.** `CprStation.begin_breathing_check()`
  calls `_suppress_legacy_menu()` → `suppress()`. That used to stand the pointers down,
  which left the trainee in COMPRESSIONS_1 with a covered chest and nothing on screen to
  open it with. It now only drops the camera claim; the pills retire themselves when no
  callout is available.
- **Arming is not a signal.** `compressions_armed` is a plain field, so there is nothing
  to re-sync on. `cpr_hands_2d.gd` tests it inside `_process` rather than gating
  `set_process()` — gating it meant the hands never appeared after the pill click.
- **`cpr_rig.gd` is a `@tool` script.** Adding an exported var and hot-reloading attaches
  the member to the editor's live instance *without running its initialiser*, so it reads
  as Nil and `_process()` spams conversion errors every frame until the scene is reopened.
  `_vec()` absorbs that; keep using it for new offsets.
- **An anchored `PanelContainer` takes its width from the child's minimum size**, and an
  autowrapping `Label`'s minimum width is one character — which is why the first bottom
  pill rendered as a vertical column of letters. Autowrap is off there now.
- **The chest overlay ships with "Mouth open" already driven.** Exposing the chest before
  the airway step swapped in a head that was tilted back on its own. Zeroed at bind time
  and re-synced across the swap in `casualty.gd`.

## 5. State of play

- Headless regression passes: `"C:/Program Files/Godot.exe" --headless --path . res://scripts/cpr/cpr_headless_test.tscn`
- The pointer system was confirmed working in game by the user mid-session.
- The bottom message pill, the tooltip suppression, the `[C]` stance toggle in the new states, the "Casualty dragged clear" dev warp, the airway tween, the hands re-appearing after "Start compressions" confirmed working in game by the user mid-session.
- `game_eval` refused to connect for most of this session even with the server listening.
  `run_project` then `get_debug_output` still works for catching parse errors.

## 6. Open

1. **`scripts/ui/debrief_screen.gd` is unreviewed and was never asked for.** Built early in
   the session off `HANDOFF_2026-08-31.md` §2 item 1, before the user took over directing
   the work. It is spawned from `main.gd` and fires on `cpr_completed`. Either review it or
   delete it and its `_spawn_debrief_screen()` hook.
2. **`HANDOFF_2026-08-31.md` §2 is stale.** Item 5 (yellow breaker) was fixed long ago;
   items 2 and 3 may be too. Do not treat that list as a backlog without checking.
3. Decision points — see `DECISION_POINTS.md`. Designed, nothing built.
4. Unchanged from the previous handoff: AED voice audio, metronome, negative tone for the
   breathing-check result; editor gizmos on `CprRig` never draw; remove the compression
   fast-forward before shipping.

## 7. Tuning

Everything worth adjusting without touching code:

- `CprRig` → **Body pointers** → `point_mouth_pos` / `point_chest_pos`. Both defaults were
  guessed and never tuned against the body. Pink cross gizmos mark them in the editor.
- `casualty_pointers.gd` — `PILL_OFFSET`, `PILL_MIN_HEIGHT`, `FONT_SIZE`, `APPEAR_SECONDS`.
- `casualty.gd` — `AIRWAY_TILT_SECONDS` (0.55).
- `hud.gd` — `MESSAGE_BOTTOM_MARGIN` (92), `MESSAGE_INK_DARKEN` (0.25).
