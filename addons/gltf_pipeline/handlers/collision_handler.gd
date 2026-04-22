## Creates physics bodies and collision shapes from the [code]collision[/code] extra.
##
## The [code]collision[/code] value is a terse string encoding both the body type
## and shape type, e.g. [code]"box-r"[/code] (BoxShape3D inside RigidBody3D) or
## [code]"trimesh"[/code] (trimesh StaticBody3D). Flags after the hyphen select
## the body type:
## [codeblock]
## -r  RigidBody3D        -a  Area3D
## -m  AnimatableBody3D   -h  CharacterBody3D
## -c  don't wrap the mesh — emit body (if any) and shape as orphan siblings
## -d  discard mesh node after building body
## [/codeblock]
## When [code]-c[/code] is combined with a body flag ([code]-r[/code],
## [code]-a[/code], [code]-m[/code], [code]-h[/code]), the requested body is
## produced as a sibling of the orphan shape rather than wrapping the mesh.
## This supports nested-gltf composition: a collider-only [code].gltf[/code]
## contributes orphan bodies/shapes that a consuming scene adopts by ancestry.
## Pure [code]-c[/code] (no body flag) produces only an orphan shape.
##
## Shape keywords before the hyphen: [code]box[/code], [code]sphere[/code],
## [code]capsule[/code], [code]cylinder[/code], [code]trimesh[/code],
## [code]simple[/code] (convex hull). Default (no keyword) is StaticBody3D with
## a trimesh shape. The [code]bodyonly[/code] keyword suppresses shape creation
## entirely; combining it with [code]-c[/code] and no body flag produces
## nothing and emits a warning.
##
## Because this handler deletes the original node and inserts a new subtree,
## it is a "consumer" handler — only one consumer may run per node.
@tool
class_name CollisionHandler
extends RefCounted

const _ExpressionApplier: GDScript = preload("res://addons/gltf_pipeline/expression_applier.gd")
const _PhysicsMaterialHandler: GDScript = preload("res://addons/gltf_pipeline/handlers/physics_material_handler.gd")
const _MeshUtils: GDScript = preload("res://addons/gltf_pipeline/mesh_utils.gd")

## Returns the physics body node for [param col], or [code]null[/code] when
## [code]-c[/code] (col_only) is set and no explicit body flag is present.
## When [code]-c[/code] is combined with a body flag ([code]-r[/code],
## [code]-a[/code], [code]-m[/code], [code]-h[/code]), an orphan body of the
## requested type is returned — the [code]apply[/code] function places it as a
## sibling of the orphan shape rather than wrapping the mesh with it. 
static func make_body(col: String, base_name: String) -> Node:
	var has_body_flag: bool = (
		col.find("-r") != -1 or col.find("-a") != -1 or
		col.find("-m") != -1 or col.find("-h") != -1
	)
	if col.find("-c") != -1 and not has_body_flag:
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

## Builds a [Shape3D] from the shape keyword in [param col] and dimension extras.
## Returns [code]null[/code] if required dimension extras are absent.
static func make_shape(col: String, node: Node, extras: Dictionary) -> Shape3D:
	var base: String = col.split("-")[0]
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

