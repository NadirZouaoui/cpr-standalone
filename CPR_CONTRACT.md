# CPR Phase — Implementation Contract

This file is the spec for the CPR phase: what it does, in what order, and why. It
describes behaviour, not permissions — nothing here is off limits to edit. Where a
decision was expensive to reach, the reasoning is recorded next to it; change it
deliberately rather than by accident.

State of play and open items: `PROJECT_STATUS.md`. Engine-level rules and traps:
`ARCHITECTURE.md`.

Nothing in this project is frozen. `main.tscn` is still best left alone in practice —
CPR nodes are instanced programmatically and the room subtree is rebuilt wholesale on
`.blend` reimport, so editor NodePaths into it go stale silently — but that is an
engineering caution, not a permission.

Revision 4 — 2 Sep 2026. Brought into line with what actually shipped.

---

## 1. Scenario spine

Eight states, one linear path, no branching.

| # | State | Camera | Player movement |
|---|---|---|---|
| 0 | `EXPOSE_CHEST` | free | free |
| 1 | `BREATHING_CHECK` | `Anchor_Head` | locked |
| 2 | `COMPRESSIONS_1` | `Anchor_Kneel` | locked |
| 3 | `AED_FETCH` | free | **free** |
| 4 | `AED_DEPLOY` | free | free |
| 5 | `PAD_PLACEMENT` | `Anchor_PadSide` | locked |
| 6 | `SHOCK` | `Anchor_Shock` | locked |
| 7 | `COMPRESSIONS_2` | `Anchor_Kneel` | locked |
| 8 | `COMPLETE` | released | free |

`AED_FETCH` / `AED_DEPLOY` is the only free-movement beat. It is deliberate — it
gives the phase a breath in the middle.

`[C]` (the `crouch` action) stands the trainee up out of `BREATHING_CHECK`,
`COMPRESSIONS_1`, `SHOCK` and `COMPRESSIONS_2` and kneels them back down, so the radio
stays reachable mid-procedure. `AED_FETCH` deliberately does not toggle — the trainee is
already up and walking. The bottom-left chip (`cpr_key_hint.gd`) reads the real binding
rather than hard-coding the letter.

---

## 2. Events bus signals

Already present in the `Events` autoload. Past-tense facts only, per project convention.

```gdscript
signal cpr_phase_entered()
signal breathing_checked(breathing: bool)
signal compression_delivered(depth: float, rate: float, index: int)
signal compression_set_completed(count: int, assisted: bool)
signal aed_picked_up()
signal aed_placed()
signal aed_pad_hovered(site_name: String)
signal aed_pad_placed(slot: int, correct: bool, site_name: String)
signal stand_clear_confirmed()
signal aed_shock_delivered()
signal cpr_state_changed(from: int, to: int)
signal cpr_completed(metrics: Dictionary)
```

### `cpr_completed` metrics dictionary

```gdscript
{
	"total_compressions":        int,
	"pct_in_depth":              float,   # 0.0-1.0
	"pct_in_rate":               float,   # 0.0-1.0
	"time_to_breathing_check":   float,   # seconds from phase entry
	"time_to_first_compression": float,
	"time_to_shock":             float,
	"pad_errors":                int,     # count of incorrect sites used
	"pads_correct":              int,     # 0, 1 or 2
	"assisted":                  bool,    # fast-forward was used
}
```

---

## 3. Node names resolved at runtime

**Runtime binders only.** Find by name in `_ready()` with a recursive search — use
`CprGhost.find_node()` / `CprGhost.find_nodes_with_prefix()`. Never editor-wired
`NodePath` exports: `.blend` reimports have dropped authored properties from
`main.tscn` before. On failure: `push_error` naming the exact string that was tried,
disable the node, do not crash.

Binding runs from `call_deferred("_build")`, never straight out of `_ready()` — the
`ControlRoom` .blend instance may still be settling on the frame a node enters the tree.

