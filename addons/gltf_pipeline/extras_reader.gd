@tool
class_name ExtrasReader
extends RefCounted

const _MeshUtils: GDScript = preload("res://addons/gltf_pipeline/mesh_utils.gd")

static func get_extras(node: Node) -> Dictionary:
	var merged: Dictionary = {}
	if _MeshUtils.is_mesh_instance(node):
		var mesh: Mesh = _MeshUtils.get_mesh(node)
		if mesh and mesh.has_meta("extras"):
			var mesh_extras: Variant = mesh.get_meta("extras")
			if mesh_extras is Dictionary:
				merged.merge(mesh_extras as Dictionary, true)
		# ImporterMeshInstance3D may carry extras on the ImporterMesh itself
		# (not the runtime ArrayMesh), so read from it too when available.
		if node is ImporterMeshInstance3D:
			var im: ImporterMesh = (node as ImporterMeshInstance3D).mesh
			if im and im.has_meta("extras"):
				var im_extras: Variant = im.get_meta("extras")
				if im_extras is Dictionary:
					merged.merge(im_extras as Dictionary, true)
	if node.has_meta("extras"):
		var node_extras: Variant = node.get_meta("extras")
		if node_extras is Dictionary:
			# Node-level wins: merge with overwrite=true
			merged.merge(node_extras as Dictionary, true)
	return merged
