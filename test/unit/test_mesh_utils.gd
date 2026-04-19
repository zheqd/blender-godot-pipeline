extends GutTest


func _make_importer_mesh() -> ImporterMesh:
	var im := ImporterMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)
	])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, null, "surf0")
	return im

func test_is_mesh_instance_accepts_both_types():
	var mi := MeshInstance3D.new()
	var ii := ImporterMeshInstance3D.new()
	var n := Node3D.new()
	assert_true(MeshUtils.is_mesh_instance(mi))
	assert_true(MeshUtils.is_mesh_instance(ii))
	assert_false(MeshUtils.is_mesh_instance(n))
	mi.free()
	ii.free()
	n.free()

func test_get_mesh_from_mesh_instance():
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	var m := MeshUtils.get_mesh(mi)
	assert_true(m is Mesh)
	mi.free()

func test_get_mesh_from_importer_mesh_instance():
	var ii := ImporterMeshInstance3D.new()
	ii.mesh = _make_importer_mesh()
	var m := MeshUtils.get_mesh(ii)
	assert_not_null(m, "ImporterMesh.get_mesh() should return an ArrayMesh")
	assert_true(m is ArrayMesh)
	ii.free()

func test_get_mesh_returns_null_for_non_mesh_node():
	var n := Node3D.new()
	assert_null(MeshUtils.get_mesh(n))
	n.free()

func test_set_surface_material_on_importer_mesh_instance():
	var ii := ImporterMeshInstance3D.new()
	ii.mesh = _make_importer_mesh()
	var mat := StandardMaterial3D.new()
	MeshUtils.set_surface_material(ii, 0, mat)
	assert_eq(ii.mesh.get_surface_material(0), mat)
	ii.free()

func test_materialize_all_replaces_importer_with_mesh_instance():
	var root := Node3D.new()
	var imi := ImporterMeshInstance3D.new()
	imi.name = "Importer"
	imi.transform = Transform3D().translated(Vector3(1, 2, 3))
	imi.set_meta("extras", {"collision": "trimesh"})
	var im := _make_importer_mesh()
	var mat := StandardMaterial3D.new()
	im.set_surface_material(0, mat)
	imi.mesh = im
	var kid := Node3D.new()
	kid.name = "Kid"
	imi.add_child(kid)
	root.add_child(imi)

	MeshUtils.materialize_all(root)

	assert_eq(root.get_child_count(), 1, "root still has one child")
	var replaced := root.get_child(0)
	assert_true(replaced is MeshInstance3D, "replaced is MeshInstance3D")
	assert_false(replaced is ImporterMeshInstance3D, "old node is gone")
	assert_eq(str(replaced.name), "Importer", "name preserved")
	assert_eq(replaced.transform, Transform3D().translated(Vector3(1, 2, 3)),
		"transform preserved")
	assert_eq(replaced.get_meta("extras"), {"collision": "trimesh"},
		"extras meta preserved")
	assert_not_null((replaced as MeshInstance3D).mesh, "mesh set")
	assert_true((replaced as MeshInstance3D).mesh is ArrayMesh,
		"ImporterMesh.get_mesh() returned ArrayMesh")
	assert_eq((replaced as MeshInstance3D).get_surface_override_material(0), mat,
		"ImporterMesh surface material copied to override slot")
	assert_eq(replaced.get_child_count(), 1, "children reparented")
	assert_eq(str(replaced.get_child(0).name), "Kid", "child order preserved")
	root.free()

func test_materialize_all_leaves_mesh_instance3d_alone():
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.name = "Plain"
	mi.mesh = BoxMesh.new()
	root.add_child(mi)
	MeshUtils.materialize_all(root)
	assert_eq(root.get_child_count(), 1)
	assert_same(root.get_child(0), mi, "plain MeshInstance3D not replaced")
	root.free()

func test_materialize_all_noop_on_tree_without_importer_instances():
	var root := Node3D.new()
	var n1 := Node3D.new()
	var n2 := Node3D.new()
	root.add_child(n1)
	n1.add_child(n2)
	MeshUtils.materialize_all(root)
	assert_eq(root.get_child_count(), 1)
	assert_same(root.get_child(0), n1)
	assert_same(n1.get_child(0), n2)
	root.free()
