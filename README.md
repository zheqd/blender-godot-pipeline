# Blender-glTF-Godot Pipeline

A Godot 4.6.2 addon that implements the v2.5.5 Blender-Godot Pipeline runtime using `GLTFDocumentExtension`.

This addon ports the Godot-side runtime of the [Blender-Godot Pipeline](https://github.com/bikemurt/blender-godot-pipeline) (v2.5.5, `SceneInit.gd`) into Godot's native `GLTFDocumentExtension` API. The Blender-side addon required for authoring extras is a separate paid product: [Blender-Godot Pipeline on SuperHive Market](https://superhivemarket.com/products/blender-godot-pipeline-addon).

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

This addon achieves 1:1 behavioral parity with the v2.5.5 runtime, but the implementation differs in several ways:

**Architecture**
- Implemented as `GLTFDocumentExtension._import_post()` instead of `EditorScenePostImport._post_import()`, integrating natively with Godot's import pipeline.
- Extras are read from engine-propagated `node.meta["extras"]` and `mesh.meta["extras"]` (Godot 4.4+) rather than re-parsing the raw glTF JSON.
- No `_Imported` hot-reload marker node — `_import_post` runs natively on every re-import.

**Behavioral corrections**
- `is_inside_tree()` guard added for world-transform reads — the import hook runs outside the SceneTree.
- `col_only` (`-c`) with conflicting body-type extras now discards the extras instead of constructing an orphaned body.
- `shader` override duplicates the material before modifying it — the original leaks changes to shared materials.
- Multimesh save paths must use `.tres`/`.res` — Godot's `ResourceSaver` rejects `.mesh`.
- `ImporterMeshInstance3D` nodes are pre-materialized to `MeshInstance3D` early so script and material changes survive the engine's own conversion step.

## License

MIT.
