extends GutTest

const PipelineGLTFExtension = preload("res://addons/gltf_pipeline/pipeline_extension.gd")

var ext: PipelineGLTFExtension

func before_each():
	ext = PipelineGLTFExtension.new()

func test_simple_child_gets_root_owner():
	var root := Node3D.new()
	var child := Node3D.new()
	root.add_child(child)
	assert_null(child.owner, "precondition: no owner")
	ext._assign_owners(root, root)
	assert_eq(child.owner, root)
	root.free()

func test_deeply_nested_structure_all_owned():
	var root := Node3D.new()
	var a := Node3D.new()
	var b := Node3D.new()
	var c := Node3D.new()
	root.add_child(a)
	a.add_child(b)
	b.add_child(c)
	ext._assign_owners(root, root)
	assert_eq(a.owner, root)
	assert_eq(b.owner, root)
	assert_eq(c.owner, root)
	root.free()

func test_instance_subtree_preserved():
	# Build a tiny packed scene: inst_root → inst_child (owned by inst_root).
	var inst_root := Node3D.new()
	inst_root.name = "InstRoot"
	var inst_child := Node3D.new()
	inst_child.name = "InstChild"
	inst_root.add_child(inst_child)
	inst_child.owner = inst_root
	var ps := PackedScene.new()
	var err := ps.pack(inst_root)
	assert_eq(err, OK)
	inst_root.free()

	# Instance the packed scene into a fresh root.
	var root := Node3D.new()
	var inst := ps.instantiate()
	root.add_child(inst)
	assert_null(inst.owner, "instance top has no owner before pass")
	var inner: Node = inst.get_node("InstChild")
	assert_eq(inner.owner, inst, "instance descendant pre-owned by instance root")

	ext._assign_owners(root, root)

	assert_eq(inst.owner, root, "instance top now owned by outer root")
	assert_eq(inner.owner, inst, "instance descendant's owner NOT rewritten")
	root.free()

func test_already_owned_node_untouched():
	var root := Node3D.new()
	var a := Node3D.new()
	var b := Node3D.new()
	root.add_child(a)
	a.add_child(b)
	# Pre-assign a as owned by something else (b owned by a).
	a.owner = root
	b.owner = a
	ext._assign_owners(root, root)
	assert_eq(a.owner, root, "a kept")
	assert_eq(b.owner, a, "b owner NOT rewritten to root")
	root.free()

func test_assign_owners_recurses_through_owned_non_instance_nodes():
	# Construct: root
	#              └── middle (owner=root, NOT a scene instance)
	#                    └── inner (owner=null)
	# _assign_owners must set inner.owner = root.
	var root := Node3D.new()
	var middle := Node3D.new()
	middle.name = "middle"
	var inner := Node3D.new()
	inner.name = "inner"
	root.add_child(middle)
	middle.owner = root
	middle.add_child(inner)
	ext._assign_owners(root, root)
	assert_eq(inner.owner, root, "inner should have been assigned root as owner")
	root.free()

func test_assign_owners_skips_packed_scene_instance_subtree():
	# When a child has scene_file_path != "", its subtree is already
	# owned via the instance root and must NOT be re-owned.
	var root := Node3D.new()
	var inst := Node3D.new()
	inst.name = "inst"
	inst.scene_file_path = "res://some_packed.tscn"
	var inside := Node3D.new()
	inside.name = "inside"
	root.add_child(inst)
	inst.owner = root
	inst.add_child(inside)
	inside.owner = inst
	ext._assign_owners(root, root)
	assert_eq(inside.owner, inst, "inside owner must remain the instance root")
	root.free()
