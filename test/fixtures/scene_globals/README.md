# scene_globals fixture

## Goal

`globals.gltf` has three top-level objects at distinct positions with
scene-level `GodotPipelineProps = { individual_origins: 1, packed_resources: 1 }`.
On import, the plugin should pack each child to
`<gltf_dir>/packed_scenes/<Name>.tscn`, replace the originals with
instances, and preserve their original positions.

## Known addon limitation

The v2.5.5 `godot_pipeline_v255_blender42+.py` addon has UI checkboxes
for "Individual Origins" and "Individual Packed Resources" but does NOT
currently write them to the exported glTF scene extras. We work around
this by patching the exported .gltf JSON post-export.

## Authoring steps

### Three objects

1. Add → Mesh → Cube, rename `Crate`, position `(0, 0, 0)`.
2. Add → Mesh → Cube, rename `Barrel`, position `(3, 0, 0)`, scale 0.6.
3. Add → Mesh → Cube, rename `Sign`,   position `(-3, 0, 0)`, rotate 45° on Y.

No addon props are needed on the objects themselves.

### Export

Save path → `test/fixtures/scene_globals/globals.gltf`. Export for Godot.
**Do NOT** enable the Individual Origins / Individual Packed Resources
checkboxes — they don't propagate. We patch in the next step instead.

### Post-export JSON patch

Run from the repo root:

```bash
python3 - <<'EOF'
import json
p = "test/fixtures/scene_globals/globals.gltf"
with open(p) as f:
    d = json.load(f)
d.setdefault("scenes", [{}])[0].setdefault("extras", {})["GodotPipelineProps"] = {
    "individual_origins": 1,
    "packed_resources": 1,
}
with open(p, "w") as f:
    json.dump(d, f, indent=2)
EOF
```

Verify the scene extras are present:

```bash
python3 -c 'import json; d=json.load(open("test/fixtures/scene_globals/globals.gltf")); print(d["scenes"][0]["extras"])'
```

Expected output:
```
{'GodotPipelineProps': {'individual_origins': 1, 'packed_resources': 1}}
```

Commit `globals.gltf`, `globals.bin`.
