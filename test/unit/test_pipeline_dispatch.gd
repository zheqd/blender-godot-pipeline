extends GutTest

const PipelineGLTFExtension = preload("res://addons/gltf_pipeline/pipeline_extension.gd")

func test_collision_and_packed_scene_only_collision_fires():
	var ext := PipelineGLTFExtension.new()
	var root := Node3D.new()
	var node := MeshInstance3D.new()
	node.name = "Both"
	node.mesh = BoxMesh.new()
	node.set_meta("extras", {
		"collision": "box",
		"size_x": 1.0, "size_y": 1.0, "size_z": 1.0,
		"packed_scene": 1,
	})
	root.add_child(node)
	var ctx := PipelineGLTFExtension.PipelineContext.new()
	ctx.root = root
	ext._dispatch(node, ctx)
	# Collision path queues the node for deletion; packed_scene must NOT have fired.
	var packed_names := 0
	for c in root.get_children():
		if str(c.name).begins_with("PackedScene_"):
			packed_names += 1
	assert_eq(packed_names, 0, "packed_scene handler must not fire when collision is present")
	root.free()
	# ext extends GLTFDocumentExtension (RefCounted) — cannot call .free() on it;
	# it will be garbage-collected automatically when it goes out of scope.

func test_multimesh_wins_over_packed_scene():
	# multimesh > packed_scene priority
	var ext := PipelineGLTFExtension.new()
	var root := Node3D.new()
	var node := MeshInstance3D.new()
	node.name = "Multi"
	node.mesh = BoxMesh.new()
	node.set_meta("extras", {
		"multimesh": "user://test_multi.tres",
		"packed_scene": 1,
	})
	root.add_child(node)
	var ctx := PipelineGLTFExtension.PipelineContext.new()
	ctx.root = root
	ext._dispatch(node, ctx)
	# multimesh fires: node goes into deferred_deletes, no PackedScene_ child
	assert_true(node in ctx.deferred_deletes, "multimesh handler must queue node for deletion")
	var packed_names := 0
	for c in root.get_children():
		if str(c.name).begins_with("PackedScene_"):
			packed_names += 1
	assert_eq(packed_names, 0, "packed_scene must not fire when multimesh is present")
	root.free()

func test_single_consumer_no_warning_and_correct_handler():
	# Single consumer: no warning, only that handler fires.
	# PackedSceneHandler warns and returns early when the scene file is missing,
	# so node is NOT added to deferred_deletes — but no collision body fires either.
	var ext := PipelineGLTFExtension.new()
	var root := Node3D.new()
	var node := MeshInstance3D.new()
	node.name = "Single"
	node.mesh = BoxMesh.new()
	node.set_meta("extras", {"packed_scene": "res://nonexistent_scene.tscn"})
	root.add_child(node)
	var ctx := PipelineGLTFExtension.PipelineContext.new()
	ctx.root = root
	ext._dispatch(node, ctx)
	# load() on a missing file emits two engine-level errors; declare them expected.
	assert_engine_error_count(2)
	# PackedSceneHandler returns early (missing file) — node not deferred-deleted.
	# Verify no collision body was spawned (collision handler must NOT have fired).
	var body_count := 0
	for c in root.get_children():
		if c is StaticBody3D or c is RigidBody3D or c is Area3D:
			body_count += 1
	assert_eq(body_count, 0, "no collision body must appear for packed_scene-only node")
	root.free()
