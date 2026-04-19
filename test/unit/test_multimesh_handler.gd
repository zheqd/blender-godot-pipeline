extends GutTest

const MultimeshHandler = preload("res://addons/gltf_pipeline/handlers/multimesh_handler.gd")
const PipelineGLTFExtension = preload("res://addons/gltf_pipeline/pipeline_extension.gd")

var tmp_mesh := "user://tree.tres"

func test_collect_groups_transforms():
	var ctx := PipelineGLTFExtension.PipelineContext.new()
	var tree_a := MeshInstance3D.new()
	tree_a.name = "TreeA"
	tree_a.mesh = BoxMesh.new()
	tree_a.position = Vector3(1, 0, 0)
	var tree_b := MeshInstance3D.new()
	tree_b.name = "TreeB"
	tree_b.mesh = BoxMesh.new()
	tree_b.position = Vector3(5, 0, 0)

	MultimeshHandler.collect(tree_a, {"multimesh": tmp_mesh}, ctx)
	MultimeshHandler.collect(tree_b, {"multimesh": tmp_mesh}, ctx)

	assert_eq(ctx.multimesh_groups.size(), 1)
	assert_eq(ctx.multimesh_groups[tmp_mesh].size(), 2)
	assert_true(tree_a in ctx.deferred_deletes)
	assert_true(tree_b in ctx.deferred_deletes)
	tree_a.free()
	tree_b.free()

func test_emit_creates_multimesh_instance():
	var ctx := PipelineGLTFExtension.PipelineContext.new()
	ctx.multimesh_groups[tmp_mesh] = [
		Transform3D().translated(Vector3(1, 0, 0)),
		Transform3D().translated(Vector3(5, 0, 0))
	]
	# Pretend we already saved the mesh
	ResourceSaver.save(BoxMesh.new(), tmp_mesh)

	var root := Node3D.new()
	MultimeshHandler.emit_all(root, ctx)

	var mm_inst: MultiMeshInstance3D = null
	for c in root.get_children():
		if c is MultiMeshInstance3D: mm_inst = c
	assert_not_null(mm_inst)
	assert_eq(mm_inst.multimesh.instance_count, 2)
	assert_eq(mm_inst.multimesh.transform_format, MultiMesh.TRANSFORM_3D)
	root.free()
