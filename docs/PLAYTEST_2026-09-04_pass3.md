# Playtest pass 3 — 4 Sep 2026

Written for Nadir, covering the four ratified changes and the two bugs from the
handover prompt. Everything below was seen in the running game unless it says
otherwise, and §6 says plainly what was not.

Suite: **14 green.** The ten that were green at handover, plus
`check_review_panel`, `check_torch_step`, `check_sign_gate` and
`check_injury_survey`. `check_spawn_gate` still fails; pre-existing, not chased.

---

## 1. What was walked, and what it showed

| Beat | Seen on screen |
|---|---|
| Kit check, opening | HUD reads one kit step, not two. "Name the LVR kit items" |
| Clicking a bench object | Naming menu opens directly over the object clicked |
| The naming menu's choices | "Resuscitation Face Shield", "LV Rescue Kit Bag", "Insulated Shears", "Hooking Pole" — the object's own title plus three of the eight approved distractors, none of them anything in the room |
| A wrong first answer | "Not correct - choose again", the pill struck through and tinted, the object still live |
| The correction | Accepted, and **it scored**: `correct: true`, `corrected: true`, `choice` the wrong one, `final_choice` the settled one |
| An object already named | Reticle reads "Named as kit - click to take it back" |
| [Enter] | Review card up: "You have named these as LV rescue kit", six lines in the trainee's own words, Correct and Confirm |
| Correct | Card down, bench live again, all six claims intact, nothing graded |
| Confirm | Step completed at quality 1.0 |
| Taking the gloves | `ppe_donned` completes, objective advances to the torch |
| **The torch** | Checklist "› Take the torch before the work starts", objective pill the same, reticle "Take Torch". Taking it completes the step and the objective moves to the hazard survey |
| Hazard pass 1 | **Seven lines.** The lighting hazard is gone. Submit pill reads "Submit assessment" |
| Submitting | Review card up, tick list stands down behind it |
| The card's contents | Two real hazards and one distractor, **all three in identical neutral styling.** Nothing marks the wrong one |
| Correct | Tick list back with all three ticks exactly as left |
| Confirm | Graded on the settled set |
| **The sign, before the reassessment** | Refused, in amber: "Reassess the open board before you sign the point of isolation." Sign not hung, incident not started |
| The beacon | On the busbars while the reassessment is outstanding; jumps to the sign ghost the moment it resolves |
| Hazard pass 2 | Four lines, "Submit reassessment", same review card |
| **The injury survey, hands first** | Burn announced at once — "Burn to the right palm — the contact point" — and both other pointers still up. Ambulance did **not** arrive |
| The last of the three sites | `injuries_checked` completes, state advances to HANDOVER |

### The grading, read off the run

```
hazard_identified   quality 1.00   first_quality 0.25   corrected true
hazards_reassessed  quality 1.00                        corrected false
kit_identified      quality 1.00
torch_taken         complete
```

And the SCORM comment log, which is the client-facing record:

> Hazard assessment: 4 of 4 identified, **after first reporting 2 of 4** —
> Identified: … First submitted: …, Ladder stored across the walkway.

That single line is both halves of the client's request: the settled answer is
what counts, and the correction is noted.

> [03:13] Found the entry burn at the contact point during the injury survey.
> [03:26] Checked the head and neck for injuries.
> [03:26] Checked the legs and feet for injuries.
> [03:26] Check for other injuries

The burn is found at 03:13 and the survey does not close until 03:26. Under the
old code the run ended at 03:13 with two sites never looked at.

---

## 2. Two faults found by playing, both fixed

Neither was visible to any test, and both are the same shape as the fault
`docs/CLIENT_CONFORMANCE_2026-09-04.md` §2 describes: green suite, broken game.

### The naming menu was unreadable on the first question of the run

The heading and three of four choices were sliced off mid-word — "entify this
item", "nsulating Mat", "tage Proving Unit". **Two causes, and only fixing both
works:**

1. `kit_identify_panel.gd` was the only one of the three diegetic panels with
   `no_depth_test` off. The bench stands against a wall, the quad billboards to
   face the camera, and from most places the bench is worked from its left half
   is inside that wall. The depth test cut the menu off square.
2. The text overflowed its pill regardless. The old distractors were other bench
   objects' names — "Torch", "Pliers" — and every one fitted at font size 34.
   The approved pool is real LV rescue equipment, and "Resuscitation Face
   Shield" is half as wide again as the pill. The stack now sizes its font to
   the longest choice on that menu, one size for all of them so no distractor is
   discountable by its type size, and draws width-limited as a backstop.

**This was caused by change 4a.** The distractors are the client's approved
wording; nothing about them is wrong. The panel had simply never been given a
long label before.

### The arrow-key path was dead in both floating panels

`_process` polls the crosshair every frame and writes the result into `_aimed`,
and the crosshair reports −1 for every frame it is not over a pill — so a
selection made with the arrow keys was wiped before the trainee could press
Enter on it. Found by trying to answer the review card from the keyboard and
watching the selection refuse to appear.

Pre-existing in `hazard_panel_3d.gd`, which is where the review card's
construction was copied from, so it arrived in the new panel too. The crosshair
now wins only when it is actually on something. Fixed in both.

---

## 3. One thing I added that nobody asked for

`torch_taken` gates nothing, which is what was ratified. But
`Assessment.next_step()` returns the first unresolved *available* step, and both
the objective pill and the checklist card read it — so a trainee who skipped the
torch would have had "Take the torch" standing where the real objective belongs
for the rest of the run. That is exactly the fault
`PLAYTEST_2026-09-04_pass2.md` §3 records "Perform the CPR set" causing for half
a run.

