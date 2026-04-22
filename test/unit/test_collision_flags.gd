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

func test_col_only_pure_with_script_queues_warning():
	# When '-c' has no body flag, 'script' has no target and must be ignored
	# with a warning. We verify behavioral correctness: no body in parent,
	# shape is present. (GUT cannot intercept push_warning directly.)
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
	CollisionHandler.apply(node, extras, ctx)
	var has_body := false
	var shape_count := 0
	for c in parent.get_children():
		if c is StaticBody3D or c is RigidBody3D or c is Area3D:
			has_body = true
		if c is CollisionShape3D:
			shape_count += 1
	assert_false(has_body, "pure -c must not add a body to parent")
	assert_eq(shape_count, 1, "pure -c must add exactly one CollisionShape3D to parent")
	parent.free()

func test_col_only_with_body_flag_routes_extras_to_orphan_body():
	# Complement to test_col_only_pure_with_script_queues_warning above:
	# when '-c' is combined with '-r', body-targeting extras have a target
	# (the orphan body) and must route there without triggering the
	# "nowhere to attach" warning. We use prop_string instead of 'script'
	# to keep the test hermetic — a bogus script path would emit an engine
	# ERROR that GUT's unexpected-errors gate treats as a failure.
	# A different gravity_scale value from the Task 6 test keeps the two
	# assertions independent for debugging.
	var parent := Node3D.new()
	var node := MeshInstance3D.new()
	node.name = "ColOnlyRigid"
	node.mesh = BoxMesh.new()
	parent.add_child(node)
	var extras := {
		"collision": "box-c-r",
		"size_x": 1.0, "size_y": 1.0, "size_z": 1.0,
		"prop_string": "gravity_scale = 0.7",
	}
	CollisionHandler.apply(node, extras, ctx)
	var orphan_body: RigidBody3D = null
	var shape_count := 0
	for c in parent.get_children():
		if c is RigidBody3D:
			orphan_body = c
		if c is CollisionShape3D:
			shape_count += 1
	assert_not_null(orphan_body, "-c-r must produce an orphan RigidBody3D")
	assert_eq(shape_count, 1, "-c-r must still produce the orphan shape")
	assert_almost_eq(orphan_body.gravity_scale, 0.7, 0.0001,
		"prop_string routed to orphan body (no warning path taken)")
	parent.free()

func test_col_only_with_rigid_flag_produces_orphan_rigidbody():
	var parent := Node3D.new()
	var mi := _make_mesh_instance()
	parent.add_child(mi)
	CollisionHandler.apply(mi, {
		"collision": "box-c-r",
		"size_x": "1", "size_y": "1", "size_z": "1"
	}, ctx)
	var rigid_count := 0
	var shape_count := 0
	var static_count := 0
	for c in parent.get_children():
		if c is RigidBody3D:
			rigid_count += 1
		if c is StaticBody3D:
			static_count += 1
		if c is CollisionShape3D:
			shape_count += 1
	assert_eq(rigid_count, 1, "'-c-r': exactly one orphan RigidBody3D")
	assert_eq(static_count, 0, "'-c-r': no StaticBody3D (would indicate body flag ignored)")
	assert_eq(shape_count, 1, "'-c-r': orphan shape also produced as sibling")
	assert_true(mi in ctx.deferred_deletes, "source mesh still queued for deletion")
	parent.free()

func test_col_only_respects_every_body_flag():
	# Each body flag (-r/-a/-m/-h) combined with -c must produce a matching
	# orphan body. Default (no body flag) must still produce no body.
	# This pins the '-c' + body-flag contract across the full matrix.
	var cases: Array = [
		["box-c",   null],  # pure -c: no body
		["box-c-r", RigidBody3D],
		["box-c-a", Area3D],
		["box-c-m", AnimatableBody3D],
		["box-c-h", CharacterBody3D],
	]
	for case: Array in cases:
		var col_str: String = case[0]
		var expected_body_type: Variant = case[1]
		var parent := Node3D.new()
		var mi := _make_mesh_instance()
		parent.add_child(mi)
		CollisionHandler.apply(mi, {
			"collision": col_str,
			"size_x": "1", "size_y": "1", "size_z": "1"
		}, ctx)
		var found_body: Node = null
		var shape_count := 0
		for c in parent.get_children():
			if c is PhysicsBody3D or c is Area3D:
				found_body = c
			if c is CollisionShape3D:
				shape_count += 1
		if expected_body_type == null:
			assert_null(found_body, "%s: no body expected" % col_str)
		else:
			assert_not_null(found_body, "%s: expected a body" % col_str)
			assert_true(
				is_instance_of(found_body, expected_body_type),
				"%s: body type mismatch, got %s" % [col_str, found_body.get_class()]
			)
		assert_eq(shape_count, 1, "%s: exactly one orphan shape" % col_str)
		parent.free()

