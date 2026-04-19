# primitives fixture

Regenerate via:

1. Open Blender 4.2+ with `godot_pipeline_v255_blender42+.py` enabled.
2. New empty scene. Add four meshes and apply Godot-Pipeline props:
   - Cube "BoxWall": collision=box, size_x=2, size_y=1, size_z=0.2.
   - UV Sphere "SphereProp": collision=sphere-r, radius=0.5.
   - Cylinder "CylinderCol": collision=cylinder, height=1.5, radius=0.3.
   - Cube (capsule-like) "CapsuleNPC": collision=capsule-h, height=1, radius=0.3.
3. File → Export → glTF 2.0 (.gltf/.glb) → Format "glTF Separate (.gltf + .bin + textures)".
4. Save to this directory as `primitives.gltf`. Commit `.gltf` and `.bin` only.