`main.gd::_close_torch_window()` fails the step on leaving `SCENE_SAFETY`. The
client's own framing is "before the work commences", and by `BREAK_CONTACT` it
has. It still costs its 4 marks and still appears in the debrief.
`check_torch_step` asserts both halves. **Overrule this if you would rather the
pill stuck.**

---

## 4. Carried from the audit, still true, still not fixed

Not in scope for this session; listed so they are not lost.

1. **The "Examine Breaker Panel" and "Reassess Open Board" reticle prompts sit
   over the hazard pills** at the working distance. Seen again this pass: at
   pass 2 the prompt covers the second and third options outright. `§7` item 6
   of the audit. It is a HUD layering question, not a hazard question.
2. **The compression hands land ~15.5 cm caudal of the sternum anchor.** Audit
   §7 item 1. Untouched.
3. **The choice card says "The casualty is not breathing" before breathing has
   been checked.** Audit §7 item 2. Untouched.
4. **The recovery roll re-closes the shirt over the AED pads.** Asset work.
5. **The hazard content is still unreviewed** apart from the one entry deleted
   this session. `OVERNIGHT_REPORT.md` §4 stands. The two unmeasured
   distractors — the ladder and the pipework — are still unmeasured, and
   `check_hazard_assessment` still asserts they stay flagged.

---

## 5. Invented decisions, listed so they are not mistaken for the client's

Everything here is ours. The audit's §3 exists because this project has form for
shipping invented content as though the client chose it.

| # | What | Where |
|---|---|---|
| V1 | **The kit grading formula.** `quality = 0.5 × selection_accuracy + 0.5 × naming_accuracy`, selection counting correct inclusions *and* correct exclusions across the whole manifest, naming counting correct names over objects named. Naming nothing scores 0.0, not 1.0 | `kit_bench.gd::quality()` |
| V2 | **The step is always completed, never failed.** The old `allowed_errors` cliff went with the merge; a merged step that scores continuously has no honest threshold in it | `kit_bench.gd::_finish()` |
| V3 | **Clicking a claimed object un-claims it.** The only way to change your mind. The alternative was a "not in the kit" entry on the naming menu, which would put the answer key's own question in front of the trainee every time they looked at a spanner | `kit_bench.gd::_on_item_inspected()` |
| V4 | **`torch_taken` fails on leaving SCENE_SAFETY** — §3 above | `main.gd` |
| V5 | **The hazard review loop is uncapped.** One correction was the old rule because a marked panel makes retrying free; nothing is marked now | `hazard_assessment.gd` |

### Client-facing wording written this session

Every new string, verbatim. None of it is the client's.

- Step title: **"Take the torch before the work starts"**
- Step prompt: *"Take the torch off the bench with the rest of your precautions. Isolating a board can take the lighting with it, and the moment you need to see the casualty is the moment after you have thrown the handle."*
- Sign mount refusal: **"Reassess the open board before you sign the point of isolation."**
- Kit brief instruction: *"Click each object you believe belongs in the low voltage rescue kit and name it. Anything you leave alone is an object you are saying is not in the bag."*
- Kit controls hint: *"Left click names an object or takes the claim back, [Enter] reviews your list, [Esc] frees the mouse."*
- Kit reticle prompts: **"In the LV rescue kit? Click to name it"** / **"Named as kit - click to take it back"**
- Kit selection chip: **"%d named  -  [Enter] to review"**
- HUD preamble labels: **"Name the LVR kit items"** / **"Check your list"**
- Kit review card: heading **"You have named these as LV rescue kit"**, empty line *"You have not named anything as rescue kit."*, buttons **"Correct"** / **"Confirm"**
- Hazard review card: heading **"You have reported these hazards"**, empty line *"You have not reported any hazards."*, buttons **"Correct"** / **"Confirm"**
- Hazard submit pills, reworded from "Confirm assessment": **"Submit assessment"** / **"Submit reassessment"** — they now submit to the review card rather than to the grader, so "confirm" belonged on the card instead

One piece of existing copy moved rather than being written: `kit_selected`'s
sentence about exclusions — *"Knowing what is not kit matters as much as knowing
what is - a bag full of the wrong things takes longer to search when it counts."*
— was merged into `kit_identified`'s prompt rather than deleted with the step,
because the merged step still grades exclusions and the trainee still has to be
told so.

---

## 6. What was NOT seen on screen

Said plainly so it is not mistaken for coverage.

- **The CPR half was not replayed.** The breathing check, the airway roll, the
  pulse hold, both compression sets, the shirt, the AED, the pads and the shock
  were all walked on screen last pass and nothing this session touched any of
  them. This pass reached the injury survey through `_warp_to_final_compressions`
  and `debug_jump_to_state`, so the casualty was not in the recovery pose during
  the survey — an artefact of the warp, not a regression.
- **The injury survey was driven through `CprStation.survey_injury()`, not
  through the body pointers.** That is the method the pointers call, and the
  three pointers were visibly still on the body after the finding, but the
  pointer clicks themselves were not exercised this pass.
- **The crook, the contact break, the drag and the breaker were not walked.**
  Reached by warp. Unchanged this session.
- **The debrief screen was not opened.** The score and the SCORM comments were
  read off the LMS log at exit instead, which is quoted in §1.
- **The kit review card was confirmed with the keyboard, not the crosshair, on
  its second raising.** The crosshair path on that card *was* exercised — Correct
  was clicked with it — and the keyboard path is the one the §2 fix restored.
- **Nothing was measured.** The ladder and the pipework are still unmeasured, as
  they were at the last two passes.
