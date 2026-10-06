# Overnight Implementation Plan — client feedback round 1

**Written 3 Sep 2026.** Executed unattended by agents. Nadir is asleep; nobody is
available to answer a question. Every decision that could have blocked has been made
here in advance — if you find one that has not, record it in the ledger, pick the
option this document's reasoning most supports, and keep going. Do not stall.

Read with `PROJECT_STATUS.md`, `CPR_CONTRACT.md`, `ARCHITECTURE.md`.
Progress ledger: `docs/OVERNIGHT_PROGRESS.md` — **update it after every task.**

---

## 0. Standing rules that are suspended for this run

Three rules in the existing docs will stop you dead if you obey them. They were
correct for daytime work with a human at the keyboard. They are suspended for this
run **by explicit instruction from Nadir on 3 Sep 2026**, and Task 0 amends the docs
so the next agent to read them is not confused.

| Rule | Where | Status tonight |
|---|---|---|
| "GDScript only. Never run Blender." | `CPR_CONTRACT.md` §8 | **Suspended.** Blender work is the first deliverable. |
| "You implement, the user tests. Do not run the project." | `PROJECT_STATUS.md` §9 | **Suspended.** You are the only tester tonight. |
| "Do not spawn sub-agents unless asked." | `PROJECT_STATUS.md` §9 | **Suspended.** You have been asked. |

Everything else in those documents still binds. In particular §1 of
`ARCHITECTURE.md` — runtime name binding, `owner = null`, `Time.get_ticks_msec()`,
blend shapes by name, mouse stays captured — is unchanged, and is why several of the
traps below exist.

### Concurrency

The machine's performance problem was fixed on 3 Sep, so the one-heavy-process-at-a-time
rule is **withdrawn**. Run tracks in parallel.

What still constrains the graph is **file collisions, not load**:

- Tasks 3 and 4 both edit `kit_identify_panel.gd` — Task 4 extends it to multi-select,
  Task 3 adds the correction flow. Same track, in order.
- Tasks 5 and 6 both edit `casualty.gd` and `cpr_station.gd`. Same track, in order.
- Task 2 touches only the `.blend` and collides with nothing.

Two things still want the machine to themselves, for correctness rather than speed:

- **Task 7's in-game verification.** Only one agent drives the running game at a time,
  or `game_eval` results interleave and mean nothing. Task 7 is after the merge anyway.
- **Blender saves.** One writer to the `.blend`, which Task 2 owns alone.

Headless Godot (`--headless`) stays the cheap check — use it constantly, in every track.

### The safety net — Task 0, before anything else

**Done during planning, 3 Sep 2026.** The project was not a git repository — there was
no undo, and a bad Blender save on a 63 MB file was the one failure tonight that could
not have been recovered from.

It is one now: local only, no remote, baseline commit `1835b5c`. **Commit after every
task.** That is the rollback, and the git log is the second copy of the ledger.

Do **not** make loose copies of the `.blend` or anything else — Nadir keeps his own
backups and asked for no duplicates.

---

## 1. Scope — client feedback, decided

The client's feedback arrived as a WhatsApp stream. Decoded and decided:

| # | What they asked | Decision |
|---|---|---|
| 1 | Kit contents: show right/wrong at the time, allow correction, note the correction | **Build.** Reverses the "no verdict until debrief" rule for this step only — the client asked twice. |
| 2 | "Identify the hazards" — as a drop-down, "so it's easier" | **Build as a tick-all-that-apply hazard assessment.** Two passes, gated on the panel being open. Task 4. |
| 3 | Gloves on *before* work commences | **Build.** `ppe_donned.min_phase` 3 → 2, reordered ahead of `hazard_identified`. |
| 3b | Torch on, "so you can see when the power goes out" | **Deferred.** Nadir: the room won't go dark for now. The torch stays a pickup that does nothing. Kept alive as a hazard-list entry (Task 4) so the mitigation exists when the lights land. |
| 4 | Check the casualty is not on fire; fire blanket if they were | **Build, outcome always "clear".** One observation beat, no fire simulation. Nadir confirmed: clear, yes. |
| 5 | "No need to open the shirt" → walked back to: compressions first, *then* open the shirt for the AED | **Build the walked-back version.** Set 1 with the shirt on, open it before the pads. |
| 6 | Roll to check the airway for a blockage, then check pulse, then CPR | **Build.** New beats between the breathing check and compressions. |
| 7 | Pulse check before the AED | **Build.** Folded into #6 — the pulse check is the beat that decides CPR. |
| 8 | ROSC → recovery position → check for injuries → ambulance arrives | **Build.** Un-cuts the recovery position, which `PROJECT_STATUS.md` §1 says not to re-add without asking. This is the asking; the answer was yes. |

