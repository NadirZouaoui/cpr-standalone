# LVR CPR — CPR Phase Handoff

Written for whoever picks this up next. Read `CPR_CONTRACT.md` and `CPR_AGENTS.md`
alongside this; they are the frozen spec and the agent briefs. This file is the state of
play and the things that are not written down anywhere else.

Project: `D:\Nadir\Documents\Work\Freelance\HV Exercices Simulations\LVR CPR\lvr-cpr`
Godot 4.7.1 · Blender 5.2 LTS · target is SCORM 1.2 / WebGL2 in an iframe.

---

## 1. What this is

A first-person training sim for Low Voltage Rescue and CPR in a simulated electrical
switchroom. The trainee identifies hazards, dons PPE, isolates the breaker, breaks
contact with an insulated crook, drags the casualty clear, then performs CPR with an AED.

The CPR phase is the newest part. It was built by scoped sub-agents (A–L), each owning an
exclusive slice of files, coordinated through `CPR_CONTRACT.md`. That structure works —
keep it. The failure mode to watch is an agent reaching for editor `NodePath`s instead of
runtime name binding.

**Design intent:** this is not a clinical CPR trainer. The trainee learns real CPR from an
instructor. The phase teaches the *shape* of the response — check breathing, compress to a
metronome, fetch and deploy the AED, place pads, shock, resume. Rescue breaths, recovery
position and rhythm analysis were cut deliberately, not forgotten. Do not re-add them.

---

## 2. The spine

Eight states, linear, no branching. Owned by `scripts/cpr/cpr_station.gd`.

```
0 EXPOSE_CHEST     free camera, free movement
1 BREATHING_CHECK  Anchor_Head    · hold ~3s, chest does not rise
2 COMPRESSIONS_1   Anchor_Kneel   · 30 reps, or 10 + fast-forward
3 AED_FETCH        free           · the one free-movement beat, deliberate
4 AED_DEPLOY       free           · click the ghost AED beside the casualty
5 PAD_PLACEMENT    Anchor_PadSide · 5 ghosts, 2 correct, wrong ones accepted silently
6 SHOCK            Anchor_Shock   · pull-back IS the stand-clear; click the AED
7 COMPRESSIONS_2   Anchor_Kneel   · ~10 reps
8 COMPLETE
```

The breathing check is the phase's **one hard gate**. Everywhere else in this sim,
out-of-order actions are permitted and recorded; here compressions are unreachable before
the check because the check is the causal reason for them. The asymmetry is intentional.

Pad placement is a **puzzle, not a drill**: all five ghosts show at once, hover recolours,
click commits, and a wrong site sticks with no feedback whatsoever. The trainee commits
without being told. The error surfaces only in the debrief.

---

## 3. Files

### Shared infrastructure (frozen to all agents)
| File | Role |
|---|---|
| `scripts/cpr/cpr_ghost.gd` | ghost material factory + cache, recursive node finders |
| `scripts/cpr/cpr_rig.gd` | camera/UI anchors derived from the chest bone; editor gizmos |
| `scripts/cpr/ghost_target.gd` | runtime wrapper turning an imported mesh into a clickable ghost |
| `scenes/cpr/CprRig.tscn` | near-empty; just the root + `cpr_rig.gd` |

### Per-agent
| File | Agent |
|---|---|
| `cpr_camera_rig.gd` | A |
| `cpr_panel_3d.gd`, `scenes/cpr/CprPanel.tscn`, `cpr_panel_stub_emitter.gd` | B |
| `compression_driver.gd`, `casualty_cpr.gd` | C |
| `aed_station.gd`, `pad_station.gd` | D |
| `cpr_station.gd`, `cpr_headless_test.gd/.tscn` | E |
| `cpr_interact_bridge.gd` | G |
| `shock_button.gd` | H |
| `scripts/main.gd` seams + `Assessment` wiring | I |

Agents A–L have all run. J and L are complete: the three `Assessment` steps exist in the
`.tres`, the legacy menu suppression is in, the fast-forward is wired, and the look clamp
is exposed as `@export`s on `CprCameraRig`.

---

## 4. Verified working (checked live via `game_eval`, not assumed)

- Spine advances correctly through every state.
- `AedStation` binds `AED Defibrilator Cabinet` and `AED Defibrilator CPR` — both names are
  correct, both `GhostTarget`s registered with the bridge, colliders built.
- All five `PadSite_*` meshes present under `/root/Main/ControlRoom/`, hidden at start.
- `CprInteractBridge._ray` resolves to the real `InteractionRay`.
- On entering `AED_FETCH` the camera releases: `active=false`, player unfrozen,
  `InteractionRay.active=true`.
- `phase_changed → PRIMARY_SURVEY` sets state 0; `Assessment.complete("chest_exposed")`
  emits `step_completed` and advances to state 1.
- All four casualty animations import again (see §6).

---

## 5. Open issues

