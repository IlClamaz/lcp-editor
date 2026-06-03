@tool
extends RefCounted
class_name OmekaEventService

# Fetches and normalizes Omeka events linked to an environment (lcp_form-event:has_environment).

const EVENT_CLASS_TYPE := "lcp_form-event:Event"
const EVENT_ENVIRONMENT_KEY := "lcp_form-event:has_environment"
const EVENT_TRIGGER_TYPE_KEY := "lcp_form-event:has_trigger_type_f"
const EVENT_TRIGGER_ARG_KEY := "lcp_form-event:has_trigger_arg_f"
const EVENT_PRECONDITIONS_KEY := "lcp_form-event:has_trigger_preconditions_f"
const EVENT_ACTION_TYPE_KEY := "lcp_form-event:has_action_type_f"
const EVENT_ACTION_PARAMS_KEY := "lcp_form-event:has_action_params_f"
const EVENT_ACTION_EFFECTS_KEY := "lcp_form-event:has_action_effects_f"
const EVENT_DESCRIPTION_KEY := "dcterms:description"

var _query: OmekaQueryService


func _init(query: OmekaQueryService = null) -> void:
	_query = query if query != null else OmekaQueryService.new()


# Returns { "ok": bool, "events": Array[Dictionary], "error": String? }
func fetch_events_for_environment(host: Node, base_url: String, environment_id: int) -> Dictionary:
	if host == null:
		return {"ok": false, "error": "Invalid host"}
	if environment_id <= 0:
		return {"ok": false, "error": "Invalid environment id"}

	var query_suffix := (
		"property[0][property]=%s&property[0][type]=res&property[0][text]=%d"
		% [EVENT_ENVIRONMENT_KEY, environment_id]
	)
	var search_result := await _query.search_items(host, base_url, query_suffix)
	if not search_result.get("ok", false):
		return search_result

	var normalized: Array[Dictionary] = []
	for raw_item in search_result.get("items", []):
		if typeof(raw_item) != TYPE_DICTIONARY:
			continue
		if not _is_event_item(raw_item):
			continue
		normalized.append(_normalize_event(raw_item))

	return {"ok": true, "events": normalized}


# Prints a human-readable summary of normalized events to the editor console.
func print_events_to_console(events: Array, environment_id: int, environment_title: String = "") -> void:
	var header := "LivingEnvironment"
	if environment_title.strip_edges() != "":
		header += " '%s'" % environment_title
	print("%s: %d event(s) linked to environment id %d." % [header, events.size(), environment_id])
	if events.is_empty():
		return

	for entry in events:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var event_id := int(entry.get("id", 0))
		var title := str(entry.get("title", "No Title"))
		var trigger := str(entry.get("trigger", ""))
		var trigger_arg := int(entry.get("trigger_arg_item_id", 0))
		var preconditions = entry.get("preconditions", [])
		var action := str(entry.get("action", ""))
		var action_param := int(entry.get("action_param_item_id", 0))
		var effects = entry.get("effects", [])
		print(" - Event #%d | %s" % [event_id, title])
		print(
			"   trigger=%s | trigger_arg_item_id=%d | action=%s | action_param_item_id=%d"
			% [trigger, trigger_arg, action, action_param]
		)
		print("   preconditions=%s | effects=%s" % [str(preconditions), str(effects)])


func _normalize_event(item: Dictionary) -> Dictionary:
	return {
		"id": int(item.get("o:id", 0)),
		"title": str(item.get("o:title", "No Title")),
		"environment_id": _first_resource_id(item, EVENT_ENVIRONMENT_KEY),
		"trigger": _first_literal(item, EVENT_TRIGGER_TYPE_KEY),
		"trigger_arg_item_id": _first_resource_id(item, EVENT_TRIGGER_ARG_KEY),
		"preconditions": _all_literals(item, EVENT_PRECONDITIONS_KEY),
		"action": _first_literal(item, EVENT_ACTION_TYPE_KEY),
		"action_param_item_id": _first_resource_id(item, EVENT_ACTION_PARAMS_KEY),
		"effects": _all_literals(item, EVENT_ACTION_EFFECTS_KEY),
		"description": _first_literal(item, EVENT_DESCRIPTION_KEY),
	}


func _is_event_item(item: Dictionary) -> bool:
	var types = item.get("@type", [])
	return typeof(types) == TYPE_ARRAY and EVENT_CLASS_TYPE in types


func _first_literal(item: Dictionary, key: String) -> String:
	var values = item.get(key, [])
	if typeof(values) != TYPE_ARRAY or values.is_empty():
		return ""
	var first = values[0]
	if typeof(first) != TYPE_DICTIONARY:
		return ""
	return str(first.get("@value", "")).strip_edges()


func _all_literals(item: Dictionary, key: String) -> Array[String]:
	var out: Array[String] = []
	var values = item.get(key, [])
	if typeof(values) != TYPE_ARRAY:
		return out
	for entry in values:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var text := str(entry.get("@value", "")).strip_edges()
		if text != "" and not out.has(text):
			out.append(text)
	return out


func _first_resource_id(item: Dictionary, key: String) -> int:
	var values = item.get(key, [])
	if typeof(values) != TYPE_ARRAY or values.is_empty():
		return 0
	var first = values[0]
	if typeof(first) != TYPE_DICTIONARY:
		return 0
	return int(first.get("value_resource_id", 0))