Also folded in, from Nadir's replies to the open items in `PROJECT_STATUS.md` §6:

- Casualty tooltip → "Interact with casualty" (`casualty_interactable.gd:63`).
- Dead step ids → cleaned up, mostly by re-authoring them (see §2).
- Web/SCORM export → **not tonight.**

---

## 2. The target spine — the contract everything codes against

This is the most important section. **Task 1 turns it into
`resources/procedures/lvr_cpr_procedure.tres`, and every later task codes against the
step ids in that file rather than against this table.** Author it once, early, so two
agents never edit the procedure resource at the same time.

New steps are **bold**. Moved steps are marked →.

| Phase | Step id | Notes |
|---|---|---|
| KIT_CHECK | `kit_selected` | unchanged |
| | `kit_identified` | now correctable — Task 3 |
| SCENE_SAFETY | → `ppe_donned` | **moved ahead of hazard ID**, `min_phase` 3 → 2 |
| | `hazard_identified` | now a multi-select assessment, pass 1 — Task 4 |
| | `panel_opened` | unchanged |
| | **`hazards_reassessed`** | **new**, pass 2, requires `panel_opened` — Task 4 |
| | `isolation_point_signed` | unchanged |
| BREAK_CONTACT | `crook_retrieved` | now requires `hazards_reassessed` rather than `ppe_donned` |
| | `contact_broken` | unchanged |
| EXTRACTION | `drag_to_safe_area` | unchanged |
| | `supply_isolated` | unchanged |
| PRIMARY_SURVEY | **`fire_checked`** | **new** — outcome always clear |
| | `check_response` | unchanged |
| | `send_for_help` | unchanged |
| | `call_for_aed` | unchanged |
| | `airway_opened` | unchanged |
| | `breathing_checked` | unchanged — the 5 s ear hold |
| | **`airway_inspected`** | **new** — roll to side, look for a blockage, roll back |
| | **`pulse_checked`** | **new** — no pulse, therefore CPR |
| RESUSCITATION | `cpr_performed` | set 1, **now with the shirt on** |
| | → `chest_exposed` | **moved after set 1**, before the pads |
| | `aed_used` | unchanged |
| RECOVERY | **`signs_of_life`** | **re-authored** (was a dead id) |
| | **`recovery_position`** | **re-authored** (was a dead id) |
| | **`injuries_checked`** | **new** |
| | **`handover`** | **new** — ambulance arrives, run ends |

18 steps → 25. Scoring is a weighted percentage, so adding weight is safe: `pass_mark`
stays 80. Suggested weights for the new steps — `fire_checked` 4, `airway_inspected` 6,
`pulse_checked` 8 critical, `hazards_reassessed` 4, `signs_of_life` 4,
`recovery_position` 8 critical, `injuries_checked` 4, `handover` 2. Task 1 owns the
final numbers and must confirm the run is still passable: walk the happy path and check
the total clears 80.

Four ids being re-authored are from the "dead step ids" list in `PROJECT_STATUS.md`
§6.4. Re-authoring them *is* the clean-up — the `push_warning` noise stops because the
steps become real again. `compressions_started`, `compressions_resumed`, `pads_placed`
and `shock_delivered` stay dead: **delete those four calls** from `casualty.gd`.

### The CPR state machine

`cpr_station.gd` holds states 0–8 (`STATE_EXPOSE_CHEST` … `STATE_COMPLETE`). Target:

```
0  BREATHING_CHECK     (was 1)  ear hold, 5 s              — unchanged
1  AIRWAY_INSPECT      NEW      roll to side, look, roll back
2  PULSE_CHECK         NEW      hold at the neck
3  COMPRESSIONS_1      (was 2)  30 reps, SHIRT ON
4  EXPOSE_CHEST        (was 0)  moved here
5  AED_FETCH           (was 3)
6  AED_DEPLOY          (was 4)
7  PAD_PLACEMENT       (was 5)
8  SHOCK               (was 6)
9  COMPRESSIONS_2      (was 7)
10 RECOVERY_ROLL       NEW      ROSC, roll to side, stays there
11 INJURY_SURVEY       NEW
12 HANDOVER            NEW      siren, fade to debrief
13 COMPLETE            (was 8)
```

