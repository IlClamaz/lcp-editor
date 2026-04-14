@tool
extends RefCounted
class_name OmekaEventQueryService

# Domain service for events:
# - query all event items
# - normalize event payload
# - resolve environment scope (environment + nested components/areas)
# - filter by scope_item_ids

const EVENT_CLASS_TYPE := "lcp_form-event:Event"
const EVENT_TYPE_KEY := "lcp_form-event:has_event_type_f"
const EVENT_ORIGIN_KEY := "lcp_form-event:has_origin_participatory_item_f"
const EVENT_DESTINATION_KEY := "lcp_form-event:has_destination_participatory_item_f"
const EVENT_ORIGIN_STATE_KEY := "lcp_form-event:has_origin_state_f"
const EVENT_DESTINATION_STATE_KEY := "lcp_form-event:has_destination_state_f"
const EVENT_PRECONDITIONS_KEY := "lcp_form-event:has_preconditions_f"
const EVENT_DESCRIPTION_KEY := "dcterms:description"
const CHILD_COMPONENTS_KEY := "lcp_form:is_composed_of_f"
const CHILD_AREAS_KEY := "lcp_form:has_participatory_area_f"

var _query_cache: OmekaQueryCache


func _init(query_cache: OmekaQueryCache = null) -> void:
	# Allows dependency injection in tests; defaults to shared cache in production.
	_query_cache = query_cache if query_cache != null else OmekaQueryCache.shared()


func list_events_for_environment(
	host: Node,
	env: LivingEnvironment,
	force_refresh: bool = false
) -> Dictionary:
	# Convenience overload when the caller already has the scene root environment.
	if env == null:
		return {"ok": false, "error": "Invalid environment"}

	var base_url := str(env.OMEKA_BASE_URL).strip_edges().trim_suffix("/")
	var environment_id := int(env.item_id)
	return await list_events_for_environment_id(host, base_url, environment_id, force_refresh)


func list_events_for_environment_id(
	host: Node,
	base_url: String,
	environment_id: int,
	force_refresh: bool = false
) -> Dictionary:
	# Full workflow: resolve scope ids first, then filter events against that scope.
	if host == null:
		return {"ok": false, "error": "Invalid host"}
	if environment_id <= 0:
		return {"ok": false, "error": "Invalid environment id"}

	var scope_result := await _collect_scope_item_ids(host, base_url, environment_id, force_refresh)
	if not scope_result.get("ok", false):
		return scope_result

	var scope_ids: Array[int] = scope_result.get("scope_ids", [])
	var events_result := await list_events_for_scope(host, base_url, scope_ids, force_refresh)
	if not events_result.get("ok", false):
		return events_result

	events_result["scope_ids"] = scope_ids
	return events_result


# Return shape:
# {
#   "ok": bool,
#   "events": Array[Dictionary],
#   "events_by_item_id": Dictionary,
#   "error": String?
# }
func list_events_for_scope(
	host: Node,
	base_url: String,
	scope_item_ids: Array[int],
	force_refresh: bool = false
) -> Dictionary:
	# Scope-only query used by higher-level callers that already computed scope ids.
	var all_items_result := await _query_cache.get_all_items(host, base_url, force_refresh)
	if not all_items_result.get("ok", false):
		return all_items_result

	var scope_set := {}
	for sid in scope_item_ids:
		var iid := int(sid)
		if iid > 0:
			scope_set[iid] = true

	if scope_set.is_empty():
		return {"ok": true, "events": [], "events_by_item_id": {}}

	var filtered_events: Array[Dictionary] = []
	var events_by_item_id := {}
	var all_items: Array = all_items_result.get("items", [])

	for item in all_items:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		if not _is_event_item(item):
			continue

		var linked_ids := _extract_event_linked_item_ids(item)
		if not _matches_scope(linked_ids, scope_set):
			continue

		var summary := _build_event_summary(item)
		filtered_events.append(summary)
		_attach_event_to_scope_items(summary, linked_ids, scope_set, events_by_item_id)

	return {
		"ok": true,
		"events": filtered_events,
		"events_by_item_id": events_by_item_id
	}


func _is_event_item(item: Dictionary) -> bool:
	# Event classification is based on Omeka @type membership.
	var types = item.get("@type", [])
	return typeof(types) == TYPE_ARRAY and EVENT_CLASS_TYPE in types


