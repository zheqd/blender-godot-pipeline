extends GutTest


const FIXTURE := "res://test/fixtures/compound_collisions/compound_collisions.gltf"

func _fixture_present() -> bool:
	return FileAccess.file_exists(FIXTURE)

func test_fixture_imports_without_error():
	if not _fixture_present():
		pending("fixture not present — author per README.md")
		return
	var scene := PipelineTestHelpers.import_gltf(FIXTURE)
	assert_not_null(scene, "import_gltf must return a scene root")
	scene.free()

# Pins the fix for the "owner inconsistent" warning that fires from
# scene/main/node.cpp when a CollisionShape3D child is reparented onto a
# freshly-built body without clearing its import-time owner. Custom-collider
# children of a mesh node (e.g. LShape.Col.001) go through the
# deferred_reparents path in pipeline_extension._flush. If that path doesn't
# null child.owner before add_child, Godot warns and the child ends up with an
# owner that isn't an ancestor of its new parent.
#
# _assign_owners runs after _flush and re-owns every unowned descendant to the
# scene root, so after import the CS3D children must have scene_root as their
# owner.
func test_custom_collider_children_owner_is_scene_root():
	if not _fixture_present():
		pending("fixture not present — author per README.md")
		return
	var scene := PipelineTestHelpers.import_gltf(FIXTURE)
	assert_not_null(scene)

	var lshape_body: Node = _find_node(scene, "StaticBody3D_LShape")
	assert_not_null(lshape_body,
		"StaticBody3D_LShape missing — custom-collider wrap regressed")
	if lshape_body == null:
		scene.free()
		return

	var shapes: Array[CollisionShape3D] = []
	for c: Node in lshape_body.get_children():
		if c is CollisionShape3D:
			shapes.append(c)
	assert_true(shapes.size() >= 1,
		"expected at least one CollisionShape3D reparented onto StaticBody3D_LShape")

	for cs: CollisionShape3D in shapes:
		assert_eq(cs.owner, scene,
			"CS3D '%s' owner must be scene root after _flush reparent + _assign_owners, got %s" % [cs.name, cs.owner])

	scene.free()

func test_cube_mesh_survives_without_collision_extra():
	if not _fixture_present():
		pending("fixture not present — author per README.md")
		return
	var scene := PipelineTestHelpers.import_gltf(FIXTURE)
	var cube := _find_node(scene, "Cube")
	assert_not_null(cube, "Cube node must survive import (no collision extra)")
	assert_true(cube is MeshInstance3D,
		"Cube must remain a MeshInstance3D — handler should not touch nodes without a 'collision' extra")
	assert_eq(cube.get_parent(), scene,
		"Cube must remain a direct child of the scene root")
	scene.free()

func test_box_d_produces_static_body_with_discarded_mesh():
	if not _fixture_present():
		pending("fixture not present — author per README.md")
		return
	var scene := PipelineTestHelpers.import_gltf(FIXTURE)

	# Godot sanitizes node names: dots become underscores when assigned to node.name.
	# Expected BoxShape3D.size per fixture's size_x/y/z extras — no axis swap.
	var expected_sizes: Dictionary = {
		"StaticBody3D_Cube_Collision_001": Vector3(16, 4, 4),
		"StaticBody3D_Cube_Collision_002": Vector3(16, 4, 4),
		"StaticBody3D_Cube_Collision_003": Vector3(4, 4, 16),
	}

	for body_name: String in expected_sizes.keys():
		var body := _find_node(scene, body_name)
		assert_not_null(body, "%s must exist (synthesized from box-d)" % body_name)
		if body == null:
			continue
		assert_true(body is StaticBody3D,
			"%s must be a StaticBody3D" % body_name)

		# Exactly one CollisionShape3D child
		var shape_children: int = 0
		var cs: CollisionShape3D = null
		for c in body.get_children():
			if c is CollisionShape3D:
				shape_children += 1
				cs = c
		assert_eq(shape_children, 1,
			"%s must have exactly one CollisionShape3D child" % body_name)
		assert_not_null(cs)
		if cs != null:
			assert_true(cs.shape is BoxShape3D,
				"%s's shape must be BoxShape3D" % body_name)
			if cs.shape is BoxShape3D:
				assert_eq((cs.shape as BoxShape3D).size, expected_sizes[body_name],
					"%s BoxShape3D.size must match size_x/y/z extras" % body_name)

		# -d flag: no MeshInstance3D child survives on the body
		for c in body.get_children():
			assert_false(c is MeshInstance3D,
				"%s must NOT have a MeshInstance3D child — '-d' flag discards the mesh" % body_name)

	scene.free()

