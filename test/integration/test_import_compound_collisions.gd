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
