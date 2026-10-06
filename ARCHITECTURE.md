# LVR CPR — Architecture Notes

The engine-level rules and the traps behind them. Every entry here has already cost a
debugging session; the reason is recorded so it does not have to be rediscovered.

Behaviour lives in `CPR_CONTRACT.md`. State of play lives in `PROJECT_STATUS.md`.

---

## 1. Rules that must not be broken

### Bind room nodes by name at runtime, never by editor NodePath
The room is an imported `.blend`. Its node subtree is rebuilt wholesale on every reimport
and authored properties in `main.tscn` have been silently dropped before. Use
`CprGhost.find_node()` / `CprGhost.find_nodes_with_prefix()`, and bind from
`call_deferred("_build")` rather than straight out of `_ready()` — the `ControlRoom`
instance may still be settling on the frame a node enters the tree.

On a failed bind: `push_error` naming the exact string that was tried, disable the node,
do not crash.

### `owner = null` on every node added in code
So it is never serialised into a scene file and survives reimports.

### `Time.get_ticks_msec()` for all gameplay timing
Never frame deltas. WebGL2 frame pacing inside a SCORM iframe is unreliable and `delta`
will lie.

### The mouse stays `MOUSE_MODE_CAPTURED`. No Area3D mouse picking.
Godot's built-in camera picking (`mouse_entered`, `input_event`) fires its ray at a stale
screen position, not at the crosshair, and does not work here. Everything goes through
`cpr_interact_bridge.gd`, which asks the project's own crosshair interactor what is under
the reticle. The one exception is `casualty_pointers.gd`, which picks in screen space
against each pill's own `Rect2` — still the crosshair, still no collider.

### The casualty's `AnimationPlayer` has exactly one owner
`Casualty` owns it. Compressions and the shock are blend shapes driven through
`casualty_cpr.gd`, never animation tracks. Two owners is what broke the shock timing before
`ShockCue` was reduced to staging only.

### Blend shape indices resolved by name, never by literal index
glTF ordering is not stable across reimports.

### Only bone origins, never bone bases
The Mixamo armature carries scale `(0.01, 0.01, -0.01)` — negative determinant — so anything
derived from a bone basis comes out mirrored. `cpr_rig.gd` builds its chest frame from
origins alone. Godot also sanitises the colon in bone names (`mixamorig:Spine2` →
`mixamorig_Spine2`); suffix matching is more robust than exact names.

### Collision layers
1 World · 2 Interactable · 3 Casualty · 4 Detail. Player layer 1 / mask 1;
`InteractionRay` mask 7. The casualty hull is on layer 4 — walk-through, still ray-hit.

### Godot winding
`cross(v1-v0, v2-v0)` points **away** from the shading normal. Negate it.

### `--check-only --script` false-positives
It reports errors on autoloads and `class_name` globals that do not exist. Booting the main
scene is the reliable parse check. A single parse error in a shared `@tool` script presents
as *nothing works and the inspector is blank*, and cascades as "Failed to compile depended
scripts" across every dependent file. Check the Errors panel first.

### `ProjectSettings.get_setting()` does not apply feature overrides
`get_setting_with_override()` does, and that is what the engine's own `GLOBAL_GET` calls
when it builds the window. A `.editor`-suffixed override in `project.godot` is invisible to
`get_setting()`, which returns the base value — so the first read of a working override
looks exactly like a broken one. A `.editor` override that reads back wrong through
`get_setting()` has probably already worked.

### A `no_focus` dev window was tried and reverted — do not re-attempt it blindly
`project.godot` briefly carried `.editor` overrides making a dev run a small `no_focus`
window on the second screen, so launching could not take the foreground off whoever was at
the machine. It worked, and it was reverted on 4 Sep because the cost is too high: **the
window cannot be focused, so the run cannot be played by hand** — including from the
editor's own play button. `project.godot` is back to the plain fullscreen window and a
dev run takes the screen again.

The three consequences below were all measured and are the reason the cheap version of this
idea does not exist. Anyone trying again starts here rather than from scratch:

1. `Input.mouse_mode = CAPTURED` still clips the cursor to an unfocused window. Godot's
   Windows backend falls back to `MAIN_WINDOW_ID` when nothing is focused, and its own
   release-on-deactivate handling hangs off `WM_ACTIVATE`, which a `no_focus` window never
   receives. So no-focus costs the mouse as well as the keyboard, and needs its own guard
   refusing every cursor grab.
