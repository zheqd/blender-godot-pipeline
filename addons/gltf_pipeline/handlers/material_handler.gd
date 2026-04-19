@tool
class_name MaterialHandler
extends RefCounted

const _MeshUtils: GDScript = preload("res://addons/gltf_pipeline/mesh_utils.gd")

static func apply(node: Node, extras: Dictionary) -> void:
	if not _MeshUtils.is_mesh_instance(node):
		return
	for i: int in range(4):
		var key: String = "material_%d" % i
		if not extras.has(key):
			continue
		var raw: Variant = extras[key]
		if not raw is String or (raw as String).is_empty():
			continue
		var path: String = raw as String
		var mat: Material = load(path) as Material
		if mat == null:
			push_warning("MaterialHandler: failed to load " + path)
			continue
		# Duplicate before mutating so the shared cached resource is not modified.
		# (v2.5.5 parity trap: that version mutated in place, causing the shader
		# to bleed into every other node loading this material path.)
		if extras.has("shader") and mat is ShaderMaterial:
			var shader_raw: Variant = extras["shader"]
			if shader_raw is String and not (shader_raw as String).is_empty():
				var shader: Shader = load(shader_raw as String) as Shader
				if shader:
					var sm: ShaderMaterial = (mat as ShaderMaterial).duplicate() as ShaderMaterial
					sm.shader = shader
					mat = sm
		_MeshUtils.set_surface_material(node, i, mat)
