extends RefCounted
class_name StateVariableRegistry

## In-memory lookup for ENTITY:VARIABLE:VALUE tokens from omeka_dynamic_properties_table.json.
## ENTITY = entity key (e.g. "GE-Video360"), VARIABLE = state dimension (e.g. "PLAYING"), VALUE = allowed value (e.g. "PAUSE-0%").

const _DEFAULT_VALUE_BY_VARIABLE: Dictionary = {
	"VISIT": "NON-VISITED",
	"ACTIVATION": "INACTIVE",
	"USE": "UNUSED",
	"PLAYING": "PAUSE-0%",
	"HIGHLIGHT": "OFF",
	"TRAINING": "ONGOING",
}

const _DEFAULT_VALUE_PRIORITY: Array[String] = [
	"NON-VISITED",
	"INACTIVE",
	"UNUSED",
	"OFF",
	"PAUSE-0%",
	"ONGOING",
]

var _loaded: bool = false
var _load_error: String = ""

var _by_omeka_item_id: Dictionary = {}  # int -> String entity_key
var _by_entity_key: Dictionary = {}  # String -> Dictionary (entity_key, omeka_item_id, state_variables, full_tokens)
var _by_full_token: Dictionary = {}  # String -> true
var _all_entity_keys: Array[String] = []


static func load_from_json(json_path: String = LivingConstants.STATE_JSON_PATH) -> StateVariableRegistry:
	var registry := StateVariableRegistry.new()
	registry._load(json_path)
	return registry


static func build_full_token(entity_key: String, variable_name: String, value: String) -> String:
	return "%s:%s:%s" % [entity_key.strip_edges(), variable_name.strip_edges(), value.strip_edges()]


# Parses a token string into entity, variable, and value (ENTITY:VARIABLE:VALUE).
static func parse_token(token: String) -> Dictionary:
	var trimmed := token.strip_edges()
	var parts := trimmed.split(":", false, 2)
	if parts.size() != 3:
		return {"ok": false, "error": "expected ENTITY:VARIABLE:VALUE (two colons)"}
	var entity := str(parts[0]).strip_edges()
	var variable := str(parts[1]).strip_edges()
	var value := str(parts[2]).strip_edges()
	if entity == "" or variable == "" or value == "":
		return {"ok": false, "error": "empty segment in token"}
	return {
		"ok": true,
		"entity": entity,
		"variable": variable,
		"value": value,
		"full": trimmed,
	}


func is_loaded() -> bool:
	return _loaded


func get_load_error() -> String:
	return _load_error


func get_all_entity_keys() -> Array[String]:
	return _all_entity_keys.duplicate()


func get_entity_for_item_id(item_id: int) -> String:
	return str(_by_omeka_item_id.get(item_id, ""))


func is_known_token(token: String) -> bool:
	return _by_full_token.has(token.strip_edges())


func has_entity(entity_key: String) -> bool:
	return _by_entity_key.has(entity_key)


func has_variable(entity_key: String, variable_name: String) -> bool:
	var def: Variant = _by_entity_key.get(entity_key)
	if typeof(def) != TYPE_DICTIONARY:
		return false
	var state_variables: Variant = def.get("state_variables", {})
	return typeof(state_variables) == TYPE_DICTIONARY and state_variables.has(variable_name)


func get_state_variables_for_entity(entity_key: String) -> Array[String]:
	var def: Variant = _by_entity_key.get(entity_key)
	if typeof(def) != TYPE_DICTIONARY:
		return []
	var out: Array[String] = []
	var state_variables: Variant = def.get("state_variables", {})
	if typeof(state_variables) != TYPE_DICTIONARY:
		return out
	for variable_name in state_variables.keys():
		out.append(str(variable_name))
	out.sort()
	return out


func get_default_value_for_variable(entity_key: String, variable_name: String) -> String:
	var allowed := get_allowed_values_for_variable(entity_key, variable_name)
	if allowed.is_empty():
		return ""

	var preferred: Variant = _DEFAULT_VALUE_BY_VARIABLE.get(variable_name)
	if preferred != null and str(preferred) in allowed:
		return str(preferred)

	for candidate in _DEFAULT_VALUE_PRIORITY:
		if candidate in allowed:
			return candidate

	return allowed[0]


