@tool
class_name MultimeshHandler
extends RefCounted

static func collect(node: Node, extras: Dictionary, ctx) -> void:
	if not (node is MeshInstance3D):
		return
	if not extras.has("multimesh"):
		return
	var path: String = extras["multimesh"]
	if path.is_empty():
		return
	var mi := node as MeshInstance3D
	if not ctx.multimesh_groups.has(path):
		ctx.multimesh_groups[path] = []
		if mi.mesh:
			mi.mesh.resource_name = mi.name
			ResourceSaver.save(mi.mesh, path)
			mi.mesh.take_over_path(path)
	ctx.multimesh_groups[path].append(mi.transform)
	ctx.deferred_deletes.append(mi)

static func emit_all(root: Node, ctx) -> void:
	for path in ctx.multimesh_groups.keys():
		var transforms: Array = ctx.multimesh_groups[path]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.instance_count = transforms.size()
		for i in range(transforms.size()):
			mm.set_instance_transform(i, transforms[i])
		mm.mesh = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		var mm_inst := MultiMeshInstance3D.new()
		mm_inst.multimesh = mm
		var nm := "Multimesh"
		if mm.mesh and mm.mesh.resource_name != "":
			nm = mm.mesh.resource_name + "_Multimesh"
		mm_inst.name = nm
		root.add_child(mm_inst)
