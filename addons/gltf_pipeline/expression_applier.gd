@tool
class_name ExpressionApplier
extends RefCounted

static func apply_string(node: Node, s: String) -> void:
	var lines := s.split(";", false)
	apply_lines(node, Array(lines))

static func apply_file(node: Node, res_path: String) -> void:
	var f := FileAccess.open(res_path, FileAccess.READ)
	if f == null:
		push_warning("ExpressionApplier: cannot open " + res_path)
		return
	var lines: Array = []
	while not f.eof_reached():
		var line := f.get_line()
		if line != "":
			lines.append(line)
	apply_lines(node, lines)

static func apply_lines(node: Node, lines: Array) -> void:
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