2. **`DisplayServer.window_is_focused()` is not usable in that mode.** It reports `true`
   for a window that has never been activated and is not the Win32 foreground window.
3. **Clearing `WINDOW_FLAG_NO_FOCUS` at runtime — the obvious way to get playability back —
   is what causes that.** With the flag left alone, no focus notification arrives for a
   whole run; clearing it emits `APPLICATION_FOCUS_IN` immediately and `WM_WINDOW_FOCUS_IN`
   60 ms later, for a window still in the background, and the state never returns.

The implementation is recoverable from git if it is ever wanted back: commits `b268a1c`,
`54d3443` and `10b8a98`, reverted together.

### godot-mcp writes `mcp_interaction_server.gd` into the project root
`injectInteractionServer()` copies it there before every `run_project` and restores it
whenever it is missing, because `project.godot` already names the autoload. The autoload
itself resolves to `scripts/mcp_interaction_server.gd` by uid, so the root copy is dead
weight that keeps coming back. It is untracked; leave it.

### Talking to a running game without godot-mcp
The MCP client does not reliably reconnect to a fresh `run_project`, and when it does not
there is no way in through the tool. There is one underneath it: the interaction server is
newline-delimited JSON on `127.0.0.1:9090`, `{"id":1,"command":"eval","params":{"code":"..."}}`,
and it answers whether or not the MCP client ever connected. `screenshot` returns base64
PNG through the same socket. That is the fallback when a session cannot get an eval through.

### `.tres` node references
Any node line using an exported `Node` reference needs an explicit
`node_paths=PackedStringArray("property_name")`. The editor writes it; a hand-authored
`.tscn` does not, and the reference is silently dropped. This is why several scripts here
take a `NodePath` export rather than a typed `Node` export.

---

## 2. Bugs worth remembering

### The PRIMARY_SURVEY ordering race
`enter_cpr_phase()` was hooked to `Events.phase_changed` reaching `PRIMARY_SURVEY`, on the
assumption that the phase begins when the extraction drag ends. It does not — the checklist
shows PRIMARY SURVEY while earlier steps are still pending, so it could fire *before*
`_spawn_cpr_station()` had run. The null guard then skipped it, `current_state` stayed at
−1, and `begin_breathing_check()` silently early-returned. Symptom: exposing the chest did
nothing, intermittently, depending on spawn order.

Fixed by making `enter_cpr_phase()` idempotent and calling it from both seams in `main.gd`.

### The animation import trap
`LVR_Fiddle`, `LVR_ShockEnter` and `LVR_ShockHold` vanished from Godot while being present
in Blender. Godot's `.blend` importer exposes `blender/animation/group_tracks`, which it
passes to the glTF exporter as `export_nla_strips=True` — one animation per NLA track. The
armature had zero NLA tracks, so only the single active action exported.

Godot's blend importer never passes `export_animation_mode='ACTIONS'`, so older pipeline
notes about Animation Mode = Actions apply only to a *manual* glTF export and cannot be
reached through direct `.blend` import.

**Fix, applied:** each clip pushed onto its own NLA track named after the action, plus the
`LVR_Fall` shape-key track pushed onto `Mesh.001` so the eye-closure morph rides along.
Active action cleared. Script stored as Blender text block **`nla_push.py`** — re-run it
after any slice stage, which recuts the clips and wipes both the NLA tracks and `LVR_Fall`'s
`KEKey` slot. Also keep `animation/fps=24` in the import dock; it was 30, making everything
play 25 % fast.

### The chest shading artefact — three causes, not one
Reported as "a stray polygon pointing up that moved with the chest", normal in Blender.
Fixed in `casualty_cpr.gd`:

1. Blend shapes are a whole-mesh property, so the normal-mapped clothing surfaces re-lit on
   every compression → `repair_mesh()` moves surfaces no blend shape touches onto a child
   `CasualtyStaticSurfaces`.
2. Four duplicate coincident triangles → `_strip_duplicate_faces()`.
3. Seam normals wrong → `_recompute_normals()`, keyed on quantised position.

Those repairs also clear the dark spot on the teeth. `repair_mesh()` is static and
`main.gd::_repair_casualty_mesh()` calls it at startup, so what is on screen is the repaired
mesh from the first frame.

**Dead ends, do not repeat:** `BLEND_SHAPE_MODE_RELATIVE` (makes the whole body translate —
the importer stores **absolute** vertex positions, so NORMALIZED is correct), epsilon-pinning
the shape weight, and repairing only the outlier normals.

