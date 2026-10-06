# Overnight run — handover report

**3 Sep 2026.** Written for Nadir. Plan: `docs/OVERNIGHT_PLAN.md`. Full ledger:
`docs/OVERNIGHT_PROGRESS.md`. This is the summary; the ledger has the detail.

Read **§4 first** if you read nothing else — it is the hazard content, which was invented
here and must not reach the client as though it were theirs.

---

## 1. What landed

| Task | Status | Notes |
|---|---|---|
| 0 Safety net + unblock docs | **DONE** | git baseline, three standing rules suspended in place |
| 1 Procedure resource | **DONE** | 18 → 26 steps, happy path scores 100% against pass_mark 80 |
| 2a `Compression` on clothed mesh | **DONE** | peak 0.0340 m vs the bare mesh's 0.0340 m |
| 2b `Casualty_Recovery_Posed` | **DONE** | superseded by 2c, kept as fallback |
| 2c `LVR_Recovery` armature clip | **DONE** | your call, and the better design — see §3 |
| 3 Kit check correction | **DONE** | grades the first answer, records both |
| 4 Hazard assessment, two passes | **DONE** | content is provisional — see §4 |
| 5 CPR spine reorder | **DONE** | 14-state machine, headless test rewritten and green |
| 6 Recovery, injuries, handover | **DONE** | ROSC → recovery → injury survey → siren |
| 7 In-game verification | **NOT DONE** | ran out of window — see §5 |
| 8 Release build | **DONE** | `build/LVR CPR.exe`, 367 MB, 18:51 |

**Checks: 367 assertions green** across `cpr_headless_test`, `check_procedure_order`,
`check_kit`, `check_kit_correction`, `check_hazard_assessment`, `check_blender_assets`.
`check_spawn_gate` still fails — **pre-existing, failing before this run started**,
verified by stashing the changes and rerunning against the baseline commit. Not chased.

---

## 2. Decisions taken without you

1. **`ppe_donned` lost its `requires`.** It used to require `hazard_identified`, which now
   comes after it — leaving it would have been a cycle. `hazard_identified.requires` now
   points at `ppe_donned` instead, which makes your "gloves on before work commences" a
   real prerequisite rather than display order.
2. **Grade the FIRST attempt, not the correction** — in both the kit check and the hazard
   assessment. Once a panel names the wrong picks, fixing them is free; a weight-6
   critical step would otherwise score ~1.0 every time. The debrief still records both.
3. **The recovery mesh is hidden in code, not in the `.blend`.** It imported *visible*, so
   a second body lay on the floor from frame one. Fixed the way `chest_mesh` already is,
   for the reason `casualty.gd:170` states in place. Blender's `hide_render` was rejected —
   it risks dropping the object from the glTF export entirely.
4. **The plan's §8 claim was corrected in the doc**, not just noted. It asserted that a
   recovery clip would violate `CPR_CONTRACT.md` §8. It does not: §8 binds *other* scripts,
   and `casualty.gd` is the AnimationPlayer's owner and already calls `play()`. As written
   it would have talked the next agent out of the better design.
5. **`Casualty_Recovery_Posed` was NOT deleted.** It is the fallback path and the ground
   truth the clip is measured against. Deleting it is your call once you have seen the clip
   run — not a tidy-up to do unasked.
6. **`LVR CPR.blend` left uncommitted.** A re-save at 17:46 made it byte-different but the
   same size and the same scene. Committing it would have cost ~64 MB of repo for a no-op.
7. **Editor setting changed:** `filesystem/import/blender/rpc_port` 0 → 6011. You asked for
   this. Backup: `%TEMP%\editor_settings-4.7.tres.bak`.

---

## 3. The recovery pose — you were right, and it changed the design

The plan built the recovery position as a **separate static mesh**. You pointed out the
clothed body is already skinned to a 65-bone armature and could simply be posed. That was
correct, and the codebase agreed with you more than the plan did: `casualty.gd` has always
carried an `anim_recovery` export and a `_play(anim_recovery)` call, empty because no clip
existed.

`LVR_Recovery` now exists and is live. Two things worth keeping:

- **The pose is the one you approved**, not a reinterpretation. The original rig pose was
  unrecoverable, so the bone transforms were solved back out of the signed-off mesh —
  weighted Procrustes per bone, then descent over the skinning equation. **Max deviation
  23.8 µm, RMS 1.1 µm**, all 7101 verts under 0.1 mm, floor line 0.6 µm off.
- **AIRWAY_INSPECT now costs no mesh swap at all.** It runs before compressions with the
  shirt still on, so the skinned body is already on screen and only the pose changes.

**There are TWO gates on whether a Blender action reaches Godot.** Anyone adding a clip
must pass both:

1. **Blender** — the glTF exporter writes only the armature's active action plus
   **NLA-strip** actions. That is why `LVR_Master` and `Shock_Retargeted` (stashed nowhere)
   and `Shock` (stashed on the armature *data*, which the exporter never inspects) never
   arrive.
