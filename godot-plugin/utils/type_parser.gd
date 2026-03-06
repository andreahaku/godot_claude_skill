@tool
class_name TypeParser

## Smart type parsing - converts string representations to proper Godot types
## Supports: Vector2, Vector3, Color, Rect2, Transform2D, Transform3D, Basis,
## AABB, Plane, Quaternion, NodePath, bool, int, float, arrays, dictionaries

## Prefix-to-parser dispatch table — O(1) lookup instead of linear if-chain
static var _type_parsers: Dictionary = {
	"Vector2": _try_parse_vector2,
	"Vector2i": _try_parse_vector2i,
	"Vector3": _try_parse_vector3,
	"Vector3i": _try_parse_vector3i,
	"Vector4": _try_parse_vector4,
	"Color": _try_parse_color,
	"Rect2": _try_parse_rect2,
	"AABB": _try_parse_aabb,
	"Plane": _try_parse_plane,
	"Quaternion": _try_parse_quaternion,
	"Basis": _try_parse_basis,
	"Transform2D": _try_parse_transform2d,
	"Transform3D": _try_parse_transform3d,
	"NodePath": _try_parse_nodepath,
}

static func parse_value(value) -> Variant:
	if value == null:
		return null
	if not value is String:
		return value

	var s: String = value.strip_edges()

	# Boolean
	if s == "true":
		return true
	if s == "false":
		return false

	# null / nil
	if s == "null" or s == "nil":
		return null

	# Integer (check before float)
	if s.is_valid_int():
		return s.to_int()

	# Float
	if s.is_valid_float():
		return s.to_float()

	# Hex color: #rrggbb or #rrggbbaa
	if s.begins_with("#") and (s.length() == 7 or s.length() == 9):
		if Color.html_is_valid(s):
			return Color.html(s)
		return value  # Return as string if invalid hex

	# Type constructor dispatch — extract prefix before '(' and look up parser
	var paren_idx = s.find("(")
	if paren_idx > 0:
		var prefix = s.substr(0, paren_idx)
		if _type_parsers.has(prefix):
			var result = _type_parsers[prefix].call(s)
			if result != null:
				return result

	# NodePath shorthand
	if s.begins_with("^"):
		var path_str = s
		if s.begins_with("^\""):
			path_str = s.substr(2, s.length() - 3)
		else:
			path_str = s.substr(1)
		return NodePath(path_str)

	# JSON array
	if s.begins_with("["):
		var json = JSON.new()
		if json.parse(s) == OK:
			var data = json.get_data()
			if data is Array:
				return data

	# JSON dictionary
	if s.begins_with("{"):
		var json = JSON.new()
		if json.parse(s) == OK:
			var data = json.get_data()
			if data is Dictionary:
				return data

	# Return as string
	return value


## Like parse_value but returns {"value": Variant, "parsed": bool}.
## "parsed" is true if the string was recognized as a type expression and converted,
## false if it was returned as-is (plain string or unrecognized format).
static func parse_value_strict(value) -> Dictionary:
	if value == null:
		return {"value": null, "parsed": true}
	if not value is String:
		return {"value": value, "parsed": true}

	var s: String = value.strip_edges()
	var result = parse_value(value)

	# If parse_value returned something other than the original string, it was parsed
	if typeof(result) != TYPE_STRING or result != value:
		return {"value": result, "parsed": true}

	# Check if the string looks like it was INTENDED to be a type expression but failed
	var paren_idx = s.find("(")
	if paren_idx > 0 and _type_parsers.has(s.substr(0, paren_idx)):
		return {"value": value, "parsed": false}

	# Plain string — not a failed parse
	return {"value": value, "parsed": true}


static func _extract_args(s: String, prefix: String) -> PackedStringArray:
	if not s.begins_with(prefix + "(") or not s.ends_with(")"):
		return PackedStringArray()
	var inner = s.substr(prefix.length() + 1, s.length() - prefix.length() - 2)
	return inner.split(",")


static func _try_parse_vector2(s: String):
	var args = _extract_args(s, "Vector2")
	if args.size() == 2:
		return Vector2(args[0].strip_edges().to_float(), args[1].strip_edges().to_float())
	return null


static func _try_parse_vector2i(s: String):
	var args = _extract_args(s, "Vector2i")
	if args.size() == 2:
		return Vector2i(args[0].strip_edges().to_int(), args[1].strip_edges().to_int())
	return null


static func _try_parse_vector3(s: String):
	var args = _extract_args(s, "Vector3")
	if args.size() == 3:
		return Vector3(args[0].strip_edges().to_float(), args[1].strip_edges().to_float(), args[2].strip_edges().to_float())
	return null


static func _try_parse_vector3i(s: String):
	var args = _extract_args(s, "Vector3i")
	if args.size() == 3:
		return Vector3i(args[0].strip_edges().to_int(), args[1].strip_edges().to_int(), args[2].strip_edges().to_int())
	return null


static func _try_parse_vector4(s: String):
	var args = _extract_args(s, "Vector4")
	if args.size() == 4:
		return Vector4(args[0].strip_edges().to_float(), args[1].strip_edges().to_float(), args[2].strip_edges().to_float(), args[3].strip_edges().to_float())
	return null


static func _try_parse_color(s: String):
	var args = _extract_args(s, "Color")
	if args.size() == 3:
		return Color(args[0].strip_edges().to_float(), args[1].strip_edges().to_float(), args[2].strip_edges().to_float())
	if args.size() == 4:
		return Color(args[0].strip_edges().to_float(), args[1].strip_edges().to_float(), args[2].strip_edges().to_float(), args[3].strip_edges().to_float())
	return null