Renumbering is safe **only** because every reference is via the named constants. Grep
for numeric literals against `current_state` before you finish; there should be none.

---

## 3. Established findings — do not re-derive these

Verified 3 Sep 2026 by headless probe. Trust them; re-deriving costs an hour.

**Blend shapes.**
- `Boots1_002` (clothed, skinned, 8 surfaces): `Key 1`, `Mouth open`. **No `Compression`.**
- `Casualty_CPR_Posed` (bare chest, static overlay, 9 surfaces): `EyesOpen_legacy`,
  `Compression`, `Shock`, `Mouth open`.

**Animations.** The `AnimationPlayer` holds exactly `LVR_Fall`, `LVR_Fiddle`,
`LVR_ShockEnter`, `LVR_ShockHold`. There is **no** recovery, breathing, drag or
compression animation — which is why `anim_recovery` / `anim_breathing` / `anim_down`
on `casualty.gd` are all empty `StringName`s.

**`Casualty_CPR_Posed` is hardcoded by name in six places.** The biggest refactor
hazard in the job:

```
scripts/cpr/breathing_check.gd:50        CASUALTY_MESH_NAME
scripts/cpr/casualty_cpr.gd:28           CASUALTY_CPR_MESH
scripts/cpr/cpr_ear_2d.gd:54             CASUALTY_MESH_NAME
scripts/cpr/cpr_hands_2d.gd:33           CASUALTY_MESH_NAME
scripts/cpr/cpr_interact_bridge.gd:287   pad sites are its children
scripts/cpr/cpr_station.gd:335,364       collider + anchor
```

**Do not rename, reparent or permanently hide `Casualty_CPR_Posed`.** It stays the
geometric authority — colliders, pad sites, ear and hand anchors all hang off it.
Anything new is a *visual* sibling driven in parallel.

**`enter_cpr_phase()` is called from three places and is idempotent on purpose**
(`main.gd:219`, `main.gd:236`, `dev_menu.gd:220`). One of those hooks fires on
`step_completed(chest_exposed)`. **Moving `chest_exposed` later in the sequence breaks
that hook** — `ARCHITECTURE.md` §2 documents the exact race this caused before, and it
cost a debugging session. Re-point that trigger at `breathing_checked`; do not simply
delete it, because the other hook is the one that loses the race.

**No git.** See Task 0.

**All three MCPs verified working at 02:30, 3 Sep 2026.** Godot MCP returns
`4.7.2.stable.official`; Windows MCP runs PowerShell; Blender MCP is connected to a
running Blender with the correct `.blend` open. (An earlier `tasklist` check in this
document wrongly said Blender was not running — it is.) If the Blender bridge ever does
fail, `blender-mcp.exe` alone is not enough: the Blender process itself must be up with
the addon connected. Launch it from
`C:\Program Files\Blender Foundation\Blender 5.2\blender.exe`.

**The open Blender file may hold unsaved changes, and that is accepted.** It reported
`is_dirty: true` on 3 Sep. Nadir was told those edits exist only in memory and chose to
proceed anyway: *"remove the dirt check let it work either way."* **Do not check
`is_dirty` and do not refuse Task 2 because of it.**

Recovery if a save goes wrong: the pre-run `.blend` is in the baseline commit —
`git checkout 1835b5c -- "LVR CPR.blend"` restores it byte for byte. That is why the
baseline exists.

Tasks 5 and 6 should still degrade gracefully when the new shape and pose are absent — a
missing `Casualty_Recovery_Posed` logs a warning and skips the visual rather than
crashing — so the CPR work stays independent of whether Task 2 landed.

**Versions.** Godot 4.7.2 at
`C:\Program Files\Godot\Godot_v4.7.2-stable_win64_console.exe` (`PROJECT_STATUS.md`
says 4.7.1 — stale, fix in Task 0). Blender 5.2. Project root is now
`C:\Users\NAD24\Documents\...`, not the `D:\Nadir\...` in the docs — Nadir changed
machines.