func test_cube_collision_bodies_are_scene_root_siblings_of_cube():
	if not _fixture_present():
		pending("fixture not present — author per README.md")
		return
	var scene := PipelineTestHelpers.import_gltf(FIXTURE)

	# Godot sanitizes dots to underscores in node names.
	# Pin parent to `scene` directly rather than inferring from cube.get_parent(),
	# so the assertion doesn't silently pass if fixture topology shifts.
	for body_name: String in [
		"StaticBody3D_Cube_Collision_001",
		"StaticBody3D_Cube_Collision_002",
		"StaticBody3D_Cube_Collision_003",
	]:
		var body := _find_node(scene, body_name)
		assert_not_null(body, "%s must exist" % body_name)
		if body != null:
			assert_eq(body.get_parent(), scene,
				"%s must be a direct child of the scene root (no unintended reparenting)" % body_name)

	scene.free()

func test_cube_collision_002_translation_propagates_to_body():
	if not _fixture_present():
		pending("fixture not present — author per README.md")
		return
	var scene := PipelineTestHelpers.import_gltf(FIXTURE)

	# Godot sanitizes dots to underscores in node names.
	var body := _find_node(scene, "StaticBody3D_Cube_Collision_002")
	assert_not_null(body)
	if body == null:
		scene.free()
		return
	assert_true(body is Node3D)
	# glTF node has translation [0, 0, -12]. The handler copies
	# (node as Node3D).position to body.position — all three components must round-trip.
	assert_almost_eq((body as Node3D).position.x, 0.0, 0.0001,
		"synthesized body X must match original node translation")
	assert_almost_eq((body as Node3D).position.y, 0.0, 0.0001,
		"synthesized body Y must match original node translation")
	assert_almost_eq((body as Node3D).position.z, -12.0, 0.0001,
		"synthesized body Z must match original node translation")

	scene.free()

func test_bodyonly_parent_composes_with_box_c_children():
	if not _fixture_present():
		pending("fixture not present — author per README.md")
		return
	var scene := PipelineTestHelpers.import_gltf(FIXTURE)

	var body := _find_node(scene, "StaticBody3D_LShape")
	assert_not_null(body, "StaticBody3D_LShape must be synthesized from the bodyonly LShape parent")
	if body == null:
		scene.free()
		return
	assert_true(body is StaticBody3D)

	# bodyonly without -d: handler duplicates the original mesh into the body.
	# Verify the mesh duplicate is present inside the body.
	var mesh_children: int = 0
	for c: Node in body.get_children():
		if c is MeshInstance3D:
			mesh_children += 1
	assert_eq(mesh_children, 1,
		"StaticBody3D_LShape must contain exactly one MeshInstance3D (bodyonly duplicates mesh without -d)")

	# Original LShape must not be a direct scene-root child after bodyonly synthesis.
	var direct_lshape: Node = null
	for c: Node in scene.get_children():
		if c.name == "LShape":
			direct_lshape = c
	assert_null(direct_lshape,
		"LShape must not be a direct scene-root child after bodyonly synthesis")

	# Exactly two CollisionShape3D descendants — the two box-c children.
	# Regression target: commits eabbe49 (composition contract) and 784146b
	# (cascade-delete of orphan shapes under bodyonly parents).
	var shape_count := _count_collision_shape_descendants(body)
	assert_eq(shape_count, 2,
		"StaticBody3D_LShape must contain exactly 2 CollisionShape3D descendants — one per box-c child")

	# Shapes are BoxShape3D. Fixture extras:
	#   LShape.Col.001 (box-c-d): size_x=4, size_y=4, size_z=4 → Vector3(4,4,4)
	#   LShape.Col.002 (box-c):   size_x=6, size_y=10, size_z=4 → Vector3(6,10,4)
	var box_sizes: Array[Vector3] = []
	_collect_box_sizes(body, box_sizes)
	assert_eq(box_sizes.size(), 2,
		"both descendant shapes must be BoxShape3D")
	box_sizes.sort()
	var expected: Array[Vector3] = [Vector3(4, 4, 4), Vector3(6, 10, 4)]
	expected.sort()
	assert_eq(box_sizes, expected,
		"box-c children sizes must match fixture extras")

	# Standalone col nodes are gone — _find_node is a full-tree search,
	# confirming they don't exist anywhere in the scene (Godot sanitizes dots to underscores).
	assert_null(_find_node(scene, "LShape_Col_001"),
		"LShape_Col_001 must be removed (deferred_deletes flushed)")
	assert_null(_find_node(scene, "LShape_Col_002"),
		"LShape_Col_002 must be removed (deferred_deletes flushed)")

	scene.free()

