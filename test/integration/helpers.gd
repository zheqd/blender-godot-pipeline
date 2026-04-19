@tool
class_name PipelineTestHelpers
extends RefCounted

const _PipelineGLTFExtension = preload("res://addons/gltf_pipeline/pipeline_extension.gd")

# Imports a .gltf with the pipeline extension registered.
# In headless test mode the EditorPlugin doesn't load, so we register the
# extension ourselves for the duration of the call. In-editor importing
# uses the plugin's own registration and this helper is not involved.
static func import_gltf(path: String) -> Node:
	var ext = _PipelineGLTFExtension.new()
	GLTFDocument.register_gltf_document_extension(ext, true)
	var result: Node = null
	var gltf := GLTFDocument.new()
	var state := GLTFState.new()
	var err := gltf.append_from_file(path, state)
	if err == OK:
		result = gltf.generate_scene(state)
	else:
		push_error("Failed to load " + path + " err=" + str(err))
	GLTFDocument.unregister_gltf_document_extension(ext)
	return result
