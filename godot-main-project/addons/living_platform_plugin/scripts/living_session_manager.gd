extends Node

## Global session state (ENTITY:STATE tokens) and legacy visited-item tracking.
# Get the state suffix for an entity: "PAUSE-0%", "VISITED", "PLAYING", ...
# var state := LivingSessionManager.get_state_suffix("GE-Video360")
# Get the full token for an entity: "GE-Video360:PAUSE-0%"
# var token := LivingSessionManager.get_full_token("GE-Video360")
# To write a token (e.g. from an Omeka event), call set_full_token with the full token string:
# var success := LivingSessionManager.set_full_token("GE-Video360:PLAYING")

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


## Insert the specified item in the set of visited items (legacy; step 2 will tie this to tokens).
func mark_as_visited(item_id: int) -> void:
	_visited_items[item_id] = true
	print("Visited items: ", _visited_items.keys())


func have_been_visited(ids: Array[int]) -> bool:
	for id in ids:
		if not _visited_items.has(id):
			return false
	return true