| Constant | Node | Type |
|---|---|---|
| `CASUALTY_ROOT` | the node the trainee drags | `Node3D` |
| `CASUALTY_CPR_MESH` | `Casualty_CPR_Posed` | `MeshInstance3D` |
| `AED_CABINET` | the AED on the cabinet — name set in `aed_station.gd` | `MeshInstance3D` |
| `AED_DEPLOYED` | `AED Defibrilator CPR` — duplicate authored at the drop position | `MeshInstance3D` |
| `PAD_SITE_PREFIX` | `PadSite_` | `MeshInstance3D` × 5 |
| `SKELETON` | `ControlRoom/Armature/Skeleton3D` | `Skeleton3D` |

### Pad site naming convention

Five conformed duplicate pad meshes on the casualty. Correctness is encoded in the
name so nothing needs authoring in the editor:

```
PadSite_Correct_Upper     <- upper right, below the clavicle
PadSite_Correct_Lower     <- lower left, below the armpit
PadSite_Wrong_01
PadSite_Wrong_02
PadSite_Wrong_03
```

A site is correct iff its name contains `Correct`. All five start hidden and are
revealed together as ghosts on entering `PAD_PLACEMENT`.

### Shape keys on `Casualty_CPR_Posed`

Resolve the blend shape **index by name**, never by literal index — glTF ordering is
not guaranteed across reimports.

| Name | Driven by |
|---|---|
| `Compression` | compression depth float, 0.0-1.0, every frame |
| `Shock` | one-shot tween 0 -> 1 -> 0 over 0.25 s |
| `EyesOpen_legacy` | never touched, stays at 0 |

---

## 4. Mechanics

### 4.0 Input model — READ THIS FIRST

**The game runs with `Input.MOUSE_MODE_CAPTURED`.** There is no visible cursor. Godot's
built-in Area3D camera picking (`mouse_entered`, `mouse_exited`, `input_event`) fires
its ray at a stale screen position, not the crosshair, and **will not work here**.

Every clickable thing in the CPR phase — pad ghosts, the AED on the cabinet, the AED
drop ghost, the shock — goes through `scripts/cpr/cpr_interact_bridge.gd`, which asks
the project's own crosshair interactor what is under the reticle and calls
`GhostTarget.set_hovered()` / `GhostTarget.activate()` accordingly.

No CPR file may build its own Area3D mouse-picking path.

**Two assessment screens are the documented exception, and they are outside the CPR
phase.** The hazard tick-list (`hazard_panel_3d.gd`) and the shared review-and-confirm
card (`review_panel_3d.gd`) are full-screen overlays with a real cursor: they raise
themselves as blocking UIs, which freezes the Player, kills the interaction ray and
releases the mouse the same way the kit brief already did. They are long prose lists,
and the client asked for the hazards to be "a drop down menu so its easier".

The rule above is unchanged for everything it was written about. Nothing on either
screen performs an act — ticking "wet floor" does not make the floor wet — so no
mis-click there can reach the casualty, which is what the rule protects. The kit
naming menu stays diegetic and crosshair-picked; treatment UI always will be.

### 4.1 Breathing check
Hold interact for 5.0 s with the crosshair on the casualty. Chest does not rise.
Release early aborts and re-prompts. Emits `breathing_checked(false)`.

Lengthened from the original ~3.0 s so the dwell reads as a real look-listen-feel rather
than a button that happens to be sticky. The protocol allows up to 10 s; 5 keeps the sim
moving without making the assessment feel skipped.

Two playtest fixes are load-bearing here and should not be undone:

- **The hold requires the crosshair on the casualty's own body collider.** It used to work
  pointed at the far wall. Off-body, the prompt reads "Aim at the casualty's mouth".
- **The progress indicator is a drawn ear pinned to the mouth** (`cpr_ear_2d.gd`), the same
  idiom the hands use on the sternum. A ring around the reticle lived here first and was
  removed — two progress indicators for one hold is one more than the trainee needs.

