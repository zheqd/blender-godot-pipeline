extends GutTest

const PipelineTestHelpers = preload("res://test/integration/helpers.gd")

const FIXTURE := "res://test/fixtures/materials_and_shaders/materials.gltf"

func _fixture_present() -> bool:
	return FileAccess.file_exists(FIXTURE)

func test_painted_has_two_surface_overrides():
	if not _fixture_present(): pending("fixture absent"); return
	var scene := PipelineTestHelpers.import_gltf(FIXTURE)
	var mi := _find(scene, "Painted") as MeshInstance3D
	assert_not_null(mi)
	assert_not_null(mi.get_surface_override_material(0))
	assert_not_null(mi.get_surface_override_material(1))
	scene.free()

func test_shaded_has_shader_override():
	if not _fixture_present(): pending("fixture absent"); return
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
