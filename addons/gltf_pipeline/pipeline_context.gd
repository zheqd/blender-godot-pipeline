@tool
class_name PipelineContext
extends RefCounted

## Shared state threaded through all handlers during a single import pass.
##
## @internal — created once by [method PipelineGLTFExtension._import_post] and
## passed to handlers as a parameter. Do not instantiate directly.
##
## [member deferred_deletes] and [member deferred_reparents] collect tree
## mutations that cannot happen mid-walk; they are applied by
## [method PipelineGLTFExtension._flush] after the post-order traversal finishes.

var state: GLTFState
var root: Node
var scene_extras: Dictionary = {}
## Keys are resource save paths; values are Array of Transform3D instances.
var multimesh_groups: Dictionary[String, Array] = {}
var deferred_deletes: Array[Node] = []
## Array of [Node, Node] pairs: [child_to_reparent, new_parent].
## Untyped inner array because GDScript cannot express Array[Array[Node]].
var deferred_reparents: Array = []
