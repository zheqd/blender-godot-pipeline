## Evaluates GDScript expressions from [code]prop_string[/code] / [code]prop_file[/code] extras
## and applies the results as properties on the target node.
##
## Each line is either an assignment ([code]property = expression[/code]) or a
## bare expression executed for side effects. Expressions are parsed and run via
## Godot's built-in [Expression] class with [code]node[/code] bound as a variable,
## so expressions can reference the node directly (e.g. [code]visible = false[/code]
## or [code]node.add_to_group("enemies")[/code]).
@tool
class_name ExpressionApplier
extends RefCounted

## Applies a semicolon-separated list of expressions from [param s] to [param node].
static func apply_string(node: Node, s: String) -> void:
	var parts := s.split(";", false)
	var lines: Array[String] = []
	for p: String in parts:
		lines.append(p)
	apply_lines(node, lines)

## Reads expressions line-by-line from [param res_path] and applies each to [param node].
static func apply_file(node: Node, res_path: String) -> void:
	var f := FileAccess.open(res_path, FileAccess.READ)
	if f == null:
		push_warning("ExpressionApplier: cannot open " + res_path)
		return
	var lines: Array[String] = []
	while not f.eof_reached():
		lines.append(f.get_line())
	apply_lines(node, lines)

static func apply_lines(node: Node, lines: Array[String]) -> void:
	for raw in lines:
		var line := String(raw).strip_edges()
		if line.is_empty():
			continue
		_apply_line(node, line)

static func _apply_line(node: Node, line: String) -> void:
	var components := line.split("=", false, 1)
	var e := Expression.new()
	if components.size() > 1:
		var prop_name := components[0].strip_edges()
		var expr := components[1].strip_edges()
		var parse_err := e.parse(expr, ["node"])
		if parse_err != OK:
			push_warning("ExpressionApplier parse error on %s: %s" % [line, e.get_error_text()])
			return
		var val = e.execute([node])
		if e.has_execute_failed():
			push_warning("ExpressionApplier execute error on %s: %s" % [line, e.get_error_text()])
			return
		node.set(prop_name, val)
	else:
		var parse_err := e.parse(line, ["node"])
		if parse_err != OK:
			push_warning("ExpressionApplier parse error on bare line %s: %s" % [line, e.get_error_text()])
			return
		e.execute([node])
