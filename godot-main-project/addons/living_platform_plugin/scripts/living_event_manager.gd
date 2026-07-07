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


func notify_button_held_10s(button_id: int):
	_check_all_events(LivingEvent.TriggerType.BUTTON_HELD_10S, button_id)


func notify_item_visited(item_id: int):
	var visit := LivingSessionManager.get_item_state_value(item_id, "VISIT")
	if visit == "":
		return
	if visit == "NON-VISITED":
		LivingSessionManager.set_item_state(item_id, "VISIT", "VISITED")
		notify_conditions_check()


func notify_environment_changed(new_env_id: int):
	var visit := LivingSessionManager.get_item_state_value(new_env_id, "VISIT")
	if visit == "NON-VISITED":
		LivingSessionManager.set_item_state(new_env_id, "VISIT", "VISITED")
	_check_all_events(LivingEvent.TriggerType.ENVIRONMENT_CHANGED, new_env_id)
	sync_scene_presentation_from_session()


func notify_training_completed() -> void:
	LivingSessionManager.set_item_state(
		LivingSceneManager.get_current_scene().item_id, "TRAINING", "COMPLETED"
	)
	notify_conditions_check()


func notify_training_failed() -> void:
	LivingSessionManager.set_item_state(
		LivingSceneManager.get_current_scene().item_id, "TRAINING", "FAILED"
	)
	notify_conditions_check()


func notify_end_video360(video_id: int):
	LivingSessionManager.set_item_state(video_id, "PLAYING", "PAUSE-100%")
	_check_all_events(LivingEvent.TriggerType.END_VIDEO360, video_id)



#
# SCENE PRESENTATION (session → nodes in current environment)
#

## Applies current session state to scene nodes (portals, highlight lights).
func sync_scene_presentation_from_session() -> void:
	if not LivingSessionManager.is_state_ready():
		push_warning("LivingEventManager: sync_scene_presentation_from_session skipped — session not ready.")
		return

	var env := LivingSceneManager.get_current_scene()
	if env == null:
		return

	_sync_portals_from_session(env)
	_sync_lights_from_session(env)


func _sync_portals_from_session(env: LivingEnvironment) -> void:
	var registry := LivingSessionManager.get_registry()
	for node in env.find_children("*", "LivingPortal", true, false):
		if not node is LivingPortal:
			continue
		var portal := node as LivingPortal
		var item_id: int = portal.get_parent().item_id
		if item_id <= 0:
			continue
		var entity_key := LivingSessionManager.get_item_code(item_id)
		if entity_key == "":
			continue

		var activation := ""
		var use_state := ""
		if registry.has_variable(entity_key, "ACTIVATION"):
			activation = LivingSessionManager.get_item_state_value(item_id, "ACTIVATION")
		if registry.has_variable(entity_key, "USE"):
			use_state = LivingSessionManager.get_item_state_value(item_id, "USE")
		if activation == "" and use_state == "":
			continue
		portal.apply_presentation_state(activation, use_state)
		if activation == "ACTIVE" or use_state == "USED": # To keep training portals open after training completion.
			portal.get_parent().show()


func _sync_lights_from_session(env: LivingEnvironment) -> void:
	for node in env.find_children("*", "LivingLight", true, false):
		if not node is LivingLight:
			continue
		var light := node as LivingLight
		if light.target_item == null or light.target_item.item_id <= 0:
			continue
		var highlight := LivingSessionManager.get_item_state_value(light.target_item.item_id, "HIGHLIGHT")
		if highlight == "ON":
			light.set_highlighted(true)
		elif highlight == "OFF":
			light.set_highlighted(false)


#
# EVENT CHECKING
#
func _check_all_events(trigger_type: LivingEvent.TriggerType, triggering_item_id: int) -> void:
	for event in events:
		if trigger_type == event.trigger_type:
			print("LivingEventManager: checking event #%d for trigger type %s and item id %d." % [event.id, LivingEvent.TriggerType.keys()[trigger_type], triggering_item_id])
			if triggering_item_id == event.triggering_item_id:
				if _check_preconditions(event.preconditions):
					_exec_action(event)
					_update_effects(event)


# Verifica che tutte le preconditions (token ENTITY:VARIABLE:VALUE) corrispondano allo stato di sessione corrente.
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
			var env := LivingSceneManager.get_current_scene()
			for target_trigger_id in event.action_params:
				for node in env.find_children("*", "LivingPortal", true, false):
					if node is LivingPortal and node.get_parent().item_id == target_trigger_id:
						if node._portal_state == LivingPortal.PortalState.INACTIVE: # In case some event is retriggered.
							node.activate()
							break

		LivingEvent.ActionType.JUMP_TO_ENVIRONMENT:
			var target_env = event.action_params[0]
			LivingSceneManager.go_to_scene(target_env)

		LivingEvent.ActionType.PLAY_VIDEO_360:
			if event.action_params.is_empty():
				push_warning("LivingEventManager: PLAY_VIDEO_360 missing action_params on event #%d." % event.id)
				return
			var video_item_id: int = event.action_params[0]
			var env := LivingSceneManager.get_current_scene()
			if env == null:
				return
			for node in env.find_children("*", "LivingVideo360", true, false): 
				# SIA QUESTO CHE IL PORTALE VERRANNO SOSTITUITI DAL LIVINGSTARGATEOBJ e LIVING360VIDEOOBJ
				if node is LivingVideo360 and node.get_parent().item_id == video_item_id:
					node.play_from_start()
					return
			push_warning(
				"LivingEventManager: no LivingVideo360 with item_id %d for PLAY_VIDEO_360 (event #%d)."
				% [video_item_id, event.id]
			)


# Aggiorna gli effects dell'evento scrivendo i token ENTITY:VARIABLE:VALUE nello stato di sessione.
func _update_effects(event: LivingEvent) -> void:
	if event == null or event.effects.is_empty():
		return

	if not LivingSessionManager.is_state_ready():
		push_warning("LivingEventManager: cannot update effects — session state not ready.")
		return

	for effect in event.effects:
		var token := effect.strip_edges()
		if token == "":
			continue
		if not LivingSessionManager.set_full_token(token):
			push_warning(
				"LivingEventManager: failed to update effect '%s' for event #%d."
				% [token, event.id]
			)
	LivingSessionManager.debug_dump()
