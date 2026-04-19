# scripts_and_props fixture

## Goal

`scripts.gltf` contains two simple Node3D objects whose glTF `extras` carry
Godot-Pipeline `script`, `prop_string`, and `prop_file` keys. When imported,
the plugin should attach `attached.gd` to each, apply the properties, and
the integration tests assert the resulting `test_value` / `test_factor`
fields on the live node.

## Authoring steps (Blender 4.2+ with `godot_pipeline_v255_blender42+.py`)

Start from an empty scene.

### Object `FastNode`

1. Add → Mesh → Plane. Rename it `FastNode` in the Outliner.
2. In the sidebar (N-panel) → **Godot Pipeline** tab:
   - **Path Setter** → Path Type `Script` → Path `res://test/fixtures/scripts_and_props/attached.gd` → click **Set Path**.
   - **String Setter** → String Type `Property String` → String `speed=9.0;damage=3` → click **Set String**.
3. Click **Display Addon Data** on `FastNode`. You should see:
   ```
   script=res://test/fixtures/scripts_and_props/attached.gd
   prop_string=speed=9.0;damage=3
   ```

### Object `FileNode`

1. Add → Mesh → Plane. Rename `FileNode`.
2. **Path Setter** → Path Type `Script` → same script path → Set Path.
3. **Path Setter** → Path Type `Parameter File` → `res://test/fixtures/scripts_and_props/props.txt` → Set Path.
4. Display Addon Data should show:
   ```
   script=res://test/fixtures/scripts_and_props/attached.gd
   prop_file=res://test/fixtures/scripts_and_props/props.txt
   ```

### Export

In the **Export** section of the Godot Pipeline panel, set the save path to
`.../blender-gltf-godot-pipeline/test/fixtures/scripts_and_props/scripts.gltf`
and click **Export for Godot**. Commit `scripts.gltf` + `scripts.bin`.
