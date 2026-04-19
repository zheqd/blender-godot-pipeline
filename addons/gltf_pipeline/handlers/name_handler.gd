@tool
class_name NameHandler
extends RefCounted

static func apply(node: Node, extras: Dictionary) -> void:
	var override = extras.get("name_override", "")
	if override is String and override != "":
		node.name = override
