extends GutTest

const PhysicsMaterialHandler = preload("res://addons/gltf_pipeline/handlers/physics_material_handler.gd")
const MAT := "res://test/fixtures/test_phys_mat.tres"

func test_applies_to_static_body():
	var b := StaticBody3D.new()
	PhysicsMaterialHandler.apply(b, MAT)
	assert_not_null(b.physics_material_override)
	assert_almost_eq(b.physics_material_override.friction, 0.7, 0.001)
	b.free()

func test_applies_to_rigid_body():
	var b := RigidBody3D.new()
	PhysicsMaterialHandler.apply(b, MAT)
	assert_not_null(b.physics_material_override)
	b.free()

func test_does_not_apply_to_area():
	var a := Area3D.new()
	PhysicsMaterialHandler.apply(a, MAT)
	# Area3D has no physics_material_override property. No crash = pass.
	assert_true(true)
	a.free()

func test_bad_path_noop():
	var b := StaticBody3D.new()
	PhysicsMaterialHandler.apply(b, "res://nope.tres")
	assert_null(b.physics_material_override)
	assert_engine_error_count(2)
	b.free()
