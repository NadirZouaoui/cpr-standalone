# Playtest pass 2 — 4 Sep 2026

Written for Nadir, picking up §4 of `docs/PLAYTEST_2026-09-04.md`. Everything
below was reproduced in the running game before it was changed and re-checked
after.

Suite: **11 green** at the time of writing — the nine from last pass plus
`check_dev_window` and `check_objective_pill`. `check_spawn_gate` still fails;
pre-existing, not chased. (`check_dev_window` was removed later the same day with
the window work it guarded — see the note in §1. The suite is 10.)

---

## 1. Godot no longer takes the screen, or the mouse

> **REVERTED, 4 Sep.** Nadir asked for the dev-run window changes to go back to
> default, and they have — commits `b268a1c`, `54d3443` and `10b8a98` are
> reverted, `check_dev_window` is gone, and a dev run is a plain focusable
> fullscreen window again. The trade below is why: an unfocusable window cannot
> be played by hand at all. The measured engine facts are kept in
> `ARCHITECTURE.md` §1 so the idea is not re-attempted from scratch. The rest of
> this section is left as written, as the record of what was built.

Asked for first, and it turned into two problems.

**Focus.** `project.godot` now carries `.editor` feature-tag overrides: a dev run
is a 1280×720 window with `no_focus` set, placed on the second screen. The base
values are untouched and an exported template has no `editor` feature tag, so the
client still launches fullscreen and focusable. Verified by recording the Win32
foreground window across a launch — unchanged.

**Mouse.** Fixing the focus broke the mouse, and you caught it before I did. The
game sets `Input.mouse_mode = CAPTURED` for the crosshair, and Godot's Windows
backend clips the cursor to the window whether or not it is focused — its own
release-on-deactivate handling hangs off `WM_ACTIVATE`, which a `no_focus` window
never receives. `GetClipCursor` was returning exactly the game's rect while the
foreground window belonged to something else. `window_focus_guard.gd` supplies
the missing half: it refuses every cursor grab and says so in the corner of the
window.

Two things that look like fixes and are not, both measured and both written into
the file so they are not retried:

- `DisplayServer.window_is_focused()` reports **true** for a window that has
  never been activated and is not the foreground window.
- Clearing `WINDOW_FLAG_NO_FOCUS` after boot — so the window could still be
  clicked into and played by hand — **is what causes that**. With the flag left
  alone the focus log is empty for a whole run; clearing it emits
  `APPLICATION_FOCUS_IN` immediately and `WM_WINDOW_FOCUS_IN` 60 ms later, for a
  window still in the background, and it never comes back.

**The trade, stated plainly: a dev run cannot be played by hand.** That includes
the editor's own play button. Delete the six `.editor` lines under `[display]` in
`project.godot` to get a normal window back; `check_dev_window` will fail and tell
you that you did. If you would rather have it the other way round, say so and I
will invert the default.

---

## 2. The handover siren — heard, measured, and its timing was wrong

**It plays, and it is audible.** Sampled every frame off the master bus:

| t after the finding | master peak | player |
|---|---|---|
| 0.03 s | — | playing, position 0.00 |
| 0.5 s | −51.1 dB | position 0.51 |
| 3.1 s | −31.7 dB | position 3.12 |
| 5.3 s | **−22.7 dB** (max) | position 5.35 |
| 6.5 s | silent | stopped |

The approach envelope is real and it reaches the output. That is §4 item 1
answered — first time anyone has confirmed it.

It also found two faults in the beat.

**The cue is 6.5 s and `HANDOVER_SECONDS` was 6.0.** `OVERNIGHT_PROGRESS.md`
records 6.0 as "matched to the generated cue's length"; it was not. The envelope
peaks on arrival, so the half second the debrief covered was the ambulance
actually arriving. The dwell now takes the longer of the floor and the cue's own
length, read off the stream — which also makes swapping in a real recording a
drop-in, as that note asked for.

**The beat's one line expired 2.5 s before the beat did.** No pill, nothing to
click, nothing else naming it — just a finished checklist and a noise. The line
now holds for the dwell. Confirmed on screen at 6.27 s in.

---

## 3. What else the run turned out to be doing

Three bugs, all of the same shape: the screen saying something that is not true.

### The opening brief came back on top of every dev warp

`_force_close_blocking_screens()` hid KitCheck's CanvasLayer but never closed the
brief underneath it, and KitCheck recomputes its own `visible` from the screens'
flags — so the next `_set_sweep_active()` put it straight back. Every warp reaches
one through `SimState.begin_exercise()`.

Found on screen **at the recovery-roll beat**, three quarters of the way through a
run, with `Events.open_uis` empty and a full-rect `MOUSE_FILTER_STOP` control
behind it eating clicks. This is what last pass's §5 note describes as "the brief
reopens a frame or two after boot, so call it twice with a wait between" — the
second call was not fixing anything, it just landed before the warp. One call is
now enough.

### Three directions on screen at once, through every spine beat

`has_visible_pointer()` required `_sequence_active`, which is the *primary
survey's* flag — and `_refresh_pointers()` draws the **spine** callouts while that
flag is false. So every spine beat that put a pill on the body drew it and
reported at the same time that nothing was drawn. Its two callers both stand down
when a pill is speaking, and both therefore did not.

Seen at the injury survey: three pills on the body, "Treat the casualty" at the
crosshair, and a step name across the bottom, simultaneously. Same at "Open the
shirt" between the sets and at the post-shock pair.

Both call sites' own docstrings already said they wanted "is a pointer actually
drawn". `CasualtyPointers.drawn_count()` is documented as the answer to exactly
that. It now asks that and nothing else.