func test_roundtrip_pack_save_instantiate_preserves_collisions():
	if not _fixture_present():
		pending("fixture not present — author per README.md")
		return
	var scene := PipelineTestHelpers.import_gltf(FIXTURE)

	var ps := PackedScene.new()
	var err := ps.pack(scene)
	assert_eq(err, OK, "PackedScene.pack must succeed")
	if err != OK:
		scene.free()
		return

	var tmp_path := "user://compound_collisions_roundtrip.tscn"
	var save_err := ResourceSaver.save(ps, tmp_path)
	assert_eq(save_err, OK, "ResourceSaver.save must succeed")
	if save_err != OK:
		scene.free()
		return

	var loaded_ps := load(tmp_path) as PackedScene
	assert_not_null(loaded_ps, "loaded PackedScene must not be null")
	if loaded_ps == null:
		scene.free()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_path))
		return

	var reloaded := loaded_ps.instantiate()

	# All three box-d bodies survive the roundtrip (Godot sanitizes dots to underscores).
	for body_name: String in [
		"StaticBody3D_Cube_Collision_001",
		"StaticBody3D_Cube_Collision_002",
		"StaticBody3D_Cube_Collision_003",
	]:
		var body := _find_node(reloaded, body_name)
		assert_not_null(body,
			"%s missing after pack/save/load — owner assignment regressed" % body_name)

	# The composed bodyonly body survives with both orphan shapes reattached.
	var l_body := _find_node(reloaded, "StaticBody3D_LShape")
	assert_not_null(l_body,
		"StaticBody3D_LShape missing after pack/save/load — owner assignment regressed")
	if l_body != null:
		var shape_count := _count_collision_shape_descendants(l_body)
		assert_eq(shape_count, 2,
			"StaticBody3D_LShape must still contain 2 shape descendants after roundtrip — _resolve_shape_host's reparented shapes must have correct owner")

	reloaded.free()
	scene.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_path))

func _collect_box_sizes(n: Node, out: Array[Vector3]) -> void:
	for c in n.get_children():
		if c is CollisionShape3D:
			var sh: Shape3D = (c as CollisionShape3D).shape
			if sh is BoxShape3D:
				out.append((sh as BoxShape3D).size)
		_collect_box_sizes(c, out)

func _find_node(root: Node, name: String) -> Node:
	if root.name == name: return root
	for c in root.get_children():
		var r := _find_node(c, name)
		if r: return r
	return null

func _count_collision_shape_descendants(n: Node) -> int:
	var total: int = 0
	for c in n.get_children():
		if c is CollisionShape3D:
			total += 1
		total += _count_collision_shape_descendants(c)
	return total
