# Client conformance audit — 4 Sep 2026

Written for Nadir. Organised **by brief requirement**, so a gap shows up as a row
rather than as an absence.

## What this is checked against

The only authority used here is the client feedback conversation Nadir pasted on
4 Sep 2026, reproduced verbatim in §9 so nobody has to trust a paraphrase.
**No design document in this repo was treated as evidence of what the client
wanted.** Where a repo document is cited it is cited as the *build's* claim,
which is the thing being audited.

**The brief is a feedback round, not a specification.** It reads as comments on
an exercise that already existed ("It's a big step up from the last exercise").
It says nothing at all about the LVR half — the kit bag, the hazard survey's
content, the isolation sign, the breaker, the crook, the drag — except for the
five points it does raise. So "the brief never asked for this" in §3 means
exactly that and no more: it is a list of things the client will see and may
reasonably assume they specified. It is not an accusation that the work is
wrong.

Every row's verdict was reached by reading the resource or the code named in it,
and — where the row says so — by watching the beat run. The whole run was walked
this session through the real interactions: §6 says which parts, and which parts
are still only inferred.

**Nothing client-facing was changed.** One outright bug was fixed (§7).

---

## 1. Brief requirements, one row each

Verdicts: **met** · **partial** · **missing** · **reinterpreted** (built, but to
a reading the client has not seen).

| # | What the client asked for | Verdict | Where it is decided |
|---|---|---|---|
| B1 | "when yu identify the contents of the bag that should be displayed" | **met** | `scripts/interaction/kit_bench.gd:9-16` — stage two prompts for each selected item by name; watched on screen this session |
| B1a | "and if incorrect should be able to correct at that stage" | **met** | `kit_bench.gd:341-366` — a wrong first answer is refused, the item stays live, one correction is taken. Reproduced: answered the bag "Two-way Radio", got "Not correct — choose again" |
| B1b | "with the correction noted" | **met** | `kit_bench.gd:368-395` — both answers stored; transcript line "answered X, corrected to Y". Verified live: `answers` held `correct: false, choice: "Two-way Radio", corrected: true, final_choice: "LV Rescue Kit Bag"` |
| B2 | "Identify the hazards but can this be a drop down menu so its easier" | **reinterpreted** | `scripts/interaction/hazard_assessment.gd:7-10` reads "drop-down" as a tick-all-that-apply list. See §4 A1 |
| B3 | "should put on the cloves before the work commences" | **met** | `scripts/core/rescuer.gd:98`; `resources/procedures/lvr_cpr_procedure.tres:22-30` (`ppe_donned`, critical, weight 8) and `:32-41` (`hazard_identified` requires it). Walked: taking the gloves off the bench completed the step and unlocked the hazard survey |
| B4 | "also turn on the torche so you can see when the power goes out" | **missing** | The torch exists only as a kit item (`resources/kit/lvr_kit.tres:191-198`) and a pickup (`scripts/interaction/tool_rack.gd:105-107`). Grep for `torch\|flashlight` across `scripts/` returns those three lines and nothing else: no on/off, no light, and **the room does not go dark on isolation** — watched, the lighting was unchanged after throwing the breaker |
| B5 | "ensure the casulity is not on fire (make this no...)" | **met** | `scripts/casualty/casualty.gd:676-686` — one observation beat, outcome always "not alight". Taken on screen as a body pill |
| B5a | "...if thy were have to put out with fire blanket" | **missing, and arguably correctly so** | No fire branch exists. The blanket is kit only (`lvr_kit.tres:182-189`). The client's own sentence makes the fire "no", so the branch is unreachable by their instruction — but the exercise never tests the knowledge either. See §4 A7 |
| B6 | "No need to open shirt this will waste critical time" — **walked back by the client** to "do CPR then before we do the Defib open the shirt" | **met** | The shirt has exactly one moment, between the sets: `lvr_cpr_procedure.tres:204-211` (`chest_exposed` requires `pulse_checked`), `scripts/ui/casualty_action_menu.gd:96-99`. Watched: 30 compressions with the shirt on, then "Open the shirt", then the pads |
| B7 | "for now we're doing 30 compressions then setting up AED" | **partial** | The first set is 30 (`scripts/cpr/compression_driver.gd:41`) and it precedes the AED. But a **second full set of 30** runs after the shock (`compression_driver.gd:42`), which the brief does not mention. See §3 I8 |
| B8 | "before the AED goes on we also need to check pulse etc as in videos" | **met** | `lvr_cpr_procedure.tres:183-192` (`pulse_checked`, critical, weight 8); `scripts/cpr/breathing_check.gd` PULSE state. Played: "Two fingers to the side of the neck — hold Left Click for a carotid pulse" |
| B9 | "The first look listen feel like you did with the ear" | **met** | `breathing_check.gd` + `scripts/cpr/cpr_ear_2d.gd`. Seen filling on screen for the first time this session — it was broken until today, §7 |
| B10 | "then they roll over to check a blocked airway" | **met** | `lvr_cpr_procedure.tres:173-181` (`airway_inspected`), `casualty.gd:690-702`. The roll runs and the finding is "airway clear". *Caveat:* the roll itself was not caught on screen this pass — see §6 |
| B11 | "if not blocked then check for pulse, if no pulse go into CPR" | **met** | Spine order `BREATHING_CHECK → AIRWAY_INSPECT → PULSE_CHECK → COMPRESSIONS_1` (`scripts/cpr/cpr_station.gd:41-44`). Walked in that order |
| B12 | "once there is a pulse they put back into recovery position (on the side)" | **met** | `lvr_cpr_procedure.tres:232-240`; the `LVR_Recovery` clip on the skinned body. Seen: on the side, top knee up, head on the lower arm |
| B13 | "and check for any other injuries whilst help arrives" | **partial** | Three sites offered, one finding (`casualty.gd:986-1002`). But it is a one-shot survey that ends the moment the burn is found, then hands over immediately — there is no "whilst help arrives" period. See §4 A6 |
| B14 | "we can then even have a ambulance sound arriving to take over if you like" | **met** | `scripts/cpr/cpr_cue_audio.gd:44`, `audio/cues/ambulance_arrive.wav`. Measured audible last session (peak −22.7 dB). **It is a synthesised placeholder, not a recording** — `cpr_cue_audio.gd:42` says so |
| B15 | implicit: "The competent assistant" is the trainee | **reinterpreted** | The trainee is cast as "Safety Observer" (`scripts/ui/kit_check.gd:36-39`). The client's own word is "competent assistant". Wording the client will read as theirs; it is not |

