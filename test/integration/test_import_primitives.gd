extends GutTest


const FIXTURE := "res://test/fixtures/primitives/primitives.gltf"

func _fixture_present() -> bool:
	return FileAccess.file_exists(FIXTURE)

func test_box_wall_becomes_static_body_with_box_shape():
	if not _fixture_present():
		pending("fixture not present — author per README.md")
		return
	var scene := PipelineTestHelpers.import_gltf(FIXTURE)
	var body: Node = _find_body(scene,"StaticBody3D_BoxWall")
	assert_not_null(body)
	assert_true(body is StaticBody3D)
	var shape: CollisionShape3D = null
	for c in body.get_children():
		if c is CollisionShape3D: shape = c
	assert_not_null(shape)
	assert_true(shape.shape is BoxShape3D)
	# Size comes from the Blender mesh bounding box via the addon's "Set
	# Collisions" operator — only assert the shape has positive dimensions.
	var sz := (shape.shape as BoxShape3D).size
	assert_true(sz.x > 0.0 and sz.y > 0.0 and sz.z > 0.0,
		"BoxShape3D.size must be positive on all axes, got %s" % sz)
	scene.free()

func test_sphere_prop_becomes_rigid_body():
	if not _fixture_present():
		pending("fixture not present — author per README.md")
		return
	var scene := PipelineTestHelpers.import_gltf(FIXTURE)
	var body: Node = _find_body(scene,"RigidBody3D_SphereProp")
	assert_not_null(body)
	assert_true(body is RigidBody3D)
	scene.free()

func test_capsule_npc_becomes_character_body():
	if not _fixture_present():
		pending("fixture not present — author per README.md")
		return
	var scene := PipelineTestHelpers.import_gltf(FIXTURE)
	var body: Node = _find_body(scene,"CharacterBody3D_CapsuleNPC")
	assert_not_null(body)
	assert_true(body is CharacterBody3D)
	scene.free()

func test_roundtrip_pack_save_instantiate_preserves_bodies():
	if not _fixture_present():
		pending("fixture not present — author per README.md")
		return
	var scene := PipelineTestHelpers.import_gltf(FIXTURE)
	# Pack imported scene to a PackedScene and round-trip through disk.
	# Without the owner-assignment post-pass in pipeline_extension.gd, the
	# saved .tscn would contain only the Node3D root — this test regresses loudly.
	var ps := PackedScene.new()
	var err := ps.pack(scene)
	assert_eq(err, OK, "PackedScene.pack must succeed")
	var tmp_path := "user://primitives_roundtrip.tscn"
	var save_err := ResourceSaver.save(ps, tmp_path)
	assert_eq(save_err, OK, "save must succeed")
	var reloaded := (load(tmp_path) as PackedScene).instantiate()
	for nm in [
		"StaticBody3D_BoxWall",
		"RigidBody3D_SphereProp",
		"StaticBody3D_CylinderCol",
		"CharacterBody3D_CapsuleNPC",
	]:
		var body := _find_body(reloaded, nm)
		assert_not_null(body,
			"%s missing after pack/save/load — owner assignment regressed" % nm)
		if body:
			# Mesh duplicate (added by CollisionHandler when discard_mesh is
			# unset) must survive. Catches regressions in materialize_all
			# and owner assignment on body-child meshes.
			var has_mesh_child := false
			for c in body.get_children():
				if c is MeshInstance3D:
					has_mesh_child = true
					break
			assert_true(has_mesh_child,
				"%s should have a MeshInstance3D child (mesh duplicate dropped)" % nm)
	reloaded.free()
	scene.free()

func _find_body(root: Node, name: String) -> Node:
	if root.name == name: return root
	for c in root.get_children():
		var r := _find_body(c, name)
		if r: return r
	return null
