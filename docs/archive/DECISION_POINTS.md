# Decision Points — design

A general mechanism for the moments where the exercise should stop and ask the trainee
**what they would do next**, then grade the answer.

Status: **designed, not built.** Written after the first case appeared in play: once the
breathing check is done, the two-way radio is still asking for a help call while the chest
pointers are asking for compressions. Two live directions, no stated priority, and no
record of which one the trainee thought was right.

Read alongside `CPR_CONTRACT.md` (§4.0 input model, §7 file ownership) and
`HANDOFF_2026-08-31.md` §4 (frozen files).

---

## 1. What a decision point is

A blocking, full-screen modal with a question and two to four options. The trainee picks
one. The pick is logged, graded, and steers what the world offers next.

It is not a quiz interstitial. It fires at a real branch in the procedure, at the moment
the branch opens, and the options are all things the trainee could physically go and do.

## 2. The rule everything else follows

> **A decision point chooses an intent. It never performs the act.**

Picking "Call for help" does not place the call. It records that the trainee said help
comes first, and then the world expects them to walk to the bench and use the radio —
which is a physical act with a physical object, deliberately (see `emergency_radio.gd`
and the handoff note that made it one). Picking "Start compressions" unlocks the
compression minigame; it does not deliver a rep.

This is the line that keeps the feature from quietly undoing the diegetic work: the menu
says *what I am going to do*, the room is still where you do it. It also gives grading
two independent facts to work with — what the trainee chose, and what they then actually
managed — which is more than either alone.

## 3. Data model

Two new resources, so decisions are authored rather than coded. Same shape as
`ProcedureStep` / `ProcedureList`, which they sit beside.

`scripts/core/decision_option.gd` — `DecisionOption`

| field | type | meaning |
|---|---|---|
| `id` | StringName | stable id, used in the transcript |
| `label` | String | the button |
| `detail` | String | one line under it; why you would pick this |
| `intent` | StringName | routed by the controller's dispatch table (§4.3) |
| `correct` | bool | whether this is the right call at this moment |
| `violation_reason` | String | recorded when a wrong option is taken |
| `feedback` | String | shown briefly after the pick, right or wrong |

`scripts/core/decision_point.gd` — `DecisionPoint`

| field | type | meaning |
|---|---|---|
| `id` | StringName | stable id |
| `title` | String | the question |
| `body` | String | optional context paragraph |
| `category` | StringName | transcript category, as on `ProcedureStep` |
| `step_id` | StringName | Assessment step the decision itself completes (optional) |
| `trigger_kind` | enum | `STEP_COMPLETED` / `CPR_STATE` / `PHASE` |
| `trigger_value` | StringName / int | the step id, CPR state, or phase to fire on |
| `requires` | Array[StringName] | steps that must be done first, else it does not fire |
| `unless` | Array[StringName] | steps that, if done, make it moot |
| `options` | Array[DecisionOption] | 2–4 |
| `time_limit` | float | 0 = untimed; see §5 |
| `weight` | int | points, if `step_id` is set |

Authored under `resources/decisions/*.tres`, collected by a `DecisionList` the way
`lvr_cpr_procedure.tres` collects steps. That resource is **not** frozen.

## 4. Runtime

### 4.1 The controller

`scripts/ui/decision_screen.gd`, a `CanvasLayer` spawned from `main.gd` alongside the
pause menu, dev menu and debrief — `main.tscn` is frozen, so nothing is authored into it.

Lifecycle:

1. `_ready()` loads the `DecisionList` and subscribes to `Events.step_completed`,
   `Events.cpr_state_changed` and `Events.phase_changed`. **No new signals** — `events.gd`
   is frozen.
2. A matching trigger whose `requires`/`unless` pass queues the decision.
3. It presents when nothing else is blocking (`Events.is_ui_blocking()` is false) and no
   camera tween is in flight; otherwise it waits. One at a time, FIFO.
4. Presenting calls `Events.open_ui(&"decision")` — the blocking path, so the player
   freezes and the mouse comes back. This is the one place in the exercise where that is
   correct: it is a deliberate pause, not a thing to be picked with the crosshair.
5. The pick is graded (§5), routed (§4.3), then `Events.close_ui(&"decision")` restores
   captured-mouse play.
6. Each decision fires once per run. `reset()` clears the record, as `Assessment.reset()`
   does.

### 4.2 What has to yield to it

