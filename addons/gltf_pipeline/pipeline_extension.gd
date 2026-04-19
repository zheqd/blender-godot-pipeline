@tool
extends GLTFDocumentExtension
class_name PipelineGLTFExtension

const _ExtrasReader = preload("res://addons/gltf_pipeline/extras_reader.gd")
const _StateHandler = preload("res://addons/gltf_pipeline/handlers/state_handler.gd")
const _NameHandler = preload("res://addons/gltf_pipeline/handlers/name_handler.gd")
const _ScriptHandler = preload("res://addons/gltf_pipeline/handlers/script_handler.gd")
const _MaterialHandler = preload("res://addons/gltf_pipeline/handlers/material_handler.gd")
const _CollisionHandler = preload("res://addons/gltf_pipeline/handlers/collision_handler.gd")
const _NavMeshHandler = preload("res://addons/gltf_pipeline/handlers/navmesh_handler.gd")
const _MultimeshHandler = preload("res://addons/gltf_pipeline/handlers/multimesh_handler.gd")
const _PackedSceneHandler = preload("res://addons/gltf_pipeline/handlers/packed_scene_handler.gd")
const _SceneGlobalsHandler = preload("res://addons/gltf_pipeline/handlers/scene_globals_handler.gd")

class PipelineContext:
	var state: GLTFState
	var root: Node
	var scene_extras: Dictionary = {}
	var multimesh_groups: Dictionary = {}
	var deferred_deletes: Array[Node] = []
	var deferred_reparents: Array = []
	var gltf_path: String = ""

# Test hooks. Set from unit tests to intercept or observe.
var _visit_for_test: Callable = Callable()
var _last_ctx: PipelineContext = null

func _import_post(state: GLTFState, root: Node) -> int:
	if root == null:
		return OK
	var ctx := PipelineContext.new()
	ctx.state = state
	ctx.root = root
	ctx.scene_extras = _extract_scene_extras(state)
	_last_ctx = ctx
	_walk_post_order(root, ctx)
	_MultimeshHandler.emit_all(root, ctx)
	_flush(ctx)
	if ctx.scene_extras.get("individual_origins", 0) == 1:
		_SceneGlobalsHandler.apply_individual_origins(root)
	if ctx.scene_extras.get("packed_resources", 0) == 1:
		var save_dir := _derive_packed_dir(state)
		var preserve: bool = ctx.scene_extras.get("individual_origins", 0) == 1
		_SceneGlobalsHandler.apply_packed_resources(root, save_dir, preserve)
	return OK

func _derive_packed_dir(state: GLTFState) -> String:
	var base := "res://packed_scenes"
	if state:
		var fn: String = ""
		if "filename" in state:
			fn = state.filename
		if fn != "":
			base = fn.get_base_dir() + "/packed_scenes"
	return base

func _extract_scene_extras(state: GLTFState) -> Dictionary:
	if state == null or state.json == null:
		return {}
	var scenes = state.json.get("scenes", [])
	if scenes is Array and scenes.size() > 0:
		var s = scenes[0]
		if s is Dictionary:
			var extras = s.get("extras", {})
			if extras is Dictionary:
				var props = extras.get("GodotPipelineProps", {})
				if props is Dictionary:
					return props
	return {}

func _walk_post_order(node: Node, ctx: PipelineContext) -> void:
	var children := node.get_children()
	for child in children:
		_walk_post_order(child, ctx)
	_dispatch(node, ctx)

func _dispatch(node: Node, ctx: PipelineContext) -> void:
	if _visit_for_test.is_valid():
		_visit_for_test.call(node)
	var extras := _ExtrasReader.get_extras(node)
	if extras.is_empty():
		return
	_StateHandler.apply(node, extras)
	if not is_instance_valid(node):
		return
	_NameHandler.apply(node, extras)
	if not extras.has("collision") and not extras.has("nav_mesh"):
		_ScriptHandler.apply(node, extras)
	_MaterialHandler.apply(node, extras)
	if extras.has("collision"):
		_CollisionHandler.apply(node, extras, ctx)
	if extras.has("nav_mesh"):
		_NavMeshHandler.apply(node, extras, ctx)
	if extras.has("multimesh"):
		_MultimeshHandler.collect(node, extras, ctx)
	if extras.has("packed_scene"):
		_PackedSceneHandler.apply(node, extras, ctx)

func _flush(ctx: PipelineContext) -> void:
	for pair in ctx.deferred_reparents:
		var child: Node = pair[0]
		var new_parent: Node = pair[1]
		var old_parent := child.get_parent()
		if old_parent:
			old_parent.remove_child(child)
		new_parent.add_child(child)
	for n in ctx.deferred_deletes:
		if is_instance_valid(n):
			var p := n.get_parent()
			if p:
				p.remove_child(n)
			n.queue_free()