1. **`AED_FETCH` gives the trainee no instruction.** The floating panel fades out during
   this state — that was a deliberate design call in `CPR_CONTRACT.md` §6 and it is
   **wrong**. It is the one moment the trainee must find an object across the room, and
   there is no prompt and no highlight. This is the most likely reason the phase "stops"
   after compressions. Needs a centre prompt ("Fetch the AED from the cabinet") plus a
   highlight or outline on the cabinet unit.
2. **Mouse may stay released at `AED_FETCH`.** `Player.reclaim_camera()` only re-captures
   the mouse when nothing is UI-blocking. Measured `Events.is_ui_blocking() == true` and
   `Input.mouse_mode == VISIBLE` at that moment in a synthetic run — possibly an artefact
   of jumping into a fresh scene, possibly real. **Unresolved question for the human:
   after 30/30, can you walk with WASD, and can you turn with the mouse?** Can't move →
   handback failed. Can move but not turn → this issue. Both fine → issue 1 is the whole
   story.
3. **Editor gizmos on `CprRig` do not appear.** Wireframe frustums are built as
   `ImmediateMesh` children of each anchor, editor-only, `owner = null`. Never draw. Not
   diagnosed. See §8.
4. **Anchor angles need tuning.** The breathing-check anchor is pitched too high — the body
   sits at the bottom of frame. All tunable in the inspector on `CprRig`.
5. **Breaker mesh renders yellow permanently.** Still unresolved, and still blocked on one
   question: is it yellow **from level load** (a material/import problem, unrelated to CPR)
   or **only after CPR starts** (a stuck interaction highlight)? Agent K added a hover-clear
   in `CprCameraRig._take_camera()` for the second case. Establish which before digging.
6. **Old granular `.tres` steps still present.** `compressions_started`, `pads_placed`,
   `clear_for_analysis`, `shock_delivered`, `compressions_resumed` remain alongside the new
   `breathing_checked` / `cpr_performed` / `aed_used`. Agent J left them because they still
   have live emitters. Retiring them is a design call nobody has made.

### Not started
- AED voice audio (~10 lines, generic non-manufacturer wording, flat unhurried delivery),
  metronome sample at 110/min, negative tone for the breathing-check result.
- `FpsArms` — cut at mid-upper-arm. Four clips: `Arms_Idle`, `Arms_Compress` (scrubbed by
  the same depth float as the shape key, so they cannot desync), `Arms_PadHold`,
  `Arms_Carry`.

---

## 6. Architectural rules that must not be broken

Each of these has already cost a debugging session.

- **Runtime node binding by name only.** Never editor `NodePath`s. The `ControlRoom` `.blend`
  node tree is rebuilt wholesale on every reimport and authored properties in `main.tscn`
  get silently dropped. Bind from `call_deferred("_build")`, not `_ready()`.
- **Nodes added in code with `owner = null`** are never serialised and survive reimports.
- **`Time.get_ticks_msec()` for all gameplay timing.** WebGL2 frame pacing inside a SCORM
  iframe is unreliable; `delta` will lie.
- **The casualty's `AnimationPlayer` has exactly one owner** (`Casualty`). Compressions and
  shock are blend shapes driven through `casualty_cpr.gd`, never animation tracks.
- **Blend shape indices resolved by name**, never literal index — glTF ordering is not
  stable across reimports.
- **No Area3D mouse picking.** The game runs `MOUSE_MODE_CAPTURED`; Godot's built-in camera
  picking fires at a stale screen point. Everything goes through `cpr_interact_bridge.gd`.
- **Only bone origins, never bone bases.** The Mixamo armature carries scale
  `(0.01, 0.01, -0.01)` — negative determinant — so anything derived from a bone basis comes
  out mirrored. `cpr_rig.gd` builds its chest frame from origins alone.
- **Godot sanitises the colon in bone names** (`mixamorig:Spine2` → `mixamorig_Spine2`).
  Suffix matching is more robust than exact names.
- **`--check-only --script` false-positives** on autoloads and `class_name` globals. Booting
  the main scene is the reliable parse check.
- **Do not trust signal-ordering assumptions across autoload spawn order.** See §7.

---

## 7. Two bugs worth remembering

### The PRIMARY_SURVEY ordering race (fixed)

Agent I hooked `enter_cpr_phase()` to `Events.phase_changed` reaching
`SimState.Phase.PRIMARY_SURVEY`, assuming that phase begins when the extraction drag ends.
It does not — the checklist shows "PRIMARY SURVEY" while "Identify the LVR rescue kit" is
still pending, so it fires near scenario start, potentially **before** `_spawn_cpr_station()`
has run. The `_cpr_station != null` guard then skips it, `current_state` stays `-1`, and
`begin_breathing_check()` silently early-returns. Symptom: exposing the chest does nothing,
intermittently, depending on spawn order.