---

## 4. Task graph

Tasks 0 and 1 are done. Task 1 was the contract — every remaining task codes against
the step ids it defines, which is what makes the fan-out below safe.

```
Task 0  Safety net + unblock the docs      DONE
Task 1  Author the procedure resource      DONE   ← the contract everything codes against
   |
   +-- TRACK A ---------------------------------------------------
   |   Task 2  Blender: compression shape + pose    ~1.5-2 h
   |           touches only the .blend
   |
   +-- TRACK B ---------------------------------------------------
   |   Task 3  Kit check: feedback + correction     ~1.5 h
   |      |    then
   |   Task 4  Hazard assessment, two passes        ~2.5 h
   |           both edit kit_identify_panel.gd
   |
   +-- TRACK C ---------------------------------------------------
       Task 5  CPR spine: reorder + new beats       ~3 h
          |    then
       Task 6  Recovery, injuries, handover         ~2 h
               both edit casualty.gd and cpr_station.gd
   |
   v  all three tracks join
Task 7  Integration + in-game verification          ~1.5 h
   |
Task 8  Release build + handover report             ~45 min
```

**Within a track, strictly in order. Across tracks, freely in parallel.** The split is
by file ownership: no two tracks write the same file, so nothing needs locking.

Track C is the long pole at ~5 h and should start first. Track A is independent of both
code tracks — if the Blender work fails, Tracks B and C are unaffected, which is why
Tasks 5 and 6 must degrade gracefully when the assets are missing.

Each task ends by updating the ledger. With tracks running concurrently, **append your
entry rather than rewriting the file**, and update only your own rows on the status
board.

If time runs short, the drop order is: Task 6 → Task 4 pass 2 → Task 2's recovery pose
(the airway inspection can fall back to a message with no visual). Tasks 1, 3 and 5 are
the spine and must land.

---

## 5. Task specs

### Task 0 — Safety net and unblocking the docs

1. `git init`, and commit everything as `baseline before overnight client-feedback work`.
   The `.gitignore` already excludes `.exe`, `build/`, `.godot/` and `*.blend1`, so the
   commit is the source plus the 63 MB `.blend`. That is acceptable for a local safety
   net. Do **not** add a remote, do **not** push.
2. **Do not make copies of the `.blend`.** Nadir keeps his own backups and said so
   explicitly. The git baseline is the only in-project safety net; that is enough.
3. Amend `CPR_CONTRACT.md` §8 — replace "Never run Blender" with a note that Blender
   work is permitted when explicitly authorised, and that this run was.
4. Amend `PROJECT_STATUS.md` §9 — same for the testing and sub-agent rules.
5. Fix the stale facts: project path `D:\Nadir\...` → `C:\Users\NAD24\...`; Godot
   4.7.1 → 4.7.2.
6. Commit again: `docs: unblock overnight run`.

Commit after every task from here on. That is the rollback.

### Task 1 — Author the procedure resource

Turn §2 into `resources/procedures/lvr_cpr_procedure.tres`. Nothing else. No code.

- Add the eight new steps with the suggested weights, fix `ppe_donned.min_phase` to 2,
  re-point `crook_retrieved.requires`, move `chest_exposed` after `cpr_performed`.
- Walk the happy path by hand and confirm the total still clears `pass_mark` 80.
- **Write a headless check** — `tools/check_procedure_order.tscn` — asserting: every
  `requires` names a step that exists; no cycles; the critical-step weights sum below
  100; the happy-path order is achievable. This check is how every later task knows it
  has not broken the spine.
- Run `scripts/cpr/cpr_headless_test.tscn`. It **will** fail once steps move — that is
  expected. Record which assertions fail in the ledger; Task 5 fixes them.

### Task 2 — Blender

Two deliverables, both mesh work. **No animation is required** — see 2b.
**Confirm the git baseline commit exists before opening Blender**
(`git log --oneline` shows `Baseline before overnight client-feedback work`). Do not
make a loose copy of the `.blend` — Nadir keeps his own backups.

**2a. `Compression` blend shape on the clothed mesh `Boots1_002`.**

Chosen approach, and why: add the shape to the *existing* skinned clothed mesh rather
than authoring a new clothed CPR-posed mesh. Blend shapes are applied before skinning,
so a local sternum depression authored on the rest pose deforms correctly in the CPR
pose. This needs no new object, no new material, and — critically — no changes to the
six hardcoded `Casualty_CPR_Posed` references in §3.

