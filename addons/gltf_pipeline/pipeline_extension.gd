@tool
extends GLTFDocumentExtension
class_name PipelineGLTFExtension

class PipelineContext:
	var state: GLTFState
	var root: Node
	var scene_extras: Dictionary = {}
	var multimesh_groups: Dictionary = {}
	var deferred_deletes: Array[Node] = []
	var deferred_reparents: Array = []
	var gltf_path: String = ""

func _import_post(state: GLTFState, root: Node) -> int:
	if root == null:
		return OK
	var ctx := PipelineContext.new()
	ctx.state = state
	ctx.root = root
	return OK
