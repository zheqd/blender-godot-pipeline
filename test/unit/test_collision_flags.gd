extends GutTest

const CollisionHandler = preload("res://addons/gltf_pipeline/handlers/collision_handler.gd")
const PipelineGLTFExtension = preload("res://addons/gltf_pipeline/pipeline_extension.gd")

var ctx: PipelineGLTFExtension.PipelineContext

func _make_mesh_instance() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Wall"
	mi.position = Vector3(5, 0, 0)
	mi.mesh = BoxMesh.new()
	return mi

func before_each():
	ctx = PipelineGLTFExtension.PipelineContext.new()

func test_normal_collision_wraps_in_body():
	var parent := Node3D.new()
	var mi := _make_mesh_instance()
	parent.add_child(mi)
	CollisionHandler.apply(mi, {
		"collision": "box",
		"size_x": "1", "size_y": "1", "size_z": "1"
	}, ctx)
	var body: Node = null
	for c in parent.get_children():
		if c is StaticBody3D:
			body = c
	assert_not_null(body, "StaticBody3D created under parent")
	assert_eq(body.position, Vector3(5, 0, 0), "body takes node's position")
	var cs: CollisionShape3D = null
	for c in body.get_children():
		if c is CollisionShape3D:
			cs = c
	assert_not_null(cs)
	assert_true(cs.shape is BoxShape3D)
	assert_true(mi in ctx.deferred_deletes)
	parent.free()

func test_col_only_attaches_shape_to_parent_no_body():
	var parent := Node3D.new()
	var mi := _make_mesh_instance()
	parent.add_child(mi)
	CollisionHandler.apply(mi, {
		"collision": "box-c",
		"size_x": "1", "size_y": "1", "size_z": "1"
	}, ctx)
	var has_body := false
	var has_shape := false
	for c in parent.get_children():
		if c is StaticBody3D:
			has_body = true
		if c is CollisionShape3D:
			has_shape = true
	assert_false(has_body, "-c: no body created")
	assert_true(has_shape, "-c: shape attached to parent")
	parent.free()

func test_center_offset_on_primitives():
	var parent := Node3D.new()
	var mi := _make_mesh_instance()
	parent.add_child(mi)
	CollisionHandler.apply(mi, {
		"collision": "box",
		"size_x": "1", "size_y": "1", "size_z": "1",
		"center_x": "0.5", "center_y": "1.0", "center_z": "0.25"
	}, ctx)
	var body: StaticBody3D = null
	for c in parent.get_children():
		if c is StaticBody3D:
			body = c
	var cs: CollisionShape3D = null
	for c in body.get_children():
		if c is CollisionShape3D:
			cs = c
	# z should be negated per v2.5.5
	assert_eq(cs.position, Vector3(0.5, 1.0, -0.25))
	parent.free()

func test_center_offset_NOT_applied_for_trimesh():
	var parent := Node3D.new()
	var mi := _make_mesh_instance()
	parent.add_child(mi)
	CollisionHandler.apply(mi, {
		"collision": "trimesh",
		"center_x": "1", "center_y": "2", "center_z": "3"
	}, ctx)
	var body: StaticBody3D = null
	for c in parent.get_children():
		if c is StaticBody3D:
			body = c
	var cs: CollisionShape3D = null
	for c in body.get_children():
		if c is CollisionShape3D:
			cs = c
	assert_eq(cs.position, Vector3.ZERO, "trimesh: center offset not applied")
	parent.free()

func test_bodyonly_flag_skips_collision_shape():
	var parent := Node3D.new()
	var mi := _make_mesh_instance()
	parent.add_child(mi)
	CollisionHandler.apply(mi, {
		"collision": "box-r bodyonly",
		"size_x": "1", "size_y": "1", "size_z": "1"
	}, ctx)
	var body: RigidBody3D = null
	for c in parent.get_children():
		if c is RigidBody3D:
			body = c
	assert_not_null(body)
	var has_cs := false
	for c in body.get_children():
		if c is CollisionShape3D:
			has_cs = true
	assert_false(has_cs, "bodyonly: no CollisionShape3D")
	parent.free()

func test_discard_mesh_flag():
	var parent := Node3D.new()
	var mi := _make_mesh_instance()
	parent.add_child(mi)
	CollisionHandler.apply(mi, {
		"collision": "box-d",
		"size_x": "1", "size_y": "1", "size_z": "1"
	}, ctx)
	var body: StaticBody3D = null
	for c in parent.get_children():
		if c is StaticBody3D:
			body = c
	# With -d, body has only the CollisionShape3D — no duplicated mesh child
	var non_cs_children := 0
	for c in body.get_children():
		if not (c is CollisionShape3D):
			non_cs_children += 1
	assert_eq(non_cs_children, 0, "-d: body has no mesh duplicate")
	parent.free()

func test_existing_collision_shape_child_is_deferred_reparent():
	var parent := Node3D.new()
	var mi := _make_mesh_instance()
	var preexisting := CollisionShape3D.new()
	preexisting.name = "PreExisting"
	mi.add_child(preexisting)
	parent.add_child(mi)
	CollisionHandler.apply(mi, {
		"collision": "box",
		"size_x": "1", "size_y": "1", "size_z": "1"
	}, ctx)
	assert_eq(ctx.deferred_reparents.size(), 1, "one reparent queued")
	assert_eq(ctx.deferred_reparents[0][0], preexisting)
	parent.free()
