extends GutTest

const ExtrasReader = preload("res://addons/gltf_pipeline/extras_reader.gd")

func test_returns_empty_when_no_extras():
	var n := Node3D.new()
	assert_eq(ExtrasReader.get_extras(n), {}, "no meta → empty dict")
	n.free()

func test_returns_node_extras_when_only_node_has_meta():
	var n := Node3D.new()
	n.set_meta("extras", {"name_override": "Wall"})
	assert_eq(ExtrasReader.get_extras(n), {"name_override": "Wall"})
	n.free()

func test_merges_mesh_extras_when_node_is_mesh_instance():
	var n := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.set_meta("extras", {"collision": "simple"})
	n.mesh = m
	n.set_meta("extras", {"name_override": "Wall"})
	var extras: Dictionary = ExtrasReader.get_extras(n)
	assert_eq(extras.get("name_override"), "Wall")
	assert_eq(extras.get("collision"), "simple")
	n.free()

func test_node_extras_win_on_conflict():
	var n := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.set_meta("extras", {"name_override": "MeshWin"})
	n.mesh = m
	n.set_meta("extras", {"name_override": "NodeWin"})
	assert_eq(ExtrasReader.get_extras(n).get("name_override"), "NodeWin")
	n.free()

func test_non_mesh_instance_ignores_mesh_path():
	var n := Node3D.new()
	n.set_meta("extras", {"a": 1})
	assert_eq(ExtrasReader.get_extras(n), {"a": 1})
	n.free()