**Nothing in the brief is flatly unbuilt except B4 (the torch and the blackout)
and B5a (the fire-blanket branch).** Everything else is either met or built to a
reading worth confirming.

---

## 2. Requirements that were met but not *reachable* — read this next to §1

Two rows above say "met" on the strength of the resource and the code, and would
have been just as true of a build nobody could finish.

- **B9, and B7's minigame, were both unplayable by hand until this session.** The
  breathing check and every compression rep refused with "Aim at the casualty's
  mouth/chest" at the game's own camera anchor. Fixed today and verified on
  screen — §7. Had the client opened the build before that, the exercise would
  have stopped dead at the first look-listen-feel.
- That is the second time a run-ending fault has sat behind a green headless
  suite. `tools/check_run_order.tscn` drives the same beats through the station's
  *methods*, which never touch the crosshair, so it passed throughout.

---

## 3. In the build, never asked for by the client

Each row names what a client would take for their own decision, and who made it.
None of this is necessarily wrong; all of it is unratified.

| # | What the client will see | Who authored it | File |
|---|---|---|---|
| I1 | **All twelve hazard lines**, the real/distractor split, and every rationale paragraph | Agent, overnight run of 3 Sep — `docs/OVERNIGHT_REPORT.md` §4 states outright that the client supplied none of it | `resources/hazards/hazards_pass1.tres`, `hazards_pass2.tres` |
| I2 | "Lighting will be lost when the board is isolated", scored as a **real** hazard | Same. **The simulation does not model it** — confirmed on screen: nothing went dark on isolation. A trainee who does not tick it loses marks for failing to perceive something absent | `hazards_pass1.tres:49-56`; its own `review_note` says this |
| I3 | "Ladder stored across the walkway" and "Overhead pipework at head height", scored as **distractors** | Same. Both objects exist; neither placement was ever measured. If either really obstructs, the trainee is marked wrong for being right | `hazards_pass1.tres:58-74` |
| I4 | **The whole 26-step procedure** — every step title, prompt, category, weight, `critical` flag, `time_limit` and late-message | Agent | `resources/procedures/lvr_cpr_procedure.tres` |
| I5 | **The grading model**: pass mark 80 %, ×0.5 out-of-order, ×0.75 late, CPR scaled by depth | Agent | `scripts/core/procedure_list.gd:14`, `scripts/core/assessment.gd` |
| I6 | **The 17-item kit manifest** — which six are in the bag, which eleven are not, and every rationale | Agent | `resources/kit/lvr_kit.tres` |
| I7 | **A second graded kit step** (`kit_selected`, weight 6): sweep the bench and tick the kit before naming it. The brief asks only that contents be *identified* | Agent | `lvr_cpr_procedure.tres:6-13` |
| I8 | **A second full 30-rep set after the shock** | Agent; `compression_driver.gd:42` argues for it ("a third of the length teaches that the work gets easier after the shock") | `scripts/cpr/compression_driver.gd:42` |
| I9 | **The post-shock trap**: "Check for signs of life" offered beside "Start compressions" and scored as a wrong move | Agent | `scripts/ui/casualty_action_menu.gd:104-110`, `CPR_CONTRACT.md` §4.5 |
| I10 | **The help/CPR choice card** and its wording, including "The casualty is not breathing. What do you do first?" | Agent | `resources/decisions/help_before_cpr.tres` |
| I11 | **The two run-ending outcomes** and their wording | Agent | `scripts/casualty/casualty.gd:339-345`, `scripts/cpr/shock_button.gd:289` |
| I12 | **The injury findings** — "Burn to the right palm — the contact point", plus two "clear" sites | Agent | `scripts/casualty/casualty.gd:986-1002` |
| I13 | **The opening brief text** — "You are the Safety Observer while a worker carries out planned live low voltage electrical work…" | Agent | `scripts/ui/kit_check.gd:36-45` |
| I14 | **Ten AED voice lines**, and a unit that repeats an unanswered instruction every 12 s | Agent | `scripts/cpr/aed_voice.gd`, `audio/aed/`. Observed in one run: "Attach the pads to the patient's bare chest" **thirteen times** between 07:22 and 09:34 |
| I15 | **"Send for help – call 000"** — an Australian emergency number | Agent | `lvr_cpr_procedure.tres:130-141`. Worth confirming the client's jurisdiction; the rest of the wording is UK/AU-neutral |
| I16 | **The two-pass hazard structure** (survey from the floor, then reassess inside the open board) | Agent | `hazard_assessment.gd:12-24` |