**It is not a gate, and this paragraph used to say it was.** The
"Start compressions" body pointer calls `CprStation.begin_compressions_early()`
(`casualty_action_menu.gd`), which moves the spine to `COMPRESSIONS_1` from any earlier
state without asking whether the check has happened. That is deliberate: skipping
straight to compressions passes over DRSABCD's B and C and the pulse check, and the
`compressions` availability rule says in place that this "is a mistake the trainee is
allowed to make and which the debrief will show". The sim behaves here exactly as it does
everywhere else — the wrong order is permitted and recorded, not blocked.

### 4.2 Compressions
Press = downstroke, release = recoil. Mouse or Space.

```gdscript
depth = clamp(hold_ms / 180.0, 0.0, 1.0)   # counts as good at >= 0.75
rate  = 60000.0 / press_to_press_ms        # rolling median of last 5; good 100-120
```

**All timing via `Time.get_ticks_msec()`.** Never frame deltas — WebGL2 frame pacing
inside a SCORM iframe is unreliable.

A rep counts on depth. Rate only colours the UI ring; it never blocks. The metronome
clicks at a fixed 110/min from state entry and never varies — it is the teaching
mechanism.

**Arming.** Reaching `COMPRESSIONS_1` is not the trainee saying they are ready — the
breathing check is assessed at the mouth with the shirt still on. `CprStation.compressions_armed`
stays false until the "Start compressions" body pointer is taken: the hands stay hidden and
reps are silently refused until then. The shock disarms it again (see §4.5).

**Set length is 30 reps in both states.** The second set was briefly shortened to 10; it is
a full set again, because a post-shock resumption that is a third of the length teaches that
the work gets easier after the shock, which is the opposite of true.

**Fast-forward (debug builds only).** After 10 consecutive in-depth reps, offer "Continue
compressions" on the `interact` action — never the compression input, which would fire the
skip on a normal rep. Fills to the target with a short animated overlay and sets
`assisted: true`; only the real reps score. `fast_forward_enabled` is
`OS.is_debug_build()`, so a release export never offers it and the trainee does all 30.

**`compression_set_completed(count, assisted)` must fire when the set ends**, by either
route. `COMPRESSIONS_1` hands off to `AED_FETCH` on that signal and nothing else; if it
never fires, the phase stalls.

### 4.3 AED handling
1. Trainee interacts with the AED on the cabinet -> it hides, `aed_picked_up`.
   Carried state is implicit; no hand-mesh attachment in v1.
2. `AED Defibrilator CPR` — hidden at start — is revealed as a ghost **in place**.
   No marker, no spawning: the mesh is already authored where it belongs.
   Interacting with it clears the ghost material and emits `aed_placed`.
3. Pads (§4.4).
4. **Shock is delivered by interacting with the deployed AED itself**, through the same
   crosshair bridge as everything else. `stand_clear_confirmed` is emitted by
   `ShockButton.arm()`, and the moment that matters is **the trainee standing up** —
   `CprStation._on_stood_up_for_shock()` calls it, because standing hands the camera back
   to the player and there is no anchor landing left to hang it on. (`arm()` is also
   reachable from a CPR camera move finishing while SHOCK is live; it is one-shot per
   entry either way.) The principle is unchanged and still right: standing clear **is**
   the stand-clear, and there is no separate confirm action. What is gone is the kneel
   back — SHOCK was removed from `STANCE_TOGGLE_STATES` because the invitation to kneel
   back "within reach of the unit" put the trainee in contact at the moment of discharge
   and ended runs. The AED then pulses (via `material_overlay`,
   never `material_override` — it must keep its real material) until interacted with,
   which emits `aed_shock_delivered` and fires the `Shock` blend shape.
5. The unit talks throughout. `aed_voice.gd` plays ten lines across the pad and shock
   beats, with supersede logic so a line never talks over the one that replaced it. It is
   asset-optional and purely reactive — it listens to Events and gates nothing, so a
   missing `.wav` degrades to a timed text line rather than stalling the beat.

**Delivering the shock while kneeling at the casualty is fatal.** `shock_button.gd` checks
`CprStation.trainee_at_anchor()` at the moment of activation: down at an anchor means hands
on the patient. The unit has already said stand clear, so this is an ignored instruction,
not a trap. It is one of only two fatal outcomes in the whole exercise.