static func apply(node: Node, extras: Dictionary, ctx: PipelineContext) -> void:
	if not extras.has("collision"):
		return
	var col: String = str(extras["collision"])
	var simple: bool = "simple" in col
	var trimesh: bool = "trimesh" in col
	var bodyonly: bool = "bodyonly" in col
	var discard_mesh: bool = "-d" in col
	var col_only: bool = "-c" in col
	var has_body_flag: bool = (
		"-r" in col or "-a" in col or "-m" in col or "-h" in col
	)

	if bodyonly and col_only and not has_body_flag:
		push_warning("CollisionHandler: '%s' has collision='%s' — bodyonly + -c with no body flag builds nothing and deletes the mesh. Remove 'collision' or add a body flag (-r/-a/-m/-h)." % [node.name, col])

	var body: Node = make_body(col, node.name)
	var shape: Shape3D = make_shape(col, node, extras)
	var parent: Node = node.get_parent()

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
		# Orphan body path: when a body flag (-r/-a/-m/-h) is combined with -c,
		# the body still gets constructed (see make_body) but is parented as a
		# sibling of the orphan shape rather than wrapping the mesh. This lets
		# a consuming scene compose body + shape independently.
		if body != null:
			parent.add_child(body)
			if node is Node3D:
				body.position = (node as Node3D).position
			# Body-targeting extras attach to the orphan body.
			_apply_body_extras(body, extras)
		else:
			# Pure -c (no body flag): body-targeting extras have nowhere to go.
			# Warn so the user understands why script/prop_*/physics_mat were ignored.
			for k: String in ["script", "prop_file", "prop_string", "physics_mat"]:
				if extras.has(k):
					push_warning("CollisionHandler: '%s' on node '%s' has no effect in col_only ('-c') mode with no body flag (-r/-a/-m/-h) - there is no body to attach it to. If this node provides orphan colliders to a parent scene's body, move '%s' to that parent. Otherwise add a body flag or drop '-c'." % [k, node.name, k])
		if cs:
			# Cascade-delete guard: if `parent` is itself being deleted (e.g. a
			# `bodyonly` ancestor whose handler already queued it), parenting the
			# orphan shape to it would destroy the shape when `_flush` frees
			# `parent`. Route the shape to the surviving replacement body (or
			# the nearest surviving ancestor) instead.
			var shape_host: Node = _resolve_shape_host(parent, ctx)
			shape_host.add_child(cs)
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
			var nd: Node3D = node.duplicate() as Node3D
			for c: Node in nd.get_children():
				nd.remove_child(c)
				c.free()
			nd.transform = Transform3D()
			nd.scale = (node as Node3D).scale
			nd.rotation = (node as Node3D).rotation
			body.add_child(nd)
		parent.add_child(body)

		for child: Node in node.get_children():
			if child is CollisionShape3D:
				ctx.deferred_reparents.append([child, body])

		# Apply script/prop_*/physics_mat to BODY
		_apply_body_extras(body, extras)

	ctx.deferred_deletes.append(node)

## Returns a surviving node to parent an orphan CollisionShape3D under.
## If [param start] is not queued for deletion, it survives flush — use it.
## Otherwise walk up the ancestry: for each ancestor that IS queued for
## deletion, check whether its parent contains a CollisionObject3D sibling
## whose name ends with "_<ancestor.name>" (the naming convention used by
## [method make_body]). That sibling is the body synthesized from the
## doomed ancestor and is the semantically correct host for the shape
## (matches the user's intent under the v2.5.5 Blender addon's
## bodyonly-parent + col_only-child composition pattern). If no such
## replacement body is found, fall back to the first ancestor that is not
## queued for deletion — the shape survives as a scene-level orphan rather
## than being destroyed by cascade.
static func _resolve_shape_host(start: Node, ctx: PipelineContext) -> Node:
	if not ctx.deferred_deletes.has(start):
		return start
	var doomed: Node = start
	while doomed != null and ctx.deferred_deletes.has(doomed):
		var grandparent: Node = doomed.get_parent()
		if grandparent == null:
			break
		var replacement_suffix: String = "_" + doomed.name
		for sibling: Node in grandparent.get_children():
			if sibling == doomed:
				continue
			if (sibling is CollisionObject3D) and sibling.name.ends_with(replacement_suffix):
				return sibling
		doomed = grandparent
	if doomed == null:
		return start
	return doomed

static func _apply_body_extras(body: Node, extras: Dictionary) -> void:
	if extras.has("script"):
		var sp: Variant = extras["script"]
		if sp is String and not (sp as String).is_empty():
			var sc: Script = load(sp as String) as Script
			if sc:
				body.set_script(sc)
	if extras.has("prop_file"):
		var pf: Variant = extras["prop_file"]
		if pf is String and not (pf as String).is_empty():
			_ExpressionApplier.apply_file(body, pf as String)
	if extras.has("prop_string"):
		var ps: Variant = extras["prop_string"]
		if ps is String and not (ps as String).is_empty():
			_ExpressionApplier.apply_string(body, ps as String)
	if extras.has("physics_mat"):
		var pm: Variant = extras["physics_mat"]
		if pm is String and not (pm as String).is_empty():
			_PhysicsMaterialHandler.apply(body, pm as String)

static func _has_all(d: Dictionary, keys: Array[String]) -> bool:
	for k: String in keys:
		if not d.has(k):
			return false
	return true
