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
const _MeshUtils = preload("res://addons/gltf_pipeline/mesh_utils.gd")

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
	# Pre-convert ImporterMeshInstance3D → MeshInstance3D so subsequent
	# handler changes (set_script, set_surface_override_material, etc.)
	# survive the engine's own conversion pass that runs at the end of
	# generate_scene().
	_MeshUtils.materialize_all(root)
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
	_assign_owners(root, root)
	return OK

# Set owner=scene_root on every descendant that doesn't already have one, so
# Godot persists them when the imported scene is baked to .scn. Skip recursion
# into packed-scene instance roots: those subtrees already own each other via
# the instance root, and re-owning them would break instance semantics.
func _assign_owners(node: Node, scene_root: Node) -> void:
	for child in node.get_children():
		if child.owner == null:
			child.owner = scene_root
		# Recurse into every child EXCEPT instanced packed-scene roots.
		if child.scene_file_path == "":
			_assign_owners(child, scene_root)

func _derive_packed_dir(state: GLTFState) -> String:
	# GLTFState.filename in Godot 4.6.2 is the basename without extension
	# (e.g. "globals"); GLTFState.base_path is the directory containing the
	# imported .gltf (e.g. "res://test/fixtures/scene_globals"). We want the
	# latter so packed scenes land next to the source file.
	if state:
		var bp: String = ""
		if "base_path" in state:
			bp = state.base_path
		if bp != "":
			return bp + "/packed_scenes"
	return "res://packed_scenes"

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
	# Consumer handlers are mutually exclusive: each deletes `node` and spawns
	# replacements, so running more than one produces undefined state.
	# Priority (deterministic): collision > nav_mesh > multimesh > packed_scene.
	if _count_consumers(extras) > 1:
		push_warning("Pipeline: node '%s' specifies multiple consumer extras [%s]; only the highest-priority one will run." % [node.name, ", ".join(_consumer_keys(extras))])
	if extras.has("collision"):
		# Material applies to the body's duplicated mesh node, so still run it.
		_MaterialHandler.apply(node, extras)
		_CollisionHandler.apply(node, extras, ctx)
	elif extras.has("nav_mesh"):
		_NavMeshHandler.apply(node, extras, ctx)
	elif extras.has("multimesh"):
		_MultimeshHandler.collect(node, extras, ctx)
	elif extras.has("packed_scene"):
		_PackedSceneHandler.apply(node, extras, ctx)
	else:
		# No consumer handler — apply material to the node itself.
		_MaterialHandler.apply(node, extras)

static func _count_consumers(extras: Dictionary) -> int:
	var n := 0
	if extras.has("collision"): n += 1
	if extras.has("nav_mesh"): n += 1
	if extras.has("multimesh"): n += 1
	if extras.has("packed_scene"): n += 1
	return n

static func _consumer_keys(extras: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for k: String in ["collision", "nav_mesh", "multimesh", "packed_scene"]:
		if extras.has(k): out.append(k)
	return out

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