- Name it exactly `Compression`. Matching by name is required
  (`ARCHITECTURE.md` §1 — glTF ordering is not stable).
- Match the displacement magnitude and centre of the existing `Compression` shape on
  `Casualty_CPR_Posed` as closely as you can, so the depth reads the same before and
  after the shirt opens.
- **Fallback if this looks wrong in-engine:** author a separate clothed CPR-posed mesh
  `Casualty_CPR_Posed_Clothed` as a visual sibling, hidden by default. Do not take this
  path unless 2a genuinely fails — it costs a mesh, a material and a parallel
  shape-driver in `casualty_cpr.gd`.

**2b. One posed mesh, used twice. No animation.**

Nadir's instruction, 3 Sep: *"we dont need roll animation just pose well cold switch."*
So author a **static posed mesh**, not an animation, and swap to it instantly.

This is how the project already works — `expose_chest()` cold-switches `Boots1_002` for
`Casualty_CPR_Posed` with no tween — so it is the established idiom rather than a
shortcut.

> **CORRECTED 3 Sep, after Nadir challenged it.** This paragraph originally went on to
> claim a posed mesh "keeps a standing rule intact that an animation would have bent:
> `CPR_CONTRACT.md` §8, *never touch the casualty's `AnimationPlayer`; `Casualty` is its
> single owner.*" **That reasoning is wrong and must not be relied on.** §8 binds *other*
> scripts; `casualty.gd` **is** the owner and already calls `animation_player.play()`
> (line 244). The casualty is lying supine in the first place because `LVR_Fall` put it
> there, so posing this body by clip is the established mechanism, not an exception to
> it. `casualty.gd` has also always carried an `anim_recovery` export and a
> `_play(anim_recovery)` call sitting empty, waiting for exactly this clip.
>
> Nadir's instruction ruled out a rolling **motion**, not the AnimationPlayer. The design
> he chose once that was clear is a single-pose clip on the existing 65-bone armature,
> posing the skinned clothed body itself. It saves a 7101-vert duplicate mesh, keeps one
> body that cannot drift out of sync with the other, and costs **no mesh swap at all** for
> the airway inspection, which runs with the shirt still on. The static mesh is retained
> as the fallback path, and `show_recovery_pose()` prefers whichever is available.

**Deliverable: `Casualty_Recovery_Posed`** — clothed, lying on the side in the recovery
position, far arm supporting, in the direction the recovery position is normally taught.

**One pose serves both beats.** The airway inspection and the recovery position are the
same physical position; only the dwell differs.

- `AIRWAY_INSPECT`: switch to it, present the finding, switch back.
- `RECOVERY_ROLL`: switch to it and stay.

Requirements:

- Same world transform and origin as `Casualty_CPR_Posed`, so the switch does not
  translate the body across the floor.
- Carry a **`Mouth open`** blend shape, like both existing meshes. The airway is open by
  the time either beat runs, and `casualty.gd::_set_mouth_open()` needs a shape to write
  or the head will read as closed after the swap.
- No `Compression` shape needed — nobody compresses a casualty on their side.

**Known compromise, flag it in the handover:** switching back to clothed for recovery
re-closes the shirt over the AED pads. Nadir asked for the clothed switch and there is
no bare-chest recovery pose. Hide the pad meshes at the switch so there are at least no
pads floating at the old supine position, and put it in `docs/OVERNIGHT_REPORT.md` for
him to look at. Do not author a second bare-chest recovery mesh to solve it without
being asked.

**After saving:** close Blender, then let Godot reimport. Verify with a headless probe
that `Boots1_002` now reports a `Compression` shape and that `Casualty_Recovery_Posed`
exists with a `Mouth open` shape. Check `mesh_repair.gd` still round-trips the new shape — it rebuilds
meshes at import and copies shapes by name (`mesh_repair.gd:55`), so a new shape should
survive, but confirm it rather than assuming.

Commit the `.blend` separately from code:
`assets: compression shape on clothed mesh, recovery pose`.

### Task 3 — Kit check: feedback and correction

Client item 1. Currently `kit_bench.gd::_on_answer_submitted` records the answer and
moves straight on, telling the trainee nothing.

