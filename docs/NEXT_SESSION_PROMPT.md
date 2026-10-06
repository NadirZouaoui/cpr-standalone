# Prompt for the next session — paste everything below the line

---

LVR CPR training simulation — implement four ratified changes
(Godot 4.7.2 + Blender 5.2)

PROJECT: C:\Users\NAD24\Documents\Work\Freelance\HV Exercices Simulations\LVR CPR\lvr-cpr

This continues the session of 4 Sep 2026. Everything in this prompt was decided
by me (Nadir) at the end of that session. **Do not re-litigate any of it and do
not re-derive it from the codebase.** Where it says "ratified", I said yes.

## READ FIRST, in this order

1. `docs/CLIENT_CONFORMANCE_2026-09-04.md` — the audit that produced this work.
   §3 is the list of content nobody at the client end ever asked for; §7 is the
   bug list. **Read §3 before you write any client-facing text.**
2. `docs/PLAYTEST_2026-09-04_pass2.md` §5 (open items) and §6 (untested).
3. `ARCHITECTURE.md` §1-2, `CPR_CONTRACT.md`, `PROJECT_STATUS.md`.

Read all of these as claims to be checked, not as facts. Across three sessions,
several confident "diagnoses" written into this codebase turned out to be wrong,
and three run-ending bugs were reached by doing exactly what the game instructed.
`CPR_CONTRACT.md` §6.2 is known-stale — see §7.3 of the audit.

## STATE

- HEAD is `659d913`. Git is local only, **no remote — do NOT push.**
- 10 headless checks green: `cpr_headless_test`, `check_procedure_order`,
  `check_kit`, `check_kit_correction`, `check_hazard_assessment`,
  `check_blender_assets`, `check_sign_reachable`, `check_help_card`,
  `check_run_order`, `check_objective_pill`.
  `check_spawn_gate` fails — **PRE-EXISTING, don't chase.**
- Uncommitted and **none of it yours to resolve**: `LVR CPR.blend` (my re-save),
  `main.tscn` (editor churn from a .blend reimport — safe to discard or keep,
  **ask me before committing it**), root `mcp_interaction_server.gd` (godot-mcp's,
  restored on every launch, leave untracked), three `tools/*.gd.uid` files.

---

# THE WORK

Four changes. All four are the client's, relayed by me, except where marked
"ours" — those need my sign-off on the wording before they ship, but build them.

## Decision 1 — score the FINAL answer, not the first (ratified)

Both the kit check and the hazard assessment currently grade the **first**
attempt and record the correction as worth nothing
(`kit_bench.gd:24-31`, `hazard_assessment.gd:26-31`).

That rule exists only because the game currently tells the trainee which lines
were wrong, which would make correcting free marks. Change 3 removes that
telling. So the reason is gone: **grade the final answer.** Delete the
first-attempt-scores machinery in both places rather than leaving it inert.

Keep recording both attempts for the debrief transcript — the client explicitly
asked for "the correction noted".

## Decision 2 — delete the lighting hazard (ratified)

Remove the entry `lighting_lost_on_isolation` from
`resources/hazards/hazards_pass1.tres:49-56` entirely.

It describes the room going dark on isolation. **The room does not go dark and
will not** — I have decided against it, the game is not designed for it. As it
stands a trainee is marked down for failing to perceive something that does not
happen. Confirmed on screen on 4 Sep.

Pass 1 drops from 8 entries to 7 (4 real, 3 distractors).
`tools/check_hazard_assessment.gd` may hard-code counts — check it.

## Decision 3 — the review-and-confirm panel, and stop marking wrong answers

This is the client's request, twice over, in their own words:

> "when yu identify the contents of the bag that should be displayed and if
> incorrect should be able to correct at that stage with the correction noted"
>
> "We need to Identify the hazards but can this be a drop down menu so its
> easier please"

**One shared panel, used by both.** Build it once. Do not write two.

Behaviour, both places:
- Trainee makes their picks.
- They submit.
- A card lists back **what they picked** — items with the names they gave them,
  or hazard lines as ticked.
- Two choices: **Correct** (return to picking, everything still ticked) or
  **Confirm** (locks it in, scores it).

**Nothing on that card says which picks are right or wrong.** For hazards this
is a change: today the wrong lines go amber and the panel says "Not a complete
assessment - the marked lines are wrong". That marking, `retry_notice`, and the
`hazard_answer_marked` signal all go.

Follow the existing idiom: a SubViewport on a billboarded quad, drawn in code,
picked with the crosshair. Copy `hazard_panel_3d.gd`'s construction. The mouse
stays CAPTURED — see `CPR_CONTRACT.md` §4.0. **No Area3D mouse picking.**

## Decision 4 — merge the two kit stages into one (ratified)

Today the kit check has two stages: sweep the bench ticking items
(`kit_selected`, weight 6), then name each one you ticked (`kit_identified`,
weight 8).

