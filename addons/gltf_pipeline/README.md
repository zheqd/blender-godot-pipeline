# glTF Pipeline

A `GLTFDocumentExtension` that applies Godot-Pipeline extras (from the Blender addon `godot_pipeline_v255_blender42+.py` v2.5.5) at glTF import time.

Requires Godot 4.6.0+.

## Enable

1. Copy this `gltf_pipeline/` folder into your project's `addons/` directory so you have `addons/gltf_pipeline/plugin.cfg`.
2. **Project → Project Settings → Plugins → glTF Pipeline** → set status to **Enable**.
3. Re-import any `.gltf`/`.glb`/`.blend` file that carries Godot-Pipeline extras — the extension runs automatically in `_import_post`.

No per-file editor script needed. No autoload.

## What it does

On every glTF import, it walks the generated scene post-order and dispatches per-node extras:

| Key                                   | Effect |
|---------------------------------------|--------|
| `state=skip` / `state=hide`           | Remove / hide the node |
| `name_override`                       | Rename the node |
| `script` + `prop_string` / `prop_file`| Attach script and apply `key=expr` properties via `Expression` |
| `material_0..3`                       | Set surface override materials |
| `shader`                              | Swap shader on loaded `ShaderMaterial` |
| `collision` + shape keys              | Generate body + `CollisionShape3D` (box/sphere/capsule/cylinder/trimesh/simple) |
| ↳ body flags: `-r` `-a` `-m` `-h` `-c` `-d` `bodyonly` | Rigid/Area/Animatable/Character, collision-only, discard-mesh, body-without-shape |
| `center_x/y/z`                        | Primitive-shape offset (z auto-negated for handedness) |
| `physics_mat`                         | `PhysicsMaterial` on the body |
| `nav_mesh=<path>`                     | Save mesh + generate `NavigationRegion3D` at path |
| `multimesh=<path>`                    | Aggregate identical-mesh nodes into one `MultiMeshInstance3D` |
| `packed_scene=<path>`                 | Replace node with instantiated PackedScene |

Scene-level extras (in `GodotPipelineProps` on scene 0):

| Key                  | Effect |
|----------------------|--------|
| `individual_origins=1` | Reset top-level Node3D positions to zero |
| `packed_resources=1`   | Pack each top-level child into `<gltf_dir>/packed_scenes/<name>.tscn` and replace with instance |

## Authoring extras

Use the Blender addon's panel to set extras on objects. Export via **glTF 2.0 → glTF Separate (.gltf + .bin)** so the extras land in the node `extras` dict. Godot 4.4+ auto-propagates those to `node.meta["extras"]` and `mesh.meta["extras"]`, which this addon reads.

## Divergences from v2.5.5 runtime

Key divergences from the v2.5.5 reference runtime:

- `state=skip` uses `queue_free()` via `remove_child()` instead of `node.free()` (safe under the `_import_post` walk).
- `multimesh=<path>` paths must use `.tres`/`.res` — Godot's `ResourceSaver` rejects the `.mesh` extension v2.5.5 allowed.
- No `_Imported` marker node — `_import_post` runs natively on every re-import.

## License

MIT.
