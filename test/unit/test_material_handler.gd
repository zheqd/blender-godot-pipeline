extends GutTest

const MaterialHandler = preload("res://addons/gltf_pipeline/handlers/material_handler.gd")

const RED := "res://test/fixtures/test_mat_red.tres"
const BLUE := "res://test/fixtures/test_mat_blue.tres"
const SHADER_MAT := "res://test/fixtures/test_shader_mat.tres"
const SHADER_ONLY := "res://test/fixtures/test_shader.gdshader"

func _make_mesh() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var array_mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 3:
		st.add_vertex(Vector3(i, 0, 0))
	st.commit(array_mesh)
	# Add a second surface
	st.clear()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 3:
		st.add_vertex(Vector3(i, 1, 0))
	st.commit(array_mesh)
	mi.mesh = array_mesh
	return mi

func test_sets_material_on_surface_0():
	var mi := _make_mesh()
	MaterialHandler.apply(mi, {"material_0": RED})
	var m = mi.get_surface_override_material(0)
	assert_not_null(m)
	assert_eq(m.resource_path, RED)
	mi.free()

func test_sets_materials_on_multiple_surfaces():
	var mi := _make_mesh()
	MaterialHandler.apply(mi, {"material_0": RED, "material_1": BLUE})
	assert_eq(mi.get_surface_override_material(0).resource_path, RED)
	assert_eq(mi.get_surface_override_material(1).resource_path, BLUE)
	mi.free()

func test_non_mesh_instance_is_noop():
	var n := Node3D.new()
	MaterialHandler.apply(n, {"material_0": RED})
	assert_true(true, "did not crash")
	n.free()

func test_missing_material_keys_is_noop():
	var mi := _make_mesh()
	MaterialHandler.apply(mi, {})
	assert_null(mi.get_surface_override_material(0))
	mi.free()

func test_bad_path_is_warned_not_crash():
	var mi := _make_mesh()
	MaterialHandler.apply(mi, {"material_0": "res://bogus.tres"})
	assert_null(mi.get_surface_override_material(0))
	assert_engine_error_count(2)
	mi.free()

func test_shader_override_on_shader_material():
	var mi := _make_mesh()
	MaterialHandler.apply(mi, {
		"material_0": SHADER_MAT,
		"shader": SHADER_ONLY
	})
	var m: Material = mi.get_surface_override_material(0)
	assert_true(m is ShaderMaterial)
	assert_eq((m as ShaderMaterial).shader.resource_path, SHADER_ONLY)
	mi.free()

func test_shader_key_without_shader_material_is_ignored():
	var mi := _make_mesh()
	# RED is a StandardMaterial3D, not a ShaderMaterial — shader key must be ignored
	MaterialHandler.apply(mi, {"material_0": RED, "shader": SHADER_ONLY})
	var m = mi.get_surface_override_material(0)
	assert_true(m is StandardMaterial3D)
	mi.free()
