extends GutTest

const CollisionHandler = preload("res://addons/gltf_pipeline/handlers/collision_handler.gd")

func test_default_is_static_body():
	var b = CollisionHandler.make_body("box", "Wall")
	assert_true(b is StaticBody3D)
	assert_eq(b.name, "StaticBody3D_Wall")
	b.free()

func test_rigid_flag():
	var b = CollisionHandler.make_body("box-r", "Crate")
	assert_true(b is RigidBody3D)
	assert_eq(b.name, "RigidBody3D_Crate")
	b.free()

func test_area_flag():
	var b = CollisionHandler.make_body("box-a", "Trigger")
	assert_true(b is Area3D)
	b.free()

func test_animatable_flag():
	var b = CollisionHandler.make_body("box-m", "Platform")
	assert_true(b is AnimatableBody3D)
	b.free()

func test_character_flag():
	var b = CollisionHandler.make_body("box-h", "Npc")
	assert_true(b is CharacterBody3D)
	b.free()

func test_col_only_returns_null():
	var b = CollisionHandler.make_body("box-c", "Whatever")
	assert_null(b, "collision-only: no body created")
