extends GutTest

const PipelineTestHelpers = preload("res://test/integration/helpers.gd")

const FIXTURE := "res://test/fixtures/nav_and_multimesh/scene.gltf"

func _fixture_present() -> bool:
	return FileAccess.file_exists(FIXTURE)

func test_nav_mesh_generates_region():
	if not _fixture_present(): pending("fixture absent"); return
	var scene := PipelineTestHelpers.import_gltf(FIXTURE)
	var region := _find(scene, "Ground_NavMesh")
	assert_true(region is NavigationRegion3D)
	scene.free()

func test_trees_aggregated_into_multimesh():
	if not _fixture_present(): pending("fixture absent"); return
	var scene := PipelineTestHelpers.import_gltf(FIXTURE)
	var mm: MultiMeshInstance3D = null
	for c in scene.get_children():
		if c is MultiMeshInstance3D: mm = c
	assert_not_null(mm)
	assert_eq(mm.multimesh.instance_count, 3)
	scene.free()

func test_spawn_replaced_with_packed_scene():
	if not _fixture_present(): pending("fixture absent"); return
	var scene := PipelineTestHelpers.import_gltf(FIXTURE)
	var inst := _find(scene, "PackedScene_Spawn")
	assert_not_null(inst)
	scene.free()

func _find(root: Node, nm: String) -> Node:
	if root.name == nm: return root
	for c in root.get_children():
		var r := _find(c, nm); if r: return r
	return null