**Make it one interaction.** Clicking an item on the bench brings the naming
menu up directly. Naming it is what claims it as kit. Items never clicked are
items you say are not in the bag. Then submit → the review panel of Decision 3
→ Correct or Confirm.

Consequences you must handle:
- **One procedure step, not two.** Delete `kit_selected`
  (`lvr_cpr_procedure.tres:6-13`). Keep `kit_identified`, retitle if needed,
  **weight 14** (the two old weights added).
- **The grading formula is new and is OURS, not the client's.** Default:
  `quality = 0.5 * selection_accuracy + 0.5 * naming_accuracy`, where selection
  accuracy counts correct inclusions *and* correct exclusions across the whole
  manifest, and naming accuracy is correct names over items named. Implement
  that, and **flag it to me in your handover as an invented decision** — the
  audit's §3 exists because this project has form for shipping invented scoring
  as though the client chose it.
- Four checks break: `check_kit`, `check_kit_correction`,
  `check_procedure_order`, `check_run_order`. Rewrite them, do not delete them.
  `check_run_order` is the one that matters — it is the only test that walks a
  whole clean run in order.
- The per-item "you named that wrong, try again" correction **stays**. The
  client asked for exactly that. It leaks nothing about kit membership: naming a
  hammer "Claw Hammer" is a correct name for an item that is still not kit.

### 4a — new naming distractors (ratified, wording approved)

`kit_bench.gd:322-337` draws the wrong answers from the manifest itself, i.e.
from other objects on the bench. A trainee can solve the menu by looking round
the room. Replace that pool with plausible LVR/CPR equipment **that is not in
the room**. I have approved these eight:

> High Voltage Tester · Hooking Pole · Insulating Mat · Earthing Lead ·
> Voltage Proving Unit · Resuscitation Face Shield · Burns Dressing Pack ·
> Insulated Shears

Put them in the manifest resource, not in code, so they can be re-authored
without a rebuild — same reasoning as the hazard lists. The asked item's own
true title must always be among the choices.

## Decision 5 — the torch becomes a step (ratified)

The client asked: *"also turn on the torche so you can see when the power goes
out"*. I have ruled out the blackout. Instead: **taking the torch is a
precaution step, exactly like the gloves.**

- New step in `lvr_cpr_procedure.tres`, category `preparation` or
  `scene_safety`, **weight 4, not critical**.
- Completed by picking the `Flashlight` up off the bench
  (`scripts/interaction/tool_rack.gd:105-107` already binds it as a pickup).
- **It gates nothing.** Missing it costs 4 marks and shows in the debrief.
- No light, no on/off, no blackout. Do not build any.

## The two bugs — already diagnosed, do not re-diagnose

**Bug 1 — the sign can be hung before the second hazard check, and that starts
the incident.**
`scripts/interaction/isolation_sign_mount.gd:53` — `can_interact()` asks only
`enabled and armed and not _hung and not SimState.is_preamble()`. It never asks
whether `hazards_reassessed` is complete. Hanging the sign is what sends the
worker in to be shocked (`scripts/interaction/breaker_panel.gd:346`). So a
trainee can open the board, skip the reassessment, hang the sign, and find
themselves with a casualty on the conductor and a 20-second timer running while
the step that gates `crook_retrieved` is still outstanding.
**Fix:** the mount refuses until `hazards_reassessed` is complete, and says why
through the normal prompt path. Add a headless check.

**Bug 2 — the ambulance arrives before the injury survey is finished.**
`scripts/cpr/cpr_station.gd:709-720` — `survey_injury()` completes
`injuries_checked` and jumps to `STATE_HANDOVER` the moment the site carrying
the finding is checked. That site is the hands
(`scripts/casualty/casualty.gd:986-1002`). Check the hands first and the
ambulance arrives with two sites unlooked-at. I reproduced this: I checked hands
and feet and it moved on.
**Fix:** all three sites must be surveyed before `injuries_checked` completes and
the spine advances. The finding still fires its own message when found. Add a
headless check.

---

# HOW TO RUN THIS

## Step 0 — you, alone, first. No agents.

Three things are touched by more than one lane. Do them by hand and commit
before spawning anything, or the agents will collide:

1. New signals in `scripts/core/events.gd`.
2. **Every** edit to `resources/procedures/lvr_cpr_procedure.tres` — merge the
   kit steps, add the torch step. Nothing else may touch this file.
3. Build the shared review panel (Decision 3). Both later lanes consume it.

## Step 1 — four agents in parallel, strict file ownership

| Lane | Job | Owns these files, and only these |
|---|---|---|
| A | The two bugs | `isolation_sign_mount.gd`, `cpr_station.gd`, two new `tools/check_*` |
| B | Hazards: review panel, no marking, final-answer scoring, delete the lighting line | `hazard_assessment.gd`, `hazard_panel_3d.gd`, `hazards_pass1.tres`, `check_hazard_assessment` |
| C | Kit: merge the stages, review panel, final-answer scoring, new distractors | `kit_bench.gd`, `kit_identify_panel.gd`, `kit_check.gd`, `lvr_kit.tres`, `check_kit`, `check_kit_correction` |
| D | Torch step | `tool_rack.gd`, `rescuer.gd` |

