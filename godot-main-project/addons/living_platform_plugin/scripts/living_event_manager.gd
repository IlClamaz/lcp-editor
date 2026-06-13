extends Node

# Runtime holder for the current environment's Omeka events (LivingEvent resources on LivingEnvironment).

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
	events.assign(env.omeka_events)

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
	_check_all_events(LivingEvent.TriggerType.CONDITION_CHECK, LivingSceneManager.get_current_scene().item_id)


func notify_stargate_collided(stargate_id: int):
	_check_all_events(LivingEvent.TriggerType.STARGATE_COLLIDED, stargate_id)


func notify_button_held(button_id: int):
	_check_all_events(LivingEvent.TriggerType.BUTTON_HELD, button_id)


func notify_item_visited(item_id: int):
	LivingSessionManager.set_item_state(item_id, "VISITED")
	LivingSessionManager.debug_dump()
	notify_conditions_check()


func notify_environment_changed(new_env_id: int):
	LivingSessionManager.set_item_state(new_env_id, "VISITED")
	# TODO -- Update also USER_LOCATION variable ???


func notify_training_completed() -> void:
	LivingSessionManager.set_item_state(LivingSceneManager.get_current_scene().item_id, "TRAINING-COMPLETED")
	notify_conditions_check()


func notify_training_failed() -> void:
	LivingSessionManager.set_item_state(LivingSceneManager.get_current_scene().item_id, "TRAINING-FAILED")
	notify_conditions_check()


func notify_end_video360(video_id: int):
	# TODO
	pass



#
# EVENT CHECKING
#
func _check_all_events(trigger_type: LivingEvent.TriggerType, triggering_item_id: int):

	for event in events:
		if trigger_type == event.trigger_type:
			print("LivingEventManager: checking event #%d for trigger type %s and item id %d." % [event.id, LivingEvent.TriggerType.keys()[trigger_type], triggering_item_id])
			if triggering_item_id == event.triggering_item_id:
				if _check_preconditions(event.preconditions):
					_exec_action(event)
					_apply_effects(event)


# Verifica che tutte le preconditions (token ENTITY:STATE) corrispondano allo stato di sessione corrente.
func _check_preconditions(preconditions: Array[String]) -> bool:
	if preconditions.is_empty():
		return true

	if not LivingSessionManager.is_state_ready():
		push_warning("LivingEventManager: cannot check preconditions — session state not ready.")
		return false

	for precondition in preconditions:
		var required := precondition.strip_edges()
		if required == "":
			continue
		if not LivingSessionManager.matches_full_token(required):
			print("LivingEventManager: precondition '%s' not met." % required)
			return false
	print("LivingEventManager: all preconditions met.")
	return true


func _exec_action(event: LivingEvent) -> void:

	match event.action:

		LivingEvent.ActionType.ACTIVATE_TRIGGER:
			if event.action_params.is_empty():
				push_warning("LivingEventManager: ACTIVATE_TRIGGER missing action_params on event #%d." % event.id)
				return
			var target_trigger_id: int = event.action_params[0]
			var env := LivingSceneManager.get_current_scene()
			if env == null:
				return
			for node in env.find_children("*", "LivingPortal", true, false):
				if node is LivingPortal and node.item_id == target_trigger_id:
					node.activate() # Attiviamo il portale...
					return
			push_warning(
				"LivingEventManager: no LivingPortal with item_id %d for ACTIVATE_TRIGGER (event #%d)."
				% [target_trigger_id, event.id]
			)

		LivingEvent.ActionType.JUMP_TO_ENVIRONMENT:
			LivingSessionManager.set_item_state(event.triggering_item_id, "USED")
			var target_env = event.action_params[0]
			print("Jumping to env ")
			LivingSceneManager.go_to_scene(target_env)

		LivingEvent.ActionType.PLAY_VIDEO_360:
			var living_video360_item_id = event.action_params[0]
			var video_player: LivingVideo360 = null  # TODO: resolve reference
			video_player.seek(0)
			video_player.play()


# Applica gli effects dell'evento scrivendo i token ENTITY:STATE nello stato di sessione.
func _apply_effects(event: LivingEvent) -> void:
	if event == null or event.effects.is_empty():
		return

	if not LivingSessionManager.is_state_ready():
		push_warning("LivingEventManager: cannot apply effects — session state not ready.")
		return

	for effect in event.effects:
		var token := effect.strip_edges()
		if token == "":
			continue
		if not LivingSessionManager.set_full_token(token):
			push_warning(
				"LivingEventManager: failed to apply effect '%s' for event #%d."
				% [token, event.id]
			)
