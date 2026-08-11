extends Node

## Global session state (ENTITY:VARIABLE:VALUE tokens).
#
# By entity key (from state JSON):
#   var value := LivingSessionManager.get_state_value("GE-Video360", "PLAYING")
#   var token := LivingSessionManager.get_full_token("GE-Video360", "PLAYING")
#   LivingSessionManager.set_full_token("GE-Video360:PLAYING:PLAYING")
#
# By Omeka item id:
#   var code := LivingSessionManager.get_item_code(12345)
#   var value := LivingSessionManager.get_item_state_value(12345, "VISIT")
#   var token := LivingSessionManager.get_item_full_token(12345, "VISIT")
#   LivingSessionManager.set_item_state(12345, "VISIT", "VISITED")

var _registry: StateVariableRegistry
var _entity_state: Dictionary = {}  # String entity_key -> Dictionary variable_name -> value
var _state_bootstrapped: bool = false

const TOUR_INDEX_VARIABLE := "TOUR_INDEX"


func _ready() -> void:
	_bootstrap_entity_state()


func get_registry() -> StateVariableRegistry:
	return _registry


func is_state_ready() -> bool:
	return _state_bootstrapped and _registry != null and _registry.is_loaded()


## Reload registry and defaults from disk (e.g. after editor sync rewrote the JSON).
func reload_state_from_json() -> void:
	_state_bootstrapped = false
	_bootstrap_entity_state()


func _bootstrap_entity_state() -> void:
	if _state_bootstrapped:
		return

	_registry = StateVariableRegistry.load_from_json(LivingConstants.STATE_JSON_PATH)
	if _registry == null or not _registry.is_loaded():
		push_error(
			"LivingSessionManager: state registry not loaded (%s)."
			% (_registry.get_load_error() if _registry != null else "null registry")
		)
		return

	_entity_state.clear()
	for entity_key in _registry.get_all_entity_keys():
		_entity_state[entity_key] = _build_default_variable_state(entity_key)

	_state_bootstrapped = true
	print("LivingSessionManager: global state initialized (%d entities)." % _entity_state.size())
	debug_dump()


func reset_entity_state() -> void:
	if _registry == null or not _registry.is_loaded():
		_bootstrap_entity_state()
		return
	for entity_key in _registry.get_all_entity_keys():
		_entity_state[entity_key] = _build_default_variable_state(entity_key)
	debug_dump()


func get_state_value(entity_key: String, variable_name: String) -> String:
	var variables: Variant = _entity_state.get(entity_key)
	if typeof(variables) != TYPE_DICTIONARY:
		return ""
	return str(variables.get(variable_name, ""))


func get_full_token(entity_key: String, variable_name: String) -> String:
	var value := get_state_value(entity_key, variable_name)
	if value == "":
		return ""
	return StateVariableRegistry.build_full_token(entity_key, variable_name, value)


func set_state_value(entity_key: String, variable_name: String, value: String) -> bool:
	return set_full_token(
		StateVariableRegistry.build_full_token(entity_key, variable_name, value)
	)


## Sets state from a full Omeka token (e.g. GE-Video360:PLAYING:PLAYING). Returns false if unknown or invalid.
func set_full_token(token: String) -> bool:
	if not is_state_ready():
		push_warning("LivingSessionManager: set_full_token ignored — state not ready.")
		return false

	var trimmed := token.strip_edges()
	var parsed := StateVariableRegistry.parse_token(trimmed)
	if not parsed.get("ok", false):
		push_warning("LivingSessionManager: invalid token '%s'" % trimmed)
		return false

	var entity: String = parsed.entity
	var variable_name: String = parsed.variable
	var value: String = parsed.value

	if not _registry.is_known_token(trimmed):
		if not _registry.has_variable(entity, variable_name):
			push_warning("LivingSessionManager: unknown token '%s'" % trimmed)
			return false
		if not _registry.is_value_allowed_for_variable(entity, variable_name, value):
			push_warning("LivingSessionManager: unknown token '%s'" % trimmed)
			return false

	if not _registry.is_value_allowed_for_variable(entity, variable_name, value):
		push_warning(
			"LivingSessionManager: value '%s' not allowed for %s:%s"
			% [value, entity, variable_name]
		)
		return false

	_ensure_entity_state(entity)
	_entity_state[entity][variable_name] = value
	return true


func get_item_code(item_id: int) -> String:
	if item_id <= 0:
		return ""
	if not is_state_ready():
		push_warning("LivingSessionManager: get_item_code ignored — state not ready.")
		return ""
	return _registry.get_entity_for_item_id(item_id)


func get_item_state_value(item_id: int, variable_name: String) -> String:
	var entity_key := get_item_code(item_id)
	if entity_key == "":
		return ""
	return get_state_value(entity_key, variable_name)


func get_item_full_token(item_id: int, variable_name: String) -> String:
	var entity_key := get_item_code(item_id)
	if entity_key == "":
		return ""
	return get_full_token(entity_key, variable_name)


func set_item_state(item_id: int, variable_name: String, value: String) -> bool:
	var entity_key := get_item_code(item_id)
	if entity_key == "":
		push_warning("LivingSessionManager: set_item_state ignored — unknown item id %d." % item_id)
		return false
	return set_state_value(entity_key, variable_name, value.strip_edges())


func get_tour_index(env_item_id: int) -> int:
	var raw := get_item_state_value(env_item_id, TOUR_INDEX_VARIABLE)
	if raw.is_empty() or not StateVariableRegistry.is_non_negative_int_string(raw):
		return 0
	return int(raw)


func set_tour_index(env_item_id: int, index: int) -> bool:
	return set_item_state(env_item_id, TOUR_INDEX_VARIABLE, str(maxi(0, index)))


func matches_full_token(token: String) -> bool:
	if not is_state_ready():
		return false
	var trimmed := token.strip_edges()
	if trimmed == "":
		return true
	var parsed := StateVariableRegistry.parse_token(trimmed)
	if not parsed.get("ok", false):
		return false

	var entity: String = parsed.entity
	var variable_name: String = parsed.variable
	var required_value: String = parsed.value
	var current_value := get_state_value(entity, variable_name)

	if required_value == StateVariableRegistry.OPEN_NUMERIC_SENTINEL:
		if not _registry.has_variable(entity, variable_name):
			return false
		var allowed := _registry.get_allowed_values_for_variable(entity, variable_name)
		if StateVariableRegistry.OPEN_NUMERIC_SENTINEL not in allowed:
			return false
		return StateVariableRegistry.is_non_negative_int_string(current_value)

	return get_full_token(entity, variable_name) == trimmed


func debug_dump() -> void:
	if not is_state_ready():
		print("LivingSessionManager: state dump skipped (not ready).")
		return

	print("LivingSessionManager: --- global entity state ---")
	var keys: Array = _entity_state.keys()
	keys.sort()
	for entity_key in keys:
		for variable_name in _registry.get_state_variables_for_entity(str(entity_key)):
			print("  %s" % get_full_token(str(entity_key), variable_name))
	print("LivingSessionManager: --- end state dump (%d entities) ---" % keys.size())


func _build_default_variable_state(entity_key: String) -> Dictionary:
	var defaults: Dictionary = {}
	for variable_name in _registry.get_state_variables_for_entity(entity_key):
		defaults[variable_name] = _registry.get_default_value_for_variable(entity_key, variable_name)
	return defaults


func _ensure_entity_state(entity_key: String) -> void:
	if typeof(_entity_state.get(entity_key)) != TYPE_DICTIONARY:
		_entity_state[entity_key] = _build_default_variable_state(entity_key)
