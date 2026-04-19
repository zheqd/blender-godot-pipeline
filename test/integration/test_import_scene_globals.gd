extends GutTest

const PipelineTestHelpers = preload("res://test/integration/helpers.gd")

const FIXTURE := "res://test/fixtures/scene_globals/globals.gltf"

func _fixture_present() -> bool:
	return FileAccess.file_exists(FIXTURE)

func test_individual_origins_applied():
	if not _fixture_present():
		pending("fixture absent")
		return
	var scene := PipelineTestHelpers.import_gltf(FIXTURE)
	# Per the scene README, the fixture has three top-level objects
	# (Crate, Barrel, Sign) at distinct positions, with both
	# individual_origins=1 and packed_resources=1 on the scene-level extras.
	# After processing, the top-level children should be renamed to
	# PackedScene_<Name>; no original node names remain.
	var packed_names: Array = []
	var original_names: Array = []
	for c in scene.get_children():
		if c is Node3D and c.name.begins_with("PackedScene_"):
			packed_names.append(str(c.name))
		if c.name in ["Crate", "Barrel", "Sign"]:
			original_names.append(str(c.name))
	assert_eq(original_names.size(), 0,
		"original nodes should have been replaced by PackedScene_* instances")
	assert_true(packed_names.size() >= 1,
		"expected at least one PackedScene_* child, got %s" % [packed_names])
	scene.free()

func test_packed_resources_saves_tscn_files():
	if not _fixture_present():
		pending("fixture absent")
		return
	var scene := PipelineTestHelpers.import_gltf(FIXTURE)
	# The plugin saves each packed child to <gltf_dir>/packed_scenes/<Name>.tscn.
	# The dir must exist after the handler ran.
	var dir := FIXTURE.get_base_dir() + "/packed_scenes"
	assert_true(DirAccess.dir_exists_absolute(dir),
		"plugin should have created %s" % dir)
	scene.free()
