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
	# Updated the game session
	var item_code: String = LivingSessionManager.get_item_code()
	LivingSessionManager.set_full_token(item_code + ":VISITED")

	self._check_all_events(LivingEvent.TriggerType.ENVIRONMENT_STATE_CHANGED, LivingSceneManager.get_current_scene().item_id)


func notify_environment_changed(new_env_id: int):
	# TODO
	# TODO -- Update also USER_LOCATION variable ???
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
					if _check_preconditions(event.preconditions):
						# Execute the action
						_exec_action(event)
						# Execute the effects
						self._apply_effects(event)


##
func _check_preconditions(preconditions: Array[String]) -> bool:
	# TODO
	return true


##
func _exec_action(event: LivingEvent) -> void:

	match self.action:

		LivingEvent.ActionType.ACTIVATE_TRIGGER:
			# TODO - update the token in the Session Manager
			print("Activating trigger...")

		LivingEvent.ActionType.JUMP_TO_ENVIRONMENT:
			var target_env = self.action_params[0]
			print("Jumping to env ")
			LivingSceneManager.go_to_scene(target_env)

		LivingEvent.ActionType.PLAY_VIDEO_360:
			var living_video360_item_id = self.action_params[0]
			var video_player: LivingVideo360 = null  # TODO: resolve reference
			video_player.seek(0)
			video_player.play()


##
func _apply_effects(event: LivingEvent):
	# TODO
	pass
