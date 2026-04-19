@tool
class_name PackedSceneHandler
extends RefCounted

static func apply(node: Node, extras: Dictionary, ctx: PipelineContext) -> void:
	if not extras.has("packed_scene"):
		return
	var raw: Variant = extras["packed_scene"]
	if not raw is String:
		return
	var path: String = raw as String
	if path.is_empty():
		return
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		push_warning("PackedSceneHandler: failed to load " + path)
		return
	var inst: Node = scene.instantiate()
	inst.name = "PackedScene_" + str(node.name)
	var parent: Node = node.get_parent()
	if parent:
		parent.add_child(inst)
	if inst is Node3D and node is Node3D:
		# Prefer global_transform so nested Spawn markers end up where the
		# user placed them in Blender, but global_transform is only valid
		# once the node is in a SceneTree. Import context (including GUT
		# headless tests) runs outside a SceneTree — fall back to local.
		var n3: Node3D = node as Node3D
		var i3: Node3D = inst as Node3D
		if n3.is_inside_tree():
			i3.global_transform = n3.global_transform
		else:
			i3.transform = n3.transform
	ctx.deferred_deletes.append(node)
