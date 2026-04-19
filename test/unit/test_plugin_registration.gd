extends GutTest

const PipelineGLTFExtension: GDScript = preload("res://addons/gltf_pipeline/pipeline_extension.gd")

func test_pipeline_extension_class_exists():
	var ext: PipelineGLTFExtension = PipelineGLTFExtension.new()
	assert_not_null(ext, "PipelineGLTFExtension class should be loadable")
	assert_true(ext is GLTFDocumentExtension,
		"must extend GLTFDocumentExtension")

func test_import_post_returns_ok_on_empty_state():
	var ext: PipelineGLTFExtension = PipelineGLTFExtension.new()
	var state: GLTFState = GLTFState.new()
	var root: Node = Node.new()
	var result: int = ext._import_post(state, root)
	assert_eq(result, OK, "empty import_post returns OK")
	root.free()
