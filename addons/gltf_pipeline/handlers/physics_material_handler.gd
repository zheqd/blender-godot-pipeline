@tool
class_name PhysicsMaterialHandler
extends RefCounted

static func apply(body: Node, path: String) -> void:
	if not (body is StaticBody3D or body is RigidBody3D):
		return
	if path.is_empty():
		return
	var mat: PhysicsMaterial = load(path)
	if mat == null:
		push_warning("PhysicsMaterialHandler: failed to load " + path)
		return
	body.physics_material_override = mat
