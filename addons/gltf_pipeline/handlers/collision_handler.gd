@tool
class_name CollisionHandler
extends RefCounted

const _ExpressionApplier = preload("res://addons/gltf_pipeline/expression_applier.gd")
const _PhysicsMaterialHandler = preload("res://addons/gltf_pipeline/handlers/physics_material_handler.gd")
const _MeshUtils = preload("res://addons/gltf_pipeline/mesh_utils.gd")

static func make_body(col: String, base_name: String) -> Node:
	if col.find("-c") != -1:
		return null
	if col.find("-r") != -1:
		var b := RigidBody3D.new()
		b.name = "RigidBody3D_" + base_name
		return b
	if col.find("-a") != -1:
		var a := Area3D.new()
		a.name = "Area3D_" + base_name
		return a
	if col.find("-m") != -1:
		var m := AnimatableBody3D.new()
		m.name = "AnimatableBody3D_" + base_name
		return m
	if col.find("-h") != -1:
		var h := CharacterBody3D.new()
		h.name = "CharacterBody3D_" + base_name
		return h
	var s := StaticBody3D.new()
	s.name = "StaticBody3D_" + base_name
	return s

static func make_shape(col: String, node: Node, extras: Dictionary) -> Shape3D:
	var base := col.split("-")[0]
	match base:
		"box":
			if not (extras.has("size_x") and extras.has("size_y") and extras.has("size_z")):
				return null
			var s_box := BoxShape3D.new()
			s_box.size = Vector3(
				float(extras["size_x"]),
				float(extras["size_y"]),
				float(extras["size_z"])
			)
			return s_box
		"sphere":
			if not extras.has("radius"):
				return null
			var s_sphere := SphereShape3D.new()
			s_sphere.radius = float(extras["radius"])
			return s_sphere
		"capsule":
			if not (extras.has("height") and extras.has("radius")):
				return null
			var s_capsule := CapsuleShape3D.new()
			s_capsule.height = float(extras["height"])
			s_capsule.radius = float(extras["radius"])
			return s_capsule
		"cylinder":
			if not (extras.has("height") and extras.has("radius")):
				return null
			var s_cylinder := CylinderShape3D.new()
			s_cylinder.height = float(extras["height"])
			s_cylinder.radius = float(extras["radius"])
			return s_cylinder
		"trimesh":
			var tm: Mesh = _MeshUtils.get_mesh(node)
			if tm:
				return tm.create_trimesh_shape()
			return null
		"simple":
			var sm: Mesh = _MeshUtils.get_mesh(node)
			if sm:
				return sm.create_convex_shape()
			return null
	return null

static func apply(node: Node, extras: Dictionary, ctx) -> void:
	if not extras.has("collision"):
		return
	var col: String = str(extras["collision"])
	var simple := "simple" in col
	var trimesh := "trimesh" in col
	var bodyonly := "bodyonly" in col
	var discard_mesh := "-d" in col
	var col_only := "-c" in col

	var body := make_body(col, node.name)
	var shape := make_shape(col, node, extras)
	var parent := node.get_parent()

	# Create CollisionShape3D unless "bodyonly"
	var cs: CollisionShape3D = null
	if not bodyonly:
		if shape == null:
			push_warning("CollisionHandler: shape build failed for %s (col=%s)" % [node.name, col])
			return
		cs = CollisionShape3D.new()
		cs.name = "CollisionShape3D_" + str(node.name)
		cs.shape = shape
		if Engine.get_version_info().hex >= 0x040400:
			cs.debug_fill = false

		if node is Node3D:
			cs.scale = (node as Node3D).scale
			cs.rotation = (node as Node3D).rotation

		# Center offset only on primitives (not simple, not trimesh)
		if not simple and not trimesh and _has_all(extras, ["center_x", "center_y", "center_z"]):
			var cx := float(extras["center_x"])
			var cy := float(extras["center_y"])
			var cz := -float(extras["center_z"])
			cs.position += Vector3(cx, cy, cz)

	if col_only:
		for k: String in ["script", "prop_file", "prop_string", "physics_mat"]:
			if extras.has(k):
				push_warning("CollisionHandler: '%s' on node '%s' is ignored because collision mode includes '-c' (no body is created). Remove '-c' or drop '%s'." % [k, node.name, k])
		if cs:
			parent.add_child(cs)
			if node is Node3D:
				cs.position = (node as Node3D).position + cs.position
	else:
		if body == null:
			return
		if node is Node3D:
			body.position = (node as Node3D).position
		if cs:
			body.add_child(cs)
		if not discard_mesh and _MeshUtils.is_mesh_instance(node):
			var nd := node.duplicate() as Node3D
			for c in nd.get_children():
				nd.remove_child(c)
				c.queue_free()
			nd.transform = Transform3D()
			nd.scale = (node as Node3D).scale
			nd.rotation = (node as Node3D).rotation
			body.add_child(nd)
		parent.add_child(body)

		for child in node.get_children():
			if child is CollisionShape3D:
				ctx.deferred_reparents.append([child, body])

		# Apply script/prop_*/physics_mat to BODY
		if extras.has("script"):
			var sp = extras["script"]
			if sp is String and not sp.is_empty():
				var sc = load(sp)
				if sc:
					body.set_script(sc)
		if extras.has("prop_file"):
			var pf = extras["prop_file"]
			if pf is String and not pf.is_empty():
				_ExpressionApplier.apply_file(body, pf)
		if extras.has("prop_string"):
			var ps = extras["prop_string"]
			if ps is String and not ps.is_empty():
				_ExpressionApplier.apply_string(body, ps)
		if extras.has("physics_mat"):
			var pm = extras["physics_mat"]
			if pm is String and not pm.is_empty():
				_PhysicsMaterialHandler.apply(body, pm)

	ctx.deferred_deletes.append(node)

static func _has_all(d: Dictionary, keys: Array) -> bool:
	for k in keys:
		if not d.has(k):
			return false
	return true
