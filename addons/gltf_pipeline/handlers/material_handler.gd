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
		# Duplicate before mutating so the shared cached resource is not modified.
		# (v2.5.5 parity trap: that version mutated in place, causing the shader
		# to bleed into every other node loading this material path.)
		if extras.has("shader") and mat is ShaderMaterial:
			var shader_path = extras["shader"]
			if shader_path is String and not shader_path.is_empty():
				var shader: Shader = load(shader_path)
				if shader:
					var sm := (mat as ShaderMaterial).duplicate() as ShaderMaterial
					sm.shader = shader
					mat = sm
		_MeshUtils.set_surface_material(node, i, mat)
