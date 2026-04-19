extends GutTest

const ScriptHandler = preload("res://addons/gltf_pipeline/handlers/script_handler.gd")
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
	assert_engine_error_count(2)
	n.free()
