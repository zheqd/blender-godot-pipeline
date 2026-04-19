extends GutTest

const NameHandler = preload("res://addons/gltf_pipeline/handlers/name_handler.gd")

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
