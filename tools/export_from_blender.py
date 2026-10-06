"""Re-export the control room from Blender into the Godot project.

Run from Blender's scripting workspace with LVR CPR.blend open, or headless:

    blender "LVR CPR.blend" --background --python tools/export_from_blender.py

Two deliberate choices here:

* Lights are NOT exported. glTF stores light power in candela, and Godot
  reads Blender's 200 W point lights as an enormous light_energy, which
  saturates every surface to flat white. The scene is lit in main.tscn
  instead, at world positions matching the Blender lights.

* Godot can import .blend directly, but this project's textures live outside
  the Godot folder and several resolve into the neighbouring substation
  project, so a self-contained .glb is safer until those paths are cleaned up.
"""

import bpy
import os

PROJECT_DIR = r"D:\Nadir\Documents\Work\Freelance\HV Exercices Simulations\LVR CPR\lvr-cpr"
OUT_PATH = os.path.join(PROJECT_DIR, "assets", "control_room.glb")

# The action that should be riding on the armature at export time.
SHOCK_ACTION = "Shock"


def main():
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)

    arm = bpy.data.objects.get("Armature")
    action = bpy.data.actions.get(SHOCK_ACTION)
    if arm and arm.animation_data and action:
        arm.animation_data.action = action
    else:
        print("WARNING: could not assign '%s' to the armature" % SHOCK_ACTION)

    bpy.ops.export_scene.gltf(
        filepath=OUT_PATH,
        export_format='GLB',
        export_apply=True,          # bakes modifiers, including BagaPie geometry nodes
        export_animations=True,
        export_animation_mode='ACTIONS',
        export_yup=True,
        export_cameras=False,
        export_lights=False,        # see module docstring
        export_materials='EXPORT',
        export_skins=True,
        use_visible=False,
    )

    size_mb = os.path.getsize(OUT_PATH) / (1024 * 1024)
    print("Exported %s (%.1f MB)" % (OUT_PATH, size_mb))


if __name__ == "__main__":
    main()
