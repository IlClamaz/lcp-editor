@tool
extends RefCounted
class_name OmekaEventService

# Recupera da Omeka gli eventi collegati a un environment (lcp_form-event:has_environment).

const EVENT_CLASS_TYPE := "lcp_form-event:Event"
const EVENT_ENVIRONMENT_KEY := "lcp_form-event:has_environment"
const EVENT_TRIGGER_TYPE_KEY := "lcp_form-event:has_trigger_type_f"
const EVENT_TRIGGER_ARG_KEY := "lcp_form-event:has_trigger_arg_f"
const EVENT_PRECONDITIONS_KEY := "lcp_form-event:has_trigger_preconditions_f"
const EVENT_ACTION_TYPE_KEY := "lcp_form-event:has_action_type_f"
const EVENT_ACTION_PARAMS_KEY := "lcp_form-event:has_action_params_f"
const EVENT_ACTION_EFFECTS_KEY := "lcp_form-event:has_action_effects_f"

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
		% [EVENT_ENVIRONMENT_KEY, environment_id]
	)
	var search_result := await _query.search_items(host, base_url, query_suffix)
	if not search_result.get("ok", false):
		return search_result

	var events: Array[LivingEvent] = []
	for raw_item in search_result.get("items", []):
		if raw_item is Dictionary and EVENT_CLASS_TYPE in raw_item.get("@type", []):
			events.append(_to_living_event(raw_item))

	return {"ok": true, "events": events}


# Stampa in console un riepilogo leggibile degli eventi (editor / debug).
func print_events_to_console(events: Array[LivingEvent], environment_id: int, environment_title: String = "") -> void:
	var label := environment_title.strip_edges()
	var header := "LivingEnvironment '%s'" % label if label != "" else "LivingEnvironment"
	print("%s: %d event(s) linked to environment id %d." % [header, events.size(), environment_id])
	for event in events:
		print(
			" - Event #%d | trigger=%s | item=%d | action=%s | params=%s | pre=%s | effects=%s"
			% [
				event.id,
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
	event.id = int(item.get("o:id", 0))
	event.environment_id = _resource_id(item, EVENT_ENVIRONMENT_KEY)
	event.trigger_type = _parse_enum(
		_literal(item, EVENT_TRIGGER_TYPE_KEY),
		LivingEvent.TriggerType,
		LivingEvent.TriggerType.CONDITION_CHECK
	)
	event.triggering_item_id = _resource_id(item, EVENT_TRIGGER_ARG_KEY)
	event.preconditions = _literals(item, EVENT_PRECONDITIONS_KEY)
	event.action = _parse_enum(
		_literal(item, EVENT_ACTION_TYPE_KEY),
		LivingEvent.ActionType,
		LivingEvent.ActionType.ACTIVATE_TRIGGER
	)
	event.action_params = _resource_ids(item, EVENT_ACTION_PARAMS_KEY)
	event.effects = _literals(item, EVENT_ACTION_EFFECTS_KEY)
	return event


# Mappa una stringa Omeka al valore corrispondente di un enum; usa default se non riconosciuta.
func _parse_enum(value: String, enum_type: Variant, default: int) -> int:
	var key := value.strip_edges().to_upper().replace(" ", "_").replace("-", "_")
	if key == "ENVIRONMENT_STATE_CHANGED":
		key = "CONDITION_CHECK"
	for name in enum_type.keys():
		if name.to_upper() == key:
			return enum_type[name]
	push_warning("OmekaEventService: unknown value '%s'" % value)
	return default


# Legge il primo valore testuale (@value) di una proprietà Omeka.
func _literal(item: Dictionary, key: String) -> String:
	var values := _literals(item, key)
	return values[0] if not values.is_empty() else ""


# Legge tutti i valori testuali (@value) di una proprietà Omeka, senza duplicati.
func _literals(item: Dictionary, key: String) -> Array[String]:
	var out: Array[String] = []
	for entry in item.get(key, []):
		if entry is Dictionary:
			var text := str(entry.get("@value", "")).strip_edges()
			if text != "" and not out.has(text):
				out.append(text)
	return out


# Legge il primo riferimento ad item Omeka (value_resource_id) di una proprietà.
func _resource_id(item: Dictionary, key: String) -> int:
	for entry in item.get(key, []):
		if entry is Dictionary:
			return int(entry.get("value_resource_id", 0))
	return 0


# Legge tutti i riferimenti ad item Omeka (value_resource_id) di una proprietà, senza duplicati.
func _resource_ids(item: Dictionary, key: String) -> Array[int]:
	var out: Array[int] = []
	for entry in item.get(key, []):
		if entry is Dictionary:
			var resource_id := int(entry.get("value_resource_id", 0))
			if resource_id > 0 and not out.has(resource_id):
				out.append(resource_id)
	return out