2. **Godot** — `scripts/import/trim_animations.gd` **deletes every clip not in its
   allowlist.** This would have silently eaten the work after a correct export. Its header
   claimed the exporter "writes out every action the armature could hold" — wrong, and
   exactly what made it a trap. Corrected.

---

## 4. THE HAZARD CONTENT — needs your eye before the client sees it

**Every one of the twelve entries was invented here. The client supplied none of it.**
It was checked against the room's actual contents, and **four did not survive**:

| Entry | Problem |
|---|---|
| P1 "Worker is about to open a panel on a live board" | **Factually wrong.** `breaker_panel.gd` keeps the worker out of the room until after the sign is hung — i.e. after `panel_opened`. He is not there during pass 1. |
| P1 "Metal hand tools in use next to a live board" | Tools exist (`Wrench`, `Pliers1`, `Hammer`, `SD1`, `SD2`, `Electric_hammerdrill1`) but sit on the bench, unused. "In use" is wrong. |
| P1 "Lighting will be lost when the board is isolated" | **Not modelled at all** — the only light is `Strip2`. It currently **penalises a trainee for failing to perceive something the simulation does not contain.** Kept per the plan as the torch hook, flagged `needs_review`. Consider making it a distractor until the lighting lands. |
| P2 "Board is incorrectly labelled" | **Weak** — there is no label either way, so it is a guess, not an assessment. Suggested: "The board is not labelled at all." |

**Still unverified — presence confirmed, position not:** the ladder across the walkway, the
pipework at head height, and the tools' placement. Global transforms are unavailable with
the `.blend` instantiated outside the tree, and headless Godot has no rendering device, so
no screenshot was possible. **If the ladder really is across the walkway, a trainee is
currently marked wrong for spotting it.** These need measuring in the editor.

Content lives in `resources/hazards/*.tres` precisely so the client can correct it without
a rebuild. `review_notes()` surfaces the open questions.

---

## 5. Not done, and what it means

- **Task 7, in-game verification, never ran.** Nothing in this run has been *looked at* in
  a running game. In particular: **the diegetic hazard panel has never been rendered**, and
  the recovery clip has never been seen in motion. The headless checks are strong on logic
  and say nothing about whether it reads correctly on screen.
  - Track B found and fixed a bug of exactly this class: the hazard panel was **silently
    never being created** (`add_child()` during `main.tscn`'s own build, which Godot
    refuses). Loud on stderr, invisible in behaviour. A second one could be sitting there.
- **The release build is unverified beyond exiting clean.** It used `--export-release`,
  which selects the release template by definition, but byte-level confirmation was not
  achieved: both templates share the same debug strings and Godot rewrites the header.
- **The ambulance siren is a generated placeholder**, not a recording. Marked as such in
  its docstring.
- **Rolling into recovery re-closes the shirt over the AED pads.** You asked for the
  clothed switch and there is no bare-chest recovery pose. The pads hide with the mesh, so
  nothing floats — but the shirt does close. Flagged, not solved.
- **`check_spawn_gate` fails** — pre-existing, unrelated, real. Worth a look sometime.

---

## 6. Machine-level things worth keeping

1. **`.blend` reimport from the CLI was crashing**, and the fix is `rpc_port = 6011`.
   Without RPC, Godot launches a fresh Blender per import and *that* Blender segfaults at
   **shutdown** — after writing a correct `.gltf`. Godot reads only the exit code, so it
   discards good output. **Your editor-driven workflow was never affected.**
   **The setting may not persist** if the editor rewrites `editor_settings-4.7.tres` on
   exit — confirm it is still 6011.
2. **A failed import silently disables the file**, rewriting `LVR CPR.blend.import` to
   `valid=false`, after which every `--import` skips it without a word.
   Recovery: `git checkout -- "LVR CPR.blend.import"`.
3. **A good import can be silently replaced by a bad one.** A check flipped from passing to
   failing with no code change. **If that happens, suspect the import cache before
   suspecting the work.**
4. **Reimports already skip unchanged assets** — 13 s for a no-op (Godot startup and scan),
   57 s for a genuine `.blend` reimport. Do not delete `.md5`/`.scn` to force one.
5. **The repo is 222 MB**, almost entirely six copies of the ~62 MB `.blend`. Commit the
   `.blend` at milestones, not every save.

---

## 7. If you pick this up cold

1. Confirm `rpc_port` is still 6011.
2. Run the suite — six checks, 367 assertions, all should be green.
3. **Do Task 7.** Launch the game and walk the run. The staging trap is in plan §5: clear
   the kit-check modal with
   `get_tree().current_scene.get_node("DevMenu")._force_close_blocking_screens()`, and
   never `game_eval` a standalone lambda or a method the object may not have — it breaks
   into the debugger and hangs the game for 30 s.
4. Look specifically at: the hazard panel rendering at all and being legible from where the
   board is worked; compressions visibly depressing the *shirt*; the shirt-open swap not
   popping; the recovery clip reading as the same body.
5. Then decide on `Casualty_Recovery_Posed` — delete it or keep the fallback.
