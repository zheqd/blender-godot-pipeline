extends GutTest

const CollisionHandler: GDScript = preload("res://addons/gltf_pipeline/handlers/collision_handler.gd")

func _ex(keys: Dictionary) -> Dictionary: return keys

func test_box_shape():
	var s: Shape3D = CollisionHandler.make_shape("box", null, _ex({
		"size_x": "2", "size_y": "3", "size_z": "4"
	}))
	assert_true(s is BoxShape3D)
	assert_eq(s.size, Vector3(2, 3, 4))

func test_sphere_shape():
	var s: Shape3D = CollisionHandler.make_shape("sphere", null, _ex({"radius": "1.5"}))
	assert_true(s is SphereShape3D)
	assert_almost_eq(s.radius, 1.5, 0.001)

func test_capsule_shape():
	var s: Shape3D = CollisionHandler.make_shape("capsule", null, _ex({
		"height": "2", "radius": "0.5"
	}))
	assert_true(s is CapsuleShape3D)
	assert_almost_eq(s.height, 2.0, 0.001)
	assert_almost_eq(s.radius, 0.5, 0.001)

func test_cylinder_shape():
	var s: Shape3D = CollisionHandler.make_shape("cylinder", null, _ex({
		"height": "4", "radius": "1"
	}))
	assert_true(s is CylinderShape3D)

func test_box_missing_size_key_returns_empty_shape():
	var s: Shape3D = CollisionHandler.make_shape("box", null, _ex({"size_x": "1"}))
	# With missing size_y/size_z, v2.5.5 never sets size; shape is created but uninitialized.
	# We return null instead to be explicit.
	assert_null(s)

func test_unknown_type_returns_null():
	var s: Shape3D = CollisionHandler.make_shape("triangle_soup", null, _ex({}))
	assert_null(s)
