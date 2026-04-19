@tool
class_name ScriptHandler
extends RefCounted

const _ExpressionApplier: GDScript = preload("res://addons/gltf_pipeline/expression_applier.gd")

static func apply(node: Node, extras: Dictionary) -> void:
	if not extras.has("script"):
		_apply_props_only(node, extras)
		return
	var raw: Variant = extras["script"]
	if not raw is String or (raw as String).is_empty():
		_apply_props_only(node, extras)
		return
	var path: String = raw as String
	var script: Script = load(path) as Script
	if script == null:
		push_warning("ScriptHandler: failed to load " + path)
		_apply_props_only(node, extras)
		return
	node.set_script(script)
	_apply_props_only(node, extras)

static func _apply_props_only(node: Node, extras: Dictionary) -> void:
	if extras.has("prop_file"):
		var p: Variant = extras["prop_file"]
		if p is String and not (p as String).is_empty():
			_ExpressionApplier.apply_file(node, p as String)
	if extras.has("prop_string"):
		var s: Variant = extras["prop_string"]
		if s is String and not (s as String).is_empty():
			_ExpressionApplier.apply_string(node, s as String)
