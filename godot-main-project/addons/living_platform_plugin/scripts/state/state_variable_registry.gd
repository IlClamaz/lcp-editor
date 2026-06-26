extends RefCounted
class_name StateVariableRegistry

## In-memory lookup for ENTITY:STATE tokens from addons/living_platform_plugin/omeka_dynamic_properties_table.json.
## ENTITY = entity key (e.g. "GE-Video360"), STATE = allowed state (e.g. "PAUSE-0%").

# The priority list for default suffixes. 
# This is needed for startup and for cases where we want to infer a default state for an entity.
const _DEFAULT_SUFFIX_PRIORITY: Array[String] = [
	"NON-VISITED",
	"INACTIVE",
	"PAUSE-0%",
]

var _loaded: bool = false
var _load_error: String = ""

var _by_omeka_item_id: Dictionary = {}  # int -> String entity_key
var _by_entity_key: Dictionary = {}  # String -> Dictionary (entity_key, omeka_item_id, allowed_states, full_tokens)
var _by_full_token: Dictionary = {}  # String -> true
var _all_entity_keys: Array[String] = []


static func load_from_json(json_path: String = LivingConstants.STATE_JSON_PATH) -> StateVariableRegistry:
	var registry := StateVariableRegistry.new()
	registry._load(json_path)
	return registry


# Parses a token string into its components.
static func parse_token(token: String) -> Dictionary:
	var trimmed := token.strip_edges()
	var idx := trimmed.find(":")
	if idx < 0:
		return {"ok": false, "error": "missing colon in token"}
	return {
		"ok": true,
		"entity": trimmed.substr(0, idx),
		"state": trimmed.substr(idx + 1),
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

# Returns the default suffix for an entity, based on the priority list and allowed states.
func get_default_suffix_for_entity(entity_key: String) -> String:
	var def: Variant = _by_entity_key.get(entity_key)
	if typeof(def) != TYPE_DICTIONARY:
		return ""
	var allowed: Array = def.get("allowed_states", [])
	if allowed.is_empty():
		return ""
	for preferred in _DEFAULT_SUFFIX_PRIORITY:
		if preferred in allowed:
			return preferred
	return str(allowed[0])

# Returns the Omeka item id linked to an entity key, or 0 if unknown.
func get_item_id_for_entity(entity_key: String) -> int:
	var def: Variant = _by_entity_key.get(entity_key)
	if typeof(def) != TYPE_DICTIONARY:
		return 0
	return int(def.get("omeka_item_id", 0))

# Returns the list of allowed states for an entity, or empty if unknown.
# E.g. for entity "GE-Video360" it returns "PAUSE-0%", "PAUSE-100%","PAUSE-N%","PLAYING"
func get_allowed_states_for_entity(entity_key: String) -> Array[String]:
	var def: Variant = _by_entity_key.get(entity_key)
	if typeof(def) != TYPE_DICTIONARY:
		return []
	var out: Array[String] = []
	for s in def.get("allowed_states", []):
		out.append(str(s))
	return out

# Here we load the JSON file, parse it, and populate our lookup dictionaries. 
# We also handle errors and log them.
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

# Here we parse each row of the properties table, 
# extract the entity key and allowed states, and populate our lookup dictionaries.
func _register_row(row: Dictionary) -> void:
	var omeka_item_id := int(row.get("item_of_state_variable_id", 0))
	var variable_names: Variant = row.get("variable_names", [])
	if omeka_item_id <= 0 or typeof(variable_names) != TYPE_ARRAY or variable_names.is_empty():
		return

	var first_token := str(variable_names[0]).strip_edges()
	var parsed := parse_token(first_token)
	if not parsed.get("ok", false):
		push_warning("StateVariableRegistry: skip row — invalid token '%s'" % first_token)
		return

	var entity_key: String = parsed.entity
	var allowed_states: Array[String] = []
	var full_tokens: Array[String] = []

	for raw_name in variable_names:
		var tok := str(raw_name).strip_edges()
		if tok == "":
			continue
		var part := parse_token(tok)
		if not part.get("ok", false):
			push_warning("StateVariableRegistry: skip token '%s' in row for %s" % [tok, entity_key])
			continue
		if part.entity != entity_key:
			push_error(
				"StateVariableRegistry: inconsistent entity in row (expected %s, got %s in '%s')"
				% [entity_key, part.entity, tok]
			)
			continue
		if not allowed_states.has(part.state):
			allowed_states.append(part.state)
		if not full_tokens.has(tok):
			full_tokens.append(tok)
		_by_full_token[tok] = true

	if allowed_states.is_empty():
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
		"allowed_states": allowed_states,
		"full_tokens": full_tokens,
	}
	_by_omeka_item_id[omeka_item_id] = entity_key
	_all_entity_keys.append(entity_key)
