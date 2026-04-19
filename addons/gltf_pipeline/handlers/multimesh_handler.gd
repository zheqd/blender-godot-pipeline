## Aggregates repeated mesh nodes into a single [MultiMeshInstance3D].
##
## Processing is split into two phases to handle nodes spread across the tree:
## [br]1. [method collect] — called per-node during the post-order walk; records
##    the node's transform and saves the mesh to [param path], then defers deletion
##    of the original node.
## [br]2. [method emit_all] — called once after the walk; builds a [MultiMesh]
##    from each group's collected transforms and attaches it to the scene root.
@tool
class_name MultimeshHandler
extends RefCounted

const _MeshUtils: GDScript = preload("res://addons/gltf_pipeline/mesh_utils.gd")

static func collect(node: Node, extras: Dictionary, ctx: PipelineContext) -> void:
	if not _MeshUtils.is_mesh_instance(node):
		return
	if not extras.has("multimesh"):
		return
	var path: String = extras["multimesh"]
	if path.is_empty():
		return
	var mesh: Mesh = _MeshUtils.get_mesh(node)
	if not ctx.multimesh_groups.has(path):
		ctx.multimesh_groups[path] = []
		if mesh:
			mesh.resource_name = str(node.name)
			ResourceSaver.save(mesh, path)
			mesh.take_over_path(path)
	var xform: Transform3D = (node as Node3D).transform if node is Node3D else Transform3D()
	ctx.multimesh_groups[path].append(xform)
	ctx.deferred_deletes.append(node)

static func emit_all(root: Node, ctx: PipelineContext) -> void:
	for path: String in ctx.multimesh_groups.keys():
		var transforms: Array = ctx.multimesh_groups[path]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
		mm.instance_count = transforms.size()
		for i: int in range(transforms.size()):
			mm.set_instance_transform(i, transforms[i] as Transform3D)
		var mm_inst := MultiMeshInstance3D.new()
		mm_inst.multimesh = mm
		var nm := "Multimesh"
		if mm.mesh and mm.mesh.resource_name != "":
			nm = mm.mesh.resource_name + "_Multimesh"
		mm_inst.name = nm
		root.add_child(mm_inst)
