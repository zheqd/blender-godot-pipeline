@tool
class_name MaterialHandler
extends RefCounted

static func apply(node: Node, extras: Dictionary) -> void:
	if not (node is MeshInstance3D):
		return
	var mi := node as MeshInstance3D
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
		mi.set_surface_override_material(i, mat)