func get_item_id_for_entity(entity_key: String) -> int:
	var def: Variant = _by_entity_key.get(entity_key)
	if typeof(def) != TYPE_DICTIONARY:
		return 0
	return int(def.get("omeka_item_id", 0))


# E.g. entity "GE-Video360", variable "PLAYING" -> ["PAUSE-0%", "PAUSE-100%", "PAUSE-N%", "PLAYING"].
func get_allowed_values_for_variable(entity_key: String, variable_name: String) -> Array[String]:
	var def: Variant = _by_entity_key.get(entity_key)
	if typeof(def) != TYPE_DICTIONARY:
		return []
	var state_variables: Variant = def.get("state_variables", {})
	if typeof(state_variables) != TYPE_DICTIONARY:
		return []
	var allowed: Variant = state_variables.get(variable_name, [])
	if typeof(allowed) != TYPE_ARRAY:
		return []
	var out: Array[String] = []
	for value in allowed:
		out.append(str(value))
	return out


func get_all_full_tokens_for_entity(entity_key: String) -> Array[String]:
	var def: Variant = _by_entity_key.get(entity_key)
	if typeof(def) != TYPE_DICTIONARY:
		return []
	var out: Array[String] = []
	for token in def.get("full_tokens", []):
		out.append(str(token))
	return out


func _load(json_path: String) -> void:
	_loaded = false
	_load_error = ""
	_by_omeka_item_id.clear()
	_by_entity_key.clear()
	_by_full_token.clear()
	_all_entity_keys.clear()

	if not FileAccess.file_exists(json_path):
		_load_error = "File not found: %s" % json_path
		push_error("StateVariableRegistry: %s" % _load_error)
		return

	var file := FileAccess.open(json_path, FileAccess.READ)
	if file == null:
		_load_error = "Cannot open: %s" % json_path
		push_error("StateVariableRegistry: %s" % _load_error)
		return

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		_load_error = "Invalid JSON root in %s" % json_path
		push_error("StateVariableRegistry: %s" % _load_error)
		return

	var properties: Variant = parsed.get("properties", [])
	if typeof(properties) != TYPE_ARRAY:
		_load_error = "Missing properties array in %s" % json_path
		push_error("StateVariableRegistry: %s" % _load_error)
		return

	for row in properties:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		_register_row(row)

	_loaded = true
	print("StateVariableRegistry: loaded %d state entity/entities from %s." % [_all_entity_keys.size(), json_path])


func _register_row(row: Dictionary) -> void:
	var omeka_item_id := int(row.get(LivingConstants.OMEKA_META_ITEM_OF_STATE_VARIABLE_ID, 0))
	var variable_names: Variant = row.get(LivingConstants.OMEKA_META_VARIABLE_NAMES, [])
	if omeka_item_id <= 0 or typeof(variable_names) != TYPE_ARRAY or variable_names.is_empty():
		return

	var entity_key := ""
	var state_variables: Dictionary = {}
	var full_tokens: Array[String] = []

	for raw_name in variable_names:
		var tok := str(raw_name).strip_edges()
		if tok == "":
			continue
		var part := parse_token(tok)
		if not part.get("ok", false):
			push_warning("StateVariableRegistry: skip token '%s'" % tok)
			continue
		if entity_key == "":
			entity_key = part.entity
		elif part.entity != entity_key:
			push_error(
				"StateVariableRegistry: inconsistent entity in row (expected %s, got %s in '%s')"
				% [entity_key, part.entity, tok]
			)
			continue

		var variable_name: String = part.variable
		var value: String = part.value
		if not state_variables.has(variable_name):
			state_variables[variable_name] = []
		var allowed: Array = state_variables[variable_name]
		if not allowed.has(value):
			allowed.append(value)
		if not full_tokens.has(tok):
			full_tokens.append(tok)
		_by_full_token[tok] = true

	if entity_key == "" or state_variables.is_empty():
		return

	if _by_entity_key.has(entity_key):
		push_warning(
			"StateVariableRegistry: duplicate entity '%s' (item_id %d); keeping first definition."
			% [entity_key, omeka_item_id]
		)
		return

	_by_entity_key[entity_key] = {
		"entity_key": entity_key,
		"omeka_item_id": omeka_item_id,
		"table_row_id": int(row.get("id", 0)),
		"state_variables": state_variables,
		"full_tokens": full_tokens,
	}
	_by_omeka_item_id[omeka_item_id] = entity_key
	_all_entity_keys.append(entity_key)
