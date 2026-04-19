@tool
class_name NameHandler
extends RefCounted

static func apply(node: Node, extras: Dictionary) -> void:
	var override: Variant = extras.get("name_override", "")
	if override is String and (override as String) != "":
		node.name = override as String
