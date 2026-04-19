extends GutTest

const ExpressionApplier = preload("res://addons/gltf_pipeline/expression_applier.gd")

class Holder extends Node:
	var int_prop: int = 0
	var float_prop: float = 0.0
	var color: Color = Color.WHITE
	var arr: Array = []

func test_simple_int_assignment():
	var h := Holder.new()
	ExpressionApplier.apply_lines(h, ["int_prop=42"])
	assert_eq(h.int_prop, 42)
	h.free()

func test_float_assignment():
	var h := Holder.new()
	ExpressionApplier.apply_lines(h, ["float_prop=3.14"])
	assert_almost_eq(h.float_prop, 3.14, 0.001)
	h.free()

func test_expression_with_node_ref():
	var h := Holder.new()
	h.int_prop = 10
	ExpressionApplier.apply_lines(h, ["int_prop=node.int_prop * 2"])
	assert_eq(h.int_prop, 20)
	h.free()

func test_color_constructor():
	var h := Holder.new()
	ExpressionApplier.apply_lines(h, ["color=Color(1,0,0)"])
	assert_eq(h.color, Color(1, 0, 0))
	h.free()

func test_multiple_lines():
	var h := Holder.new()
	ExpressionApplier.apply_lines(h, ["int_prop=1", "float_prop=2.5"])
	assert_eq(h.int_prop, 1)
	assert_almost_eq(h.float_prop, 2.5, 0.001)
	h.free()

func test_string_semicolon_split():
	var h := Holder.new()
	ExpressionApplier.apply_string(h, "int_prop=7;float_prop=8.5")
	assert_eq(h.int_prop, 7)
	assert_almost_eq(h.float_prop, 8.5, 0.001)
	h.free()

func test_empty_lines_are_skipped():
	var h := Holder.new()
	ExpressionApplier.apply_lines(h, ["", "int_prop=5", ""])
	assert_eq(h.int_prop, 5)
	h.free()

func test_bad_expression_does_not_crash():
	var h := Holder.new()
	# Malformed — must not throw, just print error.
	ExpressionApplier.apply_lines(h, ["int_prop=this_is_not_valid$$$"])
	assert_eq(h.int_prop, 0, "bad expr leaves prop at default")
	h.free()