Fixed in `scripts/main.gd` `_on_step_completed()` by calling the idempotent
`enter_cpr_phase()` immediately before `begin_breathing_check()`, making seam 2
order-independent.

### The animation import trap

`LVR_Fiddle`, `LVR_ShockEnter` and `LVR_ShockHold` vanished from Godot while being present
in Blender. Godot's `.blend` importer exposes `blender/animation/group_tracks`, which it
passes to the glTF exporter as `export_nla_strips=True` — one animation per NLA track. The
armature had zero NLA tracks, so only the single active action exported.

Godot's blend importer never passes `export_animation_mode='ACTIONS'`, so the older pipeline
notes (Animation Mode = Actions, Merge Animation = Actions) apply only to a *manual* glTF
export and cannot be reached through direct `.blend` import.

**Fix, applied:** each clip pushed onto its own NLA track named after the action, plus the
`LVR_Fall` shape-key track pushed onto `Mesh.001` so the eye-closure morph rides along.
Active action cleared. Script stored as Blender text block **`nla_push.py`**.

**Re-run `nla_push.py` after any `slice` stage** — slicing recuts the clips and wipes both
the NLA tracks and `LVR_Fall`'s `KEKey` slot. Also keep `animation/fps=24` in the import
dock; it was 30, making everything play 25 % fast.

---

## 8. The gizmo problem (open issue 3)

`cpr_rig.gd` builds wireframe view frustums as `MeshInstance3D` children of each anchor,
colour-coded, with an UP tick so roll is readable. Editor-only, `owner = null`. They do not
appear. Places to look, in order:

1. Is `_rebuild_gizmos()` reached at all? `_process` only calls it when
   `Engine.is_editor_hint() and _gizmos_dirty`. Add a `print`.
2. Do the `Anchor_*` markers exist as children at edit time? Gizmos parent to them.
3. `_attach_mesh()` sets `mat.no_depth_test`. That property was reworked in Godot 4.4 and
   this is 4.7. It compiles, so it exists — verify it behaves.
4. Verify a trivial two-vertex `ImmediateMesh` line renders at all before debugging the
   frustum maths.

**Simpler fallback:** drop the custom mesh and add a real `Camera3D` child per anchor.
Godot draws the frustum for free and gives a **Preview** button showing exactly what the
trainee sees. Catch: `owner = null` nodes do not appear in the Scene dock, so you would need
to set their owner to the edited scene root, risking serialisation. Weigh against the
reimport-resilience rule in §6.

---

## 9. Suggested order of work

1. Answer the `AED_FETCH` question in §5 item 2 — walk yes/no, turn yes/no. One playtest.
2. Fix §5 item 1: prompt plus cabinet highlight during `AED_FETCH`. Likely the whole story.
3. Play through to the end for the first complete run.
4. Resolve the breaker-yellow question (§5 item 5) — establish *when* it turns yellow first.
5. Tune anchors (§5 item 4) and the look clamp in the inspector.
6. Then audio and `FpsArms`.

The gizmo issue is quality-of-life for tuning, not a blocker. Do not let it consume a
session ahead of items 1–3.

---

## 10. Debugging technique that worked

`godot-mcp:run_project` then `game_eval` to walk the live scene tree and read node state is
far faster than reading source and guessing. Pattern used repeatedly here:

```gdscript
var stack = [Engine.get_main_loop().root]
var found = {}
while stack.size() > 0:
    var n = stack.pop_back()
    var s = n.get_script()
    if s != null:
        var p = str(s.resource_path).get_file()
        if not found.has(p): found[p] = n
    for c in n.get_children(): stack.append(c)
```

Then `get_script().get_script_property_list()` to enumerate private fields without knowing
their names in advance, and `Events`/`Assessment` calls to drive the spine directly.

**Caveat learned the hard way:** `debug_jump_to_state()` skips the states in between, so
guards like `release()`'s `if not active: return` never run and readings mislead. Drive
through the real sequence (state 2 before state 3) or the measurement is an artefact.

Also: a single parse error in a shared `@tool` script presents as *nothing works and the
inspector is blank*, and cascades as "Failed to compile depended scripts" across every
dependent file including `main.gd`. Check the Errors panel first.

---

## 11. Working preferences

- Review plans before execution; delegate implementation to tightly scoped sub-agents;
  check results before proceeding.
- Prefer executing directly via MCP over handing over instructions — except for genuinely
  small edits, which are faster to apply by hand.
- Targeted patches to existing `.gd`/`.tres` files via PowerShell `Get-Content -Raw` /
  `String.Replace()` / `Set-Content -NoNewline`, verified with `Select-String` afterwards.
  Reserve whole-file writes for new files.
- Headless regression scenes are plain `Node` + script, no `.tscn` editor involvement:
  instantiate the real main scene, drive it over the `Events` bus, assert on autoload state,
  quit with an exit code.
- Keep replies short. Detail on request.
