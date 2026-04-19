# Blender-glTF-Godot Pipeline

A Godot 4.6.2 addon that implements the v2.5.5 Blender-Godot Pipeline runtime using `GLTFDocumentExtension`.

## Compatibility

- **Blender addon:** Works with `godot_pipeline_v255_blender42+.py` (v2.5.5). Schema unchanged.
- **Godot version:** Requires Godot 4.6.0+ (uses auto-propagated glTF extras from PR #86183, shipped in 4.4; targets 4.6.2).

## Install

1. Copy `addons/gltf_pipeline/` into your project's `addons/` directory.
2. Project Settings → Plugins → enable "glTF Pipeline".
3. Import .gltf or .blend files normally — the extension runs automatically in `_import_post`.

## Behavior

The addon reads Godot-Pipeline `extras` from glTF nodes and scenes and reproduces the behavior of `SceneInit.gd` from bikemurt/blender-godot-pipeline v2.5.5:

| Extras key                           | Effect |
|--------------------------------------|--------|
| `state=skip`                         | Node removed from scene |
| `state=hide`                         | Node hidden (visible = false) |
| `name_override`                      | Node renamed |
| `script`                             | Script attached |
| `prop_string`, `prop_file`           | Properties set via `Expression` |
| `material_0..3`                      | Surface override materials |
| `shader`                             | Shader swapped on loaded ShaderMaterial |
| `collision` with flags -r/-a/-m/-h/-c/-d/bodyonly/simple/trimesh/box/sphere/capsule/cylinder | Physics body + collision shape generated |
| `size_x/y/z`, `height`, `radius`, `center_x/y/z` | Primitive shape dimensions |
| `physics_mat`                        | PhysicsMaterial override on body |
| `nav_mesh`                           | NavigationRegion3D generated from mesh, saved to path |
| `multimesh`                          | Transforms aggregated across nodes into MultiMeshInstance3D |
| `packed_scene`                       | Node replaced with instantiated PackedScene |
| **Scene-level** `individual_origins` | Top-level positions reset to zero |
| **Scene-level** `packed_resources`   | Top-level children packed to `.tscn` in `packed_scenes/` |

## Architecture

- All processing runs in `_import_post(state, root)` — we never override `_import_node`.
- Extras are read from `node.meta["extras"]` + `mesh.meta["extras"]` (node wins).
- Scene-level extras come from `state.json["scenes"][0]["extras"]["GodotPipelineProps"]`.
- `prop_string` and `prop_file` are evaluated with Godot's `Expression` class — arbitrary GDScript expressions against the node.

## Testing

```bash
./run_tests.sh
```

The script expects `godot` on `PATH` or `GODOT` env var pointing at the binary (e.g.
`GODOT=/Applications/Godot.app/Contents/MacOS/Godot ./run_tests.sh` on macOS).

Unit tests run without external assets. Integration tests require `.gltf` fixtures exported from Blender — see each `test/fixtures/*/README.md` for authoring steps. Tests mark themselves as `pending` when the fixture is absent.

## Differences from v2.5.5

See `DIVERGENCES.md` for the full list. Summary:

- `state=skip` uses `queue_free()` via `remove_child()` instead of `node.free()`.
- Multimesh save paths must be `.tres`/`.res` (Godot's `ResourceSaver` rejects `.mesh`).
- No `_Imported` hot-reload marker — `_import_post` runs natively on every re-import.
- Uses Godot's automatic extras → meta propagation (4.4+) instead of re-parsing glTF JSON.
- Implemented as `GLTFDocumentExtension`, not `EditorScenePostImport`.

## License

MIT.
