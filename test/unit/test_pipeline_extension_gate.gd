extends GutTest

## The pipeline extension must leave glTF files without pipeline data untouched,
## so skinned characters and props import exactly as without the addon.

# Headless GUT cannot resolve class_name globals — preload explicitly.
const PipelineExtensionScript: GDScript = preload("res://addons/gltf_pipeline/pipeline_extension.gd")


func _make_root() -> Node3D:
	var root := Node3D.new()
	var mesh_node := ImporterMeshInstance3D.new()
	mesh_node.name = "Mesh"
	root.add_child(mesh_node)
	mesh_node.owner = root
	add_child_autofree(root)
	return root


func _make_state(json: Dictionary) -> GLTFState:
	var state := GLTFState.new()
	state.json = json
	return state


func _run(json: Dictionary) -> Node:
	var root := _make_root()
	var ext: GLTFDocumentExtension = PipelineExtensionScript.new()
	assert_eq(ext._import_post(_make_state(json), root), OK)
	return root.get_node("Mesh")


func test_no_extras_leaves_tree_untouched() -> void:
	var mesh_node := _run({"scenes": [{"nodes": [0]}], "nodes": [{"name": "Mesh", "mesh": 0}], "meshes": [{}]})
	assert_true(mesh_node is ImporterMeshInstance3D, "no pipeline data → mesh must not be materialized")


func test_empty_json_leaves_tree_untouched() -> void:
	var mesh_node := _run({})
	assert_true(mesh_node is ImporterMeshInstance3D)


func test_empty_extras_dicts_leave_tree_untouched() -> void:
	var mesh_node := _run({"scenes": [{"extras": {}}], "nodes": [{"name": "Mesh", "extras": {}}], "meshes": [{"extras": {}}]})
	assert_true(mesh_node is ImporterMeshInstance3D, "empty extras dicts are not pipeline data")


func test_node_extras_run_pipeline() -> void:
	var mesh_node := _run({"nodes": [{"name": "Mesh", "extras": {"name_override": "Mesh"}}]})
	assert_true(mesh_node is MeshInstance3D, "node extras → pipeline runs")


func test_mesh_extras_run_pipeline() -> void:
	var mesh_node := _run({"nodes": [{"name": "Mesh", "mesh": 0}], "meshes": [{"extras": {"name_override": "Mesh"}}]})
	assert_true(mesh_node is MeshInstance3D, "mesh extras → pipeline runs")


func test_scene_props_run_pipeline() -> void:
	var mesh_node := _run({"scenes": [{"extras": {"GodotPipelineProps": {"individual_origins": 0}}}]})
	assert_true(mesh_node is MeshInstance3D, "GodotPipelineProps → pipeline runs")


func test_shape_key_target_names_leave_tree_untouched() -> void:
	# Blender writes meshes[i].extras.targetNames for meshes with shape keys.
	var mesh_node := _run({"nodes": [{"name": "Mesh", "mesh": 0}], "meshes": [{"extras": {"targetNames": ["Smile"]}}]})
	assert_true(mesh_node is ImporterMeshInstance3D, "targetNames is not a pipeline key → mesh must not be materialized")


func test_non_trigger_node_extras_leave_tree_untouched() -> void:
	var mesh_node := _run({"nodes": [{"name": "Mesh", "extras": {"rig_id": "abc"}}]})
	assert_true(mesh_node is ImporterMeshInstance3D, "unknown extras key is not pipeline data")


func test_collision_extras_run_pipeline() -> void:
	# Only materialization is asserted: the node has no "extras" meta here, so
	# CollisionHandler never runs in this unit test.
	var mesh_node := _run({"nodes": [{"name": "Mesh", "extras": {"collision": "box"}}]})
	assert_true(mesh_node is MeshInstance3D, "collision extras → pipeline runs")