### 4.5 After the shock — the resumption gotcha
`COMPRESSIONS_2` is entered with `compressions_armed` back to false, so the trainee is not
dropped into the minigame. They land on two body pointers: "Start compressions" at the
chest, and "Check for signs of life" at the mouth — the plausible wrong move. Taking either
retires the gotcha; only the compressions pill re-arms the minigame. The metronome stays
silent while the pills are up.

The gotcha only bites if resuming is itself a choice, which is why the disarm exists.

### 4.4 Pad placement — the puzzle
All five ghosts visible at once. Crosshair hover recolours. Interact places the pad:
the ghost material clears and the mesh renders with its authored material.

**Wrong sites are accepted silently.** The pad sticks, the exercise continues, no
negative tone, no re-prompt, no visual difference from a correct placement. The error
is recorded and surfaces only in the debrief. Two placements end the state regardless
of correctness.

This is a puzzle, not a drill — the trainee must commit to an answer without being told
whether they were right.

Placement order is not assessed.

The mouse stays CAPTURED for the whole CPR phase. Every interaction goes
through the crosshair and the `interact` action, so a visible cursor buys
nothing and costs clamped mouse-look.

---

## 5. Assessment steps

Three entries in `lvr_cpr_procedure.tres`:

| Step id | Requires | Weight | Weighting |
|---|---|---|---|
| `breathing_checked` | `airway_opened` | 8 | full / zero |
| `cpr_performed` | `breathing_checked` | 15, critical | scaled by `pct_in_depth` |
| `aed_used` | `cpr_performed` | 15 | halved per incorrect pad site |

Graded in `main.gd`: `breathing_checked` straight off `Events.breathing_checked` (it fires
long before the spine finishes), the other two off `cpr_completed` using
`Assessment.complete(step, quality)`. Before the quality factor existed, forty compressions
at 0 % in depth scored the same fifteen points as forty good ones — the one thing a CPR
trainer must not do.

`aed_used` with two wrong pads scores zero for that step but is still *completed*, not
failed: the AED was deployed and the shock delivered, so the step happened and satisfies
what follows it. It **never** triggers `Events.fatal_violation` — that is reserved for
outcomes where the *rescuer* dies.

These three sit inside an 18-step procedure covering the whole exercise
(`resources/procedures/lvr_cpr_procedure.tres`). Assessment applies ×0.5 for out-of-order
and ×0.75 for late on top of the weight and quality. Pass mark 80 %.

---

## 6. Floating UI

One `SubViewport` (512x512, `UPDATE_WHEN_VISIBLE`, `transparent_bg`) on a billboarded
quad. **Billboard on the Y axis only** — full billboard tumbles when the camera pitches
down at the kneel anchor.

The panel tweens (0.3 s) between per-state marker positions from
`CprRig.panel_for_state()`. It is never anchored to the sternum — that is where the
hands go. It fades out entirely during `AED_FETCH` / `AED_DEPLOY`.

That fade was a design call and it was **wrong on its own**: it left the trainee with no
instruction at the one moment they must find an object across the room, and the phase read
as having stalled after compressions. `CprStation.STATE_MESSAGES` now carries a centre
prompt for every state, and the two free-movement states are the only ones that repeat
theirs. Each line doubles as the receipt for the action that caused the transition
("AED collected — place it beside the casualty"), so instruction and confirmation never
stomp on each other.

| State | Panel content | Marker |
|---|---|---|
| Breathing | radial arc filling over the 5 s hold, "Observing..." | `Panel_Head` |
| Compressions | vertical depth column w/ green band, rate ring, `12 / 30` | `Panel_Kneel` |
| Pads | `1 / 2` + current AED instruction line | `Panel_PadSide` |
| Shock | "STAND CLEAR", then the interact prompt | `Panel_Shock` |

Text at ~48 px in the viewport; size the quad so it lands at 5-6 % of screen height.
Anything smaller is unreadable at iframe scale.

Update the viewport only when a value changes. Do not redraw a static counter at 60 fps.

### 6.1 The 2D layers, and why they are not viewport quads