### The standing objective said "Perform the CPR set" for the whole second half

`cpr_performed` and `aed_used` are graded at the **end** of the phase from the
`cpr_completed` metrics, not when their beat finishes. `Assessment.next_step()`
returns the first unresolved step whose prerequisites are met — so from the moment
`pulse_checked` lands, `cpr_performed` is its answer for the rest of the run.

Traced frame by frame over a clean checklist. Before, then after:

| Spine state | Before | After |
|---|---|---|
| `COMPRESSIONS_1` | Perform the CPR set | Perform the CPR set |
| `EXPOSE_CHEST` | Perform the CPR set | *down — the body pill speaks* |
| `AED_FETCH` | Perform the CPR set | Deploy the AED and place the pads |
| `AED_DEPLOY` | Perform the CPR set | Deploy the AED and place the pads |
| `PAD_PLACEMENT` | Perform the CPR set | Deploy the AED and place the pads |
| `SHOCK` | Perform the CPR set | Deploy the AED and place the pads |
| `COMPRESSIONS_2` | Perform the CPR set | *down — the body pills speak* |
| `RECOVERY_ROLL` | Perform the CPR set | *down — the body pill speaks* |
| `INJURY_SURVEY` | Perform the CPR set | *down — the body pills speak* |
| `HANDOVER` | Perform the CPR set | *down — nothing is asked* |

The last row is the one worth looking at: "Perform the CPR set" was sitting
directly under "Ambulance arriving — hand over to the crew" on the closing beat of
the exercise.

`CprStation.STATE_STEPS` answers per spine state and `hud.gd` asks it first. The
pill is also now refreshed on `cpr_state_changed` — the whole AED sequence is one
step, so no checklist signal fires across it and the old line would have stuck
anyway.

`check_objective_pill` walks every state and asserts the line. Against the code
before the fix it fails 8 of 13, which is the only reason to trust it.

---

## 4. Documentation that had drifted

All three checked against the code before rewriting.

- **`CPR_CONTRACT.md` §4.1** called the breathing check "the phase's one hard
  gate". It is not one — the "Start compressions" pointer calls
  `begin_compressions_early()`, which enters `COMPRESSIONS_1` from any earlier
  state without consulting it, and the availability rule for that pointer says in
  place that skipping the check is a mistake the trainee is allowed to make.
- **`CPR_CONTRACT.md` §4.3** had `stand_clear_confirmed` firing when the camera
  lands at `Anchor_Shock`. It fires from `ShockButton.arm()`, and the call that
  matters is the trainee standing up — standing hands the camera back to the
  player, so there is no landing to hang it on. `shock_button.gd`'s own docstring
  had been pointing at this drift for a while.
- **`PROJECT_STATUS.md` §8** listed `REP_TARGET_SET_2` as 10. It is 30.

`ARCHITECTURE.md` §1 gained four engine-level traps, and `PROJECT_STATUS.md` §7
now lists the real suite and the dev-window behaviour.

---

## 5. Still open

Carried from last pass, unchanged, plus what this one added.

1. **Recovery still re-closes the shirt over the AED pads.** Unchanged and still
   visible — §4 item 2 of the last report. It needs a bare-chest recovery pose,
   which is asset work, not code.
2. **The hazard content is still unreviewed.** `OVERNIGHT_REPORT.md` §4 stands in
   full. Nothing this session touched it and nothing should until the client has.
3. **`shock_pos` / `shock_rot` in `main.tscn` are dead, confirmed.** They are set
   to the head anchor's values, and `_apply_camera()` returns early for `SHOCK`
   because it is a stand-up state, so `anchor_for_state(STATE_SHOCK)` is never
   reached. Left alone: they are inert, and the script defaults underneath them
   are the authored pull-back if the beat is ever re-staged. **`panel_shock_pos`
   is NOT dead** — `panel_for_state()` does use it, so do not tidy the three away
   together.
4. **The stray root `mcp_interaction_server.gd` is not stray.** godot-mcp copies
   it there before every `run_project` and restores it whenever it is missing.
   The autoload resolves to `scripts/mcp_interaction_server.gd` by uid, so the
   root copy is dead weight that keeps coming back. Leave it untracked.
5. **`Casualty_Recovery_Posed` is still the fallback in the `.blend`.** Your call,
   unchanged.
6. **`LVR CPR.blend` is still modified from your re-save.** Left as you left it.
7. **The casualty offers "Treat the casualty" during the handover.** No callouts
   exist at that beat, so the click stands the sequence up and straight back down
   — a dead click on the closing beat. Minor; not fixed, because the same prompt
   is correct at every other beat and the fix is another reach into the spine.
8. **The step pill at `SHOCK` reads "Deploy the AED and place the pads"** — the
   step's own authored title, which does not mention the shock. It points at the
   right object; the wording is a content question for the client, not a bug.
9. **`check_spawn_gate`** — pre-existing, four assertions failing, not chased.

---

## 6. What was not tested

Said plainly so it is not mistaken for coverage.

- **The first half of the run was not walked end to end.** The kit check, the
  hazard assessment, the panel, the sign, the shock and the drag were reached only
  through the `[F10]` warps, which skip the interactions themselves. Last pass
  covered the hazard panel and the kit check on screen; this pass did not re-check
  them.
- **The AED pads were never seen on the chest.** Both of this pass's routes emitted
  `aed_pad_placed` directly rather than driving `pad_station`, so the pad meshes
  were never revealed. Whether they render where they should is still unconfirmed.
- **The compression minigame was not played**, only faked through
  `compression_set_completed`. Depth and rate scoring are unexercised on screen.
