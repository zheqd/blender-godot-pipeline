@tool
class_name PackedSceneHandler
extends RefCounted

static func apply(node: Node, extras: Dictionary, ctx) -> void:
	if not extras.has("packed_scene"):
		return
	var path: String = extras["packed_scene"]
	if path.is_empty():
		return
	var scene: PackedScene = load(path)
	if scene == null:
		push_warning("PackedSceneHandler: failed to load " + path)
		return
	var inst := scene.instantiate()
	inst.name = "PackedScene_" + str(node.name)
	var parent := node.get_parent()
	if parent:
		parent.add_child(inst)
	if inst is Node3D and node is Node3D:
		(inst as Node3D).global_transform = (node as Node3D).global_transform
	ctx.deferred_deletes.append(node)