---

## 4. Where the brief is ambiguous and we picked a reading without flagging it

| # | The words | The reading we shipped | The alternative we did not take |
|---|---|---|---|
| A1 | "can this be a drop down menu so its easier please" | A floating tick-all-that-apply checklist on the board: eight lines, one submit. `hazard_assessment.gd:7-10` records the reading in a code comment — **and nowhere the client will read it** | An actual drop-down: pick hazards one at a time from a closed list. Their stated goal was "easier", and a 1024×768 panel of eight full sentences is arguably not that |
| A2 | "if incorrect should be able to correct at that stage with the correction noted" | The **first** answer scores; the correction is recorded and worth nothing (`kit_bench.gd:24-31`, `hazard_assessment.gd:26-31`) | The correction scores. Our reasoning is sound — once the panel names the wrong lines, fixing them is free — but "noted" does not say "not counted", and they may have meant a second chance that pays |
| A3 | "turn on the torche so you can see when the power goes out" | The torch is a kit item to be *named*, not a tool to be *used*; the power going out is not modelled | Model the blackout on isolation and make the torch a working light. This is the one place where the reading and the requirement genuinely diverge — see B4 |
| A4 | "for now we're doing 30 compressions then setting up AED" | 30, AED, shock, then another 30 | 30 and done. "For now" reads as a scoping note and we widened it |
| A5 | "check pulse etc as in videos" | A single 5 s carotid hold | "etc" could be pulse + breathing + colour/skin signs. We took the narrowest reading |
| A6 | "check for any other injuries whilst help arrives" | Three checks; ends on the finding; straight to handover | A monitoring period the trainee has to hold until the ambulance arrives — closer to what "whilst help arrives" says, and it would give the siren something to interrupt |
| A7 | "make this no if thy were have to put out with fire blanket" | Always "no"; no fire, no blanket branch | Sometimes yes, with the blanket as the answer. The sentence is genuinely ambiguous between "make the answer no" and "make it no *for now*" |
| A8 | "The competent assistant should put on the cloves" | Gloves are picked up; **boots and long sleeves are seeded as already worn** (`scripts/core/rescuer.gd:24-30`), because the room contains no boots or sleeves | Model all three. Ours is defensible — site dress is worn before entering a switchroom — but the checklist reads "Long sleeves, long trousers, insulated gloves and boots" (`lvr_cpr_procedure.tres:26`) and the trainee only ever does one of them |

