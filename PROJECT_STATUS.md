# LVR CPR — Project Status

**Single source of truth for the state of play.** Updated 2 Sep 2026.

Read alongside:

| File | What it is |
|---|---|
| `CPR_CONTRACT.md` | The behavioural spec for the CPR phase — what happens, in what order, and why. |
| `ARCHITECTURE.md` | The engine-level rules and traps. Each one has already cost a debugging session. |
| `docs/archive/` | Superseded handovers, kept only for their reasoning. Nothing in there is current. |

Project: `C:\Users\NAD24\Documents\Work\Freelance\HV Exercices Simulations\LVR CPR\lvr-cpr`
Godot 4.7.2, Compatibility (OpenGL) · Blender 5.2 · Git repository since 3 Sep 2026
(local only, no remote — created as a rollback point for the overnight run).

---

## 1. What this is

A first-person Low Voltage Rescue and CPR training simulation set in an electrical
switchroom. The trainee plays the Safety Observer on a live LV job. They identify the
rescue kit, recognise and isolate the hazard, watch a worker take a shock, break contact
with an insulated crook, drag the casualty clear, run the primary survey and then perform
CPR with an AED. Every action is graded and reported in a debrief.

**Design intent:** this is not a clinical CPR trainer. The trainee learns real CPR from an
instructor. The exercise teaches the *shape* of the response and the *decisions inside it*.
Rescue breaths, rhythm analysis and the recovery position were cut deliberately, not
forgotten. Do not re-add them without asking.

The organising principle everywhere: **the simulation does not protect the trainee from a
choice. It records it.** Wrong pad sites stick silently. Compressions before the call for
help are permitted. The only actions that stop the run are the ones that kill the rescuer.

---

## 2. Working workflow

The scoped sub-agent / file-ownership / frozen-file workflow described in the archived
handovers is **retired**. There are no per-file permissions and nothing is frozen.

Two practical cautions survive it, and they are engineering facts rather than process:

- `main.tscn` is best left alone by hand. CPR nodes are instanced programmatically and the
  `ControlRoom` subtree is rebuilt wholesale on every `.blend` reimport, so editor
  NodePaths into it go stale silently. Add things from code.
- `events.gd` holds past-tense facts only. Adding a signal is fine; adding a *command*
  signal is not what the bus is for.

---

## 3. Current state — what is built and working

### The full run, end to end

| Beat | State |
|---|---|
| Kit check, stage 1 — select the 6 LV rescue items off a bench of 16 | working |
| Kit check, stage 2 — name each selected item on a diegetic in-world panel | working |
| Review-and-confirm card for both, full screen, Correct or Confirm | working |
| Opening brief and closing card | working |
| Identify the hazard at the breaker panel (full-screen tick list) | working |
| Open the breaker board | working |
| Hang the ISOLATE HERE sign at the isolation point | working |
| Worker walks in, takes the shock, arc FX at the panel | working |
| Don insulated gloves | working |
| Retrieve the insulated crook from the rack | working |
| Break contact with the crook (20 s time limit) | working |
| Drag the casualty to the safe area | working |
| Throw the breaker handle to isolate | working |
| Check for a response | working |
| **Choice card — "call for help" vs "perform CPR"** | working |
| Call for help on the two-way radio (completes both help + AED steps) | working |
| Open the airway | working |
| Hold the breathing check at the mouth, 5 s | working |
| Open the shirt | working |
| Compression set 1 — 30 reps, depth + rate scored | working |
| Fetch the AED, place it beside the casualty | working |
| Pad placement — 5 sites, 2 correct, wrong ones accepted silently | working |
| Stand clear, deliver the shock | working |
| Post-shock — two pills, one of them the wrong move | working |
| Compression set 2 — 30 reps | working |
| Debrief screen — score, checklist, correct order vs actual order | working |
| SCORM 1.2 reporting | working, verified against a mock LMS; not yet run on the client's own |

### Systems

- **Assessment.** 18 graded steps in `resources/procedures/lvr_cpr_procedure.tres`.
  Weighted scoring with a quality factor, out-of-order at ×0.5, late at ×0.75, critical
  steps, and a fatal path that zeroes the run. Pass mark 80 %.
- **Audio.** 10 AED voice lines, metronome at 110/min, breathing-check negative tone. All
  present in `audio/`. `aed_voice.gd` is asset-optional — a missing file degrades to a
  timed text line rather than breaking the beat.
