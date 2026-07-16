@tool
extends RefCounted
class_name OmekaEventService

# Recupera da Omeka gli eventi collegati a un environment (lcp_form-event:has_environment).

var _query: OmekaQueryService


# Crea il servizio; accetta un OmekaQueryService opzionale (utile per i test).
func _init(query: OmekaQueryService = null) -> void:
	_query = query if query != null else OmekaQueryService.new()


# Interroga Omeka per tutti gli eventi legati a environment_id e li restituisce come LivingEvent.
# Ritorna { "ok": bool, "events": Array[LivingEvent], "error": String? }.
func fetch_events_for_environment(host: Node, base_url: String, environment_id: int) -> Dictionary:
	if host == null:
		return {"ok": false, "error": "Invalid host"}
	if environment_id <= 0:
		return {"ok": false, "error": "Invalid environment id"}

	var query_suffix := (
		"property[0][property]=%s&property[0][type]=res&property[0][text]=%d"
		% [LivingConstants.OMEKA_KEY_EVENT_ENVIRONMENT, environment_id]
	)
	var search_result := await _query.search_items(host, base_url, query_suffix)
	if not search_result.get("ok", false):
		return search_result

	var events: Array[LivingEvent] = []
	for raw_item in search_result.get("items", []):
		if raw_item is Dictionary and LivingConstants.OMEKA_KEY_EVENT_CLASS_TYPE in raw_item.get("@type", []):
			events.append(_to_living_event(raw_item))

	return {"ok": true, "events": events}


# Stampa in console un riepilogo leggibile degli eventi (editor / debug).
func print_events_to_console(events: Array[LivingEvent], environment_id: int, environment_title: String = "") -> void:
	var label := environment_title.strip_edges()
	var header := "LivingEnvironment '%s'" % label if label != "" else "LivingEnvironment"
	print("%s: %d event(s) linked to environment id %d." % [header, events.size(), environment_id])
	for event in events:
		var event_title: String = event.title.strip_edges()
		var title_part: String = ""
		if event_title != "":
			title_part = " '%s'" % event_title
		print(
			" - Event #%d%s | trigger=%s | item=%d | action=%s | params=%s | pre=%s | effects=%s"
			% [
				event.id,
				title_part,
				LivingEvent.TriggerType.keys()[event.trigger_type],
				event.triggering_item_id,
				LivingEvent.ActionType.keys()[event.action],
				event.action_params,
				event.preconditions,
				event.effects,
			]
		)


# Converte un item Omeka grezzo (JSON) in un LivingEvent popolato.
func _to_living_event(item: Dictionary) -> LivingEvent:
	var event := LivingEvent.new()
	event.id = int(item.get(LivingConstants.OMEKA_KEY_ID, 0))
	event.title = str(item.get(LivingConstants.OMEKA_KEY_TITLE, "")).strip_edges()
	event.environment_id = _resource_id(item, LivingConstants.OMEKA_KEY_EVENT_ENVIRONMENT)
	var trigger_key := _normalize_enum_key(_literal(item, LivingConstants.OMEKA_KEY_EVENT_TRIGGER_TYPE))
	event.trigger_type = (
		LivingEvent.TriggerType[trigger_key]
		if trigger_key in LivingEvent.TriggerType
		else LivingEvent.TriggerType.CONDITION_CHECK
	)
	event.triggering_item_id = _resource_id(item, LivingConstants.OMEKA_KEY_EVENT_TRIGGER_ARG)
	event.preconditions = _literals(item, LivingConstants.OMEKA_KEY_EVENT_PRECONDITIONS)
	var action_key := _normalize_enum_key(_literal(item, LivingConstants.OMEKA_KEY_EVENT_ACTION_TYPE))
	event.action = (
		LivingEvent.ActionType[action_key]
		if action_key in LivingEvent.ActionType
		else LivingEvent.ActionType.ACTIVATE_TRIGGER
	)
	event.action_params = _resource_ids(item, LivingConstants.OMEKA_KEY_EVENT_ACTION_PARAMS)
	event.effects = _literals(item, LivingConstants.OMEKA_KEY_EVENT_ACTION_EFFECTS)
	return event


func _normalize_enum_key(value: String) -> String:
	return value.strip_edges().to_upper().replace(" ", "_").replace("-", "_")


# Legge il primo valore testuale (@value) di una proprietà Omeka.
func _literal(item: Dictionary, key: String) -> String:
	var values := _literals(item, key)
	return values[0] if not values.is_empty() else ""


# Legge tutti i valori testuali (@value) di una proprietà Omeka, senza duplicati.
func _literals(item: Dictionary, key: String) -> Array[String]:
	var out: Array[String] = []
	for entry in item.get(key, []):
		if entry is Dictionary:
			var text := str(entry.get(LivingConstants.OMEKA_KEY_AT_VALUE, "")).strip_edges()
			if text != "" and not out.has(text):
				out.append(text)
	return out


# Legge il primo riferimento ad item Omeka (value_resource_id) di una proprietà.
func _resource_id(item: Dictionary, key: String) -> int:
	for entry in item.get(key, []):
		if entry is Dictionary:
			return int(entry.get(LivingConstants.OMEKA_KEY_VALUE_RESOURCE_ID, 0))
	return 0


# Legge tutti i riferimenti ad item Omeka (value_resource_id) di una proprietà, senza duplicati.
func _resource_ids(item: Dictionary, key: String) -> Array[int]:
	var out: Array[int] = []
	for entry in item.get(key, []):
		if entry is Dictionary:
			var resource_id := int(entry.get(LivingConstants.OMEKA_KEY_VALUE_RESOURCE_ID, 0))
			if resource_id > 0 and not out.has(resource_id):
				out.append(resource_id)
	return out