Three things are drawn in screen space and anchored to world markers rather than rendered
into a billboarded viewport: the compression hands (`cpr_hands_2d.gd`), the breathing-check
ear (`cpr_ear_2d.gd`) and the treatment pointers (`casualty_pointers.gd`).

Text stays crisp at any distance — the old world-space card blurred when leaned into —
leader lines are a cheap two-segment polyline, there is no per-callout viewport, and pills
can be nudged apart in screen space. That last one is correctness, not polish: two
overlapping pills under the crosshair is an ambiguous click.

Picking is the crosshair against each pill's own `Rect2` (+6 px), nearest-to-centre wins
ties. No `Area3D`, no colliders — §4.0 still holds throughout.

### 6.2 The pre-CPR body pointers

`casualty_action_menu.gd` — still the node named `CasualtyActions` — is the sequence
controller for DRSABCD's R and A, presented as pills anchored to the body with leader lines
to the part each concerns. Two tracks advance independently so the shirt does not wait on
the airway work:

| Pill | Anchor | Appears when |
|---|---|---|
| Check for a response | mouth | not yet done |
| Open the airway | mouth | response done, airway not open |
| Check for breathing | mouth | airway open, spine still at EXPOSE_CHEST |
| Open the shirt | chest | response done, chest not exposed |
| Start compressions | chest | state **&le;** COMPRESSIONS_1. No chest requirement - see below |
| Check for signs of life | mouth | post-shock only — the §4.5 gotcha |

**The compressions row was wrong in this file until 4 Sep 2026** and is worth
reading twice, because what it describes is a trap the trainee is deliberately
allowed to fall into. The real rule is `state <= COMPRESSIONS_1` with **no chest
requirement at all** (`casualty_action_menu.gd`, `_available()`, the
`&"compressions"` branch). The chest requirement went when the client asked for
the first set with the shirt on and the shirt opened afterwards for the pads, and
nothing replaced it.

The consequence, stated plainly: **"Start compressions" is on the body from the
trainee's first interaction with the casualty, sitting at the top of the pill
stack above "Check for a response".** Taking it skips DRSABCD's B, C and the
pulse check. That is a permitted mistake and the debrief shows it - but a
document saying the pill needs an exposed chest hid the fact that the exercise's
most attractive wrong move is also its most prominent one. Recorded as item 3 of
`docs/CLIENT_CONFORMANCE_2026-09-04.md` §7.

Two pills hand over rather than acting: "Check for breathing" calls
`CprStation.begin_breathing_check()`, and "Start compressions" arms the minigame.

Sending for help is deliberately **not** here — it is a physical act with a physical object
(the two-way radio on the bench, `emergency_radio.gd`), which completes both `send_for_help`
and `call_for_aed` in one use.

### 6.3 The choice card

`choice_card_3d.gd`, spawned from `main.gd` as `HelpCard`. Fires once, on
`step_completed(check_response)`, and is moot if the radio call already went out.

> "The casualty is not breathing. What do you do first?" — *Call for help* / *Perform CPR*

**A choice card chooses an intent. It never performs the act.** Picking "Call for help"
does not place the call; it points at the radio, which is still a physical thing to walk to
and use. Picking "Perform CPR" is recorded as a violation against `send_for_help` and the
run continues — the radio stays live and still gradable, because a trainee who realises
halfway through the compressions that they skipped it must be able to get up and do it.

The card scores nothing of its own. It used to complete a `prioritised_help` step, which put
a second debrief row saying the same thing as the call five seconds later. The casualty
pills stand down while the card is up, so there is exactly one live direction at a time.

---

## 7. Where things live

A map, not a permissions table — edit whatever the task needs.

