extends GutTest

const NavMeshHandler: GDScript = preload("res://addons/gltf_pipeline/handlers/navmesh_handler.gd")
const PipelineContext = preload("res://addons/gltf_pipeline/pipeline_context.gd")

var tmp_dir := "user://navmesh_test"
var mesh_save := tmp_dir + "/nav.mesh"

func before_each():
	DirAccess.make_dir_absolute(tmp_dir)

func after_each():
	var d := DirAccess.open(tmp_dir)
	if d:
		for f in d.get_files(): d.remove(f)

func test_nav_mesh_replaces_node_with_navigation_region():
	var ctx := PipelineContext.new()
	var parent := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = BoxMesh.new()
	mi.position = Vector3(1, 0, 2)
	parent.add_child(mi)
	NavMeshHandler.apply(mi, {"nav_mesh": mesh_save}, ctx)
	var region: NavigationRegion3D = null
	for c in parent.get_children():
		if c is NavigationRegion3D: region = c
	assert_not_null(region)
	assert_eq(region.name, "Ground_NavMesh")
	assert_not_null(region.navigation_mesh)
	assert_true(mi in ctx.deferred_deletes)
	parent.free()

func test_prop_file_applied_to_region():
	var tmp_props := "user://navmesh_props.txt"
	var f := FileAccess.open(tmp_props, FileAccess.WRITE)
	f.store_line("enabled=false")
	f.close()

	var ctx := PipelineContext.new()
	var parent := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = BoxMesh.new()
	parent.add_child(mi)
	NavMeshHandler.apply(mi, {"nav_mesh": mesh_save, "prop_file": tmp_props}, ctx)
	var region: NavigationRegion3D = null
	for c in parent.get_children():
		if c is NavigationRegion3D: region = c
	assert_false(region.enabled)
	parent.free()