- **Debrief.** Score, pass/fail, the full checklist, and two side-by-side sequence columns:
  the correct order against the order the trainee actually did it in.
- **Fail screen.** Only the two fatal outcomes reach it (see §5).
- **Headless regression.** `scripts/cpr/cpr_headless_test.tscn` — passing as of this
  writing, exit 0, all assertions.

### Deprecated and removed

The `DecisionPoint` / `DecisionOption` / `DecisionList` resource system was designed as a
blocking full-screen modal for branch moments. It is **superseded by the body pointer pills
and the in-world choice card**, which do the same job without taking the screen away or
releasing the mouse. The three scripts and two authored `.tres` files were unreferenced dead
weight and now live in `docs/archive/deprecated_decisions/`. `docs/archive/.gdignore` keeps
Godot's importer out of that folder — without it the archived `.tres` files are still scanned
and fail to resolve their scripts. If you archive anything else under `res://`, put it there.

The one idea worth keeping from that design, and the rule the choice card follows: **a choice
chooses an intent, it never performs the act.**

---

## 4. What is better than the previous exercise

Worth stating plainly, because it is the substance of this delivery:

1. **Interaction is diegetic.** The old exercise drove treatment from a screen-space menu
   listing ten actions. That is gone. The mouse stays captured for the whole run, the
   crosshair is the cursor, and everything is a physical act on a physical object — the
   radio on the bench, the crook on the rack, the sign on the board, the pads on the chest.
2. **Body-anchored contextual pointers.** Treating the casualty raises glass pills anchored
   to the part of the body each one concerns, with a leader line to it. Two tracks (airway
   and chest) run independently so the trainee is not forced through an artificial order.
3. **The compressions are a real minigame.** Press for the downstroke, release for the
   recoil, depth measured off hold length, rate off press-to-press interval, against a fixed
   110/min metronome. Depth and rate are scored per rep, not assumed.
4. **The AED talks.** Ten voice lines drive the pad and shock beats the way a real unit does,
   with supersede logic so a line never talks over the one that replaced it.
5. **Decisions are assessed, not just actions.** The choice card at the primary survey, the
   silent wrong-pad acceptance, and the post-shock gotcha all record what the trainee
   *chose* — which is more than a checklist of what they managed.
6. **The debrief actually teaches.** Score, per-step status, and the trainee's own sequence
   next to the correct one. Nothing tells them they were wrong in the moment; everything
   surfaces at the end, once.
7. **The room looks right.** Casualty mesh defects (duplicate faces, bad seam normals) and
   the clothing metalness bug that turned the armpits black are both fixed at import, with a
   regression scene (`tools/check_casualty_geometry.tscn`) to keep them fixed.
8. **The two assessment lists are full-screen, the treatment UI is not.** The hazard
   list and the shared review card are screen-space with a real cursor, because they
   are long prose and the client asked for a menu that is easier to read. Everything
   that acts on the world or on the casualty - the kit naming menu included - is still
   diegetic, mouse captured, crosshair-picked. `CPR_CONTRACT.md` section 4.0 carries
   the rule and this exception to it.

---

## 5. The two fatal outcomes

Everything else is graded and continues. These stop the run:

1. **Contacting an energised casualty** without the insulated crook and gloves, while the
   worker is still on the conductor. *"The current passed through you and there are now two
   casualties."*
2. **Delivering the AED shock while kneeling at the casualty.** The unit has already said
   stand clear; the trainee is in contact with the patient at the moment of discharge.

Neither is a trap. Both are preceded by an explicit instruction.

---

## 6. Open items

### Before the client build goes out

1. **Ship `build/LVR CPR.exe`, not the one in the project root.** The root `LVR CPR.exe`
   is a *debug* export — verified by the template marker in the binary — which means the
   `[F10]` dev jump-to-stage menu, the `[F8]`/`[F9]` probes, the free camera and, most
   importantly, **the compression fast-forward** are all live in it. The fast-forward lets a
   trainee skip 20 of the 30 compressions after 10 good reps, which is not something to hand
   a client for evaluation.

   All four are gated on `OS.is_debug_build()`. A clean release export was produced on
   2 Sep at `build/LVR CPR.exe` (365 MB, self-contained, PCK embedded) and the release
   template marker was verified. That is the build to send. Either delete the root debug
   `.exe` or leave it for local testing — but do not attach it to anything.
