extends Node

## Global session state (ENTITY:STATE tokens).
#
# By entity key (from state JSON):
#   var suffix := LivingSessionManager.get_state_suffix("GE-Video360")
#   var token := LivingSessionManager.get_full_token("GE-Video360")
#   LivingSessionManager.set_full_token("GE-Video360:PLAYING")
#
# By Omeka item id:
#   var code := LivingSessionManager.get_item_code(12345)
#   var suffix := LivingSessionManager.get_item_state_suffix(12345)
#   var token := LivingSessionManager.get_item_full_token(12345)
#   LivingSessionManager.set_item_state(12345, "VISITED")

var _registry: StateVariableRegistry
var _entity_state: Dictionary = {}  # String entity_key -> String state suffix
var _state_bootstrapped: bool = false

## Legacy: items whose short text was shown. Key=item_id, value=true.
var _visited_items: Dictionary[int, bool] = {}


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


## Loads JSON registry and fills _entity_state with default suffixes per entity.
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
		_entity_state[entity_key] = _registry.get_default_suffix_for_entity(entity_key)

	_state_bootstrapped = true
	print("LivingSessionManager: global state initialized (%d entities)." % _entity_state.size())
	debug_dump()


## Resets entity states to registry defaults (does not clear legacy visited items).
func reset_entity_state() -> void:
	if _registry == null or not _registry.is_loaded():
		_bootstrap_entity_state()
		return
	for entity_key in _registry.get_all_entity_keys():
		_entity_state[entity_key] = _registry.get_default_suffix_for_entity(entity_key)
	debug_dump()


func get_state_suffix(entity_key: String) -> String:
	return str(_entity_state.get(entity_key, ""))


func get_full_token(entity_key: String) -> String:
	var suffix := get_state_suffix(entity_key)
	if suffix == "":
		return ""
	return "%s:%s" % [entity_key, suffix]


## Sets state from a full Omeka token (e.g. GE-Video360:PLAYING). Returns false if unknown or invalid.
func set_full_token(token: String) -> bool:
	if not is_state_ready():
		push_warning("LivingSessionManager: set_full_token ignored — state not ready.")
		return false

	var trimmed := token.strip_edges()
	var parsed := StateVariableRegistry.parse_token(trimmed)
	if not parsed.get("ok", false):
		push_warning("LivingSessionManager: invalid token '%s'" % trimmed)
		return false

	if not _registry.is_known_token(trimmed):
		push_warning("LivingSessionManager: unknown token '%s'" % trimmed)
		return false

	var entity: String = parsed.entity
	var state: String = parsed.state
	if not _registry.get_allowed_states_for_entity(entity).has(state):
		push_warning(
			"LivingSessionManager: state '%s' not allowed for entity '%s'" % [state, entity]
		)
		return false

	_entity_state[entity] = state
	return true


# Returns the entity key (e.g. "GE-Video360") registered for an Omeka item id, or "" if unknown.
func get_item_code(item_id: int) -> String:
	if item_id <= 0:
		return ""
	if not is_state_ready():
		push_warning("LivingSessionManager: get_item_code ignored — state not ready.")
		return ""
	return _registry.get_entity_for_item_id(item_id)


# Returns the current state suffix for an Omeka item id (e.g. "VISITED", "PLAYING").
func get_item_state_suffix(item_id: int) -> String:
	var entity_key := get_item_code(item_id)
	if entity_key == "":
		return ""
	return get_state_suffix(entity_key)


# Returns the full ENTITY:STATE token for an Omeka item id.
func get_item_full_token(item_id: int) -> String:
	var entity_key := get_item_code(item_id)
	if entity_key == "":
		return ""
	return get_full_token(entity_key)


# Sets the state suffix for an Omeka item id (e.g. "VISITED"). Returns false if the item or state is unknown.
func set_item_state(item_id: int, state_suffix: String) -> bool:
	var entity_key := get_item_code(item_id)
	if entity_key == "":
		push_warning("LivingSessionManager: set_item_state ignored — unknown item id %d." % item_id)
		return false
	return set_full_token("%s:%s" % [entity_key, state_suffix.strip_edges()])


# Returns true if the current session state matches the given ENTITY:STATE token.
func matches_full_token(token: String) -> bool:
	if not is_state_ready():
		return false
	var trimmed := token.strip_edges()
	if trimmed == "":
		return true
	var parsed := StateVariableRegistry.parse_token(trimmed)
	if not parsed.get("ok", false):
		return false
	return get_full_token(parsed.entity) == trimmed


func debug_dump() -> void:
	if not is_state_ready():
		print("LivingSessionManager: state dump skipped (not ready).")
		return

	print("LivingSessionManager: --- global entity state ---")
	var keys: Array = _entity_state.keys()
	keys.sort()
	for entity_key in keys:
		print("  %s" % get_full_token(str(entity_key)))
	print("LivingSessionManager: --- end state dump (%d) ---" % keys.size())
