@tool
class_name ScriptHandler
extends RefCounted

const _ExpressionApplier = preload("res://addons/gltf_pipeline/expression_applier.gd")

static func apply(node: Node, extras: Dictionary) -> void:
	if not extras.has("script"):
		_apply_props_only(node, extras)
		return
	var path = extras["script"]
	if not (path is String) or path.is_empty():
		_apply_props_only(node, extras)
		return
	var script = load(path)
	if script == null:
		push_warning("ScriptHandler: failed to load " + path)
		_apply_props_only(node, extras)
		return
	node.set_script(script)
	_apply_props_only(node, extras)

static func _apply_props_only(node: Node, extras: Dictionary) -> void:
	if extras.has("prop_file"):
		var p = extras["prop_file"]
		if p is String and not p.is_empty():
			_ExpressionApplier.apply_file(node, p)
	if extras.has("prop_string"):
		var s = extras["prop_string"]
		if s is String and not s.is_empty():
			_ExpressionApplier.apply_string(node, s)
