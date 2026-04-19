extends GutTest

const SceneGlobalsHandler = preload("res://addons/gltf_pipeline/handlers/scene_globals_handler.gd")

func test_individual_origins_resets_top_level_positions():
	var root := Node3D.new()
	get_tree().root.add_child(root)
	var a := Node3D.new()
	a.name = "A"
	root.add_child(a)
	a.global_position = Vector3(10, 0, 0)
	var b := Node3D.new()
	b.name = "B"
	root.add_child(b)
	b.global_position = Vector3(-5, 3, 2)

	SceneGlobalsHandler.apply_individual_origins(root)

	assert_eq(a.global_position, Vector3.ZERO)
	assert_eq(b.global_position, Vector3.ZERO)
	root.queue_free()

func test_individual_origins_ignores_non_node3d():
	var root := Node3D.new()
	get_tree().root.add_child(root)
	var label := Label3D.new()
	root.add_child(label)
	SceneGlobalsHandler.apply_individual_origins(root)
	assert_true(true)
	root.queue_free()

const SAVE_DIR := "user://packed_scenes"

func test_packed_resources_packs_each_top_level_child():
	var dir := DirAccess.open("user://")
	if dir and not dir.dir_exists("packed_scenes"):
		dir.make_dir("packed_scenes")
	var root := Node3D.new()
	get_tree().root.add_child(root)
	var c1 := Node3D.new()
	c1.name = "Crate"
	c1.add_child(Node3D.new())
	root.add_child(c1)
	var c2 := Node3D.new()
	c2.name = "Barrel"
	root.add_child(c2)

	SceneGlobalsHandler.apply_packed_resources(root, SAVE_DIR, false)

	assert_true(ResourceLoader.exists(SAVE_DIR + "/Crate.tscn"))
	assert_true(ResourceLoader.exists(SAVE_DIR + "/Barrel.tscn"))
	var names := []
	for c in root.get_children(): names.append(c.name)
	assert_has(names, "PackedScene_Crate")
	assert_has(names, "PackedScene_Barrel")
	root.free()

func test_packed_resources_with_individual_origins_preserves_position():
	var root := Node3D.new()
	get_tree().root.add_child(root)
	var c1 := Node3D.new()
	c1.name = "Placed"
	root.add_child(c1)
	c1.global_position = Vector3(7, 8, 9)
	SceneGlobalsHandler.apply_packed_resources(root, SAVE_DIR, true)
	var reloaded: Node3D = null
	for c in root.get_children():
		if c.name == "PackedScene_Placed": reloaded = c
	assert_not_null(reloaded)
	assert_eq(reloaded.global_position, Vector3(7, 8, 9))
	root.free()
