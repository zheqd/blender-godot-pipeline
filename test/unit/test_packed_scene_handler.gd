extends GutTest

const PackedSceneHandler = preload("res://addons/gltf_pipeline/handlers/packed_scene_handler.gd")
const PipelineGLTFExtension = preload("res://addons/gltf_pipeline/pipeline_extension.gd")

const PACKED := "res://test/fixtures/test_packed.tscn"

func test_instantiates_and_positions_at_node_transform():
	var ctx := PipelineGLTFExtension.PipelineContext.new()
	var parent := Node3D.new()
	get_tree().root.add_child(parent)
	var marker := Node3D.new()
	marker.name = "Spawn"
	parent.add_child(marker)
	marker.global_position = Vector3(10, 5, -3)

	PackedSceneHandler.apply(marker, {"packed_scene": PACKED}, ctx)

	var inst: Node = null
	for c in parent.get_children():
		if c.name == "PackedScene_Spawn": inst = c
	assert_not_null(inst)
	assert_eq((inst as Node3D).global_position, Vector3(10, 5, -3))
	assert_true(marker in ctx.deferred_deletes)
	parent.queue_free()

# Import pipeline (and GUT's integration helper) run outside a SceneTree.
# global_transform access on detached nodes warns loudly — handler should
# fall back to local transform without complaining.
func test_falls_back_to_local_transform_when_not_in_tree():
	var ctx := PipelineGLTFExtension.PipelineContext.new()
	var parent := Node3D.new()   # NOT in SceneTree
	var marker := Node3D.new()
	marker.name = "Spawn"
	marker.transform = Transform3D().translated(Vector3(4, 5, 6))
	parent.add_child(marker)

	PackedSceneHandler.apply(marker, {"packed_scene": PACKED}, ctx)

	var inst: Node = null
	for c in parent.get_children():
		if c.name == "PackedScene_Spawn": inst = c
	assert_not_null(inst)
	assert_eq((inst as Node3D).transform.origin, Vector3(4, 5, 6),
		"local transform should be copied when parent isn't in a SceneTree")
	parent.free()