Lane C is roughly twice the size of B. Give it the most room.

**The agents write code and reason. They do NOT launch Godot.** You run every
Godot invocation yourself, serially. Four headless engines against one project
will fight over the import cache, and a failed import silently writes
`valid=false` into `LVR CPR.blend.import`, after which every later import skips
the file without a word. Recover with `git checkout -- "LVR CPR.blend.import"`.

## Step 2 — you, alone, again

1. Fix the broken checks, run the whole suite.
2. **Launch the game and walk the entire run by hand.** Not optional.
   On 4 Sep a run-ending bug sat behind ten green tests for a full day: the
   breathing check and every compression rep refused on the body, because the
   crosshair test named a hidden mesh. `check_run_order` passed throughout,
   because it drives the station's *methods* and never touches the crosshair.
   The tests cannot catch that class of fault. Only playing it can.
3. Write a playtest report, `docs/PLAYTEST_<date>.md`, and say plainly what you
   did not manage to see on screen.

---

# MACHINE NOTES — these cost previous sessions real time

- Verify headlessly and constantly:
  `"C:/Program Files/Godot/Godot_v4.7.2-stable_win64_console.exe" --headless --path . res://scripts/cpr/cpr_headless_test.tscn`
  3 leaked ObjectDB instances + 1 resource-in-use error at exit are expected.
- In game: godot-mcp `run_project`, wait ~15 s, then `game_eval` / `game_screenshot`.
  **A dev run takes the foreground and the mouse — plain exclusive fullscreen, by
  design.** A no-focus windowed run was built on 4 Sep and reverted the same day
  (`0c77946`) because an unfocusable window cannot be played by hand at all,
  including from the editor's play button. `ARCHITECTURE.md` §1 has the measured
  engine facts. **Do not re-attempt it without asking me.**
- Clear the startup modal with
  `get_tree().current_scene.get_node("DevMenu")._force_close_blocking_screens()`
  — one call is enough.
- **NEVER `game_eval` a bare property read or method call you have not checked
  exists.** Both wedge the game permanently in the debugger. Use `obj.get("prop")`
  and `obj.has_method(...)`, which return null / false instead of throwing.
- Screenshots lag evals by seconds. For any beat under ~5 s, set
  `get_tree().paused = true` immediately before the screenshot.
- Synthetic input: `Input.parse_input_event()` with an `InputEventAction` works
  for `interact` and `crouch`. **The compression minigame does not read the
  action** — `compression_driver.gd:179-192` hard-codes left-click and Space, so
  drive it with a raw `InputEventKey` for `KEY_SPACE`.
- CPR clickables (AED, pads, shock) go through `CprInteractBridge`, not
  `InteractionRay.current`. Aim, then call the bridge's `_unhandled_input`.
- At `PAD_PLACEMENT` the camera is owned by `CprCameraRig`; aim by setting its
  `_yaw_offset` / `_pitch_offset`, not by moving the player.
- If godot-mcp will not reconnect: kill every Godot process whose window title
  contains DEBUG, confirm port 9090 is free, one `run_project`, wait ~15 s. Or
  talk to the game directly — newline-delimited JSON on 127.0.0.1:9090,
  `{"id":1,"command":"eval","params":{"code":"..."}}` and
  `{"id":1,"command":"screenshot"}`.
- Blender import rpc_port is 6011 (Editor Settings > FileSystem > Import >
  Blender). If a check flips from passing to failing with no code change,
  **suspect the import cache before the work.**

# COMMIT RULES

- **Commit after every fix. Explicit paths only, never `-A`.**
  `git -c user.email=nad0479@gmail.com -c user.name=Nadir commit -m "..."`
- End every message with: `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`
- Long messages: write to a file with the Write tool and use `-F`. **Do not build
  them with shell heredocs** — backticks and quotes in the body break the command.
- The `.blend` is ~64 MB and every commit stores a full copy (`.git` is >220 MB).
  Milestones only. Ask me before committing `LVR CPR.blend` or `main.tscn`.

# GROUND RULES

- **Do not change client-facing content beyond what this prompt ratifies.** Step
  titles, prompts, hazard lines, kit rationales, weights and scoring are already
  full of decisions the client never made — that is what
  `docs/CLIENT_CONFORMANCE_2026-09-04.md` §3 documents. Do not add to the pile.
  Anything new you must invent, build it and **list it in your handover as
  invented**.
- Outright bugs you may fix as you go. Say so when you do.
- **Report failures honestly.** A fix claimed and not verified is worse than one
  left open, and so is a requirement marked done that you only checked against
  our own docs.

Start with Step 0.
