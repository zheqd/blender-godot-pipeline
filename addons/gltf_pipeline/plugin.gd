@tool
extends EditorPlugin

var _extension: PipelineGLTFExtension

func _enter_tree() -> void:
	_extension = PipelineGLTFExtension.new()
	GLTFDocument.register_gltf_document_extension(_extension, true)

func _exit_tree() -> void:
	if _extension:
		GLTFDocument.unregister_gltf_document_extension(_extension)
		_extension = null