---

## 5. The two questions already put to the client, answered against the brief

These are the questions standing in `docs/client_messages.md`. Answered here from
the brief, not from our own documents.

### "Does the sequence match your training standard?"

**Against the brief: yes, for the stretch the brief describes, with one addition.**

The client gave an explicit order in their last two messages: *look-listen-feel
with the ear → roll over to check for a blocked airway → if not blocked, check
for a pulse → if no pulse, CPR*; then *30 compressions → open the shirt → check
pulse etc → AED*; then *pulse returns → recovery position → check for injuries →
ambulance*.

The build runs exactly that:

```
BREATHING_CHECK -> AIRWAY_INSPECT -> PULSE_CHECK -> COMPRESSIONS_1 (30)
  -> EXPOSE_CHEST -> AED_FETCH -> AED_DEPLOY -> PAD_PLACEMENT -> SHOCK
  -> COMPRESSIONS_2 (30) -> RECOVERY_ROLL -> INJURY_SURVEY -> HANDOVER
```

(`scripts/cpr/cpr_station.gd:41-53`; walked end to end this session.)

Two honest qualifications:

1. **`COMPRESSIONS_2` is ours, not theirs** (§3 I8). It is the only element of
   the sequence the brief does not contain. Ask about it specifically, or the
   answer will not be about it.
2. **The pulse is checked once, before CPR — not again before the AED.** The
   client wrote "before the AED goes on we also need to check pulse". In the
   build the pulse is checked before the first compression set and never again;
   between the set and the pads the trainee only opens the shirt. Whether that
   satisfies them is exactly what "does it match your standard" should be asked
   *about*, by name.

So the question as currently worded is too broad to get a useful answer. It
should name I8 and the single pulse check.

### "Are the two run-ending mistakes the right two?"

**Against the brief: unanswerable, because the brief never mentions run-ending
mistakes at all.** Both were invented here (§3 I11):

1. Reaching a casualty still in contact with the conductor without the insulated
   crook *and* gloves — `casualty.gd:339-345`.
2. Delivering the shock while kneeling at the casualty — `shock_button.gd:289`,
   which tests `CprStation.trainee_at_anchor()` at the moment of activation.

Judged against the brief rather than against our docs:

- **(1) is well-founded.** It is the one thing the client's own instruction
  implies — "the competent assistant should put on the gloves before the work
  commences" only means something if working without them has a consequence.
