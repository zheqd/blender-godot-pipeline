# nav_and_multimesh fixture

## Goal

`scene.gltf` combines three pipeline features in one scene: a ground plane
tagged for `nav_mesh` generation, three linked-duplicate trees aggregated
into a `multimesh`, and a `Spawn` empty replaced with an instance of
`test_packed.tscn`.

## Authoring steps

### Object `Ground`

1. Add → Mesh → Plane, scale it up to ~10m on X and Z. Rename `Ground`.
2. Path Setter → Path Type `Nav Mesh` → Path `res://test/fixtures/nav_and_multimesh/nav.tres` → Set Path.

   **Note the `.tres` extension** — Godot's `ResourceSaver` rejects `.mesh`.
   This is documented in `DIVERGENCES.md`.

### Objects `Tree1`, `Tree2`, `Tree3`

1. Add → Mesh → Cylinder (tall and narrow — it's a stand-in for a tree).
   Rename `Tree1`.
2. Duplicate twice with **Alt+D** (linked duplicates — share mesh data).
   Rename to `Tree2` and `Tree3`. Move each to a distinct position.
3. Select all three. In Godot Pipeline panel → Path Setter → Path Type
   `Multimesh` → `res://test/fixtures/nav_and_multimesh/tree.tres` → Set Path.
   (The operator applies the current path to every selected object.)

### Object `Spawn`

1. Add → Empty → Plain Axes. Rename `Spawn`, position at e.g. `(0, 1, 0)`.
2. Path Setter → Path Type `Packed Scene` → `res://test/fixtures/test_packed.tscn` → Set Path.

### Export

Save path → `test/fixtures/nav_and_multimesh/scene.gltf`. Export for Godot. Commit.
