@tool
class_name StateHandler
extends RefCounted

static func apply(node: Node, extras: Dictionary) -> void:
	var state: Variant = extras.get("state", "")
	match state:
		"skip":
			var parent: Node = node.get_parent()
			if parent:
				parent.remove_child(node)
				node.queue_free()
		"hide":
			if node is Node3D:
				(node as Node3D).visible = false
			elif node is CanvasItem:
				(node as CanvasItem).visible = false
