# materials_and_shaders fixture

## Goal

`materials.gltf` has one mesh with two material override slots and another
mesh with a ShaderMaterial whose shader is additionally overridden at
import time. Exercises `MaterialHandler` and the shader-override branch.

## Pre-existing fixture resources (committed separately)

- `test/fixtures/test_mat_red.tres` (StandardMaterial3D)
- `test/fixtures/test_mat_blue.tres`
- `test/fixtures/test_shader.gdshader`
- `test/fixtures/test_shader_mat.tres` (ShaderMaterial referencing test_shader.gdshader)

## Authoring steps

### Object `Painted` — two surfaces, two materials

1. Add → Mesh → Cube. Rename `Painted`.
2. Enter Edit Mode, select half the faces, in the Materials panel create a
   second material slot, assign the faces to slot 1. This produces TWO
   surfaces on export.
3. Back in Object Mode, in the Godot Pipeline panel:
   - Path Setter → Path Type `Material 0` → `res://test/fixtures/test_mat_red.tres` → Set Path.
   - Path Setter → Path Type `Material 1` → `res://test/fixtures/test_mat_blue.tres` → Set Path.

### Object `Shaded` — one surface with shader override

1. Add → Mesh → Cube. Rename `Shaded`.
2. Path Setter → Path Type `Material 0` → `res://test/fixtures/test_shader_mat.tres`.
3. Path Setter → Path Type `Shader` → `res://test/fixtures/test_shader.gdshader`.

### Export

Save path → `test/fixtures/materials_and_shaders/materials.gltf`. Export for Godot. Commit.