- **(2) is not.** The brief says nothing about the shock, standing clear, or
  contact at discharge. It is defensible first-aid teaching and it is entirely
  ours. It is also the mistake `docs/PLAYTEST_2026-09-04.md` fix 5 records the
  game *inviting* a trainee into — the kneel-back prompt has since been removed,
  but the outcome was reached by following an instruction, once.
- **A third candidate exists and we do not fail on it.** `aed_used` with two
  wrong pads scores zero for the step and is still *completed*, never fatal
  (`CPR_CONTRACT.md` §5). If the client's standard treats gross
  mis-defibrillation as a run-ender, that is a third to add — and it is a
  question they can actually answer.

The message should therefore not ask "are these the right two". It should say
which two exist, say plainly that they are our proposal, and ask what they want
failed.

---

## 6. What was actually walked this session, and what was not

Because §1's verdicts are only worth what the evidence behind them is worth.

**Walked through the real interactions, most of it seen on screen for the first
time:**

- The opening brief and the bench sweep — six items ticked by crosshair, "6
  selected", `KitBench.selected` confirmed.
- The identify stage, including a deliberate wrong answer and its correction.
- Donning the gloves; `ppe_donned` completing off the pickup.
- Hazard pass 1: the panel rendered and legible from the board, a deliberate
  incomplete answer, the retry notice, the marked line, "Confirm your
  correction", and the recorded `quality 0.8` / `final_quality 1.0`.
- Opening the panel; the busbars exposed; hazard pass 2 on screen.
- Taking the sign, hanging it, the shock, the crook, breaking contact against the
  live 20 s timer, the drag, and throwing the breaker.
- The primary-survey body pills; the fire check; the response check; the choice
  card and its "Call for help" route; the radio.
- **The breathing check — the drawn ear filling.** Never before seen.
- The airway-blockage roll and the carotid pulse hold.
- **The compression minigame, both sets, 60 reps by hand.** Never before played.
  Debrief: 100 % in depth, 83 % in rate.
- Opening the shirt; fetching, deploying and arming the AED.
- **The AED pads on the chest.** Never before seen. Both correct sites, cabled to
  the unit.
- Standing clear, the shock, the post-shock gotcha pair, the recovery roll, the
  injury survey and the debrief.

**Still not confirmed on screen:**

- **The airway-inspection roll itself.** The step completes and
  `in_recovery_pose()` read true, but the screenshot lagged the roll both times.
  The recovery-position roll *was* seen, and it is the same clip.
- **The ambulance siren.** Not heard this pass; the debrief took the screen. It
  was measured audible last session, so this is a gap in this pass's evidence,
  not a regression.
- **The shock arc.** It fired while the camera was inside the worker's mesh.

---

## 7. Bugs found, and the one that was fixed

Fixed and committed, because it was a run-ender rather than content:

- **`877962f` — the breathing check and every compression rep refused, on the
  body.** `CprInteractBridge.crosshair_on_node_named("Casualty_CPR_Posed")`
  returned false at the authored `Anchor_Head` pose with the crosshair squarely
  on the casualty. The 3 Sep reorder put `BREATHING_CHECK` and `COMPRESSIONS_1`
  before `EXPOSE_CHEST`, so the clothed skinned body is what is on screen and the
  posed mesh is hidden through both; the posed mesh's collider is one coarse
  convex hull that the anchor's own ray misses. The test never moved with the
  reorder. `crosshair_on_casualty()` now accepts either body. Suite 10 green.

Found, **not** fixed, because they are content or placement and are yours to call:

1. **The compression hands land ~15.5 cm caudal of the point the game itself
   calls the sternum.** `CprRig.point_chest_pos` — the "Open the shirt" anchor,
   documented at `scripts/cpr/cpr_rig.gd:169` as "the sternum: where the shirt is
   opened and the compressions land" — sits at world x 3.704; the hands are drawn
   at the chest-frame origin, x 3.549. On screen the hands rest over the
   waistband. Hand placement is the one thing a CPR assessor looks at.