func _extract_event_linked_item_ids(item: Dictionary) -> Array[int]:
	# Collects item ids referenced as event origin and destination.
	var out: Array[int] = []
	_append_relation_ids(item, EVENT_ORIGIN_KEY, out)
	_append_relation_ids(item, EVENT_DESTINATION_KEY, out)
	return out


func _append_relation_ids(item: Dictionary, key: String, out: Array[int]) -> void:
	# Shared relation parser for value_resource_id arrays.
	var rel = item.get(key, [])
	if typeof(rel) != TYPE_ARRAY:
		return
	for entry in rel:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var rid := int(entry.get("value_resource_id", 0))
		if rid > 0 and not out.has(rid):
			out.append(rid)


func _matches_scope(linked_ids: Array[int], scope_set: Dictionary) -> bool:
	# Event is in scope if at least one linked item belongs to the scope set.
	for linked_id in linked_ids:
		if scope_set.has(linked_id):
			return true
	return false


func _attach_event_to_scope_items(event_summary: Dictionary, linked_ids: Array[int], scope_set: Dictionary, out_map: Dictionary) -> void:
	# Builds reverse index: item_id -> list of matching event summaries.
	for linked_id in linked_ids:
		if not scope_set.has(linked_id):
			continue
		if not out_map.has(linked_id):
			out_map[linked_id] = []
		out_map[linked_id].append(event_summary)


func _build_event_summary(item: Dictionary) -> Dictionary:
	# App-level event payload used by EventManager and editor tooling.
	return {
		"id": int(item.get("o:id", 0)),
		"title": str(item.get("o:title", "No Title")),
		"description": _extract_literal(item, EVENT_DESCRIPTION_KEY),
		"event_type": _extract_literal(item, EVENT_TYPE_KEY),
		"origin_ids": _extract_relation_ids(item, EVENT_ORIGIN_KEY),
		"destination_ids": _extract_relation_ids(item, EVENT_DESTINATION_KEY),
		"origin_state": _extract_literal(item, EVENT_ORIGIN_STATE_KEY),
		"destination_state": _extract_literal(item, EVENT_DESTINATION_STATE_KEY),
		"preconditions": _extract_literal(item, EVENT_PRECONDITIONS_KEY),
		"item": item
	}


func _extract_relation_ids(item: Dictionary, key: String) -> Array[int]:
	# Immutable helper that returns a new array instead of mutating an external one.
	var out: Array[int] = []
	_append_relation_ids(item, key, out)
	return out


func _extract_literal(item: Dictionary, key: String) -> String:
	# Omeka literals are stored as arrays of value objects; this returns the first value.
	var values = item.get(key, [])
	if typeof(values) != TYPE_ARRAY or values.is_empty():
		return ""
	var first = values[0]
	if typeof(first) != TYPE_DICTIONARY:
		return ""
	return str(first.get("@value", "")).strip_edges()


func _collect_scope_item_ids(host: Node, base_url: String, root_env_id: int, force_refresh: bool) -> Dictionary:
	# Computes full environment scope by traversing composed items and areas.
	var visited := {}
	var scope_ids: Array[int] = []
	await _collect_scope_recursive(host, base_url, root_env_id, force_refresh, visited, scope_ids)
	return {"ok": true, "scope_ids": scope_ids}


func _collect_scope_recursive(
	host: Node,
	base_url: String,
	item_id: int,
	force_refresh: bool,
	visited: Dictionary,
	scope_ids: Array[int]
) -> void:
	# DFS traversal with cycle guard (`visited`) to handle graph-like references safely.
	if item_id <= 0:
		return
	if visited.has(item_id):
		return

	visited[item_id] = true
	if not scope_ids.has(item_id):
		scope_ids.append(item_id)

	var item_result := await _query_cache.get_item_by_id(host, base_url, item_id, force_refresh)
	if not item_result.get("ok", false):
		return

	var item: Dictionary = item_result.get("item", {})
	if typeof(item) != TYPE_DICTIONARY:
		return

	for child_id in _extract_relation_ids(item, CHILD_COMPONENTS_KEY):
		await _collect_scope_recursive(host, base_url, child_id, force_refresh, visited, scope_ids)
	for area_id in _extract_relation_ids(item, CHILD_AREAS_KEY):
		await _collect_scope_recursive(host, base_url, area_id, force_refresh, visited, scope_ids)
