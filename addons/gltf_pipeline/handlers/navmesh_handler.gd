@tool
class_name NavMeshHandler
extends RefCounted

const _ExpressionApplier = preload("res://addons/gltf_pipeline/expression_applier.gd")
const _MeshUtils = preload("res://addons/gltf_pipeline/mesh_utils.gd")

static func apply(node: Node, extras: Dictionary, ctx) -> void:
	if not _MeshUtils.is_mesh_instance(node):
		return
	if not extras.has("nav_mesh"):
		return
	var save_path: String = extras["nav_mesh"]
	if save_path.is_empty():
		return
	var mesh: Mesh = _MeshUtils.get_mesh(node)
	if mesh == null:
		push_warning("NavMeshHandler: MeshInstance has no mesh")
		return
	mesh.resource_name = str(node.name) + "_NavMesh"
	ResourceSaver.save(mesh, save_path)

	var navmesh := NavigationMesh.new()
	navmesh.create_from_mesh(mesh)

	var region := NavigationRegion3D.new()
	region.navigation_mesh = navmesh
	if node is Node3D:
		region.transform = (node as Node3D).transform
	region.name = str(node.name) + "_NavMesh"

	if extras.has("prop_file"):
		var pf = extras["prop_file"]
		if pf is String and not pf.is_empty():
			_ExpressionApplier.apply_file(region, pf)

	var parent := node.get_parent()
	if parent:
		parent.add_child(region)
	ctx.deferred_deletes.append(node)
