@tool
class_name ExtrasReader
extends RefCounted

static func get_extras(node: Node) -> Dictionary:
	var merged: Dictionary = {}
	if node is MeshInstance3D:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh and mesh.has_meta("extras"):
			var mesh_extras = mesh.get_meta("extras")
			if mesh_extras is Dictionary:
				merged.merge(mesh_extras, true)
	if node.has_meta("extras"):
		var node_extras = node.get_meta("extras")
		if node_extras is Dictionary:
			# Node-level wins: merge with overwrite=true
			merged.merge(node_extras, true)
	return merged
