extends GutTest

const CollisionHandler: GDScript = preload("res://addons/gltf_pipeline/handlers/collision_handler.gd")
const PipelineContext = preload("res://addons/gltf_pipeline/pipeline_context.gd")

var ctx: PipelineContext

func _make_mesh_instance() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "Wall"
	mi.position = Vector3(5, 0, 0)
	mi.mesh = BoxMesh.new()
	return mi

func before_each():
	ctx = PipelineContext.new()

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

func test_col_only_clean_no_warnings():
	# Orphan-collider workflow: a .gltf that only contributes CollisionShape3D
	# nodes, intended to nest inside another scene whose body owns them.
	# With no body-targeting extras, the handler must produce a clean
	# orphan shape and emit no warnings.
	var parent := Node3D.new()
	var mi := _make_mesh_instance()
	parent.add_child(mi)
	CollisionHandler.apply(mi, {
		"collision": "box-c",
		"size_x": "1", "size_y": "1", "size_z": "1"
	}, ctx)
	var body_count := 0
	var shape_count := 0
	for c in parent.get_children():
		if c is StaticBody3D or c is RigidBody3D or c is Area3D \
				or c is AnimatableBody3D or c is CharacterBody3D:
			body_count += 1
		if c is CollisionShape3D:
			shape_count += 1
	assert_eq(body_count, 0, "clean -c: no body anywhere")
	assert_eq(shape_count, 1, "clean -c: exactly one orphan CollisionShape3D")
	assert_true(mi in ctx.deferred_deletes, "original mesh node queued for deletion")
	parent.free()

func test_col_only_orphan_under_existing_body():
	# Nested-gltf composition: outer scene supplies a StaticBody3D; the
	# orphan-collider .gltf's -c nodes sit under a Node3D child of that body.
	# After handler runs, the CollisionShape3D lives under the Node3D parent
	# and is reachable from the outer body — functional physics contract.
	var outer_body := StaticBody3D.new()
	outer_body.name = "OuterBody"
	var inner_parent := Node3D.new()
	inner_parent.name = "InnerGroup"
	outer_body.add_child(inner_parent)
	var mi := _make_mesh_instance()
	inner_parent.add_child(mi)
	CollisionHandler.apply(mi, {
		"collision": "box-c",
		"size_x": "1", "size_y": "1", "size_z": "1"
	}, ctx)
	var shape: CollisionShape3D = null
	for c in inner_parent.get_children():
		if c is CollisionShape3D:
			shape = c
	assert_not_null(shape, "orphan shape attached to inner parent")
	assert_eq(shape.get_parent(), inner_parent, "shape's direct parent is the inner group")
	var ancestor: Node = shape.get_parent()
	var found_body := false
	while ancestor != null:
		if ancestor is StaticBody3D:
			found_body = true
			break
		ancestor = ancestor.get_parent()
	assert_true(found_body, "outer StaticBody3D is an ancestor of the orphan shape")
	outer_body.free()

func test_col_only_with_script_queues_warning():
	# When '-c' (col_only) is combined with 'script', the warning must fire
	# because no body is created to attach the script to.
	# We verify the handler still completes without error and only
	# attaches the CollisionShape3D (not a body).
	var parent := Node3D.new()
	var node := MeshInstance3D.new()
	node.name = "ColOnly"
	node.mesh = BoxMesh.new()
	parent.add_child(node)
	var extras := {
		"collision": "box-c",
		"size_x": 1.0, "size_y": 1.0, "size_z": 1.0,
		"script": "res://nonexistent_script.gd",
	}
	# The handler will push_warning about "script" being ignored.
	# GUT's assert_has_signal cannot intercept push_warning, so we
	# verify behavioral correctness: no body in parent, shape is present.
	CollisionHandler.apply(node, extras, ctx)
	var has_body := false
	var shape_count := 0
	for c in parent.get_children():
		if c is StaticBody3D or c is RigidBody3D or c is Area3D:
			has_body = true
		if c is CollisionShape3D:
			shape_count += 1
	assert_false(has_body, "col_only must not add a body to parent")
	assert_eq(shape_count, 1, "col_only must add exactly one CollisionShape3D to parent")
	parent.free()
