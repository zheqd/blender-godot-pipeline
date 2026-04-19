# Changelog

All notable changes to this project will be documented in this file.

## [1.0.0] - 2026-04-18

Initial release. Full feature parity with the v2.5.5 runtime of [bikemurt/blender-godot-pipeline](https://github.com/bikemurt/blender-godot-pipeline), implemented as a `GLTFDocumentExtension`.

### Features

- **Node control**: `state=skip`, `state=hide`, `name_override`
- **Scripting**: `script` attachment, `prop_string` / `prop_file` property binding via `Expression`
- **Materials**: `material_0..3` surface overrides, `shader` swap (duplicates material before modify)
- **Physics**: collision bodies (Static/Rigid/Area/Animatable/Character), collision shapes (box/sphere/capsule/cylinder/trimesh/simple), `physics_mat` override
- **Navigation**: `nav_mesh` — generates and saves `NavigationRegion3D` from mesh
- **MultiMesh**: `multimesh` — aggregates repeated nodes into `MultiMeshInstance3D`
- **Scene composition**: `packed_scene` instantiation, scene-level `individual_origins`, `packed_resources`
- 106 tests (unit + integration) with manually authored Blender fixtures