`casualty_pointers.gd` must hide while a blocking UI is up — it currently does not test
for that, unlike `cpr_key_hint.gd`, which is the pattern to copy. Same for any repeating
centre prompt (`emergency_radio.gd`'s 12-second reminder): a decision modal should not
have a prompt shouting behind it.

### 4.3 Dispatch

The controller owns a small table mapping `intent` to a call, and nothing else in the
codebase knows decisions exist:

| intent | unlocks | closes off |
|---|---|---|
| `&"prioritise_help"` | the radio is the only live prompt | compressions pill withheld until the call is placed |
| `&"prioritise_compressions"` | `CprStation.compressions_armed = true` | radio's repeating prompt goes quiet; one reminder at AED_FETCH, graded late |
| `&"defer"` | nothing | the decision re-arms after N seconds |

Adding an intent is a table entry plus the one line it calls. Anything that needs more
than a line belongs in the system that owns it, not here.

### 4.4 What "closed off" means

Committing to one option takes the other off the screen. That is the point of the
feature: one instruction at a time, no two prompts arguing. But *off the screen* is not
*disabled*, and the difference matters to whoever builds this.

- **Withheld** — the affordance is not offered, and appears on its own the moment the
  chosen path completes. The compressions pill after `prioritise_help` is this: the call
  lands, the pill appears, nothing else to do.
- **Quietened** — the affordance still works, but stops asking. The radio after
  `prioritise_compressions` is this.

**Nothing on a mandatory safety path is ever disabled.** The radio in particular must stay
usable whatever the trainee chose: calling for help is graded, it is required, and a
trainee who realises halfway through the compressions that they skipped it has to be able
to get up and do it. Refusing that would teach the wrong lesson and cost them a step they
could otherwise still earn — late, but earned.

A branch closes when its chosen path completes, not when the modal shuts. Until then the
decision is still in force and the other option stays withheld or quiet.

## 5. Grading

- The chosen option is written to the transcript through `Events.log_action()` —
  `&"ok"` when `correct`, `&"warning"` otherwise, with `label` as the message and
  `feedback`/`violation_reason` as the detail. It lands in the debrief and in the SCORM
  comments field for free.
- A wrong pick calls `Assessment.record_violation(step_id, violation_reason)`.
- If `step_id` is set, a correct pick calls `Assessment.complete(step_id)` so the decision
  carries weight and appears as its own line in the debrief checklist. Add the step to
  `lvr_cpr_procedure.tres` when you add the decision.
- **A wrong pick is never blocked.** The trainee does the wrong thing, the world lets
  them, and the debrief says so. This is the same principle as reaching for an energised
  casualty bare-handed: the sim does not protect the trainee from a choice, it records it.
- `time_limit > 0` and no answer in time records the decision as hesitated — a `warning`
  line, no violation — and presents the correct option's routing so the run continues.

## 6. The first instance — help vs compressions

`resources/decisions/help_before_cpr.tres`

- **trigger** `CPR_STATE` = `BREATHING_CHECK`
- **unless** `[&"send_for_help"]` — already called, nothing to ask
- **title** "The casualty is not breathing. What do you do first?"
- **options**
  1. *Call for help and send for an AED* — `intent: prioritise_help`, `correct: true`,
     detail "One rescuer cannot run the resuscitation alone."
  2. *Start chest compressions immediately* — `intent: prioritise_compressions`,
     `correct: false`, reason "Compressions started before help was called."
- **step_id** `&"prioritised_help"` (new step in the procedure resource)

Result: after the breathing check there is exactly one live direction, and it is the one
the trainee chose. The contradiction that prompted this document stops being a UI bug and
becomes the thing being assessed.

Either way the run continues without a dead end: choose help and the compressions arrive
the moment the call is placed; choose compressions and the radio is still on the bench,
still gradable, just no longer shouting.

## 7. Other places this earns its keep

Candidates, in rough order of value:

- **Before touching the casualty** — isolate the supply, break contact with the hook, or
  check for a response first. The fatal-contact rule already exists; this makes the
  reasoning gradable instead of only the outcome.
- ~~**After the shock** — resume compressions, or re-check for signs of life.~~ Shipped,
  as body pills rather than a choice card: the shock leaves the minigame disarmed and
  both moves on screen (`casualty_action_menu.gd`, `_post_shock_callouts()`).
- **PPE at the kit bench** — which items this job actually needs.
- **AED pad placement** — offered only if both pads land wrong, as a teaching beat rather
  than a silent zero.

## 8. Constraints and edge cases

- `events.gd` and `main.tscn` are frozen. Triggers reuse existing signals; the controller
  is spawned from `main.gd`.
- Blocking UI freezes the player, which also switches `InteractionRay.active` off — the
  existing `open_ui`/`close_ui` path handles this, but anything holding the CPR camera
  must not be mid-tween when the modal opens, hence the deferral in §4.1 step 3.
- A decision that fires during the kit-check preamble must queue behind it, not stack on
  it.
- `fail_screen.gd` restarting the scene has to clear queued and answered decisions.
- WebGL2/SCORM: no new assets, no new fonts, plain Control drawing on `Tokens` styles.

## 9. Build order

1. `DecisionOption` / `DecisionPoint` / `DecisionList` resources, and one authored `.tres`.
2. `decision_screen.gd`: load, trigger, present, close. Hard-code the dispatch to a
   `print()` so the modal can be seen and clicked before it steers anything.
3. Grading and transcript.
4. Dispatch table and the `prioritise_help` / `prioritise_compressions` routing, plus the
   pointer/radio yielding in §4.2.
5. Second decision point, to prove the authoring path works without touching code.