### The black patches under the arms
Not geometry. Every clothing material imports with `metallic = 1.0` and its
`metallic_texture` pointing at the *roughness* map — glTF expects metal in that texture's
blue channel, and these are plain greyscale roughness maps, so the shirt renders as a metal
of ~0.79. Metal with nothing to reflect (Compatibility: no GI, no probes) goes black in any
crevice, and the armpits are the deepest crevice on a body with its arms out. The character
pack's real metalness maps are black, so the fix is `metallic = 0.0` in
`scripts/casualty/mesh_repair.gd::fix_clothing_metalness()`.

**Ruled out first, do not repeat:** recomputing normals (wholesale and outlier-only), forcing
`CULL_BACK`, and reversing winding — the region is FRONT_FACING and consistently wound.

The same defect is on the room's `Iron`, `Fabric Rough 01` and `Material.0xx` materials.
Deliberately left alone; only the two casualty meshes are touched.

### `suppress()` must not tear the sequence down
`CprStation.begin_breathing_check()` calls `suppress()` on the casualty pointers. That used
to stand them down, which left the trainee in `COMPRESSIONS_1` with a covered chest and
nothing on screen to open it with. It now only drops the camera claim; the pills retire
themselves when no callout is available.

### Arming is not a signal
`CprStation.compressions_armed` is a plain field, so there is nothing to re-sync on.
`cpr_hands_2d.gd` tests it inside `_process` rather than gating `set_process()` — gating it
meant the hands never appeared after the pill click.

### `cpr_rig.gd` is a `@tool` script
Adding an exported var and hot-reloading attaches the member to the editor's live instance
*without running its initialiser*, so it reads as Nil and `_process()` spams conversion
errors every frame until the scene is reopened. `_vec()` absorbs that; keep using it for new
offsets.

### An anchored `PanelContainer` takes its width from the child's minimum size
An autowrapping `Label`'s minimum width is one character — which is why the first bottom pill
rendered as a vertical column of letters. Autowrap is off there.

### The chest overlay ships with "Mouth open" already driven
Exposing the chest before the airway step swapped in a head that was tilted back on its own.
Zeroed at bind time and re-synced across the swap in `casualty.gd`.

### A used one-shot Interactable keeps re-emitting its prompt
`prompt_text()` returning `""` is not enough. `InteractionRay._resolve()` falls back to an
*unavailable* Interactable rather than to nothing, and `_set_current()` early-returns when
`next == current`, so a used one-shot keeps re-emitting until the crosshair moves off it.
Every other one-shot hides its mesh on use, so this only showed on the radio, which stays on
the bench. Worth knowing before adding another persistent one-shot.

### Interactable id must be set before `add_child`
`Interactable._ready()` warns on a missing id, and `_ready_impl()` runs after that check.

### Bind new scripts via `preload()`, not `class_name`
A newly added script is not in the global class cache until the editor rescans, and the
headless checks must work without one.

---

## 3. Debugging technique that works

`godot-mcp run_project` then `game_eval` to walk the live scene tree and read node state,
rather than reading source and guessing:

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
their names, and `Events` / `Assessment` calls to drive the spine directly.

**Caveats learned the hard way:**

- `debug_jump_to_state()` skips the states in between, so guards like `release()`'s
  `if not active: return` never run and readings mislead. Drive through the real sequence or
  the measurement is an artefact.
- Never `game_eval` a standalone lambda or a method the object may not have (e.g.
  `QuadMesh.get_blend_shape_count()`) — it breaks into the debugger and hangs the game for
  30 s.
- Teleporting the player: set `global_position` with feet near y ≈ 0.05 and zero the
  velocity, or it falls out of the world. "1 m from X" can land it outside the building —
  offset toward `CprAnchor`.
- Aiming: the player yaws the **body** and pitches the **head**. `head.look_at()` writes a
  full basis and fights that. Zero `head.rotation.y`/`.z`, then
  `p.rotation.y = atan2(-d.x, -d.z)` and `p.head.rotation.x = asin(d.y)`.
- The kit-check modal blocks the ray at startup. Clear it with
  `get_tree().current_scene.get_node("DevMenu")._force_close_blocking_screens()`.
- `[F10]` dev menu warps to any stage; `[F8]` is the render-triangle probe; `[F9]` the
  collider probe. All debug-build only.