func test_col_only_with_body_flag_attaches_script_to_orphan_body():
	# When '-c' produces an orphan body (via -r/-a/-m/-h), body-targeting
	# extras must route to that orphan body, not be discarded with a warning.
	# Uses prop_string (inline, no file load) to keep the test hermetic.
	var parent := Node3D.new()
	var mi := _make_mesh_instance()
	parent.add_child(mi)
	CollisionHandler.apply(mi, {
		"collision": "box-c-r",
		"size_x": "1", "size_y": "1", "size_z": "1",
		"prop_string": "gravity_scale = 0.5",
	}, ctx)
	var orphan_body: RigidBody3D = null
	for c in parent.get_children():
		if c is RigidBody3D:
			orphan_body = c
	assert_not_null(orphan_body, "orphan RigidBody3D produced")
	assert_almost_eq(orphan_body.gravity_scale, 0.5, 0.0001,
		"prop_string applied to orphan body")
	parent.free()

func test_bodyonly_col_only_no_body_flag_is_noop_and_deletes_mesh():
	# Regression: the Blender addon's "Collision: None + Body: None" UI labels
	# emit the literal 'bodyonly-c' — bodyonly suppresses the shape, -c with
	# no body flag suppresses the body, and nothing is produced. Mesh still
	# gets deleted (no reason to keep a pure no-op node). Pin this so a
	# future refactor can't silently change it, and so the handler emits
	# the warning users need to understand why their mesh vanished.
	var parent := Node3D.new()
	var mi := _make_mesh_instance()
	parent.add_child(mi)
	CollisionHandler.apply(mi, {
		"collision": "bodyonly-c",
	}, ctx)
	var non_source_siblings := 0
	for c in parent.get_children():
		if c != mi:
			non_source_siblings += 1
	assert_eq(non_source_siblings, 0,
		"bodyonly-c (no body flag): no body, no shape, no sibling nodes")
	assert_true(mi in ctx.deferred_deletes,
		"bodyonly-c: source mesh is still queued for deletion")
	parent.free()

func test_bodyonly_parent_composes_with_col_only_child():
	# Real-world Blender pairing: outer node with 'Collision: None + Body: Static'
	# (emits 'bodyonly' → StaticBody3D, no shape) wrapping an inner node with
	# 'Collision: Box + Body: None' (emits 'box-c' → orphan shape, no body).
	#
	# Naive parenting of the orphan shape to the outer mesh would cascade-
	# delete the shape when _flush frees the outer source node. The handler's
	# _resolve_shape_host fixes this by routing the shape to the synthesized
	# StaticBody3D that replaces the outer (identified by naming convention:
	# "StaticBody3D_<outer.name>" as a sibling of the doomed node).
	#
	# This test exercises the full lifecycle — handler apply + deferred_deletes
	# flush — and asserts the shape SURVIVES inside the StaticBody3D. The
	# pre-flush check alone would miss the bug.
	var scene_root := Node3D.new()
	var outer := Node3D.new()
	outer.name = "Wall"
	scene_root.add_child(outer)
	var inner := _make_mesh_instance()
	inner.name = "WallCollider"
	outer.add_child(inner)

	# Top-down dispatch: outer (bodyonly) before inner (box-c).
	CollisionHandler.apply(outer, {"collision": "bodyonly"}, ctx)
	CollisionHandler.apply(inner, {
		"collision": "box-c",
		"size_x": "1", "size_y": "1", "size_z": "1",
	}, ctx)

	var outer_body: StaticBody3D = null
	for c in scene_root.get_children():
		if c is StaticBody3D:
			outer_body = c
	assert_not_null(outer_body, "bodyonly outer node produced a StaticBody3D sibling")

	# Pre-flush: the shape lives under outer_body (not under the doomed outer),
	# thanks to _resolve_shape_host's cascade-delete rescue.
	var shape_in_body: CollisionShape3D = null
	for c in outer_body.get_children():
		if c is CollisionShape3D:
			shape_in_body = c
	assert_not_null(shape_in_body,
		"box-c shape routed to the replacement body, not the doomed outer")

	assert_true(outer in ctx.deferred_deletes, "outer bodyonly source queued for delete")
	assert_true(inner in ctx.deferred_deletes, "inner box-c source queued for delete")

	# Flush: mirror what PipelineGLTFExtension._flush does — apply reparents
	# (none queued for this pairing), then free the deferred_deletes nodes.
	# The shape must survive because it lives under outer_body, not outer.
	for pair: Array in ctx.deferred_reparents:
		var child: Node = pair[0]
		var new_parent: Node = pair[1]
		var old_parent: Node = child.get_parent()
		if old_parent:
			old_parent.remove_child(child)
		new_parent.add_child(child)
	for n: Node in ctx.deferred_deletes:
		if is_instance_valid(n):
			var p: Node = n.get_parent()
			if p:
				p.remove_child(n)
			n.free()

	assert_true(is_instance_valid(shape_in_body),
		"post-flush: shape survived cascade (it sat under the body, not the doomed outer)")
	assert_true(is_instance_valid(outer_body),
		"post-flush: StaticBody3D is still in the tree")
	assert_eq(shape_in_body.get_parent(), outer_body,
		"post-flush: shape's parent is the StaticBody3D")

	scene_root.free()