| Concern | Files |
|---|---|
| **Camera** | `scripts/cpr/cpr_camera_rig.gd` |
| **Floating panel** | `scripts/cpr/cpr_panel_3d.gd`, `scenes/cpr/CprPanel.tscn`, `scripts/cpr/cpr_panel_stub_emitter.gd` |
| **Compressions** | `scripts/cpr/compression_driver.gd`, `scripts/cpr/casualty_cpr.gd`, `scripts/cpr/cpr_hands_2d.gd` |
| **AED** | `scripts/cpr/aed_station.gd`, `scripts/cpr/pad_station.gd` |
| **Station / spine** | `scripts/cpr/cpr_station.gd`, `scripts/cpr/cpr_headless_test.gd` |
| **Input bridge** | `scripts/cpr/cpr_interact_bridge.gd`, `scripts/cpr/ghost_target.gd` |
| **Shock** | `scripts/cpr/shock_button.gd` |
| **Treatment pointers** | `scripts/ui/casualty_action_menu.gd`, `scripts/ui/casualty_pointers.gd` |
| **Breathing check** | `scripts/cpr/breathing_check.gd`, `scripts/cpr/cpr_ear_2d.gd` |
| **Audio** | `scripts/cpr/aed_voice.gd`, `scripts/cpr/cpr_cue_audio.gd`, `audio/aed/`, `audio/cues/` |
| **Choice card** | `scripts/ui/choice_card_3d.gd`, spawned in `scripts/main.gd` |
| **Debrief** | `scripts/ui/debrief_screen.gd` |
| **Key hint chip** | `scripts/cpr/cpr_key_hint.gd` |
| **Shared helpers** | `scripts/cpr/cpr_ghost.gd`, `scripts/cpr/cpr_rig.gd` |

`cpr_ghost.gd`, `ghost_target.gd` and `cpr_interact_bridge.gd` are the shared helpers —
use them rather than writing a second way to do the same thing.

---

## 8. Standing rules

- **GDScript only, unless Blender work is explicitly authorised.** The default remains:
  asset changes are reported back to the human as instructions, not executed. Nadir
  lifted this for the overnight run of 3 Sep 2026 (`docs/OVERNIGHT_PLAN.md` §0), which
  authored the `Compression` shape on the clothed mesh and the `Casualty_Recovery_Posed`
  mesh. No animation was added — the casualty's `AnimationPlayer` rule below still holds.
  The rule reasserts itself once that run is finished: do not open Blender again without
  being told to.
- **Runtime binders, never editor NodePaths.** Bind from `call_deferred("_build")`.
- **`Time.get_ticks_msec()`** for anything time-based. Do not reach for `delta`.
- **Never touch the casualty's `AnimationPlayer`.** `Casualty` is its single owner.
  Compressions and shock are blend shapes, driven through `casualty_cpr.gd` only.
- **Never build Area3D mouse picking.** See §4.0.
- **Instance CPR nodes programmatically** rather than adding them to `main.tscn`.
- **Verify in game.** `run_project` + `game_eval` and a screenshot beat a written
  request for someone else to look. The headless regression
  (`scripts/cpr/cpr_headless_test.tscn`) must still pass.

---

## 9. Integration seams

All five are now built. Recorded because they are the joins most likely to be broken by a
change made elsewhere.

1. **Instancing `CprStation`** — `main.gd::_spawn_cpr_station()`. `enter_cpr_phase()` is
   called from two places (`phase_changed` → `PRIMARY_SURVEY`, and
   `step_completed(chest_exposed)`) and is idempotent, deliberately: losing that race left
   `current_state` at −1 and the CPR camera never engaged. See `ARCHITECTURE.md` §2.
2. **Starting the breathing check** — owned by the "Check for breathing" body pointer, not
   by `chest_exposed`. Triggering it off the shirt forced shirt-before-airway, which is the
   wrong way round for DRSABCD.
3. **Grading** — `main.gd::_on_breathing_checked()` and `_on_cpr_completed()`, plus
   `debrief_screen.gd` listening for `cpr_completed`.
4. **Audio assets** — recorded and in `audio/`. `aed_voice.gd` finds new lines by filename;
   adding one needs no code change.
5. **`FpsArms`** — cut. Replaced by `cpr_hands_2d.gd`, drawn translucent hands world-anchored
   to `CprRig` and driven by `CasualtyCpr.current_depth()`, so they stay on the sternum while
   the look stays free. Do not re-add a 3D arms rig without asking.