2. **The SCORM package reports nothing unless it is rebuilt from this commit or later.**
   Fixed now, but worth recording what shipped. `scorm_shell.html` loads
   `SCORM_API_wrapper.js` and `lms.gd` drives every write through `pipwerks.SCORM.*`, and
   that wrapper had never been in the repo. Because the shell guards on
   `typeof pipwerks !== 'undefined'`, the course ran, played perfectly and told the LMS
   absolutely nothing — the one failure mode that looks like success from every angle
   except the LMS's. The wrapper is now vendored at `scorm/vendor/SCORM_API_wrapper.js`
   (pipwerks v1.1.20180906, MIT, byte-identical to upstream), so every package
   `tools/make_scorm.py` builds from here on carries it, and the script still prints
   `NO SCORM REPORTING IN THIS PACKAGE` if it ever goes missing again. **Any zip built
   before this commit should be treated as non-reporting and replaced.**

### Nice to have

3. **Casualty tooltip text.** `casualty_interactable.gd:63` still returns "Treat the
   casualty"; the requested wording was "interact with casualty".
4. **Dead step ids.** `casualty.gd` still calls `Assessment.complete()` for seven ids that
   were retired from the procedure resource (`check_breathing`, `compressions_started`,
   `compressions_resumed`, `pads_placed`, `shock_delivered`, `signs_of_life`,
   `recovery_position`). They are harmless no-ops that each emit one `push_warning`. Either
   delete the calls or re-author the steps.
5. **Editor gizmos on `CprRig` never draw.** Quality-of-life for tuning anchors, nothing
   more. The simpler fix is a real `Camera3D` child per anchor — Godot draws the frustum for
   free and gives a Preview button.
6. **`[C] Crouch / stand up` chip appears early**, because `enter_cpr_phase()` fires at
   `PRIMARY_SURVEY`. Holding it back until the breathing check has been offered was proposed
   and never decided.

---

## 7. Build and test

### Headless regression — the fast loop

```bash
"C:/Program Files/Godot.exe" --headless --path . res://scripts/cpr/cpr_headless_test.tscn
```

Exits 0 and prints `cpr_headless_test: all assertions passed.` Three leaked ObjectDB
instances and one resource-in-use error at exit are expected teardown noise, not failures.

The suite, all 15 green as of 18 Sep: `cpr_headless_test`, `check_procedure_order`,
`check_kit`, `check_kit_correction`, `check_hazard_assessment`, `check_blender_assets`,
`check_sign_reachable`, `check_help_card`, `check_run_order`, `check_objective_pill`,
`check_review_panel`, `check_torch_step`, `check_sign_gate`, `check_injury_survey`,
`check_lms`. `check_spawn_gate` still fails — 4 assertions, pre-existing, unrelated,
not chased.

The last four are new with the 4 Sep changes: the shared review-and-confirm card,
the torch step and the two run-ending faults it fixed. Note what the suite still
cannot see — `docs/PLAYTEST_2026-09-04_pass3.md` section 2 records two faults it
was blind to, both found by playing the thing.

Other checks, same pattern: `tools/check_casualty_geometry.tscn`, `tools/check_aed_voice.tscn`,
`tools/check_shock_skip.tscn`.

### Testing the SCORM reporting

`check_lms` covers the GDScript half — which data model elements are written, the 1.2
vocabularies, the 4096-character cap, and that `uri_encode()` survives the trip through
`decodeURIComponent`. It cannot cover the JavaScript half, because outside a browser every
`Lms` call is a no-op by design; that is precisely how a package with no wrapper in it
passed every check and still reported nothing.

For the other half there is a mock LMS. From the project root:

```bash
python -m http.server 8777
```

then open `http://localhost:8777/tools/scorm_test_harness.html`. It puts a strict
SCORM 1.2 `API` object in the parent window, frames the export, and logs every call. A
correct launch shows `LMSInitialize` → `lesson_status = incomplete` → `LMSCommit`
within a few seconds. Quitting from the pause menu should add `lesson_status`,
`cmi.core.exit` (empty), a commit and `LMSFinish`. The mock rejects unknown elements,
read-only writes, bad vocabulary and over-length strings, so a red line there is a bug in
the course, not in the harness.

### Release build for the client

```bash
"C:/Program Files/Godot.exe" --headless --path . --export-release "Windows Desktop" "build/LVR CPR.exe"
```

The preset embeds the PCK, so the `.exe` is self-contained. Ship it with the generated
`LVR CPR.console.exe` omitted unless you want a console window for bug reports.

