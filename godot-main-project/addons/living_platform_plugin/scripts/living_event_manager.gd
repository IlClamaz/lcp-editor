extends Node

# Runtime holder for the current environment's Omeka events (normalized dictionaries on LivingEnvironment).

var events: Array[LivingEvent] = []

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


#
# NOTIFICATION functions
# Public API for any class in the project that need to notify an event
#

func notify_conditions_check():
	# TODO
	pass


func notify_stargate_collided(stargate_id: int):
	# TODO
	pass


func notify_button_held(button_id: int):
	# TODO
	pass


func notify_item_visited(item_id: int):
	# TODO
	self._check_all_events(item_id)
	pass


func notify_environment_changed(new_env_id: int):
	# TODO
	pass


func notify_end_video360(video_id: int):
	# TODO
	pass



#
# EVENT CHECKING
#
func _check_all_events(trigger_type: LivingEvent.TriggerType, triggering_item_id: int):

	for event in self.events:
		# First check: if the current environment matches the event environment
		if LivingSceneManager.get_current_scene().item_id == event.environment_id:
			# Check if the trigger type matches
			if trigger_type == event.trigger_type:
				#  Check if the event is triggered by the corresponding id
				if triggering_item_id == event.triggering_item_id:
					# Check the preconditions of the event
					if event.check_preconditions():
						# Execute the action
						event.exec_action()
						# Execute the effects
						self._apply_effects(event)



func _apply_effects(event: LivingEvent):
	# TODO
	pass
