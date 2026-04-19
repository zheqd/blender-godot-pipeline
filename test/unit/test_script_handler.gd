extends GutTest

const ScriptHandler = preload("res://addons/gltf_pipeline/handlers/script_handler.gd")
const MeshUtils = preload("res://addons/gltf_pipeline/mesh_utils.gd")
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

# Regression guard for the ImporterMeshInstance3D → MeshInstance3D conversion
# bug: set_script called directly on ImporterMeshInstance3D is silently lost
# when the engine converts the node. We materialize up front, so the script
# lands on a real MeshInstance3D that survives.
func test_set_script_survives_after_materialize():
	var root := Node3D.new()
	var imi := ImporterMeshInstance3D.new()
	imi.name = "Target"
	var im := ImporterMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)
	])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
	imi.mesh = im
	root.add_child(imi)

	MeshUtils.materialize_all(root)
	var materialized := root.get_child(0)
	assert_true(materialized is MeshInstance3D, "precondition: materialized")

	ScriptHandler.apply(materialized, {"script": SCRIPT_PATH})
	assert_not_null(materialized.get_script(),
		"script must stick on the materialized MeshInstance3D")
	assert_eq(materialized.get_script().resource_path, SCRIPT_PATH)
	root.free()
