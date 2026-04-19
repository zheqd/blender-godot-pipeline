@tool
class_name NavMeshHandler
extends RefCounted

const _ExpressionApplier = preload("res://addons/gltf_pipeline/expression_applier.gd")

static func apply(node: Node, extras: Dictionary, ctx) -> void:
	if not (node is MeshInstance3D):
		return
	if not extras.has("nav_mesh"):
		return
	var save_path: String = extras["nav_mesh"]
	if save_path.is_empty():
		return
	var mi := node as MeshInstance3D
	if mi.mesh == null:
		push_warning("NavMeshHandler: MeshInstance has no mesh")
		return
	mi.mesh.resource_name = mi.name + "_NavMesh"
	ResourceSaver.save(mi.mesh, save_path)

	var navmesh := NavigationMesh.new()
	navmesh.create_from_mesh(mi.mesh)

	var region := NavigationRegion3D.new()
	region.navigation_mesh = navmesh
	region.transform = mi.transform
	region.name = str(mi.name) + "_NavMesh"

	if extras.has("prop_file"):
		var pf = extras["prop_file"]
		if pf is String and not pf.is_empty():
			_ExpressionApplier.apply_file(region, pf)

	var parent := mi.get_parent()
	if parent:
		parent.add_child(region)
	ctx.deferred_deletes.append(mi)