- On a wrong answer: say so on the panel, keep the item live, and let them choose
  again. On the retry, mark the item answered whatever they pick.
- **The correction must be noted.** Keep the first answer *and* the corrected one in
  `answers[item_id]`, and log both through `Events.log_action` so the debrief and the
  SCORM comments carry "answered X, corrected to Y". Grade the first answer, not the
  correction — the trainee still got it wrong first time; the debrief should say so.
- `kit_identify_panel.gd` is a pure view and must stay one. It does not know which
  choice is right; `KitBench` tells it what to show.

Add `tools/check_kit_correction.tscn` asserting: a wrong-then-right sequence records
both answers, grades the first, and completes the step.

### Task 4 — Hazard assessment

Client item 2. Replaces the current one-click `hazard_identified`, which awards a
critical weight-6 step for clicking a panel and then *tells the trainee the answer*.

**Shape:** a tick-all-that-apply list on a diegetic in-world panel, picked with the
crosshair, same idiom as the kit identify panel. This is not a re-introduction of the
screen-space menu that was removed — `CPR_CONTRACT.md` §6.3: *a choice chooses an
intent, it never performs the act.* A hazard list performs nothing; it is assessment,
exactly like the kit panel already in the game.

**Two passes, because of the door.** The busbars are inside the board and cannot
honestly be identified before it is open — Nadir raised this. So:

- **Pass 1** (`hazard_identified`, before `panel_opened`): what is visible from the
  floor.
- **Pass 2** (`hazards_reassessed`, after `panel_opened`): what opening the board
  exposed.

Reassessing after exposing something is also what the trade actually teaches, so the
gating is a feature rather than a workaround.