static func _try_parse_rect2(s: String):
	var args = _extract_args(s, "Rect2")
	if args.size() == 4:
		return Rect2(args[0].strip_edges().to_float(), args[1].strip_edges().to_float(), args[2].strip_edges().to_float(), args[3].strip_edges().to_float())
	return null


static func _try_parse_aabb(s: String):
	var args = _extract_args(s, "AABB")
	if args.size() == 6:
		return AABB(
			Vector3(args[0].strip_edges().to_float(), args[1].strip_edges().to_float(), args[2].strip_edges().to_float()),
			Vector3(args[3].strip_edges().to_float(), args[4].strip_edges().to_float(), args[5].strip_edges().to_float())
		)
	return null


static func _try_parse_plane(s: String):
	var args = _extract_args(s, "Plane")
	if args.size() == 4:
		return Plane(args[0].strip_edges().to_float(), args[1].strip_edges().to_float(), args[2].strip_edges().to_float(), args[3].strip_edges().to_float())
	return null


static func _try_parse_quaternion(s: String):
	var args = _extract_args(s, "Quaternion")
	if args.size() == 4:
		return Quaternion(args[0].strip_edges().to_float(), args[1].strip_edges().to_float(), args[2].strip_edges().to_float(), args[3].strip_edges().to_float())
	return null


static func _try_parse_basis(s: String):
	var args = _extract_args(s, "Basis")
	if args.size() == 9:
		return Basis(
			Vector3(args[0].strip_edges().to_float(), args[1].strip_edges().to_float(), args[2].strip_edges().to_float()),
			Vector3(args[3].strip_edges().to_float(), args[4].strip_edges().to_float(), args[5].strip_edges().to_float()),
			Vector3(args[6].strip_edges().to_float(), args[7].strip_edges().to_float(), args[8].strip_edges().to_float())
		)
	return null


static func _try_parse_transform2d(s: String):
	var args = _extract_args(s, "Transform2D")
	if args.size() == 6:
		return Transform2D(
			Vector2(args[0].strip_edges().to_float(), args[1].strip_edges().to_float()),
			Vector2(args[2].strip_edges().to_float(), args[3].strip_edges().to_float()),
			Vector2(args[4].strip_edges().to_float(), args[5].strip_edges().to_float())
		)
	return null


static func _try_parse_transform3d(s: String):
	var args = _extract_args(s, "Transform3D")
	if args.size() == 12:
		return Transform3D(
			Basis(
				Vector3(args[0].strip_edges().to_float(), args[1].strip_edges().to_float(), args[2].strip_edges().to_float()),
				Vector3(args[3].strip_edges().to_float(), args[4].strip_edges().to_float(), args[5].strip_edges().to_float()),
				Vector3(args[6].strip_edges().to_float(), args[7].strip_edges().to_float(), args[8].strip_edges().to_float())
			),
			Vector3(args[9].strip_edges().to_float(), args[10].strip_edges().to_float(), args[11].strip_edges().to_float())
		)
	return null


static func _try_parse_nodepath(s: String):
	if not s.begins_with("NodePath(") or not s.ends_with(")"):
		return null
	var path_str = s.substr(9, s.length() - 10).strip_edges()
	if path_str.begins_with("\"") and path_str.ends_with("\""):
		path_str = path_str.substr(1, path_str.length() - 2)
	return NodePath(path_str)


## Convert a Godot value to a JSON-safe representation.
## Uses _seen array to detect circular references in Arrays/Dictionaries.
static func value_to_json(value, _depth: int = 0) -> Variant:
	if value == null:
		return null
	if _depth > 32:
		return "<max depth exceeded>"
	if value is bool or value is int or value is float or value is String:
		return value
	if value is Vector2:
		return "Vector2(%s, %s)" % [value.x, value.y]
	if value is Vector2i:
		return "Vector2i(%s, %s)" % [value.x, value.y]
	if value is Vector3:
		return "Vector3(%s, %s, %s)" % [value.x, value.y, value.z]
	if value is Vector3i:
		return "Vector3i(%s, %s, %s)" % [value.x, value.y, value.z]
	if value is Vector4:
		return "Vector4(%s, %s, %s, %s)" % [value.x, value.y, value.z, value.w]
	if value is Color:
		return "Color(%s, %s, %s, %s)" % [value.r, value.g, value.b, value.a]
	if value is Rect2:
		return "Rect2(%s, %s, %s, %s)" % [value.position.x, value.position.y, value.size.x, value.size.y]
	if value is AABB:
		return "AABB(%s, %s, %s, %s, %s, %s)" % [value.position.x, value.position.y, value.position.z, value.size.x, value.size.y, value.size.z]
	if value is Plane:
		return "Plane(%s, %s, %s, %s)" % [value.normal.x, value.normal.y, value.normal.z, value.d]
	if value is Quaternion:
		return "Quaternion(%s, %s, %s, %s)" % [value.x, value.y, value.z, value.w]
	if value is Transform2D:
		return "Transform2D(%s, %s, %s, %s, %s, %s)" % [value.x.x, value.x.y, value.y.x, value.y.y, value.origin.x, value.origin.y]
	if value is Transform3D:
		var b = value.basis
		var o = value.origin
		return "Transform3D(%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)" % [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z, o.x, o.y, o.z]
	if value is NodePath:
		return "NodePath(\"%s\")" % str(value)
	if value is Array:
		var arr = []
		for item in value:
			arr.append(value_to_json(item, _depth + 1))
		return arr
	if value is Dictionary:
		var dict = {}
		for key in value:
			dict[str(key)] = value_to_json(value[key], _depth + 1)
		return dict
	if value is Resource:
		return {"_type": value.get_class(), "_path": value.resource_path}
	if value is Object:
		return {"_type": value.get_class()}
	return str(value)