2. **The choice card says "The casualty is not breathing" before the trainee has
   checked breathing** (`help_before_cpr.tres:330`; it fires on
   `check_response`). It hands the trainee the finding of the assessment the
   client asked to be made with the ear.
3. **`CPR_CONTRACT.md` §6.2 is stale.** It says "Start compressions" needs "state
   COMPRESSIONS_1 and chest exposed". The real rule is `state <= COMPRESSIONS_1`
   with no chest requirement (`casualty_action_menu.gd:521-532`) — so the pill is
   on the body from the trainee's first interaction, sitting at the top of the
   stack above "Check for a response". Deliberate as a permitted mistake; it
   reads as the recommended one.
4. **`supply_isolated` is critical, weight 8, and `suppress_prompt = true`**
   (`lvr_cpr_procedure.tres:101-110`). After the drag the objective card is
   blank; nothing on screen asks for the breaker.
5. **The kit identify panel draws its choices behind the checklist card** in the
   top-left, so the heading — including "Not correct — choose again" — is
   partially occluded. Screenshotted.
6. **The "Examine Breaker Panel" interaction prompt covers a hazard option**
   ("Ladder stored across the walkway") at the working distance.
7. **The post-shock pills' leader lines cross**, so "Check for signs of life"
   appears to point at the chest and "Start compressions" at the mouth.
8. **The AED repeats "Attach the pads to the patient's bare chest" every 12 s**
   until the first pad lands — thirteen times in one observed run
   (`aed_voice.gd:63`, `NAG_SECONDS`). Deliberate, and more insistent than a real
   unit.
9. **`compression_driver.gd:179-192` hard-codes left-click and Space** rather than
   reading the `compress` action, so a rebind silently does nothing.
10. Carried, unchanged: **the recovery roll re-closes the shirt over the AED
    pads** (`docs/PLAYTEST_2026-09-04_pass2.md` §5.1). Seen again this session.

---

## 8. What to do before the client sees this

In the order that matters.

1. **`OVERNIGHT_REPORT.md` §4's warning still stands and nothing has retired it.**
   The twelve hazard lines are the largest block of invented content the client
   would read as theirs, and two of them (I2, I3) can mark a correct trainee
   wrong. Either get them reviewed or hold the hazard survey out of the review
   build.
2. **Rewrite the two questions in `docs/client_messages.md`** along §5 — name the
   second compression set, name the single pulse check, and present the two fatal
   outcomes as a proposal rather than a fait accompli.
3. **Decide B4.** The torch is the one plain instruction in the brief the build
   does not carry out, and the hazard list already scores a trainee on the
   blackout that is missing.
4. **Measure the ladder and the pipework** before either ships as a distractor.
5. Nothing in §3 or §4 should be changed until you say so.

---

## 9. The brief, verbatim

> The first up I think when yu identify the contents of the bag that should be displayed and if incorrect should be able to correct at that stage with the correction noted................We need to Identify the hazards but can this be a drop down menu so its easier please........................The competent assistant should put on the cloves before the work commences also turn on the torche so you can see when the power goes out...............Need to ensure the casulity is not on fire (make this no if thy were have to put out with fire blanket.........No need to open shirt this will waste critical time....................When the casualty begins breathing we need to place into the recovery position and monitor for any injury until the emergency response arrives............
>
> — *Are you sure about the no need to open shirt? That way we can't do AED part*
>
> Oh I forgot about that what don't we go CPR then before we do the Defib open the shirt
>
> — *Yes for now we're doing 30 compressions then setting up AED. So we can do the first compressions with shirt on then open it for AED*
>
> Yes but before the AED goes on we also need to check pulse etc as in videos
>
> — *Sure. For now we're checking breath, I'll add pulse check*
>
> See how they roll him over that is to check their airway for a blockage........................The first look listen feel like you did with the ear then they roll over to check a blocked airway if not blocked then check for pulse, if no pulse go into CPR..........once there is a pulse they put back into recovery position (on the side) and check for any other injuries whilst help arrives we can then even have a ambulance sound arriving to take over if you like :)