**Correctable, like the kit** (Nadir's instruction). Show which picks were wrong,
allow one correction pass, record both attempts.

**Provisional content — verify it against the room before committing.** The client is
slow to supply detail, so this is authored here. Take screenshots of the switchroom
from the trainee's position and confirm each entry is actually visible and actually
present; drop or reword anything that is not.

Pass 1 — from the floor, board shut:

| Option | |
|---|---|
| Switchboard is energised and has not been isolated | ✓ real |
| No point of isolation identified or marked | ✓ real |
| Worker is about to open a panel on a live board | ✓ real |
| Metal hand tools in use next to a live board | ✓ real |
| Lighting will be lost when the board is isolated | ✓ real — the torch hook, keep it even though the lights are deferred |
| Ladder stored across the walkway | ✗ distractor (`FoldingLadder` is in the room) |
| Overhead pipework at head height | ✗ distractor (`BagaPie_Pipes_001/002`) |
| Wet floor around the switchboard | ✗ distractor — not modelled, and that is the point |

Pass 2 — board open:

| Option | |
|---|---|
| Exposed live busbars within arm's reach | ✓ real (`Breaker busbars`) |
| No barrier or insulating mat in front of the open board | ✓ real |
| Rodent damage to the internal wiring | ✗ distractor |
| Board is incorrectly labelled | ✗ distractor |

**Grading:** use the existing quality factor —
`Assessment.complete(step, quality)`, as `cpr_performed` and `aed_used` already do.
Quality = (hits − false positives) / real count, floored at 0. No new grading
machinery is needed.

Put the content in a resource (`resources/hazards/*.tres`) rather than in code, so the
client can be handed a list to correct later without a rebuild.

Add `tools/check_hazard_assessment.tscn` asserting: pass 2 cannot be answered before
`panel_opened`; quality maths is right; a correction is recorded.

### Task 5 — CPR spine: reorder and new beats

The heart of the job. Client items 5, 6, 7.

- Renumber `cpr_station.gd` to the §2 state list. Named constants only.
- **Re-point the `enter_cpr_phase()` trigger off `chest_exposed`** — see §3. Do this
  first; everything else in this task depends on the phase actually starting.
- `COMPRESSIONS_1` now runs with the shirt on. `casualty_cpr.gd` must drive
  `Compression` on whichever mesh is visible. There is a precedent for writing both
  meshes every frame: `casualty.gd::_tween_mouth_open`. Follow it.
- `EXPOSE_CHEST` moves to after set 1. `attach_pads()` already refuses without
  `chest_exposed` (`casualty.gd:626`) — that guard now does real work, so keep it.
- **`AIRWAY_INSPECT`:** cold-switch to `Casualty_Recovery_Posed`, present the finding
  ("airway clear, no obstruction"), switch back. No tween, no `AnimationPlayer`.
  Completes `airway_inspected`.
- **`PULSE_CHECK`:** a hold at the neck, same construction as the existing 5 s
  breathing check (`breathing_check.gd`) — reuse it rather than writing a second timer.
  Finding: no pulse. Completes `pulse_checked` and is what licenses compressions.
- **`fire_checked`:** one observation beat during the primary survey. Outcome always
  clear. The fire blanket stays in the kit as the answer to a question that is not
  asked this run.

`cpr_headless_test.gd` must be updated and passing before this task closes.

### Task 6 — Recovery, injuries, handover

Client item 8. Un-cuts the recovery position.

- After `COMPRESSIONS_2`, ROSC: `casualty.gd::_achieve_rosc()` already exists and
  already sets `SimState.phase = RECOVERY`. Wire it up rather than rewriting it.
- Cold-switch the bare posed mesh to `Casualty_Recovery_Posed` and leave it there.
  `casualty.gd::roll_to_recovery()` already exists — it needs a caller and a mesh swap
  rather than the animation name its empty `anim_recovery` export implies. Hide the pad
  meshes on the switch (see Task 2b).
- **`INJURY_SURVEY`:** the client asked to "check for any other injuries". Simplest
  honest version: two or three body-anchored pills over the casualty, same machinery
  as the existing pre-CPR pointers (`casualty_pointers.gd`). Finding: a burn at the
  contact point, which is medically right for an electrical casualty and rewards
  looking.
- **`HANDOVER`:** ambulance siren approaching, then the debrief. No siren asset
  exists. Generate a placeholder the way `tools/gen_breathing_negative.py` does — a
  stdlib Python two-tone siren with an approach envelope, written to
  `audio/cues/ambulance_arrive.wav`. Mark it clearly in the file docstring as a
  placeholder for a real recording. `aed_voice.gd`'s asset-optional pattern is the
  model: a missing file must degrade to a text line, never break the beat.

### Task 7 — Integration and in-game verification

The one place the expensive checks are allowed.

1. All headless checks green: `cpr_headless_test`, `check_procedure_order`,
   `check_kit_correction`, `check_hazard_assessment`, plus the pre-existing
   `check_casualty_geometry`, `check_aed_voice`, `check_shock_skip`, `check_spawn_gate`.
2. `godot-mcp run_project`, wait ~8 s for the interaction server, then walk the full
   run with `game_eval` and the `[F10]` dev warps. Screenshot each new beat.
3. Known staging trap from `PROJECT_STATUS.md` §7: the kit-check modal blocks the ray
   at startup — clear it with
   `get_tree().current_scene.get_node("DevMenu")._force_close_blocking_screens()`.
   Never `game_eval` a standalone lambda or a method the object may not have; it breaks
   into the debugger and hangs the game for 30 s.
4. Specifically confirm: compressions visibly depress the *shirt*; the shirt-open swap
   does not pop; both rolls read as the same body; the hazard panel is legible at the
   distance the board is worked from.

### Task 8 — Release build and handover

1. Release export — **not** the debug one. `PROJECT_STATUS.md` §6.1 is explicit about
   why: the debug build leaves the `[F10]` warps and the compression fast-forward live,
   and the fast-forward lets a trainee skip 20 of 30 compressions.

   ```
   "C:/Program Files/Godot/Godot_v4.7.2-stable_win64_console.exe" --headless --path . --export-release "Windows Desktop" "build/LVR CPR.exe"
   ```

2. Verify the release template marker in the binary before calling it done.
3. Update `PROJECT_STATUS.md` §3 to the new spine, and `CPR_CONTRACT.md` §1 to the new
   state list.
4. Write `docs/OVERNIGHT_REPORT.md` for Nadir: what landed, what did not, every
   decision taken without him, every place the provisional hazard content needs the
   client's eye, and anything that needs a real recording or a real animator.

---

## 6. Verification standard

**No task is done until it has a headless assertion that would fail if the work were
reverted.** That is the only way autonomous work is trustworthy overnight.

```
"C:/Program Files/Godot/Godot_v4.7.2-stable_win64_console.exe" --headless --path . res://scripts/cpr/cpr_headless_test.tscn
```

Exits 0 and prints `cpr_headless_test: all assertions passed.` Three leaked ObjectDB
instances and one resource-in-use error at exit are expected teardown noise, not
failures.

**Report failures honestly in the ledger.** A task recorded as done that is not done is
worse than a task recorded as blocked — Nadir will build on it in the morning.

---

## 7. Auto-resume

The 5-hour usage window is expected to run out roughly 2 h 50 m into the run. The
resume strategy is **not** a clever scheduler; it is making the work restartable.

**`docs/OVERNIGHT_PROGRESS.md` is the ledger.** Every task appends: what it did, which
files it touched, which checks pass, what it decided, what it deferred. An agent
resuming cold reads the ledger, finds the first task not marked DONE, and starts there.

Rules that make that work:

- **Commit after every task.** The git log is the second copy of the ledger.
- **Never leave a file half-edited across a task boundary.** Finish or revert.
- **Never leave Blender holding an unsaved 63 MB scene.** Save or discard before the
  task closes.
- Write the ledger entry *before* starting the next task, not after.

### How this run is launched

**Run by hand, in a live session.** The scheduled task that fired once on 3 Sep (getting
through Task 1) was deleted afterwards — Nadir prefers to drive it himself and watch it,
rather than have it consume a window unattended. Its prompt is kept at
`~/.claude/scheduled-tasks/lvr-cpr-overnight-run/SKILL.md` and is the text to paste in to
resume. Everything below is the history of why it was scheduled in the first place, kept
because the reasoning still applies if it is ever scheduled again.

### Why it was scheduled, and with which scheduler

**A one-shot scheduled task at 04:37 on 3 Sep 2026**, created during planning and stored
at `C:\Users\NAD24\.claude\scheduled-tasks\lvr-cpr-overnight-run\`. Nothing runs before
then — Nadir chose a clean full window over starting immediately and being cut off
roughly a quarter of the way in, which would likely have landed mid-Blender-session.

Two schedulers were available and the choice mattered:

| | Survives the session ending? |
|---|---|
| `CronCreate` | **No.** Session-only, in memory, gone when Claude exits. |
| scheduled-tasks MCP | **Yes.** On disk; if the app is closed when due, it runs at next launch. |

The failure being guarded against is the session dying at the usage limit, so the
session-only scheduler was exactly the wrong tool. An interval `/loop` had the same
weakness *and* would have burned firings against a dead window.

The scheduled run starts cold with **no memory of the conversation that planned it**.
That is why this document and the ledger exist, and why they are written to be read by a
stranger. If the run is interrupted again, resuming is just re-issuing the same prompt —
the ledger is what makes a cold start cheap.

### Permissions

`.claude/settings.json` sets `permissions.defaultMode` to `bypassPermissions` for this
project, because a scheduled run is a fresh session and would otherwise stop at the first
prompt with nobody awake to answer it. Nadir chose this deliberately over a narrower
allowlist.

Three denies are kept as guardrails on an unattended run, and none of them block any task
in this plan: `git push`, `git remote add` (this repository is deliberately local-only),
and `rm -rf /`.

---

## 8. Risks, ranked

1. **The Blender compression shape does not read through the shirt.** Most likely
   failure. Mitigation: the fallback clothed posed mesh in Task 2a — but that costs a
   parallel shape-driver, so try hard to make 2a work first.
1b. **The recovery pose does not line up with `Casualty_CPR_Posed`.** Same origin and
   world transform, or the body jumps across the floor on the switch. Check it in
   Blender before saving, not in the engine afterwards.
2. **Moving `chest_exposed` breaks the CPR phase entry.** Documented, has bitten
   before, and the symptom is intermittent (`ARCHITECTURE.md` §2). Re-point the trigger
   *first*, in Task 5, before touching anything else.
3. **The hazard content is invented.** The client did not supply it. Everything in Task
   4 is provisional and must be flagged for review in the handover report. Do not let
   it ship to the client as though it were their content.
4. **Renumbering the CPR states silently breaks a numeric comparison.** Grep for
   integer literals near `current_state` before closing Task 5.
5. **Scope.** Eight client items plus a state-machine reorder is a lot for one night.
   The drop order is in §4. Landing Tasks 0–5 well beats landing all eight badly.
