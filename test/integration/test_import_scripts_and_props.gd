extends GutTest

const PipelineTestHelpers = preload("res://test/integration/helpers.gd")

const FIXTURE := "res://test/fixtures/scripts_and_props/scripts.gltf"
const SCRIPT := "res://test/fixtures/scripts_and_props/attached.gd"

func _fixture_present() -> bool:
	return FileAccess.file_exists(FIXTURE)

func test_prop_string_applied():
	if not _fixture_present(): pending("fixture absent"); return
	var scene := PipelineTestHelpers.import_gltf(FIXTURE)
	var n := _find_by_name(scene, "FastNode")
	assert_not_null(n)
	assert_eq(n.get_script().resource_path, SCRIPT)
	assert_almost_eq(n.get("speed"), 9.0, 0.001)
	assert_eq(n.get("damage"), 3)
	scene.free()

func test_prop_file_applied():
	if not _fixture_present(): pending("fixture absent"); return
	var scene := PipelineTestHelpers.import_gltf(FIXTURE)
	var n := _find_by_name(scene, "FileNode")
	assert_almost_eq(n.get("speed"), 12.5, 0.001)
	assert_eq(n.get("damage"), 7)
	scene.free()

# Regression guard — packs the imported scene, saves to disk, reloads, and
# re-asserts the script plus its applied properties. Catches two bug
# classes: ImporterMeshInstance3D → MeshInstance3D conversion dropping the
# script, AND owner-assignment failures dropping the node from the .scn bake.
func test_roundtrip_pack_save_preserves_scripts_and_props():
	if not _fixture_present(): pending("fixture absent"); return
	var scene := PipelineTestHelpers.import_gltf(FIXTURE)
	var ps := PackedScene.new()
	var err := ps.pack(scene)
	assert_eq(err, OK, "PackedScene.pack must succeed")
	var tmp_path := "user://scripts_and_props_roundtrip.tscn"
	var save_err := ResourceSaver.save(ps, tmp_path)
	assert_eq(save_err, OK, "ResourceSaver.save must succeed")
	var reloaded := (load(tmp_path) as PackedScene).instantiate()
	var fast := _find_by_name(reloaded, "FastNode")
	assert_not_null(fast, "FastNode missing after pack/save/load")
	assert_not_null(fast.get_script(),
		"FastNode script dropped — ImporterMeshInstance3D conversion or owner assignment regressed")
	assert_eq(fast.get_script().resource_path, SCRIPT)
	assert_almost_eq(fast.get("speed"), 9.0, 0.001,
		"prop_string value lost after round-trip")
	var file_node := _find_by_name(reloaded, "FileNode")
	assert_not_null(file_node)
	assert_not_null(file_node.get_script())
	assert_almost_eq(file_node.get("speed"), 12.5, 0.001,
		"prop_file value lost after round-trip")
	reloaded.free()
	scene.free()

func _find_by_name(root: Node, nm: String) -> Node:
	if root.name == nm: return root
	for c in root.get_children():
		var r := _find_by_name(c, nm)
		if r: return r
	return null
