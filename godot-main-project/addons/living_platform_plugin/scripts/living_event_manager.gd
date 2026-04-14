@tool
extends Node

# Runtime/editor registry of instantiated LivingEvent objects.
# Omeka retrieval is delegated to OmekaEventQueryService.
var registered_events: Array[LivingEvent] = []

var _event_query_service := OmekaEventQueryService.new()


func register_event(event: LivingEvent) -> void:
	# Registers a single event instance in the active manager list.
	if event == null:
		return
	registered_events.append(event)


func register_events(events: Array[LivingEvent]) -> void:
	# Convenience batch registration.
	for event in events:
		register_event(event)


func clear_events() -> void:
	# Clears the active event set (used on scene/environment switches).
	registered_events.clear()


func load_for_environment(
	host: Node,
	env: LivingEnvironment,
	force_refresh: bool = false,
	dispatch_environment_shown: bool = true
) -> Dictionary:
	# High-level loader when the caller already has a LivingEnvironment node.
	if env == null:
		return {"ok": false, "error": "Invalid environment"}

	var base_url := str(env.OMEKA_BASE_URL).strip_edges().trim_suffix("/")
	if base_url == "":
		return {"ok": false, "error": "Invalid base URL"}

	return await load_for_environment_id(
		host,
		base_url,
		int(env.item_id),
		force_refresh,
		env,
		dispatch_environment_shown
	)


func load_for_environment_id(
	host: Node,
	base_url: String,
	environment_id: int,
	force_refresh: bool = false,
	scene_env: LivingEnvironment = null,
	dispatch_environment_shown: bool = false
) -> Dictionary:
	# Loads event summaries from Omeka, instantiates LivingEvent objects, and registers them.
	if host == null:
		return {"ok": false, "error": "Invalid host"}
	if environment_id <= 0:
		return {"ok": false, "error": "Invalid environment id"}

	var query_result = await _event_query_service.list_events_for_environment_id(
		host,
		base_url,
		environment_id,
		force_refresh
	)
	if not query_result.get("ok", false):
		return query_result

	var scope_ids: Array[int] = query_result.get("scope_ids", [])
	var event_summaries: Array = query_result.get("events", [])
	var events_by_item_id: Dictionary = query_result.get("events_by_item_id", {})
	if event_summaries.is_empty():
		clear_events()
		return {"ok": true, "events": [], "scope_ids": scope_ids, "events_by_item_id": {}}

	var item_map := _build_scene_item_map(scene_env)
	var living_events := _build_living_events(event_summaries, item_map)

	clear_events()
	register_events(living_events)

	if dispatch_environment_shown and scene_env != null:
		dispatch_on_environment_shown(scene_env)

	return {
		"ok": true,
		"events": event_summaries,
		"scope_ids": scope_ids,
		"events_by_item_id": events_by_item_id
	}


func dispatch_on_environment_shown(env: LivingItem = null) -> void:
	# Calls event hook only for events linked to the shown environment.
	for event in registered_events:
		if event == null:
			continue
		if not event.matches_environment(env):
			continue
		event._on_environment_shown(env)


func dispatch_on_process() -> void:
	# Frame/process dispatch for all registered events.
	for event in registered_events:
		if event == null:
			continue
		event._on_process()


func dispatch_on_user_click() -> void:
	# User-click dispatch restricted to events that click the origin side.
	for event in registered_events:
		if event == null:
			continue
		if not event.clicks_origin():
			continue
		event._on_user_click()


func dispatch_on_triggered(source: Variant) -> void:
	# Dispatches triggered events filtered by source (id/item/portal).
	for event in registered_events:
		if event == null:
			continue
		if not event.matches_trigger_source(source):
			continue
		event._on_triggered(source)


func _build_scene_item_map(scene_env: LivingEnvironment) -> Dictionary:
	# Scene lookup map: item_id -> LivingItem instance.
	var map := {}
	if scene_env == null:
		return map

	if scene_env.item_id > 0:
		map[scene_env.item_id] = scene_env

	var all_items := scene_env.find_children("*", "LivingItem", true, false)
	for node in all_items:
		var item := node as LivingItem
		if item == null or item.item_id <= 0:
			continue
		map[item.item_id] = item

	return map


func _build_living_events(event_summaries: Array, item_by_id: Dictionary) -> Array[LivingEvent]:
	# Converts normalized event dictionaries to runtime LivingEvent instances.
	var out: Array[LivingEvent] = []

	for summary in event_summaries:
		if typeof(summary) != TYPE_DICTIONARY:
			continue

		var evt := LivingEvent.new()
		var origin_ids: Array = summary.get("origin_ids", [])
		var destination_ids: Array = summary.get("destination_ids", [])

		if not origin_ids.is_empty():
			evt.origin_id = int(origin_ids[0])
			if item_by_id.has(evt.origin_id):
				evt.originEPD = item_by_id[evt.origin_id]

		if not destination_ids.is_empty():
			var dest_id := int(destination_ids[0])
			if item_by_id.has(dest_id):
				evt.destEPD = item_by_id[dest_id]

		evt.origin_state = str(summary.get("origin_state", ""))
		evt.dest_state = str(summary.get("destination_state", ""))
		out.append(evt)

	return out
