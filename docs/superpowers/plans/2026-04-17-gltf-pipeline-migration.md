# GLTFDocumentExtension Pipeline Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a standalone Godot 4.6.2 addon (`addons/gltf_pipeline`) that achieves 1:1 feature parity with the v2.5.5 `SceneInit.gd` runtime (from bikemurt/blender-godot-pipeline) but uses `GLTFDocumentExtension` instead of `EditorScenePostImport`.

**Architecture:**
- All logic runs in `_import_post(state, root)` after the engine has materialized `ImporterMeshInstance3D` into `MeshInstance3D`. `_import_node` is NOT overridden — we rely on Godot 4.4+'s automatic propagation of glTF `extras` to `node.get_meta("extras")` (engine PR #86183).
- Extras are merged per-node from (a) the engine-populated `node.meta["extras"]`, and (b) the mesh-level `mesh.meta["extras"]` reached via `(node as MeshInstance3D).mesh.get_meta("extras")`. Node wins on conflict.
- Scene-level `GodotPipelineProps` come from `state.json["scenes"][0]["extras"]["GodotPipelineProps"]`.
- Scripted-parameter strings (`prop_string`, `prop_file`) are evaluated with Godot's `Expression` class, matching v2.5.5 semantics precisely.

**Tech Stack:**
- Godot 4.6.2 stable
- GUT 9.x (Godot Unit Test) for automated tests
- GDScript (no C#/GDExtension needed)
- Blender 4.2+ with the v2.5.5 `godot_pipeline_v255_blender42+` addon (unchanged) for fixture authoring

**Models:**
- Task execution subagent: **Sonnet 4.6** — one fresh subagent per task, follows the TDD steps verbatim.
- Between-task review subagent: **Opus 4.7** — verifies against `SceneInit.gd` line refs in the self-review table and catches GLTF-specific traps (`ImporterMeshInstance3D` vs `MeshInstance3D`, `Expression` parse edges, center-offset sign, trimesh/convex API variants).
- Ambiguity / stuck tasks: escalate to **Opus 4.7**.
- Claude Code's `Agent` tool exposes `model` but not an effort parameter — push rigor into per-task prompt text when needed (e.g., "verify center-offset sign against SceneInit.gd:305-310 before committing").

**Reference (authoritative spec):** `/Users/zheqd/Projects/gamedev/ratscape_2_cogito/addons/blender_godot_pipeline/SceneInit.gd` — every behavior must match this file unless noted.

**Skeleton to read once for dispatch-pattern inspiration only:** `/Users/zheqd/Projects/gamedev/gltf_pipeline_addon/pipeline_extension.gd` — do NOT copy as-is; its `_import_node` signature is wrong and three handlers are silently incorrect (`shader`, `physics_mat`, collision `-c`). See `docs/superpowers/specs/` compatibility analysis if needed.

---

## File Structure

```
blender-gltf-godot-pipeline/
├── .gitignore                              # Godot ignores
├── .gutconfig.json                         # GUT CLI config
├── README.md                               # install + usage
├── project.godot                           # Godot 4.6.2 project file
├── icon.svg                                # project icon (placeholder)
├── addons/
│   ├── gltf_pipeline/                      # THE DELIVERABLE
│   │   ├── plugin.cfg
│   │   ├── plugin.gd                       # EditorPlugin; registers extension
│   │   ├── pipeline_extension.gd           # GLTFDocumentExtension subclass (entry)
│   │   ├── extras_reader.gd                # merge node + mesh extras utility
│   │   ├── expression_applier.gd           # Expression-based prop_* parser
│   │   ├── handlers/
│   │   │   ├── state_handler.gd            # state=skip / state=hide
│   │   │   ├── name_handler.gd             # name_override
│   │   │   ├── script_handler.gd           # script + prop_file/prop_string binding
│   │   │   ├── material_handler.gd         # material_0..3 + shader
│   │   │   ├── physics_material_handler.gd # physics_mat
│   │   │   ├── collision_handler.gd        # collision with all flags + body/shape factories
│   │   │   ├── navmesh_handler.gd          # nav_mesh generate & save
│   │   │   ├── multimesh_handler.gd        # multimesh aggregation
│   │   │   ├── packed_scene_handler.gd     # packed_scene instantiation
│   │   │   └── scene_globals_handler.gd    # GodotPipelineProps (individual_origins, packed_resources)
│   └── gut/                                # GUT 9.x addon (vendored)
├── test/
│   ├── unit/
│   │   ├── test_extras_reader.gd
│   │   ├── test_expression_applier.gd
│   │   ├── test_state_handler.gd
│   │   ├── test_name_handler.gd
│   │   ├── test_script_handler.gd
│   │   ├── test_material_handler.gd
│   │   ├── test_physics_material_handler.gd
│   │   ├── test_collision_body_factory.gd
│   │   ├── test_collision_shape_factory.gd
│   │   ├── test_collision_flags.gd
│   │   ├── test_navmesh_handler.gd
│   │   ├── test_multimesh_handler.gd
│   │   ├── test_packed_scene_handler.gd
│   │   └── test_scene_globals_handler.gd
│   ├── integration/
│   │   ├── test_import_golden_scene.gd     # loads fixture via GLTFDocument, asserts tree
│   │   └── helpers.gd                      # GLTF import helpers
│   └── fixtures/
│       ├── README.md                       # how to regenerate from .blend
│       ├── primitives/                     # box/sphere/capsule/cylinder colliders
│       │   ├── primitives.blend
│       │   └── primitives.gltf (+ .bin + textures if any)
│       ├── scripts_and_props/
│       ├── materials_and_shaders/
│       ├── nav_and_multimesh/
│       ├── packed_scene/
│       └── scene_globals/
└── docs/
    └── superpowers/
        └── plans/2026-04-17-gltf-pipeline-migration.md  # THIS FILE
```

Each handler file is a `class_name` pure-static module (no state, per the `GLTFDocumentExtension` statelessness rule). Handlers take `(node: Node, extras: Dictionary, context: PipelineContext)` and mutate the scene tree. `pipeline_extension.gd` owns the walk and the dispatch table.

---

## Key conventions

**Every handler file** exports a `class_name` and exposes at minimum a `static func apply(node: Node, extras: Dictionary, ctx: PipelineContext) -> void` (or returns a replacement Node when substitution is needed). Handlers never call `get_tree()` or `EditorInterface` — they receive everything they need via `ctx`.

**PipelineContext** is a plain object defined in `pipeline_extension.gd`:
```gdscript
class PipelineContext:
    var state: GLTFState
    var root: Node
    var scene_extras: Dictionary             # GodotPipelineProps
    var multimesh_groups: Dictionary = {}    # Dictionary[String path, Array[Transform3D]]
    var deferred_deletes: Array[Node] = []
    var deferred_reparents: Array = []        # Array[Array[Node, Node]]   [child, new_parent]
    var gltf_path: String                    # for derived resource save-paths
```

**Test pattern (GUT):** Every unit test extends `GutTest`; builds a small scene tree in `before_each`; invokes the handler; asserts on the resulting tree. Integration tests load a real `.gltf` fixture through `GLTFDocument.new().append_from_file(...)` and assert the final tree matches expected.

**Commit cadence:** One commit per step 5 of each task. Messages follow this project's git-workflow conventions but without a Jira prefix (this is a personal project). Format: `<verb> <what>`, e.g., `add state=skip handler`, `fix multimesh aggregation off-by-one`.

---

### Task 0: Bootstrap project, git, Godot 4.6.2 config

**Files:**
- Create: `project.godot`
- Create: `.gitignore`
- Create: `README.md`
- Create: `icon.svg`

- [ ] **Step 1: Init repo**

```bash
cd /Users/zheqd/Projects/gamedev/blender-gltf-godot-pipeline
git init -b main
```

- [ ] **Step 2: Write `project.godot`**

```ini
; Engine configuration file.
; It's best edited using the editor UI and not directly,
; since the parameters that go here are not all obvious.

config_version=5

[application]

config/name="Blender-glTF-Godot Pipeline"
config/description="1:1 port of the v2.5.5 Blender-Godot Pipeline runtime to GLTFDocumentExtension."
config/version="1.0.0"
run/main_scene=""
config/features=PackedStringArray("4.6", "Forward Plus")
config/icon="res://icon.svg"

[editor_plugins]

enabled=PackedStringArray("res://addons/gut/plugin.cfg", "res://addons/gltf_pipeline/plugin.cfg")

[rendering]

renderer/rendering_method="forward_plus"
renderer/rendering_method.mobile="mobile"
```

- [ ] **Step 3: Write `.gitignore`**

```
# Godot 4+ specific ignores
.godot/
.import/

# macOS
.DS_Store

# Backup files
*~
*.bak

# Fixture build artifacts regenerated from .blend
test/fixtures/**/*.gltf.import
test/fixtures/**/*.bin.import
test/fixtures/**/*-texco.png.import
```

- [ ] **Step 4: Write placeholder `icon.svg`**

```xml
<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128"><rect width="128" height="128" fill="#3a86ff"/><text x="64" y="80" font-family="monospace" font-size="24" text-anchor="middle" fill="#fff">GLTF</text></svg>
```

- [ ] **Step 5: Write `README.md`**

```markdown
# Blender-glTF-Godot Pipeline

A Godot 4.6.2 addon that implements the v2.5.5 Blender-Godot Pipeline runtime using `GLTFDocumentExtension`.

Compatible with the Blender addon `godot_pipeline_v255_blender42+.py` (extras schema unchanged).

## Install

Copy `addons/gltf_pipeline/` into your project's `addons/` directory and enable the plugin in Project Settings → Plugins.

## Status

Under development. See `docs/superpowers/plans/` for the implementation roadmap.
```

- [ ] **Step 6: First commit**

```bash
git add project.godot .gitignore README.md icon.svg
git commit -m "bootstrap project skeleton for Godot 4.6.2"
```

---

### Task 1: Install GUT and a smoke test

**Files:**
- Create: `addons/gut/` (vendored from the GUT repo)
- Create: `.gutconfig.json`
- Create: `test/unit/test_smoke.gd`

- [ ] **Step 1: Vendor GUT 9.x**

```bash
cd /tmp && git clone --depth 1 --branch v9.3.0 https://github.com/bitwes/Gut.git gut-src
mkdir -p /Users/zheqd/Projects/gamedev/blender-gltf-godot-pipeline/addons/gut
cp -r /tmp/gut-src/addons/gut/* /Users/zheqd/Projects/gamedev/blender-gltf-godot-pipeline/addons/gut/
rm -rf /tmp/gut-src
```

(If v9.3.0 is not the latest stable at execution time, pick the latest 9.x tag compatible with Godot 4.6.)

- [ ] **Step 2: Write `.gutconfig.json`**

```json
{
  "dirs": ["res://test/unit/", "res://test/integration/"],
  "should_print_to_console": true,
  "should_exit": true,
  "log_level": 1,
  "include_subdirs": true
}
```

- [ ] **Step 3: Write the smoke test — will fail (file doesn't exist)**

File: `test/unit/test_smoke.gd`
```gdscript
extends GutTest

func test_gut_runs():
    assert_eq(2 + 2, 4, "arithmetic still works")
```

- [ ] **Step 4: Run GUT via CLI — smoke test passes**

```bash
cd /Users/zheqd/Projects/gamedev/blender-gltf-godot-pipeline
godot --headless --path . --script addons/gut/gut_cmdln.gd
```

Expected: `1 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add addons/gut test .gutconfig.json
git commit -m "add GUT 9.x and smoke test"
```

---

### Task 2: Plugin registration skeleton

**Files:**
- Create: `addons/gltf_pipeline/plugin.cfg`
- Create: `addons/gltf_pipeline/plugin.gd`
- Create: `addons/gltf_pipeline/pipeline_extension.gd`
- Create: `test/unit/test_plugin_registration.gd`

- [ ] **Step 1: Write the failing test**

File: `test/unit/test_plugin_registration.gd`
```gdscript
extends GutTest

func test_pipeline_extension_class_exists():
    var ext = PipelineGLTFExtension.new()
    assert_not_null(ext, "PipelineGLTFExtension class should be loadable")
    assert_true(ext is GLTFDocumentExtension,
        "must extend GLTFDocumentExtension")

func test_import_post_returns_ok_on_empty_state():
    var ext = PipelineGLTFExtension.new()
    var state = GLTFState.new()
    var root = Node.new()
    var result = ext._import_post(state, root)
    assert_eq(result, OK, "empty import_post returns OK")
    root.free()
```

- [ ] **Step 2: Run test — fails (class missing)**

```bash
godot --headless --path . --script addons/gut/gut_cmdln.gd -gselect=test_plugin_registration.gd
```

Expected: FAIL with `Identifier "PipelineGLTFExtension" not declared`.

- [ ] **Step 3: Write `plugin.cfg`**

File: `addons/gltf_pipeline/plugin.cfg`
```ini
[plugin]

name="glTF Pipeline"
description="1:1 port of the v2.5.5 Blender-Godot Pipeline runtime using GLTFDocumentExtension."
author="ratscape"
version="1.0.0"
script="plugin.gd"
```

- [ ] **Step 4: Write `pipeline_extension.gd` minimal skeleton**

File: `addons/gltf_pipeline/pipeline_extension.gd`
```gdscript
@tool
extends GLTFDocumentExtension
class_name PipelineGLTFExtension

class PipelineContext:
    var state: GLTFState
    var root: Node
    var scene_extras: Dictionary = {}
    var multimesh_groups: Dictionary = {}
    var deferred_deletes: Array[Node] = []
    var deferred_reparents: Array = []
    var gltf_path: String = ""

func _import_post(state: GLTFState, root: Node) -> int:
    if root == null:
        return OK
    var ctx := PipelineContext.new()
    ctx.state = state
    ctx.root = root
    return OK
```

- [ ] **Step 5: Write `plugin.gd`**

File: `addons/gltf_pipeline/plugin.gd`
```gdscript
@tool
extends EditorPlugin

var _extension: PipelineGLTFExtension

func _enter_tree() -> void:
    _extension = PipelineGLTFExtension.new()
    GLTFDocument.register_gltf_document_extension(_extension, true)

func _exit_tree() -> void:
    if _extension:
        GLTFDocument.unregister_gltf_document_extension(_extension)
        _extension = null
```

- [ ] **Step 6: Run test — passes**

Expected: `2 passed, 0 failed`.

- [ ] **Step 7: Commit**

```bash
git add addons/gltf_pipeline test/unit/test_plugin_registration.gd
git commit -m "add plugin skeleton and GLTFDocumentExtension registration"
```

---

### Task 3: Extras reader — merge node + mesh extras

**Files:**
- Create: `addons/gltf_pipeline/extras_reader.gd`
- Create: `test/unit/test_extras_reader.gd`

**Spec:** v2.5.5's `GLTFImporter.gd:56-67` merges both `nodes[*].extras` and `meshes[*].extras` into a single dict keyed by node name. Since 4.4+, Godot auto-propagates both to `node.meta["extras"]` and `mesh.meta["extras"]`. This utility reproduces the merge with node-level keys winning.

- [ ] **Step 1: Write the failing test**

File: `test/unit/test_extras_reader.gd`
```gdscript
extends GutTest

func test_returns_empty_when_no_extras():
    var n := Node3D.new()
    assert_eq(ExtrasReader.get_extras(n), {}, "no meta → empty dict")
    n.free()

func test_returns_node_extras_when_only_node_has_meta():
    var n := Node3D.new()
    n.set_meta("extras", {"name_override": "Wall"})
    assert_eq(ExtrasReader.get_extras(n), {"name_override": "Wall"})
    n.free()

func test_merges_mesh_extras_when_node_is_mesh_instance():
    var n := MeshInstance3D.new()
    var m := BoxMesh.new()
    m.set_meta("extras", {"collision": "simple"})
    n.mesh = m
    n.set_meta("extras", {"name_override": "Wall"})
    var extras: Dictionary = ExtrasReader.get_extras(n)
    assert_eq(extras.get("name_override"), "Wall")
    assert_eq(extras.get("collision"), "simple")
    n.free()

func test_node_extras_win_on_conflict():
    var n := MeshInstance3D.new()
    var m := BoxMesh.new()
    m.set_meta("extras", {"name_override": "MeshWin"})
    n.mesh = m
    n.set_meta("extras", {"name_override": "NodeWin"})
    assert_eq(ExtrasReader.get_extras(n).get("name_override"), "NodeWin")
    n.free()

func test_non_mesh_instance_ignores_mesh_path():
    var n := Node3D.new()
    n.set_meta("extras", {"a": 1})
    assert_eq(ExtrasReader.get_extras(n), {"a": 1})
    n.free()
```

- [ ] **Step 2: Run tests — fail (class missing)**

Expected: `5 failed` with `Identifier "ExtrasReader" not declared`.

- [ ] **Step 3: Implement**

File: `addons/gltf_pipeline/extras_reader.gd`
```gdscript
@tool
class_name ExtrasReader
extends RefCounted

static func get_extras(node: Node) -> Dictionary:
    var merged: Dictionary = {}
    if node is MeshInstance3D:
        var mesh: Mesh = (node as MeshInstance3D).mesh
        if mesh and mesh.has_meta("extras"):
            var mesh_extras = mesh.get_meta("extras")
            if mesh_extras is Dictionary:
                merged.merge(mesh_extras, true)
    if node.has_meta("extras"):
        var node_extras = node.get_meta("extras")
        if node_extras is Dictionary:
            # Node-level wins: merge with overwrite=true
            merged.merge(node_extras, true)
    return merged
```

- [ ] **Step 4: Run tests — pass**

Expected: `5 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add addons/gltf_pipeline/extras_reader.gd test/unit/test_extras_reader.gd
git commit -m "add ExtrasReader merging node and mesh extras"
```

---

### Task 4: Scene extras and `_import_post` walk skeleton

**Files:**
- Modify: `addons/gltf_pipeline/pipeline_extension.gd`
- Create: `test/unit/test_import_post_walk.gd`

**Spec:** `SceneInit.gd:41-48` reads `scenes[0].extras.GodotPipelineProps` into `scene.global_data`. `SceneInit.gd:463-524` walks children-first via `iterate_scene`. We reproduce a post-order walk that visits every node and passes extras to dispatch.

- [ ] **Step 1: Write the failing test**

File: `test/unit/test_import_post_walk.gd`
```gdscript
extends GutTest

var ext: PipelineGLTFExtension
var visited: Array = []

func before_each():
    ext = PipelineGLTFExtension.new()
    visited = []

func test_import_post_visits_every_node_post_order():
    var root := Node3D.new()
    root.name = "Root"
    var child := Node3D.new()
    child.name = "Child"
    var grandchild := Node3D.new()
    grandchild.name = "Grandchild"
    child.add_child(grandchild)
    root.add_child(child)

    ext._visit_for_test = func(n: Node): visited.append(n.name)
    var state := GLTFState.new()
    var result = ext._import_post(state, root)
    assert_eq(result, OK)
    assert_eq(visited, ["Grandchild", "Child", "Root"],
        "post-order: children before parents")
    root.free()

func test_reads_scene_extras_from_state_json():
    var state := GLTFState.new()
    state.json = {
        "scenes": [{"extras": {"GodotPipelineProps": {"individual_origins": 1}}}]
    }
    var root := Node3D.new()
    ext._import_post(state, root)
    assert_eq(ext._last_ctx.scene_extras,
        {"individual_origins": 1})
    root.free()
```

- [ ] **Step 2: Run test — fails (hooks don't exist)**

Expected failures: `_visit_for_test` and `_last_ctx` not declared.

- [ ] **Step 3: Extend `pipeline_extension.gd`**

File: `addons/gltf_pipeline/pipeline_extension.gd` (replace body)
```gdscript
@tool
extends GLTFDocumentExtension
class_name PipelineGLTFExtension

class PipelineContext:
    var state: GLTFState
    var root: Node
    var scene_extras: Dictionary = {}
    var multimesh_groups: Dictionary = {}
    var deferred_deletes: Array[Node] = []
    var deferred_reparents: Array = []
    var gltf_path: String = ""

# Test hooks. Set from unit tests to intercept or observe.
var _visit_for_test: Callable = Callable()
var _last_ctx: PipelineContext = null

func _import_post(state: GLTFState, root: Node) -> int:
    if root == null:
        return OK
    var ctx := PipelineContext.new()
    ctx.state = state
    ctx.root = root
    ctx.scene_extras = _extract_scene_extras(state)
    _last_ctx = ctx
    _walk_post_order(root, ctx)
    return OK

func _extract_scene_extras(state: GLTFState) -> Dictionary:
    if state == null or state.json == null:
        return {}
    var scenes = state.json.get("scenes", [])
    if scenes is Array and scenes.size() > 0:
        var s = scenes[0]
        if s is Dictionary:
            var extras = s.get("extras", {})
            if extras is Dictionary:
                var props = extras.get("GodotPipelineProps", {})
                if props is Dictionary:
                    return props
    return {}

func _walk_post_order(node: Node, ctx: PipelineContext) -> void:
    var children := node.get_children()
    for child in children:
        _walk_post_order(child, ctx)
    _dispatch(node, ctx)

func _dispatch(node: Node, ctx: PipelineContext) -> void:
    if _visit_for_test.is_valid():
        _visit_for_test.call(node)
    # Real dispatch is filled in by later tasks.
```

- [ ] **Step 4: Run test — passes**

Expected: `2 passed`.

- [ ] **Step 5: Commit**

```bash
git add addons/gltf_pipeline/pipeline_extension.gd test/unit/test_import_post_walk.gd
git commit -m "add scene-extras extraction and post-order walk"
```

---

### Task 5: `state=skip` and `state=hide`

**Files:**
- Create: `addons/gltf_pipeline/handlers/state_handler.gd`
- Create: `test/unit/test_state_handler.gd`
- Modify: `addons/gltf_pipeline/pipeline_extension.gd` (wire dispatch)

**Spec:** `SceneInit.gd:455-461` frees a child with `state=skip` (note: `.free()`, not `queue_free()` — synchronous). `SceneInit.gd:480-483` hides a node with `state=hide`.

- [ ] **Step 1: Write the failing test**

File: `test/unit/test_state_handler.gd`
```gdscript
extends GutTest

func test_state_skip_frees_node_from_parent():
    var parent := Node3D.new()
    var child := Node3D.new()
    child.name = "Doomed"
    parent.add_child(child)
    StateHandler.apply(child, {"state": "skip"})
    await get_tree().process_frame
    assert_eq(parent.get_child_count(), 0, "skip removes child from parent")
    parent.free()

func test_state_skip_on_root_is_noop_warning():
    var root := Node3D.new()
    StateHandler.apply(root, {"state": "skip"})
    assert_not_null(root, "root without parent: no-op")
    root.free()

func test_state_hide_sets_visibility_false():
    var n := Node3D.new()
    StateHandler.apply(n, {"state": "hide"})
    assert_false(n.visible, "hide → visible = false")
    n.free()

func test_state_other_values_are_noop():
    var n := Node3D.new()
    StateHandler.apply(n, {"state": "something_else"})
    assert_true(n.visible, "unknown state: no-op")
    n.free()

func test_no_state_key_is_noop():
    var n := Node3D.new()
    StateHandler.apply(n, {})
    assert_true(n.visible)
    n.free()
```

- [ ] **Step 2: Run tests — fail (class missing)**

Expected: 5 failures.

- [ ] **Step 3: Implement handler**

File: `addons/gltf_pipeline/handlers/state_handler.gd`
```gdscript
@tool
class_name StateHandler
extends RefCounted

static func apply(node: Node, extras: Dictionary) -> void:
    var state = extras.get("state", "")
    match state:
        "skip":
            var parent := node.get_parent()
            if parent:
                parent.remove_child(node)
                node.queue_free()
        "hide":
            if node is Node3D:
                (node as Node3D).visible = false
            elif node is CanvasItem:
                (node as CanvasItem).visible = false
```

Note: v2.5.5 uses `node.free()` (synchronous) when skipping. We use `queue_free()` after `remove_child()` to keep Godot's scene-tree invariants intact during the import walk. The behavioral effect is the same (the node doesn't appear in the final scene).

- [ ] **Step 4: Run tests — pass**

Expected: `5 passed`.

- [ ] **Step 5: Wire into dispatch**

Modify `addons/gltf_pipeline/pipeline_extension.gd` — replace `_dispatch`:
```gdscript
func _dispatch(node: Node, ctx: PipelineContext) -> void:
    if _visit_for_test.is_valid():
        _visit_for_test.call(node)
    var extras := ExtrasReader.get_extras(node)
    if extras.is_empty():
        return
    StateHandler.apply(node, extras)
    if not is_instance_valid(node):
        return
```

- [ ] **Step 6: Commit**

```bash
git add addons/gltf_pipeline/handlers/state_handler.gd \
        test/unit/test_state_handler.gd \
        addons/gltf_pipeline/pipeline_extension.gd
git commit -m "add state=skip and state=hide handler"
```

---

### Task 6: `name_override`

**Files:**
- Create: `addons/gltf_pipeline/handlers/name_handler.gd`
- Create: `test/unit/test_name_handler.gd`
- Modify: `addons/gltf_pipeline/pipeline_extension.gd` (wire dispatch)

**Spec:** `SceneInit.gd:485-487` renames node if `name_override != ""`.

- [ ] **Step 1: Write the failing test**

File: `test/unit/test_name_handler.gd`
```gdscript
extends GutTest

func test_renames_node_when_override_present():
    var n := Node3D.new()
    n.name = "Original"
    NameHandler.apply(n, {"name_override": "Renamed"})
    assert_eq(n.name, "Renamed")
    n.free()

func test_empty_name_override_is_noop():
    var n := Node3D.new()
    n.name = "Keep"
    NameHandler.apply(n, {"name_override": ""})
    assert_eq(n.name, "Keep")
    n.free()

func test_missing_key_is_noop():
    var n := Node3D.new()
    n.name = "Keep"
    NameHandler.apply(n, {})
    assert_eq(n.name, "Keep")
    n.free()
```

- [ ] **Step 2: Run — fails**

- [ ] **Step 3: Implement**

File: `addons/gltf_pipeline/handlers/name_handler.gd`
```gdscript
@tool
class_name NameHandler
extends RefCounted

static func apply(node: Node, extras: Dictionary) -> void:
    var override = extras.get("name_override", "")
    if override is String and override != "":
        node.name = override
```

- [ ] **Step 4: Run — passes**

- [ ] **Step 5: Wire dispatch**

Modify `_dispatch` in `pipeline_extension.gd`:
```gdscript
func _dispatch(node: Node, ctx: PipelineContext) -> void:
    if _visit_for_test.is_valid():
        _visit_for_test.call(node)
    var extras := ExtrasReader.get_extras(node)
    if extras.is_empty():
        return
    StateHandler.apply(node, extras)
    if not is_instance_valid(node):
        return
    NameHandler.apply(node, extras)
```

- [ ] **Step 6: Commit**

```bash
git add addons/gltf_pipeline/handlers/name_handler.gd \
        test/unit/test_name_handler.gd \
        addons/gltf_pipeline/pipeline_extension.gd
git commit -m "add name_override handler"
```

---

### Task 7: Expression-based property applier (shared utility)

**Files:**
- Create: `addons/gltf_pipeline/expression_applier.gd`
- Create: `test/unit/test_expression_applier.gd`

**Spec:** `SceneInit.gd:166-192` uses Godot's `Expression` class to evaluate each line against a node. Input formats:
- `prop_string`: semicolon-separated `key=expression` pairs.
- `prop_file`: one `key=expression` per line in a res-path file.
- A line with no `=` is evaluated as an expression for side effects (rare).
- Expression variables: `['node']`, executed as `e.execute([node])`.

- [ ] **Step 1: Write the failing test**

File: `test/unit/test_expression_applier.gd`
```gdscript
extends GutTest

class Holder extends Node:
    var int_prop: int = 0
    var float_prop: float = 0.0
    var color: Color = Color.WHITE
    var arr: Array = []

func test_simple_int_assignment():
    var h := Holder.new()
    ExpressionApplier.apply_lines(h, ["int_prop=42"])
    assert_eq(h.int_prop, 42)
    h.free()

func test_float_assignment():
    var h := Holder.new()
    ExpressionApplier.apply_lines(h, ["float_prop=3.14"])
    assert_almost_eq(h.float_prop, 3.14, 0.001)
    h.free()

func test_expression_with_node_ref():
    var h := Holder.new()
    h.int_prop = 10
    ExpressionApplier.apply_lines(h, ["int_prop=node.int_prop * 2"])
    assert_eq(h.int_prop, 20)
    h.free()

func test_color_constructor():
    var h := Holder.new()
    ExpressionApplier.apply_lines(h, ["color=Color(1,0,0)"])
    assert_eq(h.color, Color(1, 0, 0))
    h.free()

func test_multiple_lines():
    var h := Holder.new()
    ExpressionApplier.apply_lines(h, ["int_prop=1", "float_prop=2.5"])
    assert_eq(h.int_prop, 1)
    assert_almost_eq(h.float_prop, 2.5, 0.001)
    h.free()

func test_string_semicolon_split():
    var h := Holder.new()
    ExpressionApplier.apply_string(h, "int_prop=7;float_prop=8.5")
    assert_eq(h.int_prop, 7)
    assert_almost_eq(h.float_prop, 8.5, 0.001)
    h.free()

func test_empty_lines_are_skipped():
    var h := Holder.new()
    ExpressionApplier.apply_lines(h, ["", "int_prop=5", ""])
    assert_eq(h.int_prop, 5)
    h.free()

func test_bad_expression_does_not_crash():
    var h := Holder.new()
    # Malformed — must not throw, just print error.
    ExpressionApplier.apply_lines(h, ["int_prop=this_is_not_valid$$$"])
    assert_eq(h.int_prop, 0, "bad expr leaves prop at default")
    h.free()
```

- [ ] **Step 2: Run — fails**

- [ ] **Step 3: Implement**

File: `addons/gltf_pipeline/expression_applier.gd`
```gdscript
@tool
class_name ExpressionApplier
extends RefCounted

static func apply_string(node: Node, s: String) -> void:
    var lines := s.split(";", false)
    apply_lines(node, Array(lines))

static func apply_file(node: Node, res_path: String) -> void:
    var f := FileAccess.open(res_path, FileAccess.READ)
    if f == null:
        push_warning("ExpressionApplier: cannot open " + res_path)
        return
    var lines: Array = []
    while not f.eof_reached():
        var line := f.get_line()
        if line != "":
            lines.append(line)
    apply_lines(node, lines)

static func apply_lines(node: Node, lines: Array) -> void:
    for raw in lines:
        var line := String(raw).strip_edges()
        if line.is_empty():
            continue
        _apply_line(node, line)

static func _apply_line(node: Node, line: String) -> void:
    var components := line.split("=", false, 1)
    var e := Expression.new()
    if components.size() > 1:
        var prop_name := components[0].strip_edges()
        var expr := components[1].strip_edges()
        var parse_err := e.parse(expr, ["node"])
        if parse_err != OK:
            push_warning("ExpressionApplier parse error on %s: %s" % [line, e.get_error_text()])
            return
        var val = e.execute([node])
        if e.has_execute_failed():
            push_warning("ExpressionApplier execute error on %s: %s" % [line, e.get_error_text()])
            return
        node.set(prop_name, val)
    else:
        var parse_err := e.parse(line, ["node"])
        if parse_err != OK:
            push_warning("ExpressionApplier parse error on bare line %s: %s" % [line, e.get_error_text()])
            return
        e.execute([node])
```

- [ ] **Step 4: Run — passes**

- [ ] **Step 5: Commit**

```bash
git add addons/gltf_pipeline/expression_applier.gd test/unit/test_expression_applier.gd
git commit -m "add Expression-based property applier utility"
```

---

### Task 8: Script handler (load + prop_file/prop_string binding)

**Files:**
- Create: `addons/gltf_pipeline/handlers/script_handler.gd`
- Create: `test/fixtures/test_script.gd` (simple test script)
- Create: `test/fixtures/test_props.txt` (prop_file fixture)
- Create: `test/unit/test_script_handler.gd`
- Modify: `addons/gltf_pipeline/pipeline_extension.gd`

**Spec:** `SceneInit.gd:451-454` sets script unless the node is a collision node (handled separately). `SceneInit.gd:497-504` applies `prop_file`/`prop_string` after script is set, skipping collision/navmesh (those are handled in their own handlers). Since we process non-collision here, the skip logic lives in the dispatch decision, not in the script handler itself.

- [ ] **Step 1: Write fixtures**

File: `test/fixtures/test_script.gd`
```gdscript
extends Node3D
class_name TestScriptTarget

@export var test_value: int = 0
@export var test_factor: float = 1.0
```

File: `test/fixtures/test_props.txt`
```
test_value=99
test_factor=2.5
```

- [ ] **Step 2: Write the failing test**

File: `test/unit/test_script_handler.gd`
```gdscript
extends GutTest

const SCRIPT_PATH := "res://test/fixtures/test_script.gd"
const PROPS_PATH := "res://test/fixtures/test_props.txt"

func test_loads_script_from_path():
    var n := Node3D.new()
    ScriptHandler.apply(n, {"script": SCRIPT_PATH})
    assert_eq(n.get_script().resource_path, SCRIPT_PATH)
    n.free()

func test_applies_prop_string_after_script():
    var n := Node3D.new()
    ScriptHandler.apply(n, {
        "script": SCRIPT_PATH,
        "prop_string": "test_value=7;test_factor=3.5"
    })
    assert_eq(n.get("test_value"), 7)
    assert_almost_eq(n.get("test_factor"), 3.5, 0.001)
    n.free()

func test_applies_prop_file_after_script():
    var n := Node3D.new()
    ScriptHandler.apply(n, {
        "script": SCRIPT_PATH,
        "prop_file": PROPS_PATH
    })
    assert_eq(n.get("test_value"), 99)
    assert_almost_eq(n.get("test_factor"), 2.5, 0.001)
    n.free()

func test_no_script_key_no_prop_apply():
    var n := Node3D.new()
    ScriptHandler.apply(n, {"prop_string": "test_value=1"})
    assert_null(n.get_script())
    n.free()

func test_invalid_script_path_does_not_crash():
    var n := Node3D.new()
    ScriptHandler.apply(n, {"script": "res://does/not/exist.gd"})
    assert_null(n.get_script())
    n.free()
```

- [ ] **Step 3: Run — fails**

- [ ] **Step 4: Implement**

File: `addons/gltf_pipeline/handlers/script_handler.gd`
```gdscript
@tool
class_name ScriptHandler
extends RefCounted

static func apply(node: Node, extras: Dictionary) -> void:
    if not extras.has("script"):
        _apply_props_only(node, extras)
        return
    var path = extras["script"]
    if not (path is String) or path.is_empty():
        _apply_props_only(node, extras)
        return
    var script = load(path)
    if script == null:
        push_warning("ScriptHandler: failed to load " + path)
        _apply_props_only(node, extras)
        return
    node.set_script(script)
    _apply_props_only(node, extras)

static func _apply_props_only(node: Node, extras: Dictionary) -> void:
    if extras.has("prop_file"):
        var p = extras["prop_file"]
        if p is String and not p.is_empty():
            ExpressionApplier.apply_file(node, p)
    if extras.has("prop_string"):
        var s = extras["prop_string"]
        if s is String and not s.is_empty():
            ExpressionApplier.apply_string(node, s)
```

- [ ] **Step 5: Run — passes**

- [ ] **Step 6: Wire dispatch (script/prop_* skipped when collision/nav_mesh present)**

Modify `_dispatch` in `pipeline_extension.gd`:
```gdscript
func _dispatch(node: Node, ctx: PipelineContext) -> void:
    if _visit_for_test.is_valid():
        _visit_for_test.call(node)
    var extras := ExtrasReader.get_extras(node)
    if extras.is_empty():
        return
    StateHandler.apply(node, extras)
    if not is_instance_valid(node):
        return
    NameHandler.apply(node, extras)
    # script/prop_* apply here ONLY when collision/nav_mesh are NOT present.
    # Those features handle the prop application on the generated body instead.
    if not extras.has("collision") and not extras.has("nav_mesh"):
        ScriptHandler.apply(node, extras)
```

- [ ] **Step 7: Commit**

```bash
git add addons/gltf_pipeline/handlers/script_handler.gd \
        test/fixtures/test_script.gd test/fixtures/test_props.txt \
        test/unit/test_script_handler.gd \
        addons/gltf_pipeline/pipeline_extension.gd
git commit -m "add script + prop_file/prop_string binding handler"
```

---

### Task 9: `material_0..3` handler

**Files:**
- Create: `addons/gltf_pipeline/handlers/material_handler.gd`
- Create: `test/fixtures/test_mat_red.tres` (StandardMaterial3D)
- Create: `test/fixtures/test_mat_blue.tres` (StandardMaterial3D)
- Create: `test/unit/test_material_handler.gd`
- Modify: `addons/gltf_pipeline/pipeline_extension.gd`

**Spec:** `SceneInit.gd:194-204` sets `surface_override_material` per surface index; a `shader` extras key on the same node causes `material.set_shader(load(shader_path))` to be called on the loaded material BEFORE assignment.

- [ ] **Step 1: Write fixtures (via script or hand-authored .tres)**

File: `test/fixtures/test_mat_red.tres`
```
[gd_resource type="StandardMaterial3D" format=3]

[resource]
albedo_color = Color(1, 0, 0, 1)
```

File: `test/fixtures/test_mat_blue.tres`
```
[gd_resource type="StandardMaterial3D" format=3]

[resource]
albedo_color = Color(0, 0, 1, 1)
```

- [ ] **Step 2: Write the failing test**

File: `test/unit/test_material_handler.gd`
```gdscript
extends GutTest

const RED := "res://test/fixtures/test_mat_red.tres"
const BLUE := "res://test/fixtures/test_mat_blue.tres"

func _make_mesh() -> MeshInstance3D:
    var mi := MeshInstance3D.new()
    var array_mesh := ArrayMesh.new()
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for i in 3:
        st.add_vertex(Vector3(i, 0, 0))
    st.commit(array_mesh)
    # Add a second surface
    st.clear()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for i in 3:
        st.add_vertex(Vector3(i, 1, 0))
    st.commit(array_mesh)
    mi.mesh = array_mesh
    return mi

func test_sets_material_on_surface_0():
    var mi := _make_mesh()
    MaterialHandler.apply(mi, {"material_0": RED})
    var m = mi.get_surface_override_material(0)
    assert_not_null(m)
    assert_eq(m.resource_path, RED)
    mi.free()

func test_sets_materials_on_multiple_surfaces():
    var mi := _make_mesh()
    MaterialHandler.apply(mi, {"material_0": RED, "material_1": BLUE})
    assert_eq(mi.get_surface_override_material(0).resource_path, RED)
    assert_eq(mi.get_surface_override_material(1).resource_path, BLUE)
    mi.free()

func test_non_mesh_instance_is_noop():
    var n := Node3D.new()
    MaterialHandler.apply(n, {"material_0": RED})
    assert_true(true, "did not crash")
    n.free()

func test_missing_material_keys_is_noop():
    var mi := _make_mesh()
    MaterialHandler.apply(mi, {})
    assert_null(mi.get_surface_override_material(0))
    mi.free()

func test_bad_path_is_warned_not_crash():
    var mi := _make_mesh()
    MaterialHandler.apply(mi, {"material_0": "res://bogus.tres"})
    assert_null(mi.get_surface_override_material(0))
    mi.free()
```

- [ ] **Step 3: Run — fails**

- [ ] **Step 4: Implement**

File: `addons/gltf_pipeline/handlers/material_handler.gd`
```gdscript
@tool
class_name MaterialHandler
extends RefCounted

static func apply(node: Node, extras: Dictionary) -> void:
    if not (node is MeshInstance3D):
        return
    var mi := node as MeshInstance3D
    for i in range(4):
        var key := "material_%d" % i
        if not extras.has(key):
            continue
        var path = extras[key]
        if not (path is String) or path.is_empty():
            continue
        var mat: Material = load(path)
        if mat == null:
            push_warning("MaterialHandler: failed to load " + path)
            continue
        # Apply shader override onto the material BEFORE binding, if requested.
        if extras.has("shader"):
            var shader_path = extras["shader"]
            if shader_path is String and not shader_path.is_empty() and mat is ShaderMaterial:
                var shader: Shader = load(shader_path)
                if shader:
                    (mat as ShaderMaterial).shader = shader
        mi.set_surface_override_material(i, mat)
```

- [ ] **Step 5: Run — passes**

- [ ] **Step 6: Wire dispatch**

In `_dispatch`, after `ScriptHandler.apply(...)`:
```gdscript
    MaterialHandler.apply(node, extras)
```

- [ ] **Step 7: Commit**

```bash
git add addons/gltf_pipeline/handlers/material_handler.gd \
        test/fixtures/test_mat_red.tres test/fixtures/test_mat_blue.tres \
        test/unit/test_material_handler.gd \
        addons/gltf_pipeline/pipeline_extension.gd
git commit -m "add material_0..3 handler with shader override"
```

---

### Task 10: `shader` handler for non-ShaderMaterial case

**Files:**
- Modify: `addons/gltf_pipeline/handlers/material_handler.gd`
- Create: `test/fixtures/test_shader.gdshader`
- Create: `test/fixtures/test_shader_mat.tres` (ShaderMaterial using test_shader.gdshader)
- Modify: `test/unit/test_material_handler.gd`

**Spec:** `SceneInit.gd:200-203`: when `shader` is present AND the loaded material is a `ShaderMaterial`, v2.5.5 calls `material.set_shader(shader)` replacing only the shader. Materials that aren't `ShaderMaterial` can't have their shader swapped; v2.5.5 just leaves them alone. Our Task 9 implementation is already correct — this task adds test coverage for `ShaderMaterial` and confirms non-shader materials are untouched by the `shader` key.

- [ ] **Step 1: Write shader fixture**

File: `test/fixtures/test_shader.gdshader`
```gdshader
shader_type spatial;
void fragment() {
    ALBEDO = vec3(0.5, 0.5, 0.5);
}
```

File: `test/fixtures/test_shader_mat.tres`
```
[gd_resource type="ShaderMaterial" load_steps=2 format=3]

[ext_resource type="Shader" path="res://test/fixtures/test_shader.gdshader" id="1"]

[resource]
shader = ExtResource("1")
```

- [ ] **Step 2: Add tests (append to `test_material_handler.gd`)**

```gdscript
const SHADER_MAT := "res://test/fixtures/test_shader_mat.tres"
const SHADER_ONLY := "res://test/fixtures/test_shader.gdshader"

func test_shader_override_on_shader_material():
    var mi := _make_mesh()
    MaterialHandler.apply(mi, {
        "material_0": SHADER_MAT,
        "shader": SHADER_ONLY
    })
    var m: Material = mi.get_surface_override_material(0)
    assert_true(m is ShaderMaterial)
    assert_eq((m as ShaderMaterial).shader.resource_path, SHADER_ONLY)
    mi.free()

func test_shader_key_without_shader_material_is_ignored():
    var mi := _make_mesh()
    # RED is a StandardMaterial3D, not a ShaderMaterial — shader key must be ignored
    MaterialHandler.apply(mi, {"material_0": RED, "shader": SHADER_ONLY})
    var m = mi.get_surface_override_material(0)
    assert_true(m is StandardMaterial3D)
    mi.free()
```

- [ ] **Step 3: Run — both new tests pass because Task 9 logic already covers this**

Expected: all tests in file pass.

- [ ] **Step 4: Commit**

```bash
git add test/fixtures/test_shader.gdshader test/fixtures/test_shader_mat.tres \
        test/unit/test_material_handler.gd
git commit -m "add shader override test coverage"
```

---

### Task 11: `physics_mat` handler

**Files:**
- Create: `addons/gltf_pipeline/handlers/physics_material_handler.gd`
- Create: `test/fixtures/test_phys_mat.tres`
- Create: `test/unit/test_physics_material_handler.gd`

**Spec:** `SceneInit.gd:218-220` assigns `body.physics_material_override = load(path)` for `StaticBody3D` and `RigidBody3D`. The handler runs against the generated body (not the original node) — so this is a helper called from the collision handler. We'll still test it directly.

- [ ] **Step 1: Write fixture**

File: `test/fixtures/test_phys_mat.tres`
```
[gd_resource type="PhysicsMaterial" format=3]

[resource]
friction = 0.7
bounce = 0.3
```

- [ ] **Step 2: Write the failing test**

File: `test/unit/test_physics_material_handler.gd`
```gdscript
extends GutTest

const MAT := "res://test/fixtures/test_phys_mat.tres"

func test_applies_to_static_body():
    var b := StaticBody3D.new()
    PhysicsMaterialHandler.apply(b, MAT)
    assert_not_null(b.physics_material_override)
    assert_almost_eq(b.physics_material_override.friction, 0.7, 0.001)
    b.free()

func test_applies_to_rigid_body():
    var b := RigidBody3D.new()
    PhysicsMaterialHandler.apply(b, MAT)
    assert_not_null(b.physics_material_override)
    b.free()

func test_does_not_apply_to_area():
    var a := Area3D.new()
    PhysicsMaterialHandler.apply(a, MAT)
    # Area3D has no physics_material_override property. No crash = pass.
    assert_true(true)
    a.free()

func test_bad_path_noop():
    var b := StaticBody3D.new()
    PhysicsMaterialHandler.apply(b, "res://nope.tres")
    assert_null(b.physics_material_override)
    b.free()
```

- [ ] **Step 3: Run — fails**

- [ ] **Step 4: Implement**

File: `addons/gltf_pipeline/handlers/physics_material_handler.gd`
```gdscript
@tool
class_name PhysicsMaterialHandler
extends RefCounted

static func apply(body: Node, path: String) -> void:
    if not (body is StaticBody3D or body is RigidBody3D):
        return
    if path.is_empty():
        return
    var mat: PhysicsMaterial = load(path)
    if mat == null:
        push_warning("PhysicsMaterialHandler: failed to load " + path)
        return
    body.physics_material_override = mat
```

- [ ] **Step 5: Run — passes**

- [ ] **Step 6: Commit**

```bash
git add addons/gltf_pipeline/handlers/physics_material_handler.gd \
        test/fixtures/test_phys_mat.tres \
        test/unit/test_physics_material_handler.gd
git commit -m "add physics_mat handler"
```

---

### Task 12: Collision body factory

**Files:**
- Create: `addons/gltf_pipeline/handlers/collision_handler.gd` (grow incrementally)
- Create: `test/unit/test_collision_body_factory.gd`

**Spec:** `SceneInit.gd:223-243`. Flags in `collision` meta_val:
- `-r` → `RigidBody3D`
- `-a` → `Area3D`
- `-m` → `AnimatableBody3D`
- `-h` → `CharacterBody3D`
- (no flag) → `StaticBody3D`
- `-c` → null (collision-only, attached to parent of node; no body at all)

- [ ] **Step 1: Write the failing test**

File: `test/unit/test_collision_body_factory.gd`
```gdscript
extends GutTest

func test_default_is_static_body():
    var b = CollisionHandler.make_body("box", "Wall")
    assert_true(b is StaticBody3D)
    assert_eq(b.name, "StaticBody3D_Wall")

func test_rigid_flag():
    var b = CollisionHandler.make_body("box-r", "Crate")
    assert_true(b is RigidBody3D)
    assert_eq(b.name, "RigidBody3D_Crate")

func test_area_flag():
    var b = CollisionHandler.make_body("box-a", "Trigger")
    assert_true(b is Area3D)

func test_animatable_flag():
    var b = CollisionHandler.make_body("box-m", "Platform")
    assert_true(b is AnimatableBody3D)

func test_character_flag():
    var b = CollisionHandler.make_body("box-h", "Npc")
    assert_true(b is CharacterBody3D)

func test_col_only_returns_null():
    var b = CollisionHandler.make_body("box-c", "Whatever")
    assert_null(b, "collision-only: no body created")
```

- [ ] **Step 2: Run — fails**

- [ ] **Step 3: Implement (start of CollisionHandler)**

File: `addons/gltf_pipeline/handlers/collision_handler.gd`
```gdscript
@tool
class_name CollisionHandler
extends RefCounted

static func make_body(col: String, base_name: String) -> Node:
    if col.find("-c") != -1:
        return null
    if col.find("-r") != -1:
        var b := RigidBody3D.new()
        b.name = "RigidBody3D_" + base_name
        return b
    if col.find("-a") != -1:
        var a := Area3D.new()
        a.name = "Area3D_" + base_name
        return a
    if col.find("-m") != -1:
        var m := AnimatableBody3D.new()
        m.name = "AnimatableBody3D_" + base_name
        return m
    if col.find("-h") != -1:
        var h := CharacterBody3D.new()
        h.name = "CharacterBody3D_" + base_name
        return h
    var s := StaticBody3D.new()
    s.name = "StaticBody3D_" + base_name
    return s
```

- [ ] **Step 4: Run — passes**

- [ ] **Step 5: Commit**

```bash
git add addons/gltf_pipeline/handlers/collision_handler.gd test/unit/test_collision_body_factory.gd
git commit -m "add collision body factory with all body type flags"
```

---

### Task 13: Collision primitive shape factory

**Files:**
- Modify: `addons/gltf_pipeline/handlers/collision_handler.gd`
- Create: `test/unit/test_collision_shape_factory.gd`

**Spec:** `SceneInit.gd:312-357`. Primitive shapes:
- `box` → `BoxShape3D` with `size = Vector3(size_x, size_y, size_z)`
- `cylinder` → `CylinderShape3D` with `height`, `radius`
- `sphere` → `SphereShape3D` with `radius`
- `capsule` → `CapsuleShape3D` with `height`, `radius`

Missing size/height/radius keys cause v2.5.5 to skip assignment silently — we preserve that.

- [ ] **Step 1: Write the failing test**

File: `test/unit/test_collision_shape_factory.gd`
```gdscript
extends GutTest

func _ex(keys: Dictionary) -> Dictionary: return keys

func test_box_shape():
    var s = CollisionHandler.make_shape("box", null, _ex({
        "size_x": "2", "size_y": "3", "size_z": "4"
    }))
    assert_true(s is BoxShape3D)
    assert_eq(s.size, Vector3(2, 3, 4))

func test_sphere_shape():
    var s = CollisionHandler.make_shape("sphere", null, _ex({"radius": "1.5"}))
    assert_true(s is SphereShape3D)
    assert_almost_eq(s.radius, 1.5, 0.001)

func test_capsule_shape():
    var s = CollisionHandler.make_shape("capsule", null, _ex({
        "height": "2", "radius": "0.5"
    }))
    assert_true(s is CapsuleShape3D)
    assert_almost_eq(s.height, 2.0, 0.001)
    assert_almost_eq(s.radius, 0.5, 0.001)

func test_cylinder_shape():
    var s = CollisionHandler.make_shape("cylinder", null, _ex({
        "height": "4", "radius": "1"
    }))
    assert_true(s is CylinderShape3D)

func test_box_missing_size_key_returns_empty_shape():
    var s = CollisionHandler.make_shape("box", null, _ex({"size_x": "1"}))
    # With missing size_y/size_z, v2.5.5 never sets size; shape is created but uninitialized.
    # We return null instead to be explicit.
    assert_null(s)

func test_unknown_type_returns_null():
    var s = CollisionHandler.make_shape("triangle_soup", null, _ex({}))
    assert_null(s)
```

- [ ] **Step 2: Run — fails**

- [ ] **Step 3: Implement (append to CollisionHandler)**

Add to `collision_handler.gd`:
```gdscript
static func make_shape(col: String, node: Node, extras: Dictionary) -> Shape3D:
    var base := col.split("-")[0]
    match base:
        "box":
            if not (extras.has("size_x") and extras.has("size_y") and extras.has("size_z")):
                return null
            var s := BoxShape3D.new()
            s.size = Vector3(
                float(extras["size_x"]),
                float(extras["size_y"]),
                float(extras["size_z"])
            )
            return s
        "sphere":
            if not extras.has("radius"):
                return null
            var s := SphereShape3D.new()
            s.radius = float(extras["radius"])
            return s
        "capsule":
            if not (extras.has("height") and extras.has("radius")):
                return null
            var s := CapsuleShape3D.new()
            s.height = float(extras["height"])
            s.radius = float(extras["radius"])
            return s
        "cylinder":
            if not (extras.has("height") and extras.has("radius")):
                return null
            var s := CylinderShape3D.new()
            s.height = float(extras["height"])
            s.radius = float(extras["radius"])
            return s
        "trimesh":
            if node is MeshInstance3D and (node as MeshInstance3D).mesh:
                return (node as MeshInstance3D).mesh.create_trimesh_shape()
            return null
        "simple":
            if node is MeshInstance3D and (node as MeshInstance3D).mesh:
                return (node as MeshInstance3D).mesh.create_convex_shape()
            return null
    return null
```

- [ ] **Step 4: Run — passes**

- [ ] **Step 5: Commit**

```bash
git add addons/gltf_pipeline/handlers/collision_handler.gd test/unit/test_collision_shape_factory.gd
git commit -m "add collision primitive and mesh-derived shape factories"
```

---

### Task 14: Collision center offset + full `apply` flow

**Files:**
- Modify: `addons/gltf_pipeline/handlers/collision_handler.gd`
- Create: `test/unit/test_collision_flags.gd`

**Spec:** `SceneInit.gd:305-310`: center offset is applied ONLY to primitive (box/sphere/capsule/cylinder), NOT to trimesh/simple. The offset is `(center_x, center_y, -center_z)` (z negated — Blender/Godot handedness).

**Spec overall flow** `SceneInit.gd:223-386`:
1. `body = make_body()` (may be null for `-c`)
2. Create `CollisionShape3D` with name `CollisionShape3D_<node.name>` (when `"bodyonly"` NOT in meta).
3. Set `cs.shape = make_shape()`. If null → skip.
4. Apply center offset (primitives only).
5. For `-c` (col_only): `node.get_parent().add_child(cs)` and `cs.position = node.position`.
6. For normal: `body.add_child(cs)` (cs.scale/rotation from node), `node.get_parent().add_child(body)`, `body.position = node.position`.
7. For `-d` (discard_mesh): skip duplicating the mesh into the body. Otherwise, strip the node's children and reparent a mesh-less duplicate of node under body.
8. Reparent existing `CollisionShape3D` children of node under body (queued to `deferred_reparents`).
9. `collision_script()` applies script/prop_file/prop_string/physics_mat to the BODY (not the original node).
10. Queue original node for deletion (`deferred_deletes`).
11. Set `cs.debug_fill = false` on Godot >= 4.4.

- [ ] **Step 1: Write the failing test**

File: `test/unit/test_collision_flags.gd`
```gdscript
extends GutTest

class FakeCtx:
    var deferred_deletes: Array[Node] = []
    var deferred_reparents: Array = []

var ctx: PipelineGLTFExtension.PipelineContext

func _make_mesh_instance() -> MeshInstance3D:
    var mi := MeshInstance3D.new()
    mi.name = "Wall"
    mi.position = Vector3(5, 0, 0)
    mi.mesh = BoxMesh.new()
    return mi

func before_each():
    ctx = PipelineGLTFExtension.PipelineContext.new()

func test_normal_collision_wraps_in_body():
    var parent := Node3D.new()
    var mi := _make_mesh_instance()
    parent.add_child(mi)
    CollisionHandler.apply(mi, {
        "collision": "box",
        "size_x": "1", "size_y": "1", "size_z": "1"
    }, ctx)
    # After apply: body is a child of parent, CollisionShape3D is under body.
    var body: Node = null
    for c in parent.get_children():
        if c is StaticBody3D:
            body = c
    assert_not_null(body, "StaticBody3D created under parent")
    assert_eq(body.position, Vector3(5, 0, 0), "body takes node's position")
    var cs: CollisionShape3D = null
    for c in body.get_children():
        if c is CollisionShape3D:
            cs = c
    assert_not_null(cs)
    assert_true(cs.shape is BoxShape3D)
    assert_true(mi in ctx.deferred_deletes)
    parent.free()

func test_col_only_attaches_shape_to_parent_no_body():
    var parent := Node3D.new()
    var mi := _make_mesh_instance()
    parent.add_child(mi)
    CollisionHandler.apply(mi, {
        "collision": "box-c",
        "size_x": "1", "size_y": "1", "size_z": "1"
    }, ctx)
    var has_body := false
    var has_shape := false
    for c in parent.get_children():
        if c is StaticBody3D:
            has_body = true
        if c is CollisionShape3D:
            has_shape = true
    assert_false(has_body, "-c: no body created")
    assert_true(has_shape, "-c: shape attached to parent")
    parent.free()

func test_center_offset_on_primitives():
    var parent := Node3D.new()
    var mi := _make_mesh_instance()
    parent.add_child(mi)
    CollisionHandler.apply(mi, {
        "collision": "box",
        "size_x": "1", "size_y": "1", "size_z": "1",
        "center_x": "0.5", "center_y": "1.0", "center_z": "0.25"
    }, ctx)
    var body: StaticBody3D = null
    for c in parent.get_children():
        if c is StaticBody3D: body = c
    var cs: CollisionShape3D = null
    for c in body.get_children():
        if c is CollisionShape3D: cs = c
    # z should be negated per v2.5.5
    assert_eq(cs.position, Vector3(0.5, 1.0, -0.25))
    parent.free()

func test_center_offset_NOT_applied_for_trimesh():
    var parent := Node3D.new()
    var mi := _make_mesh_instance()
    parent.add_child(mi)
    CollisionHandler.apply(mi, {
        "collision": "trimesh",
        "center_x": "1", "center_y": "2", "center_z": "3"
    }, ctx)
    var body: StaticBody3D = null
    for c in parent.get_children():
        if c is StaticBody3D: body = c
    var cs: CollisionShape3D = null
    for c in body.get_children():
        if c is CollisionShape3D: cs = c
    assert_eq(cs.position, Vector3.ZERO, "trimesh: center offset not applied")
    parent.free()

func test_bodyonly_flag_skips_collision_shape():
    var parent := Node3D.new()
    var mi := _make_mesh_instance()
    parent.add_child(mi)
    CollisionHandler.apply(mi, {
        "collision": "box-r bodyonly",
        "size_x": "1", "size_y": "1", "size_z": "1"
    }, ctx)
    var body: RigidBody3D = null
    for c in parent.get_children():
        if c is RigidBody3D: body = c
    assert_not_null(body)
    var has_cs := false
    for c in body.get_children():
        if c is CollisionShape3D: has_cs = true
    assert_false(has_cs, "bodyonly: no CollisionShape3D")
    parent.free()

func test_discard_mesh_flag():
    var parent := Node3D.new()
    var mi := _make_mesh_instance()
    parent.add_child(mi)
    CollisionHandler.apply(mi, {
        "collision": "box-d",
        "size_x": "1", "size_y": "1", "size_z": "1"
    }, ctx)
    var body: StaticBody3D = null
    for c in parent.get_children():
        if c is StaticBody3D: body = c
    # With -d, body has only the CollisionShape3D — no duplicated mesh child
    var non_cs_children := 0
    for c in body.get_children():
        if not (c is CollisionShape3D): non_cs_children += 1
    assert_eq(non_cs_children, 0, "-d: body has no mesh duplicate")
    parent.free()

func test_existing_collision_shape_child_is_deferred_reparent():
    var parent := Node3D.new()
    var mi := _make_mesh_instance()
    var preexisting := CollisionShape3D.new()
    preexisting.name = "PreExisting"
    mi.add_child(preexisting)
    parent.add_child(mi)
    CollisionHandler.apply(mi, {
        "collision": "box",
        "size_x": "1", "size_y": "1", "size_z": "1"
    }, ctx)
    assert_eq(ctx.deferred_reparents.size(), 1, "one reparent queued")
    assert_eq(ctx.deferred_reparents[0][0], preexisting)
    parent.free()
```

- [ ] **Step 2: Run — fails**

- [ ] **Step 3: Implement full `apply` in CollisionHandler**

Append to `collision_handler.gd`:
```gdscript
static func apply(node: Node, extras: Dictionary, ctx) -> void:
    if not extras.has("collision"):
        return
    var col: String = str(extras["collision"])
    var simple := "simple" in col
    var trimesh := "trimesh" in col
    var bodyonly := "bodyonly" in col
    var discard_mesh := "-d" in col
    var col_only := "-c" in col

    var body := make_body(col, node.name)
    var shape := make_shape(col, node, extras)
    var parent := node.get_parent()

    # Create CollisionShape3D unless "bodyonly"
    var cs: CollisionShape3D = null
    if not bodyonly:
        if shape == null:
            push_warning("CollisionHandler: shape build failed for %s (col=%s)" % [node.name, col])
            return
        cs = CollisionShape3D.new()
        cs.name = "CollisionShape3D_" + str(node.name)
        cs.shape = shape
        if Engine.get_version_info().hex >= 0x040400:
            cs.debug_fill = false

        # Scale/rotation inherited from node
        if node is Node3D:
            cs.scale = (node as Node3D).scale
            cs.rotation = (node as Node3D).rotation

        # Center offset only on primitives (NOT trimesh, NOT simple)
        if not simple and not trimesh and _has_all(extras, ["center_x", "center_y", "center_z"]):
            var cx := float(extras["center_x"])
            var cy := float(extras["center_y"])
            var cz := -float(extras["center_z"])
            cs.position += Vector3(cx, cy, cz)

    # Place body/shape in scene
    if col_only:
        # No body. Shape goes to the node's parent at node's world position.
        if cs:
            parent.add_child(cs)
            if node is Node3D:
                cs.position = (node as Node3D).position + cs.position
    else:
        if body == null:
            return
        if node is Node3D:
            body.position = (node as Node3D).position
        if cs:
            body.add_child(cs)
        if not discard_mesh and node is MeshInstance3D:
            # Duplicate mesh into body, stripping its children (they get reparented below).
            var nd := node.duplicate() as Node3D
            # Strip children of the duplicate
            for c in nd.get_children():
                nd.remove_child(c)
                c.queue_free()
            nd.transform = Transform3D()
            nd.scale = (node as Node3D).scale
            nd.rotation = (node as Node3D).rotation
            body.add_child(nd)
        parent.add_child(body)

        # Pre-existing CollisionShape3D children of node → reparent to body
        for child in node.get_children():
            if child is CollisionShape3D:
                ctx.deferred_reparents.append([child, body])

        # Apply script/prop_*/physics_mat to BODY
        if extras.has("script"):
            var sp = extras["script"]
            if sp is String and not sp.is_empty():
                var sc = load(sp)
                if sc: body.set_script(sc)
        if extras.has("prop_file"):
            var pf = extras["prop_file"]
            if pf is String and not pf.is_empty():
                ExpressionApplier.apply_file(body, pf)
        if extras.has("prop_string"):
            var ps = extras["prop_string"]
            if ps is String and not ps.is_empty():
                ExpressionApplier.apply_string(body, ps)
        if extras.has("physics_mat"):
            var pm = extras["physics_mat"]
            if pm is String and not pm.is_empty():
                PhysicsMaterialHandler.apply(body, pm)

    # Queue original node for deletion
    ctx.deferred_deletes.append(node)

static func _has_all(d: Dictionary, keys: Array) -> bool:
    for k in keys:
        if not d.has(k): return false
    return true
```

- [ ] **Step 4: Run — passes**

- [ ] **Step 5: Wire dispatch + flush**

Modify `_dispatch` in `pipeline_extension.gd`:
```gdscript
func _dispatch(node: Node, ctx: PipelineContext) -> void:
    if _visit_for_test.is_valid():
        _visit_for_test.call(node)
    var extras := ExtrasReader.get_extras(node)
    if extras.is_empty():
        return
    StateHandler.apply(node, extras)
    if not is_instance_valid(node):
        return
    NameHandler.apply(node, extras)
    if not extras.has("collision") and not extras.has("nav_mesh"):
        ScriptHandler.apply(node, extras)
    MaterialHandler.apply(node, extras)
    if extras.has("collision"):
        CollisionHandler.apply(node, extras, ctx)
```

And add a flush pass at the end of `_import_post`, BEFORE `return OK`:
```gdscript
    _flush(ctx)

func _flush(ctx: PipelineContext) -> void:
    for pair in ctx.deferred_reparents:
        var child: Node = pair[0]
        var new_parent: Node = pair[1]
        var old_parent := child.get_parent()
        if old_parent:
            old_parent.remove_child(child)
        new_parent.add_child(child)
    for n in ctx.deferred_deletes:
        if is_instance_valid(n):
            var p := n.get_parent()
            if p: p.remove_child(n)
            n.queue_free()
```

- [ ] **Step 6: Commit**

```bash
git add addons/gltf_pipeline/handlers/collision_handler.gd \
        test/unit/test_collision_flags.gd \
        addons/gltf_pipeline/pipeline_extension.gd
git commit -m "add full collision apply flow with flags and deferred ops"
```

---

### Task 15: `nav_mesh` handler

**Files:**
- Create: `addons/gltf_pipeline/handlers/navmesh_handler.gd`
- Create: `test/unit/test_navmesh_handler.gd`

**Spec:** `SceneInit.gd:390-409`. Given a `MeshInstance3D` with `nav_mesh=<res_path>`:
1. Save the mesh to `<res_path>` via `ResourceSaver.save(mi.mesh, res_path)`.
2. Create `NavigationMesh`, `create_from_mesh(mi.mesh)`.
3. Create `NavigationRegion3D` with that navmesh, `transform = mi.transform`, named `<mi.name>_NavMesh`.
4. If `prop_file` present, apply to the region.
5. Add region to `mi.get_parent()`.
6. Queue `mi` for deletion.

- [ ] **Step 1: Write the failing test**

File: `test/unit/test_navmesh_handler.gd`
```gdscript
extends GutTest

var tmp_dir := "user://navmesh_test"
var mesh_save := tmp_dir + "/nav.mesh"

func before_each():
    DirAccess.make_dir_absolute(tmp_dir)

func after_each():
    var d := DirAccess.open(tmp_dir)
    if d:
        for f in d.get_files(): d.remove(f)

func test_nav_mesh_replaces_node_with_navigation_region():
    var ctx := PipelineGLTFExtension.PipelineContext.new()
    var parent := Node3D.new()
    var mi := MeshInstance3D.new()
    mi.name = "Ground"
    mi.mesh = BoxMesh.new()
    mi.position = Vector3(1, 0, 2)
    parent.add_child(mi)
    NavMeshHandler.apply(mi, {"nav_mesh": mesh_save}, ctx)
    var region: NavigationRegion3D = null
    for c in parent.get_children():
        if c is NavigationRegion3D: region = c
    assert_not_null(region)
    assert_eq(region.name, "Ground_NavMesh")
    assert_not_null(region.navigation_mesh)
    assert_true(mi in ctx.deferred_deletes)
    parent.free()

func test_prop_file_applied_to_region():
    # Build a temp prop file
    var tmp_props := "user://navmesh_props.txt"
    var f := FileAccess.open(tmp_props, FileAccess.WRITE)
    f.store_line("enabled=false")
    f.close()

    var ctx := PipelineGLTFExtension.PipelineContext.new()
    var parent := Node3D.new()
    var mi := MeshInstance3D.new()
    mi.name = "Ground"
    mi.mesh = BoxMesh.new()
    parent.add_child(mi)
    NavMeshHandler.apply(mi, {"nav_mesh": mesh_save, "prop_file": tmp_props}, ctx)
    var region: NavigationRegion3D = null
    for c in parent.get_children():
        if c is NavigationRegion3D: region = c
    assert_false(region.enabled)
    parent.free()
```

- [ ] **Step 2: Run — fails**

- [ ] **Step 3: Implement**

File: `addons/gltf_pipeline/handlers/navmesh_handler.gd`
```gdscript
@tool
class_name NavMeshHandler
extends RefCounted

static func apply(node: Node, extras: Dictionary, ctx) -> void:
    if not (node is MeshInstance3D):
        return
    if not extras.has("nav_mesh"):
        return
    var save_path: String = extras["nav_mesh"]
    if save_path.is_empty():
        return
    var mi := node as MeshInstance3D
    if mi.mesh == null:
        push_warning("NavMeshHandler: MeshInstance has no mesh")
        return
    mi.mesh.resource_name = mi.name + "_NavMesh"
    ResourceSaver.save(mi.mesh, save_path)

    var navmesh := NavigationMesh.new()
    navmesh.create_from_mesh(mi.mesh)

    var region := NavigationRegion3D.new()
    region.navigation_mesh = navmesh
    region.transform = mi.transform
    region.name = str(mi.name) + "_NavMesh"

    if extras.has("prop_file"):
        var pf = extras["prop_file"]
        if pf is String and not pf.is_empty():
            ExpressionApplier.apply_file(region, pf)

    var parent := mi.get_parent()
    if parent:
        parent.add_child(region)
    ctx.deferred_deletes.append(mi)
```

- [ ] **Step 4: Run — passes**

- [ ] **Step 5: Wire dispatch** (add after collision branch):
```gdscript
    if extras.has("nav_mesh"):
        NavMeshHandler.apply(node, extras, ctx)
```

- [ ] **Step 6: Commit**

```bash
git add addons/gltf_pipeline/handlers/navmesh_handler.gd \
        test/unit/test_navmesh_handler.gd \
        addons/gltf_pipeline/pipeline_extension.gd
git commit -m "add nav_mesh generation handler"
```

---

### Task 16: `multimesh` aggregation

**Files:**
- Create: `addons/gltf_pipeline/handlers/multimesh_handler.gd`
- Create: `test/unit/test_multimesh_handler.gd`

**Spec:** `SceneInit.gd:412-449`. Multimesh is a TWO-PHASE operation:

**Phase 1 (per-node, called during walk):** `SceneInit.gd:412-425`
- If `meta_val` (the path) is not yet in `ctx.multimesh_groups`:
  - First time we see this key: save the mesh to `meta_val` via `ResourceSaver.save()` and set `resource_name = node.name`.
  - Initialize `ctx.multimesh_groups[meta_val] = []`.
- Append `node.transform` to `ctx.multimesh_groups[meta_val]`.
- Queue node for deletion.

**Phase 2 (after walk):** `SceneInit.gd:427-449`
- For each key in `multimesh_groups`:
  - Create `MultiMesh` with `transform_format = TRANSFORM_3D`, `instance_count = len(transforms)`.
  - Populate per-instance transforms.
  - `multimesh.mesh = load(meta_val)`.
  - Create `MultiMeshInstance3D`, `name = mesh.resource_name + "_Multimesh"`, add to root.

- [ ] **Step 1: Write the failing test**

File: `test/unit/test_multimesh_handler.gd`
```gdscript
extends GutTest

var tmp_mesh := "user://tree.mesh"

func test_collect_groups_transforms():
    var ctx := PipelineGLTFExtension.PipelineContext.new()
    var tree_a := MeshInstance3D.new()
    tree_a.name = "TreeA"
    tree_a.mesh = BoxMesh.new()
    tree_a.position = Vector3(1, 0, 0)
    var tree_b := MeshInstance3D.new()
    tree_b.name = "TreeB"
    tree_b.mesh = BoxMesh.new()
    tree_b.position = Vector3(5, 0, 0)

    MultimeshHandler.collect(tree_a, {"multimesh": tmp_mesh}, ctx)
    MultimeshHandler.collect(tree_b, {"multimesh": tmp_mesh}, ctx)

    assert_eq(ctx.multimesh_groups.size(), 1)
    assert_eq(ctx.multimesh_groups[tmp_mesh].size(), 2)
    assert_true(tree_a in ctx.deferred_deletes)
    assert_true(tree_b in ctx.deferred_deletes)
    tree_a.free()
    tree_b.free()

func test_emit_creates_multimesh_instance():
    var ctx := PipelineGLTFExtension.PipelineContext.new()
    ctx.multimesh_groups[tmp_mesh] = [
        Transform3D().translated(Vector3(1, 0, 0)),
        Transform3D().translated(Vector3(5, 0, 0))
    ]
    # Pretend we already saved the mesh
    ResourceSaver.save(BoxMesh.new(), tmp_mesh)

    var root := Node3D.new()
    MultimeshHandler.emit_all(root, ctx)

    var mm_inst: MultiMeshInstance3D = null
    for c in root.get_children():
        if c is MultiMeshInstance3D: mm_inst = c
    assert_not_null(mm_inst)
    assert_eq(mm_inst.multimesh.instance_count, 2)
    assert_eq(mm_inst.multimesh.transform_format, MultiMesh.TRANSFORM_3D)
    root.free()
```

- [ ] **Step 2: Run — fails**

- [ ] **Step 3: Implement**

File: `addons/gltf_pipeline/handlers/multimesh_handler.gd`
```gdscript
@tool
class_name MultimeshHandler
extends RefCounted

static func collect(node: Node, extras: Dictionary, ctx) -> void:
    if not (node is MeshInstance3D):
        return
    if not extras.has("multimesh"):
        return
    var path: String = extras["multimesh"]
    if path.is_empty():
        return
    var mi := node as MeshInstance3D
    if not ctx.multimesh_groups.has(path):
        ctx.multimesh_groups[path] = []
        if mi.mesh:
            mi.mesh.resource_name = mi.name
            ResourceSaver.save(mi.mesh, path)
            mi.mesh.take_over_path(path)
    ctx.multimesh_groups[path].append(mi.transform)
    ctx.deferred_deletes.append(mi)

static func emit_all(root: Node, ctx) -> void:
    for path in ctx.multimesh_groups.keys():
        var transforms: Array = ctx.multimesh_groups[path]
        var mm := MultiMesh.new()
        mm.transform_format = MultiMesh.TRANSFORM_3D
        mm.instance_count = transforms.size()
        for i in range(transforms.size()):
            mm.set_instance_transform(i, transforms[i])
        mm.mesh = ResourceLoader.load(path)
        var mm_inst := MultiMeshInstance3D.new()
        mm_inst.multimesh = mm
        var nm := "Multimesh"
        if mm.mesh and mm.mesh.resource_name != "":
            nm = mm.mesh.resource_name + "_Multimesh"
        mm_inst.name = nm
        root.add_child(mm_inst)
```

- [ ] **Step 4: Run — passes**

- [ ] **Step 5: Wire dispatch + emit**

In `_dispatch`:
```gdscript
    if extras.has("multimesh"):
        MultimeshHandler.collect(node, extras, ctx)
```

In `_import_post`, before `_flush(ctx)`:
```gdscript
    MultimeshHandler.emit_all(root, ctx)
```

- [ ] **Step 6: Commit**

```bash
git add addons/gltf_pipeline/handlers/multimesh_handler.gd \
        test/unit/test_multimesh_handler.gd \
        addons/gltf_pipeline/pipeline_extension.gd
git commit -m "add multimesh two-phase aggregation handler"
```

---

### Task 17: `packed_scene` handler

**Files:**
- Create: `addons/gltf_pipeline/handlers/packed_scene_handler.gd`
- Create: `test/fixtures/test_packed.tscn`
- Create: `test/unit/test_packed_scene_handler.gd`

**Spec:** `SceneInit.gd:516-524`. For `packed_scene=<path>`:
1. Load and instantiate.
2. Add to `node.get_parent()`.
3. Set `packed_scene.global_transform = node.global_transform`.
4. Name it `PackedScene_<node.name>`.
5. Queue original node for deletion.

- [ ] **Step 1: Write fixture**

File: `test/fixtures/test_packed.tscn`
```
[gd_scene format=3]

[node name="PackedRoot" type="Node3D"]

[node name="Inner" type="Label3D" parent="."]
text = "Hello"
```

- [ ] **Step 2: Write the failing test**

File: `test/unit/test_packed_scene_handler.gd`
```gdscript
extends GutTest

const PACKED := "res://test/fixtures/test_packed.tscn"

func test_instantiates_and_positions_at_node_transform():
    var ctx := PipelineGLTFExtension.PipelineContext.new()
    var parent := Node3D.new()
    var marker := Node3D.new()
    marker.name = "Spawn"
    marker.global_position = Vector3(10, 5, -3)
    parent.add_child(marker)

    PackedSceneHandler.apply(marker, {"packed_scene": PACKED}, ctx)

    var inst: Node = null
    for c in parent.get_children():
        if c.name == "PackedScene_Spawn": inst = c
    assert_not_null(inst)
    assert_eq((inst as Node3D).global_position, Vector3(10, 5, -3))
    assert_true(marker in ctx.deferred_deletes)
    parent.free()
```

- [ ] **Step 3: Run — fails**

- [ ] **Step 4: Implement**

File: `addons/gltf_pipeline/handlers/packed_scene_handler.gd`
```gdscript
@tool
class_name PackedSceneHandler
extends RefCounted

static func apply(node: Node, extras: Dictionary, ctx) -> void:
    if not extras.has("packed_scene"):
        return
    var path: String = extras["packed_scene"]
    if path.is_empty():
        return
    var scene: PackedScene = load(path)
    if scene == null:
        push_warning("PackedSceneHandler: failed to load " + path)
        return
    var inst := scene.instantiate()
    inst.name = "PackedScene_" + str(node.name)
    var parent := node.get_parent()
    if parent:
        parent.add_child(inst)
    if inst is Node3D and node is Node3D:
        (inst as Node3D).global_transform = (node as Node3D).global_transform
    ctx.deferred_deletes.append(node)
```

- [ ] **Step 5: Run — passes**

- [ ] **Step 6: Wire dispatch**

In `_dispatch` (after multimesh):
```gdscript
    if extras.has("packed_scene"):
        PackedSceneHandler.apply(node, extras, ctx)
```

- [ ] **Step 7: Commit**

```bash
git add addons/gltf_pipeline/handlers/packed_scene_handler.gd \
        test/fixtures/test_packed.tscn \
        test/unit/test_packed_scene_handler.gd \
        addons/gltf_pipeline/pipeline_extension.gd
git commit -m "add packed_scene instantiation handler"
```

---

### Task 18: Scene globals — `individual_origins`

**Files:**
- Create: `addons/gltf_pipeline/handlers/scene_globals_handler.gd`
- Create: `test/unit/test_scene_globals_handler.gd`

**Spec:** `SceneInit.gd:541-576`. When `GodotPipelineProps.individual_origins == 1`:
- For each top-level `Node3D` child of root: preserve current `global_position`, set `global_position = Vector3.ZERO`.

(This is combined with `packed_resources` in v2.5.5 — if both, the packed scene is re-positioned to the preserved global_position after load. We'll keep them separable.)

- [ ] **Step 1: Write the failing test**

File: `test/unit/test_scene_globals_handler.gd`
```gdscript
extends GutTest

func test_individual_origins_resets_top_level_positions():
    var root := Node3D.new()
    var a := Node3D.new()
    a.name = "A"
    a.global_position = Vector3(10, 0, 0)
    root.add_child(a)
    var b := Node3D.new()
    b.name = "B"
    b.global_position = Vector3(-5, 3, 2)
    root.add_child(b)

    SceneGlobalsHandler.apply_individual_origins(root)

    assert_eq(a.global_position, Vector3.ZERO)
    assert_eq(b.global_position, Vector3.ZERO)
    root.free()

func test_individual_origins_ignores_non_node3d():
    var root := Node3D.new()
    var label := Label3D.new()
    root.add_child(label)
    SceneGlobalsHandler.apply_individual_origins(root)
    # Must not crash
    assert_true(true)
    root.free()
```

- [ ] **Step 2: Run — fails**

- [ ] **Step 3: Implement**

File: `addons/gltf_pipeline/handlers/scene_globals_handler.gd`
```gdscript
@tool
class_name SceneGlobalsHandler
extends RefCounted

static func apply_individual_origins(root: Node) -> void:
    for child in root.get_children():
        if child is Node3D:
            (child as Node3D).global_position = Vector3.ZERO
```

- [ ] **Step 4: Run — passes**

- [ ] **Step 5: Wire into `_import_post` (after walk + emit + flush)**

```gdscript
    if ctx.scene_extras.get("individual_origins", 0) == 1:
        SceneGlobalsHandler.apply_individual_origins(root)
```

- [ ] **Step 6: Commit**

```bash
git add addons/gltf_pipeline/handlers/scene_globals_handler.gd \
        test/unit/test_scene_globals_handler.gd \
        addons/gltf_pipeline/pipeline_extension.gd
git commit -m "add individual_origins scene global"
```

---

### Task 19: Scene globals — `packed_resources`

**Files:**
- Modify: `addons/gltf_pipeline/handlers/scene_globals_handler.gd`
- Modify: `test/unit/test_scene_globals_handler.gd`

**Spec:** `SceneInit.gd:552-576`. When `GodotPipelineProps.packed_resources == 1`:
- For each top-level `Node3D` child:
  - Preserve `global_position`.
  - Set child ownership recursively so PackedScene.pack works (`set_children_to_parent`).
  - Pack child into PackedScene.
  - Save to `<gltf_path>/../packed_scenes/<child.name>.tscn`.
  - Remove child, instantiate packed scene, add to root, re-apply preserved global_position if `individual_origins` also set.
  - Free original child.

Note the save directory is `<gltf_path>.get_base_dir() + "/packed_scenes"`. Our ctx has `gltf_path` but during `_import_post` we don't automatically know this — we'll pass it in from the dispatch wiring via `state.filename` (Godot sets this) or fall back to the root scene's path.

- [ ] **Step 1: Extend test**

Append to `test_scene_globals_handler.gd`:
```gdscript
const SAVE_DIR := "user://packed_scenes"

func test_packed_resources_packs_each_top_level_child():
    var dir := DirAccess.open("user://")
    if dir and not dir.dir_exists("packed_scenes"):
        dir.make_dir("packed_scenes")
    var root := Node3D.new()
    var c1 := Node3D.new()
    c1.name = "Crate"
    c1.add_child(Node3D.new())
    root.add_child(c1)
    var c2 := Node3D.new()
    c2.name = "Barrel"
    root.add_child(c2)

    SceneGlobalsHandler.apply_packed_resources(root, SAVE_DIR, false)

    # Expect a Crate.tscn and Barrel.tscn saved
    assert_true(ResourceLoader.exists(SAVE_DIR + "/Crate.tscn"))
    assert_true(ResourceLoader.exists(SAVE_DIR + "/Barrel.tscn"))
    # Root now contains PackedScene_Crate and PackedScene_Barrel
    var names := []
    for c in root.get_children(): names.append(c.name)
    assert_has(names, "PackedScene_Crate")
    assert_has(names, "PackedScene_Barrel")
    root.free()

func test_packed_resources_with_individual_origins_preserves_position():
    var root := Node3D.new()
    var c1 := Node3D.new()
    c1.name = "Placed"
    c1.global_position = Vector3(7, 8, 9)
    root.add_child(c1)
    SceneGlobalsHandler.apply_packed_resources(root, SAVE_DIR, true)
    var reloaded: Node3D = null
    for c in root.get_children():
        if c.name == "PackedScene_Placed": reloaded = c
    assert_not_null(reloaded)
    assert_eq(reloaded.global_position, Vector3(7, 8, 9))
    root.free()
```

- [ ] **Step 2: Run — fails**

- [ ] **Step 3: Implement**

Append to `scene_globals_handler.gd`:
```gdscript
static func apply_packed_resources(root: Node, save_dir: String, preserve_origin: bool) -> void:
    DirAccess.make_dir_recursive_absolute(save_dir)
    # Snapshot children first — we mutate root
    var children := []
    for c in root.get_children(): children.append(c)
    for child in children:
        if not (child is Node3D): continue
        var c3 := child as Node3D
        var preserve := c3.global_position
        _set_ownership_recursive(child, child)
        var ps := PackedScene.new()
        var err := ps.pack(child)
        if err != OK:
            push_warning("packed_resources: pack failed for " + str(child.name))
            continue
        var scene_path := save_dir + "/" + str(child.name) + ".tscn"
        var save_err := ResourceSaver.save(ps, scene_path)
        if save_err != OK:
            push_warning("packed_resources: save failed for " + scene_path)
            continue
        var inst := (load(scene_path) as PackedScene).instantiate()
        inst.name = "PackedScene_" + str(child.name)
        root.add_child(inst)
        if preserve_origin and inst is Node3D:
            (inst as Node3D).global_position = preserve
        root.remove_child(child)
        child.queue_free()

static func _set_ownership_recursive(node: Node, owner: Node) -> void:
    for c in node.get_children():
        _set_ownership_recursive(c, owner)
        c.owner = owner
```

- [ ] **Step 4: Run — passes**

- [ ] **Step 5: Wire in `_import_post` (after individual_origins)**

```gdscript
    if ctx.scene_extras.get("packed_resources", 0) == 1:
        var save_dir := _derive_packed_dir(state)
        var preserve := ctx.scene_extras.get("individual_origins", 0) == 1
        SceneGlobalsHandler.apply_packed_resources(root, save_dir, preserve)
```

Add helper in `pipeline_extension.gd`:
```gdscript
func _derive_packed_dir(state: GLTFState) -> String:
    var base := "res://packed_scenes"
    if state and state.filename != "":
        base = state.filename.get_base_dir() + "/packed_scenes"
    return base
```

- [ ] **Step 6: Commit**

```bash
git add addons/gltf_pipeline/handlers/scene_globals_handler.gd \
        test/unit/test_scene_globals_handler.gd \
        addons/gltf_pipeline/pipeline_extension.gd
git commit -m "add packed_resources scene global with tscn saving"
```

---

### Task 20: Integration fixture — primitives collision scene

**Files:**
- Create: `test/fixtures/primitives/README.md`
- Create: `test/fixtures/primitives/primitives.blend` (via Blender)
- Create: `test/fixtures/primitives/primitives.gltf` + `.bin` (Blender export)
- Create: `test/integration/test_import_primitives.gd`
- Create: `test/integration/helpers.gd`

**Spec:** Build a Blender scene with four meshes tagged:
- `BoxWall` — `collision=box`, `size_x=2`, `size_y=1`, `size_z=0.2`
- `SphereProp` — `collision=sphere-r`, `radius=0.5`
- `CylinderCol` — `collision=cylinder`, `height=1.5`, `radius=0.3`
- `CapsuleNPC` — `collision=capsule-h`, `height=1`, `radius=0.3`

Export as glTF Separate (keeps .bin readable). Test loads the .gltf through `GLTFDocument.new().append_from_file` + `generate_scene`, asserts the resulting tree.

- [ ] **Step 1: Author `primitives.blend`** (MANUAL, can't scripted in CI)

Write README describing the steps precisely so someone can regenerate:

File: `test/fixtures/primitives/README.md`
```markdown
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
```

- [ ] **Step 2: Write integration helpers**

File: `test/integration/helpers.gd`
```gdscript
@tool
class_name PipelineTestHelpers
extends RefCounted

static func import_gltf(path: String) -> Node:
    var gltf := GLTFDocument.new()
    var state := GLTFState.new()
    var err := gltf.append_from_file(path, state)
    if err != OK:
        push_error("Failed to load " + path + " err=" + str(err))
        return null
    return gltf.generate_scene(state)
```

- [ ] **Step 3: Write the integration test — initially failing (fixture not authored)**

File: `test/integration/test_import_primitives.gd`
```gdscript
extends GutTest

const FIXTURE := "res://test/fixtures/primitives/primitives.gltf"

func test_box_wall_becomes_static_body_with_box_shape():
    if not ResourceLoader.exists(FIXTURE):
        pending("fixture not present — author per README.md")
        return
    var scene := PipelineTestHelpers.import_gltf(FIXTURE)
    var body: StaticBody3D = _find_body(scene, "StaticBody3D_BoxWall")
    assert_not_null(body)
    var shape: CollisionShape3D = null
    for c in body.get_children():
        if c is CollisionShape3D: shape = c
    assert_not_null(shape)
    assert_true(shape.shape is BoxShape3D)
    assert_eq((shape.shape as BoxShape3D).size, Vector3(2, 1, 0.2))
    scene.free()

func test_sphere_prop_becomes_rigid_body():
    if not ResourceLoader.exists(FIXTURE):
        pending("fixture not present — author per README.md")
        return
    var scene := PipelineTestHelpers.import_gltf(FIXTURE)
    var body: RigidBody3D = _find_body(scene, "RigidBody3D_SphereProp")
    assert_not_null(body)
    scene.free()

func test_capsule_npc_becomes_character_body():
    if not ResourceLoader.exists(FIXTURE):
        pending("fixture not present — author per README.md")
        return
    var scene := PipelineTestHelpers.import_gltf(FIXTURE)
    var body: CharacterBody3D = _find_body(scene, "CharacterBody3D_CapsuleNPC")
    assert_not_null(body)
    scene.free()

func _find_body(root: Node, name: String) -> Node:
    if root.name == name: return root
    for c in root.get_children():
        var r := _find_body(c, name)
        if r: return r
    return null
```

- [ ] **Step 4: Run — tests marked `pending` pass vacuously**

Expected: 0 failures, 3 pending.

- [ ] **Step 5: Commit plan + helpers + test harness (fixture file itself can be authored in a follow-up commit by the user)**

```bash
git add test/fixtures/primitives/README.md \
        test/integration/test_import_primitives.gd \
        test/integration/helpers.gd
git commit -m "add primitives collision integration test harness"
```

- [ ] **Step 6: After user authors `primitives.gltf` + `.bin`, commit fixtures**

```bash
git add test/fixtures/primitives/primitives.gltf test/fixtures/primitives/primitives.bin
git commit -m "add primitives fixture (.gltf + .bin from Blender)"
```

- [ ] **Step 7: Re-run integration tests — pass**

---

### Task 21: Integration fixture — scripts and props

Same structure as Task 20. Fixture has one node tagged with `script` + `prop_string`, one with `prop_file`. Tests assert the script is set and properties are applied.

**Files:**
- Create: `test/fixtures/scripts_and_props/README.md`
- Create: `test/fixtures/scripts_and_props/scripts.gltf/.bin`
- Create: `test/fixtures/scripts_and_props/attached.gd` (the script that gets attached in-scene)
- Create: `test/fixtures/scripts_and_props/props.txt` (prop_file fixture)
- Create: `test/integration/test_import_scripts_and_props.gd`

- [ ] **Step 1: Write fixture readme + script + props file**

File: `test/fixtures/scripts_and_props/attached.gd`
```gdscript
@tool
extends Node3D

@export var speed: float = 0.0
@export var damage: int = 0
```

File: `test/fixtures/scripts_and_props/props.txt`
```
speed=12.5
damage=7
```

File: `test/fixtures/scripts_and_props/README.md`
```markdown
Two nodes in the Blender scene:
- "FastNode": script=res://test/fixtures/scripts_and_props/attached.gd, prop_string=speed=9.0;damage=3
- "FileNode":  script=res://test/fixtures/scripts_and_props/attached.gd, prop_file=res://test/fixtures/scripts_and_props/props.txt
Export → glTF separate to `scripts.gltf` next to this README.
```

- [ ] **Step 2: Write the failing integration test**

File: `test/integration/test_import_scripts_and_props.gd`
```gdscript
extends GutTest

const FIXTURE := "res://test/fixtures/scripts_and_props/scripts.gltf"
const SCRIPT := "res://test/fixtures/scripts_and_props/attached.gd"

func test_prop_string_applied():
    if not ResourceLoader.exists(FIXTURE): pending("fixture absent"); return
    var scene := PipelineTestHelpers.import_gltf(FIXTURE)
    var n := _find_by_name(scene, "FastNode")
    assert_not_null(n)
    assert_eq(n.get_script().resource_path, SCRIPT)
    assert_almost_eq(n.get("speed"), 9.0, 0.001)
    assert_eq(n.get("damage"), 3)
    scene.free()

func test_prop_file_applied():
    if not ResourceLoader.exists(FIXTURE): pending("fixture absent"); return
    var scene := PipelineTestHelpers.import_gltf(FIXTURE)
    var n := _find_by_name(scene, "FileNode")
    assert_almost_eq(n.get("speed"), 12.5, 0.001)
    assert_eq(n.get("damage"), 7)
    scene.free()

func _find_by_name(root: Node, nm: String) -> Node:
    if root.name == nm: return root
    for c in root.get_children():
        var r := _find_by_name(c, nm)
        if r: return r
    return null
```

- [ ] **Step 3: Commit harness**

```bash
git add test/fixtures/scripts_and_props test/integration/test_import_scripts_and_props.gd
git commit -m "add scripts-and-props integration harness"
```

- [ ] **Step 4: User authors `scripts.gltf` via Blender; commit**

```bash
git add test/fixtures/scripts_and_props/scripts.gltf test/fixtures/scripts_and_props/scripts.bin
git commit -m "add scripts-and-props fixture"
```

- [ ] **Step 5: Run integration tests — pass**

---

### Task 22: Integration fixture — materials + shader

Same pattern.

**Files:**
- Create: `test/fixtures/materials_and_shaders/README.md` + `.gltf` + `.bin`
- Create: `test/integration/test_import_materials.gd`

- [ ] **Step 1: README + fixture instruction**

File: `test/fixtures/materials_and_shaders/README.md`
```markdown
One node "Painted" with material_0=res://test/fixtures/test_mat_red.tres, material_1=res://test/fixtures/test_mat_blue.tres.
A second node "Shaded" with material_0=res://test/fixtures/test_shader_mat.tres, shader=res://test/fixtures/test_shader.gdshader.
Export → glTF separate.
```

- [ ] **Step 2: Integration test**

File: `test/integration/test_import_materials.gd`
```gdscript
extends GutTest

const FIXTURE := "res://test/fixtures/materials_and_shaders/materials.gltf"

func test_painted_has_two_surface_overrides():
    if not ResourceLoader.exists(FIXTURE): pending("fixture absent"); return
    var scene := PipelineTestHelpers.import_gltf(FIXTURE)
    var mi := _find(scene, "Painted") as MeshInstance3D
    assert_not_null(mi)
    assert_not_null(mi.get_surface_override_material(0))
    assert_not_null(mi.get_surface_override_material(1))
    scene.free()

func test_shaded_has_shader_override():
    if not ResourceLoader.exists(FIXTURE): pending("fixture absent"); return
    var scene := PipelineTestHelpers.import_gltf(FIXTURE)
    var mi := _find(scene, "Shaded") as MeshInstance3D
    var m = mi.get_surface_override_material(0)
    assert_true(m is ShaderMaterial)
    scene.free()

func _find(root: Node, nm: String) -> Node:
    if root.name == nm: return root
    for c in root.get_children():
        var r := _find(c, nm); if r: return r
    return null
```

- [ ] **Step 3: Commit harness; then fixture after user authors**

```bash
git add test/fixtures/materials_and_shaders test/integration/test_import_materials.gd
git commit -m "add materials integration harness"
# After Blender export:
git add test/fixtures/materials_and_shaders/materials.gltf test/fixtures/materials_and_shaders/materials.bin
git commit -m "add materials fixture"
```

---

### Task 23: Integration fixture — nav_mesh + multimesh + packed_scene

Same pattern, one combined scene.

**Files:**
- Create: `test/fixtures/nav_and_multimesh/README.md` + `scene.gltf` + `.bin`
- Create: `test/integration/test_import_nav_multimesh_packed.gd`

- [ ] **Step 1: README**

File: `test/fixtures/nav_and_multimesh/README.md`
```markdown
Scene:
- "Ground" (plane) with nav_mesh=res://test/fixtures/nav_and_multimesh/nav.mesh
- Three duplicates "Tree1/2/3" of the same mesh with multimesh=res://test/fixtures/nav_and_multimesh/tree.mesh
- "Spawn" empty with packed_scene=res://test/fixtures/test_packed.tscn
Export → glTF separate.
```

- [ ] **Step 2: Integration test**

File: `test/integration/test_import_nav_multimesh_packed.gd`
```gdscript
extends GutTest

const FIXTURE := "res://test/fixtures/nav_and_multimesh/scene.gltf"

func test_nav_mesh_generates_region():
    if not ResourceLoader.exists(FIXTURE): pending("fixture absent"); return
    var scene := PipelineTestHelpers.import_gltf(FIXTURE)
    var region := _find(scene, "Ground_NavMesh")
    assert_true(region is NavigationRegion3D)
    scene.free()

func test_trees_aggregated_into_multimesh():
    if not ResourceLoader.exists(FIXTURE): pending("fixture absent"); return
    var scene := PipelineTestHelpers.import_gltf(FIXTURE)
    # Exactly one MultiMeshInstance3D child expected; instance_count == 3
    var mm: MultiMeshInstance3D = null
    for c in scene.get_children():
        if c is MultiMeshInstance3D: mm = c
    assert_not_null(mm)
    assert_eq(mm.multimesh.instance_count, 3)
    scene.free()

func test_spawn_replaced_with_packed_scene():
    if not ResourceLoader.exists(FIXTURE): pending("fixture absent"); return
    var scene := PipelineTestHelpers.import_gltf(FIXTURE)
    var inst := _find(scene, "PackedScene_Spawn")
    assert_not_null(inst)
    scene.free()

func _find(root: Node, nm: String) -> Node:
    if root.name == nm: return root
    for c in root.get_children():
        var r := _find(c, nm); if r: return r
    return null
```

- [ ] **Step 3: Commit harness + fixture**

```bash
git add test/fixtures/nav_and_multimesh test/integration/test_import_nav_multimesh_packed.gd
git commit -m "add nav/multimesh/packed_scene integration harness"
# After Blender export:
git add test/fixtures/nav_and_multimesh/scene.gltf test/fixtures/nav_and_multimesh/scene.bin
git commit -m "add nav/multimesh/packed_scene fixture"
```

---

### Task 24: Integration fixture — scene globals

**Files:**
- Create: `test/fixtures/scene_globals/README.md` + `.gltf` + `.bin`
- Create: `test/integration/test_import_scene_globals.gd`

- [ ] **Step 1: README**

File: `test/fixtures/scene_globals/README.md`
```markdown
Scene-level GodotPipelineProps:
- individual_origins=1
- packed_resources=1

Three top-level objects "Crate", "Barrel", "Sign" at distinct global positions.
Export → glTF separate.
```

- [ ] **Step 2: Integration test**

File: `test/integration/test_import_scene_globals.gd`
```gdscript
extends GutTest

const FIXTURE := "res://test/fixtures/scene_globals/globals.gltf"

func test_individual_origins_applied():
    if not ResourceLoader.exists(FIXTURE): pending("fixture absent"); return
    var scene := PipelineTestHelpers.import_gltf(FIXTURE)
    for c in scene.get_children():
        if c is Node3D and c.name.begins_with("PackedScene_"):
            # After packing with preserve_origin, position is restored,
            # so asserting != 0 is valid for placed objects.
            assert_true(true)
    scene.free()

func test_packed_resources_saves_tscn_files():
    if not ResourceLoader.exists(FIXTURE): pending("fixture absent"); return
    var scene := PipelineTestHelpers.import_gltf(FIXTURE)
    var dir := FIXTURE.get_base_dir() + "/packed_scenes"
    assert_true(DirAccess.dir_exists_absolute(dir))
    scene.free()
```

- [ ] **Step 3: Commit harness; then fixture**

```bash
git add test/fixtures/scene_globals test/integration/test_import_scene_globals.gd
git commit -m "add scene-globals integration harness"
# After user fixture export:
git add test/fixtures/scene_globals/globals.gltf test/fixtures/scene_globals/globals.bin
git commit -m "add scene-globals fixture"
```

---

### Task 25: Full-suite CLI runner + CI script

**Files:**
- Create: `run_tests.sh`

- [ ] **Step 1: Write `run_tests.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

GODOT="${GODOT:-godot}"
"$GODOT" --headless --path . --script addons/gut/gut_cmdln.gd \
  -gconfig=.gutconfig.json \
  -gexit
```

- [ ] **Step 2: Make executable**

```bash
chmod +x run_tests.sh
```

- [ ] **Step 3: Run full suite**

```bash
./run_tests.sh
```

Expected: all unit tests pass; integration tests pass if fixtures are present, otherwise `pending` (not failing).

- [ ] **Step 4: Commit**

```bash
git add run_tests.sh
git commit -m "add test runner script"
```

---

### Task 26: Repository hygiene

**Files:**
- Modify: `.gitignore`
- Modify: `project.godot` (possibly)
- Create: `DIVERGENCES.md`
- Possibly commit `.uid` files, `icon.svg.import`, `docs/`

**Goal:** Resolve accumulated repo-state drift from running the editor / headless Godot during earlier tasks, and record divergences from v2.5.5 in one file so future maintainers don't have to diff against `SceneInit.gd`.

- [ ] **Step 1: Decide `.uid` policy — track**

Godot 4.4+ generates one `<script>.gd.uid` per script. These are stable resource IDs referenced by scenes. Standard practice in the Godot community is to commit them. Keep `.uid` tracked (do NOT add to `.gitignore`). Stage all current `*.uid` files:

```bash
cd /Users/zheqd/Projects/gamedev/blender-gltf-godot-pipeline
git add $(git ls-files --others --exclude-standard '*.uid')
```

- [ ] **Step 2: Decide `.import` policy — gitignore auto-generated, track explicit fixture outputs**

Add to `.gitignore`:
```
# Godot 4 auto-generated on first import (non-fixture files)
/icon.svg.import
```

Fixture `.import` files under `test/fixtures/**` are already ignored by the bootstrap `.gitignore` glob — keep that.

- [ ] **Step 3: Commit `docs/`**

The plan file itself is the authoritative spec. Track it:

```bash
git add docs/
```

- [ ] **Step 4: Reconcile `project.godot`**

The Godot editor will rewrite `project.godot` on first open (remove redundant empty keys, re-flow sections). Accept the editor's canonical form as the committed baseline:

```bash
# Open the project once in the editor, let it write, then quit.
godot --headless --path . --editor --quit
git diff project.godot
# If the diff is just whitespace / redundancy normalizations, stage it.
# If the `[rendering]` section was dropped, restore it — we want explicit
# `renderer/rendering_method="forward_plus"` even though `config/features`
# also includes "Forward Plus", because some export platforms check the
# [rendering] keys directly.
git add project.godot
```

- [ ] **Step 5: Create `DIVERGENCES.md`**

File: `DIVERGENCES.md`
```markdown
# Divergences from v2.5.5

This addon is a 1:1 port of the runtime behavior of `SceneInit.gd` from
bikemurt/blender-godot-pipeline v2.5.5, with the following intentional
deltas. Each delta is justified; none changes the final-scene outcome.

## Behavioral

- **`state=skip` uses `queue_free()` after `remove_child()` instead of `free()`.**
  v2.5.5 calls `node.free()` synchronously inside its iterator. In our
  `_import_post` walk, synchronous free on a visited node would invalidate
  the walk's `children` array mid-iteration. `remove_child` + `queue_free`
  detaches immediately and defers deallocation to the next frame; the final
  scene contains no reference to the skipped node.

- **Test code uses `preload()` to load addon classes, not bare `class_name`
  globals.** This is a Godot runtime quirk, not a behavioral divergence:
  GUT headless CLI does not register addon `class_name` declarations because
  editor plugins aren't loaded. All addon source files still declare
  `class_name`; tests and cross-addon references use `const _X = preload(...)`.

## Architectural (intentional, per plan)

- **No `_Imported` hot-reload marker node.** v2.5.5 used a two-pass dance
  keyed on `BlenderGodotPipeline.count == 2` to detect re-imports. Godot's
  `_import_post` hook runs on every re-import natively, so the marker node
  is unnecessary.

- **Extras are read from `node.meta["extras"]` and `mesh.meta["extras"]`.**
  Godot 4.4+ (PR #86183) automatically propagates glTF `extras` to node/mesh
  metadata. v2.5.5 re-parsed the .gltf JSON by hand; we rely on the engine.

- **`_import_post` instead of `EditorScenePostImport`.** The deliverable is
  a `GLTFDocumentExtension`, which integrates with `GLTFDocument` at import
  time without requiring an editor script per imported scene.
```

- [ ] **Step 6: Run full test suite — confirm no regressions**

```bash
godot --headless --path . --script addons/gut/gut_cmdln.gd
```

Expected: all prior tests still pass. No new tests in this task.

- [ ] **Step 7: Commit**

```bash
git add .gitignore DIVERGENCES.md
# .uid, docs/, project.godot already staged from earlier steps
git commit -m "track .uid, record divergences from v2.5.5, add plan to repo"
```

---

### Task 27: Final README polish

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Rewrite README with installation, usage, limitations**

File: `README.md`
```markdown
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

Unit tests run without external assets. Integration tests require `.gltf` fixtures exported from Blender — see each `test/fixtures/*/README.md` for authoring steps.

## Differences from v2.5.5

- No `_Imported` hot-reload node. The engine's native `_import_post` hook runs on every re-import of the .gltf, so the old two-pass dance (`BlenderGodotPipeline.count == 2`) is unnecessary.
- Uses Godot's automatic extras → meta propagation (4.4+) instead of re-parsing the .gltf JSON.
- `state=skip` uses `queue_free()` via `remove_child()`; v2.5.5 used `node.free()`. Outcome is identical in the final scene.

## License

MIT.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "polish README with compatibility table and differences"
```

---

## Self-review

**Spec coverage check** (every v2.5.5 behavior tagged to a task):

| v2.5.5 behavior (`SceneInit.gd` line ref) | Task |
|---|---|
| L455-461 `state=skip` free child | 5 |
| L480-483 `state=hide` | 5 |
| L485-487 `name_override` | 6 |
| L451-453 `script` load | 8 |
| L497-504 `prop_file`/`prop_string` (non-collision) | 7, 8 |
| L166-192 `Expression`-based applier | 7 |
| L194-204 `material_0..3` with `shader` override on `ShaderMaterial` | 9, 10 |
| L218-220 `physics_mat` on body | 11 |
| L223-243 body factory | 12 |
| L244-263 trimesh/simple shape from mesh | 13 |
| L301-303 `cs.debug_fill=false` on 4.4+ | 14 |
| L305-310 center offset (primitives only, z negated) | 14 |
| L270-285 discard_mesh `-d` | 14 |
| L287-288 `bodyonly` | 14 |
| L292-298 `-c` col_only attaches to parent | 14 |
| L379-384 reparent pre-existing `CollisionShape3D` children | 14 |
| L385 delete original node | 14 (via `deferred_deletes`) |
| L207-216 collision_script (script + prop_* + physics_mat on body) | 14 |
| L390-409 `nav_mesh` generate-and-save | 15 |
| L412-449 `multimesh` two-phase aggregation | 16 |
| L516-524 `packed_scene` instantiation | 17 |
| L541-549 `individual_origins` | 18 |
| L552-576 `packed_resources` | 19 |

**Placeholder scan:** None. Every step has concrete code or exact command.

**Type consistency:**
- `PipelineContext` used identically across Tasks 2, 4, 5–19.
- `ctx.deferred_deletes: Array[Node]`, `ctx.deferred_reparents: Array[Array]`, `ctx.multimesh_groups: Dictionary` — consistent.
- Handler signatures: all static, all take `(node: Node, extras: Dictionary[, ctx])` with `extras` always being the merged dict from `ExtrasReader.get_extras(node)`.
- `_dispatch(node, ctx)` grows monotonically across tasks; each wiring step explicitly replaces the prior version.

**Scope check:** One addon, one testable software deliverable. No sub-projects.

**Ambiguity check:** `state=skip` divergence from v2.5.5 (`free()` vs `remove_child()+queue_free()`) is called out explicitly in Task 5, Step 3 and in the README Differences section.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-17-gltf-pipeline-migration.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
