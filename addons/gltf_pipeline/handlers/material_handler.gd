@tool
class_name MaterialHandler
extends RefCounted

const _MeshUtils = preload("res://addons/gltf_pipeline/mesh_utils.gd")

static func apply(node: Node, extras: Dictionary) -> void:
	if not _MeshUtils.is_mesh_instance(node):
		return
	for i in range(4):
		var key := "material_%d" % i
		if not extras.has(key):
			continue
		var path = extras[key]
		if not (path is String) or path.is_empty():
			continue
		var mat: Material = load(path)
		if mat == null:
			push_warning("MaterialHandler: failed to load " + path)
			continue
		# Apply shader override onto the material BEFORE binding, if requested.
		if extras.has("shader"):
			var shader_path = extras["shader"]
			if shader_path is String and not shader_path.is_empty() and mat is ShaderMaterial:
				var shader: Shader = load(shader_path)
				if shader:
					(mat as ShaderMaterial).shader = shader
		_MeshUtils.set_surface_material(node, i, mat)
