@tool
class_name SceneGlobalsHandler
extends RefCounted

static func apply_individual_origins(root: Node) -> void:
	for child in root.get_children():
		if child is Node3D:
			(child as Node3D).global_position = Vector3.ZERO

static func apply_packed_resources(root: Node, save_dir: String, preserve_origin: bool) -> void:
	DirAccess.make_dir_recursive_absolute(save_dir)
	var children := []
	for c in root.get_children(): children.append(c)
	for child in children:
		if not (child is Node3D): continue
		var c3 := child as Node3D
		var preserve: Vector3 = c3.global_position
		_set_ownership_recursive(child, child)
		var ps := PackedScene.new()
		var err := ps.pack(child)
		if err != OK:
			push_warning("packed_resources: pack failed for " + str(child.name))
			continue
		var scene_path := save_dir + "/" + str(child.name) + ".tscn"
		var save_err := ResourceSaver.save(ps, scene_path)
		if save_err != OK:
			push_warning("packed_resources: save failed for " + scene_path)
			continue
		var inst := (load(scene_path) as PackedScene).instantiate()
		inst.name = "PackedScene_" + str(child.name)
		root.add_child(inst)
		if preserve_origin and inst is Node3D:
			(inst as Node3D).global_position = preserve
		root.remove_child(child)
		child.queue_free()

static func _set_ownership_recursive(node: Node, owner: Node) -> void:
	for c in node.get_children():
		_set_ownership_recursive(c, owner)
		c.owner = owner
