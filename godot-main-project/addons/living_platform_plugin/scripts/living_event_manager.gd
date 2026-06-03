extends Node

# Runtime holder for the current environment's Omeka events (normalized dictionaries on LivingEnvironment).

var events: Array = []

var _event_service := OmekaEventService.new()


# Clears the in-memory event list for the previous scene.
func clear_events() -> void:
	events.clear()


# Reads env.omeka_events from the scene (populated in editor via Restore) and prints them.
# Returns { "ok": bool, "events": Array, "error": String? }
func load_for_environment(env: LivingEnvironment) -> Dictionary:
	clear_events()
	if env == null:
		return {"ok": false, "error": "Invalid environment"}

	var env_id := int(env.item_id)
	for entry in env.omeka_events:
		if typeof(entry) == TYPE_DICTIONARY:
			events.append(entry)

	if events.is_empty():
		push_warning(
			"LivingEventManager: no events on scene for environment id %d — "
			+ "run Restore Saved Components in the editor and save the scene."
			% env_id
		)
	else:
		_event_service.print_events_to_console(events, env_id, env.title)

	print("LivingEventManager: %d event(s) for environment id %d." % [events.size(), env_id])
	return {"ok": true, "events": events}
