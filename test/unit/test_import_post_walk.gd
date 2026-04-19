extends GutTest

const PipelineGLTFExtension = preload("res://addons/gltf_pipeline/pipeline_extension.gd")

var ext: PipelineGLTFExtension
var visited: Array[String] = []

func before_each():
	ext = PipelineGLTFExtension.new()
	visited = []

func test_import_post_visits_every_node_post_order():
	var root := Node3D.new()
	root.name = "Root"
	var child := Node3D.new()
	child.name = "Child"
	var grandchild := Node3D.new()
	grandchild.name = "Grandchild"
	child.add_child(grandchild)
	root.add_child(child)

	ext._visit_for_test = func(n: Node): visited.append(String(n.name))
	var state := GLTFState.new()
	var result: int = ext._import_post(state, root)
	assert_eq(result, OK)
	assert_eq(visited, ["Grandchild", "Child", "Root"],
		"post-order: children before parents")
	root.free()

func test_reads_scene_extras_from_state_json():
	var state := GLTFState.new()
	state.json = {
		"scenes": [{"extras": {"GodotPipelineProps": {"individual_origins": 1}}}]
	}
	var root := Node3D.new()
	ext._import_post(state, root)
	assert_eq(ext._last_ctx.scene_extras,
		{"individual_origins": 1})
	root.free()
