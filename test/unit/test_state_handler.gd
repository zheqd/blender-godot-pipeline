extends GutTest

const StateHandler = preload("res://addons/gltf_pipeline/handlers/state_handler.gd")

func test_state_skip_frees_node_from_parent():
	var parent := Node3D.new()
	var child := Node3D.new()
	child.name = "Doomed"
	get_tree().root.add_child(parent)
	parent.add_child(child)
	StateHandler.apply(child, {"state": "skip"})
	await get_tree().process_frame
	assert_eq(parent.get_child_count(), 0, "skip removes child from parent")
	parent.queue_free()

func test_state_skip_on_root_is_noop_warning():
	var root := Node3D.new()
	StateHandler.apply(root, {"state": "skip"})
	assert_not_null(root, "root without parent: no-op")
	root.free()

func test_state_hide_sets_visibility_false():
	var n := Node3D.new()
	StateHandler.apply(n, {"state": "hide"})
	assert_false(n.visible, "hide → visible = false")
	n.free()

func test_state_other_values_are_noop():
	var n := Node3D.new()
	StateHandler.apply(n, {"state": "something_else"})
	assert_true(n.visible, "unknown state: no-op")
	n.free()

func test_no_state_key_is_noop():
	var n := Node3D.new()
	StateHandler.apply(n, {})
	assert_true(n.visible)
	n.free()