### SCORM package for the LMS

```bash
"C:/Program Files/Godot.exe" --headless --path . --export-release index build/scorm_build/index.html
python tools/make_scorm.py
```

Out comes `build/LVR_CPR_SCORM12.zip` (~290 MB), manifest at the archive root. The loose
export files stay in `build/scorm_build/`, so `build/` itself holds only the two things
anyone ships — the `.exe` and the `.zip`.

Two empty files in there are tracked on purpose, so leave both:

- `build/.gdignore` keeps Godot's filesystem scan out of that tree (a `.gdignore` covers
  the folder and everything under it), and so keeps a 260 MB PCK, a 39 MB wasm and a
  370 MB exe from being folded into the next export's PCK.
- `build/scorm_build/.gitkeep` keeps the folder existing on a fresh clone. Godot does not
  create its target folder — it stops with `Target folder does not exist or is
  inaccessible` and writes nothing. `mkdir build/scorm_build` if it ever goes missing.

### Live inspection

`godot-mcp run_project`, wait ~15 s for the interaction server, then `game_eval`.

**A dev run takes the screen.** The window is plain exclusive fullscreen and focusable,
which is the default and what the client gets. A `no_focus` windowed dev run was built on
4 Sep and reverted the same day: it did keep the foreground, but an unfocusable window
cannot be played by hand at all, including from the editor's play button. `ARCHITECTURE.md`
§1 records why the cheap version of that idea does not exist, so it is not re-attempted
from scratch.

**If the MCP client will not reconnect**, talk to the game directly: newline-delimited JSON
on `127.0.0.1:9090`, `{"id":1,"command":"eval","params":{"code":"..."}}`. It answers
regardless. `screenshot` comes back base64 on the same socket.

**Never reach for a property or a method you have not checked.** A bare `.rep_count` on
CompressionDriver — a property that does not exist — broke into the debugger and wedged the
run permanently, the same failure the arity warning describes. In `game_eval`, reach through
`obj.get("prop")` and `obj.has_method(...)`, which return null and false instead of
throwing.

Screenshot from inside the game:

```gdscript
get_viewport().get_texture().get_image().save_png("<path>/shot.png")
```

Staging traps that cost time: the kit-check modal blocks the ray at startup — clear it with
`get_tree().current_scene.get_node("DevMenu")._force_close_blocking_screens()`. Never
`game_eval` a standalone lambda or a method the object may not have; it breaks into the
debugger and hangs the game for 30 s.

---

## 8. Tuning without touching code

- `CprRig` → **Body pointers** → `point_mouth_pos` / `point_chest_pos`. Both defaults were
  guessed and never tuned against the body.
- `CprCameraRig` → `look_yaw_limit_deg` (110), `look_pitch_min_deg` (−80), `look_pitch_max_deg` (55).
- `casualty_pointers.gd` — `PILL_OFFSET`, `PILL_MIN_HEIGHT`, `FONT_SIZE`, `APPEAR_SECONDS`.
- `casualty.gd` — `AIRWAY_TILT_SECONDS` (0.55).
- `hud.gd` — `MESSAGE_BOTTOM_MARGIN` (92), `MESSAGE_INK_DARKEN` (0.25).
- `breathing_check.gd` — `HOLD_MS` (5000).
- `compression_driver.gd` — `REP_TARGET_SET_1` (30), `REP_TARGET_SET_2` (30 — a full
  second set, same as the first; this line said 10 and had not been true for a while).
- `procedure_list.gd` — `pass_mark` (80).

---

## 9. Working preferences

- **Division of labour: you implement, the user tests.** That is the point — it saves the
  token budget that launching and driving the game consumes. Do not run the project, drive
  it via `game_eval` or take in-game screenshots to verify your own work unless the user
  explicitly asks for a playtest. Implement, run the headless checks, and hand it over.
  **Suspended for unattended runs**, where there is no one awake to test — see
  `docs/OVERNIGHT_PLAN.md` §0. An agent working alone must verify its own work.
- Replies 3–4 lines unless detail is asked for.
- Execute directly via MCP; hand over only genuinely small edits to do by hand.
- Targeted patches to existing `.gd` / `.tres` files rather than whole-file rewrites.
  Reserve whole-file writes for new files.
- Do not spawn sub-agents or workflows unless asked. (Asked, for the overnight run of
  3 Sep 2026 — `docs/OVERNIGHT_PLAN.md`.)
