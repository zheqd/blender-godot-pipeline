@tool
class_name SceneGlobalsHandler
extends RefCounted

static func apply_individual_origins(root: Node) -> void:
	for child in root.get_children():
		if child is Node3D:
			_set_world_zero(child as Node3D)

static func apply_packed_resources(root: Node, save_dir: String, preserve_origin: bool) -> void:
	DirAccess.make_dir_recursive_absolute(save_dir)
	# If caller already ran apply_individual_origins, world positions here are
	# Vector3.ZERO. preserve_origin=true then re-applies that zero to each
	# packed instance, keeping the intended "every root at origin" layout.
	var children := []
	for c in root.get_children(): children.append(c)
	for child in children:
		if not (child is Node3D): continue
		var c3 := child as Node3D
		var preserve: Vector3 = _world_position(c3)
		_set_ownership_recursive(child, child)
		var ps := PackedScene.new()
		var err := ps.pack(child)
		if err != OK:
			push_warning("packed_resources: pack failed for " + str(child.name))
			continue
		var scene_path := save_dir + "/" + str(child.name) + ".tscn"
		var save_err := ResourceSaver.save(ps, scene_path)
		if save_err != OK:
			push_warning("packed_resources: save failed for %s err=%d" % [scene_path, save_err])
			continue
		var inst := (load(scene_path) as PackedScene).instantiate()
		inst.name = "PackedScene_" + str(child.name)
		root.add_child(inst)
		if preserve_origin and inst is Node3D:
			_set_world_position(inst as Node3D, preserve)
		root.remove_child(child)
		child.queue_free()

# Read world position if the node is in a SceneTree; otherwise return the
# local position (valid fallback when root is at identity, which it is for
# GLTF-imported scenes).
static func _world_position(n: Node3D) -> Vector3:
	if n.is_inside_tree():
		return n.global_position
	return n.position

static func _set_world_position(n: Node3D, p: Vector3) -> void:
	if n.is_inside_tree():
		n.global_position = p
	else:
		n.position = p

static func _set_world_zero(n: Node3D) -> void:
	_set_world_position(n, Vector3.ZERO)

static func _set_ownership_recursive(node: Node, owner: Node) -> void:
	# Post-order: set owner on descendants before their ancestors so that
	# PackedScene.pack() captures the full subtree (it skips nodes whose
	# owner is not the pack root).
	for c in node.get_children():
		_set_ownership_recursive(c, owner)
		c.owner = owner
