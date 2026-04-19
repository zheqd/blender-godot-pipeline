@tool
class_name MeshUtils
extends RefCounted

# In _import_post, mesh nodes are typically ImporterMeshInstance3D. They only
# get converted to MeshInstance3D when the scene is later instantiated. Every
# handler that reads/writes the mesh must accept both.

static func is_mesh_instance(node: Node) -> bool:
	return node is MeshInstance3D or node is ImporterMeshInstance3D

static func get_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D:
		return (node as MeshInstance3D).mesh
	if node is ImporterMeshInstance3D:
		var im = (node as ImporterMeshInstance3D).mesh
		if im != null:
			return im.get_mesh()
	return null

static func set_mesh(node: Node, mesh: Mesh) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).mesh = mesh

static func set_surface_material(node: Node, idx: int, mat: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).set_surface_override_material(idx, mat)
	elif node is ImporterMeshInstance3D:
		var im = (node as ImporterMeshInstance3D).mesh
		if im != null and idx < im.get_surface_count():
			im.set_surface_material(idx, mat)

static func get_surface_material(node: Node, idx: int) -> Material:
	if node is MeshInstance3D:
		return (node as MeshInstance3D).get_surface_override_material(idx)
	if node is ImporterMeshInstance3D:
		var im = (node as ImporterMeshInstance3D).mesh
		if im != null and idx < im.get_surface_count():
			return im.get_surface_material(idx)
	return null

# Replace every ImporterMeshInstance3D in the tree with a real MeshInstance3D
# in-place, preserving name / transform / mesh / surface materials / metadata.
#
# Why: Godot's GLTF import converts ImporterMeshInstance3D → MeshInstance3D
# at the END of generate_scene(), AFTER our _import_post hook. That engine
# conversion silently drops any script we set on the original node (meta
# is preserved, script is not). By materializing ourselves up front, the
# node is already MeshInstance3D before any handler touches it, so
# set_script and set_surface_override_material stick through to the final
# scene tree.
static func materialize_all(root: Node) -> void:
	# Snapshot first; we're about to mutate parent.children.
	var targets: Array[ImporterMeshInstance3D] = []
	_collect_importer_instances(root, targets)
	for old in targets:
		_materialize_one(old)

static func _collect_importer_instances(node: Node, out: Array[ImporterMeshInstance3D]) -> void:
	if node is ImporterMeshInstance3D:
		out.append(node)
	for c in node.get_children():
		_collect_importer_instances(c, out)

static func _materialize_one(old: ImporterMeshInstance3D) -> void:
	var parent := old.get_parent()
	if parent == null:
		return
	var idx := old.get_index()

	var mi := MeshInstance3D.new()
	mi.name = old.name
	mi.transform = old.transform

	var im := old.mesh
	if im != null:
		mi.mesh = im.get_mesh()
		# Mirror ImporterMesh per-surface materials onto override slots so
		# any pre-existing material assignment survives the swap.
		for i in range(im.get_surface_count()):
			var m := im.get_surface_material(i)
			if m != null:
				mi.set_surface_override_material(i, m)

	# Copy all metadata, including "extras".
	for k in old.get_meta_list():
		mi.set_meta(k, old.get_meta(k))

	# Move old's children to the new node (in order).
	var children := old.get_children()
	for c in children:
		old.remove_child(c)
		mi.add_child(c)

	parent.remove_child(old)
	parent.add_child(mi)
	parent.move_child(mi, idx)
	old.free()
