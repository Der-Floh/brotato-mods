extends Reference


static func convert_value(value):
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return value
		TYPE_REAL:
			return str(value) if is_nan(value) or is_inf(value) else value
		TYPE_NODE_PATH:
			return str(value)
		TYPE_DICTIONARY:
			return _convert_dictionary(value)
		TYPE_ARRAY:
			return _convert_array(value)
		TYPE_OBJECT:
			return _describe_object(value) if is_instance_valid(value) else null
	if typeof(value) >= TYPE_RAW_ARRAY:
		return _convert_array(Array(value))
	return var2str(value)


static func _convert_dictionary(dictionary: Dictionary) -> Dictionary:
	var result := {}
	for key in dictionary:
		result[str(key)] = convert_value(dictionary[key])
	return result


static func _convert_array(array: Array) -> Array:
	var result := []
	for item in array:
		result.append(convert_value(item))
	return result


static func _describe_object(object: Object) -> Dictionary:
	var description := {"class": object.get_class()}
	var script = object.get_script()
	if script and not script.resource_path.empty():
		description["script"] = script.resource_path
	if object is Node:
		description["name"] = String(object.name)
		if object.is_inside_tree():
			description["path"] = String(object.get_path())
	elif object is Resource and not object.resource_path.empty():
		description["resource"] = object.resource_path
	if "my_id" in object:
		description["my_id"] = object.my_id
	return description
