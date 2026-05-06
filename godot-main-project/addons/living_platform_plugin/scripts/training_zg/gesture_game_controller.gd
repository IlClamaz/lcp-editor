extends Node3D
class_name GestureGameController


@export var animated_character: LivingElement
@export var living_camera: LivingCamera
@export var stargate_coreography: LivingPortal
@export var stargate_experience: LivingPortal

## Array di pose, mostrate in ordine
@export var gestures: Array[String]

## Abilitato per il debug
@export var debug_mode: bool = false
@export var arm_feedback_enabled: bool = true
@export var vr_hud_enabled: bool = true
@export var skip_tutorial: bool = false
@export var environment_lights: Array[Light3D]
@export var game_lights: Array[Light3D]

# Confirmation HUD settings
var confirm_hud_enabled: bool = true
var confirm_hud_offset: Vector3 = Vector3(0.0, -0.35, -0.8)
var confirm_hud_scale: float = 0.35
var confirm_hud_font_size: int = 8
var confirm_hud_font_depth: float = 0.002
var vr_hud_base_position: Vector3 = Vector3(-0.22, -0.2, -0.8)

# Player Nodes
var camera: XRCamera3D
var xr_origin: XROrigin3D
var left_controller: XRController3D
var right_controller: XRController3D

# Other nodes
var character: Living3DModelAnimated

# Stato interno
var _current_level: int = 0
var _remaining_trials: int = 3
var _current_size_index: int = 0  # [1.0, 2.0, 3.0, 4.0]
var _character_size_index: int = 0
var _pose_recognizer: PoseRecognizer
var _is_playing: bool = false
var _vr_hud_root: Node3D
var _vr_left_label: Label3D
var _vr_right_label: Label3D
var _vr_timer_label: Label3D
var _feedback_left_arm_line: MeshInstance3D
var _feedback_right_arm_line: MeshInstance3D
var _hud: LivingCaptionStandaloneHud
var _hud_confirmed: bool = false
var _hud_timeout_serial: int = 0
var _recognition_timer_left: float = GestureConstants.GAME_TIMER
var _timer_expired: bool = false


func _can_continue() -> bool:
	return is_inside_tree() and not is_queued_for_deletion()


func _has_live_character() -> bool:
	return is_instance_valid(character) and character.is_inside_tree()


func _has_live_xr_origin() -> bool:
	return is_instance_valid(xr_origin) and xr_origin.is_inside_tree()


func _has_live_camera() -> bool:
	return is_instance_valid(camera) and camera.is_inside_tree()


func _wait_seconds(seconds: float) -> bool:
	if not _can_continue():
		return false
	await get_tree().create_timer(seconds).timeout
	return _can_continue()



# Siccome il LivingCamera al momento istanzia la scena nel ready,
# dovremmo aspettare che tutto sia pronto prima di cercare i nodi necessari.
# Possiamo mettere una callback che ascolta la LivingCamera
# Potrebbe essere utile anche per altre cose...in generale rischiamo race condition
func _ready() -> void:
	if animated_character: 
		character = animated_character.find_child("Living3DModelAnimated*", true, false)
	else:
		push_error("GestureGameController: animated model not found")
		return
	
	if living_camera:
		camera = living_camera.find_child("XRCamera3D", true, false)
		xr_origin = living_camera.find_child("XROrigin3D", true, false)
		left_controller = living_camera.find_child("XRController3D_left", true, false)
		right_controller = living_camera.find_child("XRController3D_right", true, false)
		if living_camera.using_xr and stargate_coreography and stargate_experience:
			stargate_coreography.visible = false
			stargate_experience.visible = false
	else:
		push_error("GestureGameController: living_camera not found")
		return
	
	########

	if debug_mode:
		print("[INIT] GestureGameController initialized")
		print("  - Character: %s" % character.name)
		print("  - Camera: %s" % camera.name)
		print("  - XR Origin: %s" % xr_origin.name)
		print("  - Left Controller: %s" % left_controller.name)
		print("  - Right Controller: %s" % right_controller.name)
	
	# Crea il riconoscitore di pose
	_pose_recognizer = PoseRecognizer.new(left_controller, right_controller)
	add_child(_pose_recognizer)
	_setup_arm_feedback()
	_setup_hud()

	if vr_hud_enabled and camera:
		_vr_hud_root = Node3D.new()
		camera.add_child(_vr_hud_root)
		
		_vr_hud_root.position = _get_dynamic_vr_hud_position()

		_vr_left_label = _create_vr_hud_label(Vector3(0.0, 0.06, 0.0))
		_vr_right_label = _create_vr_hud_label(Vector3(0.0, 0.0, 0.0))
		_vr_timer_label = _create_vr_hud_label(Vector3(0.0, -0.06, 0.0))
		_vr_hud_root.add_child(_vr_left_label)
		_vr_hud_root.add_child(_vr_right_label)
		_vr_hud_root.add_child(_vr_timer_label)

		_update_vr_feedback_hud(0.0, 0.0)
		_set_vr_feedback_hud_visible(false)
	
	# Imposta lo stato iniziale
	tween_lights_by_order(game_lights, environment_lights, 0.01)
	_current_size_index = 0  # 1.0 di scala
	_character_size_index = 0
	_set_node_scale(xr_origin, GestureConstants.SIZE_SCALES[_current_size_index])
	_current_level = 0
	_remaining_trials = 3

	# START TUTORIAL
	if not skip_tutorial:
		if not await _wait_seconds(10.0):
			return
		_show_confirmation_hud("Maciste esegue 3 pose \n Tu dovrai imitarle.", false, 5.0)
		if not await _wait_seconds(5.0):
			return
		await start_tutorial()
		if not _can_continue():
			return
	
	# START GAME
	if not _has_live_character():
		return
	character.play_idle_pose()
	tween_lights_by_order(environment_lights, game_lights, 1.0, 0.5)
	if not await _wait_seconds(5.0):
		return
	start_game()


func start_tutorial() -> void:
	if gestures.is_empty() or not _can_continue() or not _has_live_character():
		return

	# Primo giro: mostra "Posa i" su ogni animazione.
	for i in range(gestures.size()):
		if not is_inside_tree():
			return

		await _play_tutorial_pose(gestures[i], i + 1, true)
		if not _can_continue() or not _has_live_character():
			return

	# Dopo il primo giro, aspettiamo la conferma utente ma continuiamo
	# a ciclare le pose con la stessa pausa a meta' (3 secondi).
	_show_confirmation_hud("Click qui \n Quando sei pronto")
	stargate_coreography.show()
	var loop_index: int = 0

	while is_inside_tree() and not _hud_confirmed:
		await _play_tutorial_pose(gestures[loop_index], loop_index + 1, false)
		if not _can_continue() or not _has_live_character():
			return
		loop_index = (loop_index + 1) % gestures.size()

	if _hud:
		_hud.hide_hud()


func _play_tutorial_pose(pose_name: String, pose_index: int, show_pose_hud: bool) -> void:
	if not _has_live_character() or not _can_continue():
		return
	_show_pose(pose_name)

	var anim_length: float = character.get_current_animation_length()
	if anim_length <= 0.0:
		anim_length = 2.0

	if show_pose_hud:
		_show_confirmation_hud("Posa %d" % pose_index, false, anim_length + 3.0, false)

	await _wait_until_animation_halfway()
	if not _has_live_character() or not _can_continue():
		return
	character.pause_animation()
	if not await _wait_seconds(3.0):
		return
	if not _has_live_character():
		return
	character.resume_animation()
	await character.await_animation_finish()
	if not _can_continue():
		return

	if show_pose_hud and _hud and _hud.has_active_prompt():
		_hud.hide_hud()


## Avvia il gioco
func start_game() -> void:
	print("Starting Gesture Game...")
	if _is_playing or not _can_continue() or not _has_live_character() or not _has_live_xr_origin():
		return

	_recognition_timer_left = GestureConstants.GAME_TIMER
	_timer_expired = false
	_update_vr_feedback_hud(0.0, 0.0)
	_is_playing = true
	
	_game_loop()

## Ferma il gioco
func stop_game() -> void:
	_is_playing = false
	_hud_confirmed = true
	_set_arm_feedback_visible(false)
	_set_vr_feedback_hud_visible(false)
	if _hud:
		_hud.hide_hud()


## Ciclo principale del gioco
func _game_loop() -> void:
	var hold_window_s: float = GestureConstants.HOLD_WINDOW

	while _is_playing and _current_level < GestureConstants.MAX_LEVEL:
		if not _can_continue() or not _has_live_character():
			return
		var pose_name: String = gestures[_current_level % gestures.size()]
		var success: bool = false
		_remaining_trials = 3

		# HUD guida persistente durante i tentativi della stessa posa.
		_show_confirmation_hud("Imita la Posa %d" % (_current_level + 1), false, -1.0, false)

		while _is_playing and not success:
			_show_pose(pose_name)
			await _wait_until_animation_halfway()
			if not _can_continue() or not _has_live_character():
				return
			character.pause_animation()

			# Durante i 15 secondi di pausa resta attivo il riconoscimento.
			success = await _recognize_pose(hold_window_s)
			if not _can_continue() or not _has_live_character():
				return

			character.resume_animation()
			await character.await_animation_finish()
			if not _can_continue():
				return
			if _timer_expired:
				var can_retry_level: bool = await _on_recognition_timer_expired()
				if not _can_continue():
					return
				if can_retry_level:
					# Dopo un timeout il prompt potrebbe essere stato nascosto/sostituito.
					# Lo ripristiniamo prima del nuovo tentativo della stessa posa.
					_show_confirmation_hud("Imita la Posa %d" % (_current_level + 1), false, -1.0, false)
					continue
				return

		if not _is_playing:
			break


		if _hud and _hud.has_active_prompt():
			_hud.hide_hud()
		_show_confirmation_hud("Corretto! \n Sei un gigante!", false, 5.0)
		if not await _wait_seconds(5.0):
			return
		_on_success()
		if _current_level >= GestureConstants.MAX_LEVEL:
			# Sul successo finale lasciamo tempo al tween di scala per essere percepito.
			if not await _wait_seconds(1.0):
				return

	if _is_playing:
		await _on_game_end()


func _wait_until_animation_halfway() -> void:
	if not _has_live_character() or not _can_continue():
		return
	while character.is_animation_playing():
		if character.get_current_animation_position() >= 0.5:
			return
		if not await _wait_seconds(0.05):
			return
		if not _has_live_character():
			return


## Mostra una posa specifica
func _show_pose(pose_name: String) -> void:
	if not _has_live_character() or not _can_continue():
		return
	if debug_mode:
		print("[GAME] Showing pose: %s (Level %d)" % [pose_name, _current_level + 1])
	character.play_pose(pose_name, false)


## Riconosce se il player ha riprodotto la posa correttamente
func _recognize_pose(recognition_duration: float = GestureConstants.HOLD_WINDOW) -> bool:
	if not _has_live_character() or (not _has_live_camera() and not _has_live_xr_origin()) or not _can_continue():
		return false
	if debug_mode:
		print("[GAME] Starting pose recognition...")
	
	# Leggi le posizioni target dal character
	var target_left: Vector3   = character.get_hand_position(false)
	var target_right: Vector3  = character.get_hand_position(true)
	var target_anchor: Vector3 = character.get_pose_anchor_position()
	
	# Tempo continuo necessario in posa corretta
	var required_hold_duration: float = GestureConstants.REQUIRED_HOLD
	var current_hold_duration: float  = 0.0
	var sample_step: float            = 0.1
	var confidence_threshold: float   = max(GestureConstants.CONFIDENCE_THRESHOLD, 0.001)
	var start_time: float             = Time.get_ticks_msec() / 1000.0
	_set_arm_feedback_visible(true)
	_set_vr_feedback_hud_visible(true)
	
	while Time.get_ticks_msec() / 1000.0 - start_time < recognition_duration:
		if not _can_continue() or not _has_live_character() or (not _has_live_camera() and not _has_live_xr_origin()):
			_set_arm_feedback_visible(false)
			_set_vr_feedback_hud_visible(false)
			return false
		var player_anchor: Vector3 = camera.global_position if camera else xr_origin.global_position
		var confidence_data: Dictionary = _pose_recognizer.calculate_pose_confidences(
			target_left,
			target_right,
			target_anchor,
			player_anchor
		)
		var left_confidence: float = float(confidence_data["player_left_confidence"])
		var right_confidence: float = float(confidence_data["player_right_confidence"])
		_update_vr_feedback_hud(left_confidence, right_confidence)

		var right_arm_points: Dictionary = character.get_arm_feedback_points(true)
		var left_arm_points: Dictionary = character.get_arm_feedback_points(false)

		# In riconoscimento usiamo il confronto specchiato incrociato:
		# mano sx player <-> braccio dx target, mano dx player <-> braccio sx target.
		_update_arm_feedback_polyline(
			_feedback_right_arm_line,
			[right_arm_points["chest"], right_arm_points["shoulder"], right_arm_points["elbow"], right_arm_points["hand"]],
			left_confidence
		)
		_update_arm_feedback_polyline(
			_feedback_left_arm_line,
			[left_arm_points["chest"], left_arm_points["shoulder"], left_arm_points["elbow"], left_arm_points["hand"]],
			right_confidence
		)

		# Successo solo per confidenza per-braccio: entrambe devono raggiungere 100%
		# (normalizzate sulla threshold configurata).
		var is_left_correct: bool = left_confidence >= confidence_threshold
		var is_right_correct: bool = right_confidence >= confidence_threshold
		var is_correct: bool = is_left_correct and is_right_correct

		# Debug verbose separato dall'HUD VR di gioco.
		# if debug_mode:
		# 	var debug_text: String = _pose_recognizer.get_debug_pose_string(
		# 						 target_left,
		# 						 target_right,
		# 						 target_anchor,
		# 						 player_anchor,
		# 						 "Level %d - Confidence: %.1f%% - Hold: %.1fs/%.1fs" % [
		# 						 _current_level + 1,
		# 						 confidence * 100,
		# 						 current_hold_duration,
		# 						 required_hold_duration
		# 						 ]
		# 					 )
		# 	if _vr_debug_label:
		# 		_vr_debug_label.text = debug_text

		# Conta solo il tempo continuo in cui la posa e' corretta
		if is_correct:
			current_hold_duration += sample_step
		else:
			current_hold_duration = 0.0

		# Se mantiene la posa per il tempo richiesto, successo
		if current_hold_duration >= required_hold_duration:
			if debug_mode:
				print("[GAME] [OK] Pose recognized (hold completed)!")
			_set_arm_feedback_visible(false)
			_set_vr_feedback_hud_visible(false)
			return true

		_consume_recognition_timer(sample_step, left_confidence, right_confidence)
		if _timer_expired:
			if debug_mode:
				print("[GAME] [NO] Recognition timer expired")
			_set_arm_feedback_visible(false)
			_set_vr_feedback_hud_visible(false)
			return false

		if not await _wait_seconds(sample_step):
			_set_arm_feedback_visible(false)
			_set_vr_feedback_hud_visible(false)
			return false

	if debug_mode:
		print("[GAME] [NO] Pose not recognized (window expired)")

	_set_arm_feedback_visible(false)
	_set_vr_feedback_hud_visible(false)
	return false


## Eseguito quando il player supera una posa
func _on_success() -> void:
	if not _can_continue():
		return
	if debug_mode:
		print("[GAME] SUCCESS! Level up!")
	
	if _hud:
		_hud.hide_hud()

	_current_level += 1
	_recognition_timer_left = GestureConstants.GAME_TIMER
	_update_vr_feedback_hud(0.0, 0.0)

	# Aumenta la grandezza del player
	if _current_size_index < GestureConstants.SIZE_SCALES.size() - 1:
		_current_size_index += 1
		if _has_live_xr_origin():
			_set_node_scale(xr_origin, GestureConstants.SIZE_SCALES[_current_size_index])
	if debug_mode:
		print("[GAME] Player scale increased to: %.1f" % GestureConstants.SIZE_SCALES[_current_size_index])


## Termina il gioco, successo
func _on_game_end() -> void:
	if not _can_continue():
		return
	_is_playing = false
	_hud_confirmed = true
	_set_arm_feedback_visible(false)
	_set_vr_feedback_hud_visible(false)
	if _hud:
		_hud.hide_hud()

	if _has_live_character():
		character.play_pose("victory", true)

	# Set the world scale back to default
	_set_node_scale(xr_origin, 1.0)

	tween_lights_by_order(game_lights, environment_lights, 1.0, 0.5)
	await _wait_seconds(5.0)
	if is_instance_valid(stargate_experience) and _can_continue():
		_trigger_portal_transition(stargate_experience)

	if debug_mode:
		print("[GAME] Game ended! Final level: %d | Final size: %.1f" % [
			_current_level, GestureConstants.SIZE_SCALES[_current_size_index]
		])


func _consume_recognition_timer(delta_seconds: float, left_confidence: float, right_confidence: float) -> void:
	if _timer_expired:
		return
	_recognition_timer_left = max(_recognition_timer_left - delta_seconds, 0.0)
	_update_vr_feedback_hud(left_confidence, right_confidence)
	if _recognition_timer_left <= 0.0:
		_timer_expired = true


func _on_recognition_timer_expired() -> bool:
	if not _can_continue():
		return false
	# Ogni timeout fa crescere il character con lo stesso flow a step delle SIZE_SCALES.
	_grow_character_on_timeout()

	_remaining_trials -= 1
	if _remaining_trials > 0:
		if _hud and _hud.has_active_prompt():
			_hud.hide_hud()
		var tries_suffix: String = "volta" if _remaining_trials == 1 else "volte"
		_show_confirmation_hud(
			"Fallito!\nPuoi riprovarci ancora %d %s!" % [_remaining_trials, tries_suffix],
			false,
			5.0
		)
		if not await _wait_seconds(5.0):
			return false
		if _hud and _hud.has_active_prompt():
			_hud.hide_hud()
		_recognition_timer_left = GestureConstants.GAME_TIMER
		_timer_expired = false
		_update_vr_feedback_hud(0.0, 0.0)
		return true
	else:
		_is_playing = false
		_set_arm_feedback_visible(false)
		_set_vr_feedback_hud_visible(false)
		if _hud and _hud.has_active_prompt():
			_hud.hide_hud()

		if _has_live_character():
			character.play_pose("defeat", true)
		tween_lights_by_order(game_lights, environment_lights, 1.0, 0.5)
		_show_confirmation_hud("Fallito! \n Torna al Capannone Coreografie", false, 6.0)
		await get_tree().create_timer(6.0).timeout
		_trigger_portal_transition(stargate_coreography)
		return false


func _grow_character_on_timeout() -> void:
	if not _has_live_character():
		return
	if _character_size_index < GestureConstants.SIZE_SCALES.size() - 1:
		_character_size_index += 1
	var character_scale: float = GestureConstants.SIZE_SCALES[_character_size_index]
	_set_node_scale(character, character_scale, 1.0)


func _trigger_portal_transition(portal: LivingPortal) -> void:
	if not is_instance_valid(portal):
		if debug_mode:
			push_warning("GestureGameController: portal non valido, transizione annullata")
		return
	var do_switch := func():
		if is_instance_valid(portal):
			portal.switch_to_target_environment()

	if is_instance_valid(living_camera):
		living_camera.fade_out(Color.WHITE_SMOKE, do_switch)
	else:
		do_switch.call()


func _update_vr_feedback_hud(left_confidence: float, right_confidence: float) -> void:
	if not _vr_left_label or not _vr_right_label or not _vr_timer_label:
		return

	var threshold: float = max(GestureConstants.CONFIDENCE_THRESHOLD, 0.001)
	var left_fill_ratio: float = clamp(left_confidence / threshold, 0.0, 1.0)
	var right_fill_ratio: float = clamp(right_confidence / threshold, 0.0, 1.0)
	var left_percent: float = clamp(left_confidence / threshold, 0.0, 1.0) * 100.0
	var right_percent: float = clamp(right_confidence / threshold, 0.0, 1.0) * 100.0
	var left_color: Color = Color(1.0, 0.2, 0.2, 0.95).lerp(Color(0.2, 1.0, 0.2, 0.95), left_fill_ratio)
	var right_color: Color = Color(1.0, 0.2, 0.2, 0.95).lerp(Color(0.2, 1.0, 0.2, 0.95), right_fill_ratio)

	var total_seconds: int = int(ceil(_recognition_timer_left))
	var minutes: int = int(total_seconds / 60)
	var seconds: int = total_seconds % 60
	var timer_text: String = "%02d:%02d" % [minutes, seconds]

	_vr_left_label.text = "Braccio SX: %3.0f%%" % [left_percent]
	_vr_right_label.text = "Braccio DX: %3.0f%%" % [right_percent]
	_vr_timer_label.text = "Tempo: %s" % timer_text
	_vr_left_label.modulate = left_color
	_vr_right_label.modulate = right_color
	_vr_timer_label.modulate = Color(1.0, 1.0, 1.0, 0.95)


func _set_vr_feedback_hud_visible(is_visible: bool) -> void:
	if _vr_hud_root:
		if is_visible:
			_vr_hud_root.position = _get_dynamic_vr_hud_position()
		_vr_hud_root.visible = is_visible


func _create_vr_hud_label(local_position: Vector3) -> Label3D:
	var label := Label3D.new()
	label.position = local_position
	label.pixel_size = 0.0012
	label.font_size = 16
	label.outline_size = 3
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.modulate = Color(1, 1, 1, 0.9)
	return label


func _get_dynamic_vr_hud_position() -> Vector3:
	var dynamic_position: Vector3 = vr_hud_base_position
	var scale_index: int = clampi(_current_size_index, 0, GestureConstants.SIZE_SCALES.size() - 1)
	var player_scale: float = GestureConstants.SIZE_SCALES[scale_index]

	# Stessa logica del confirmation HUD: quando il player e' grande, aumenta la distanza.
	if player_scale >= 1.5:
		var extra_distance: float = min((player_scale - 1.5) * 0.25, 0.9)
		dynamic_position.z -= extra_distance

	return dynamic_position


## Scala gradualmente un nodo
func _set_node_scale(target_node: Node3D, target_scale: float, duration: float = 1.0) -> void:
	if not target_node:
		return

	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)

	# Controlliamo dinamicamente se il nodo ha la proprietà specifica della VR
	if "world_scale" in target_node:
		tween.tween_property(target_node, "world_scale", target_scale, duration)
	else:
		var target_vector: Vector3 = Vector3(target_scale, target_scale, target_scale)
		tween.tween_property(target_node, "scale", target_vector, duration)


## LIGHT TWEEN METHODS

## Spegne in tween le luci del primo array e accende in tween quelle del secondo.
## L'ordine dei parametri definisce l'effetto:
## - tween_lights_by_order(environment_lights, game_lights) => env OFF, game ON
## - tween_lights_by_order(game_lights, environment_lights) => game OFF, env ON
func tween_lights_by_order(
		lights_to_turn_off: Array[Light3D],
		lights_to_turn_on: Array[Light3D],
		duration: float = 1.0,
		wait_between_groups: float = 0.0
	) -> void:
	if not _can_continue():
		return
	await _tween_light_group(lights_to_turn_off, false, duration)
	if not _can_continue():
		return
	if wait_between_groups > 0.0:
		if not await _wait_seconds(wait_between_groups):
			return
	await _tween_light_group(lights_to_turn_on, true, duration)


func _tween_light_group(lights: Array[Light3D], turn_on: bool, duration: float) -> void:
	if not _can_continue():
		return
	if lights.is_empty():
		return

	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	var has_valid_light: bool = false

	for light in lights:
		if not light:
			continue
		has_valid_light = true
		_cache_light_default_energy(light)

		if turn_on:
			light.visible = true
			if light.light_energy <= 0.0:
				light.light_energy = 0.0
			var target_energy: float = _get_light_default_energy(light)
			tween.parallel().tween_property(light, "light_energy", target_energy, duration)
		else:
			tween.parallel().tween_property(light, "light_energy", 0.0, duration)

	if not has_valid_light:
		return

	await tween.finished
	if not _can_continue():
		return

	if not turn_on:
		for light in lights:
			if light:
				light.visible = false


func _cache_light_default_energy(light: Light3D) -> void:
	if light.has_meta("default_light_energy"):
		return
	light.set_meta("default_light_energy", light.light_energy)


func _get_light_default_energy(light: Light3D) -> float:
	if light.has_meta("default_light_energy"):
		return max(float(light.get_meta("default_light_energy")), 0.001)
	return max(light.light_energy, 0.001)



# ARM FEEDBACK METHODS

func _setup_arm_feedback() -> void:
	if not arm_feedback_enabled:
		return

	_feedback_left_arm_line = _create_feedback_line()
	_feedback_right_arm_line = _create_feedback_line()
	add_child(_feedback_left_arm_line)
	add_child(_feedback_right_arm_line)
	_set_arm_feedback_visible(false)

func _create_feedback_line() -> MeshInstance3D:
	var line_mesh := MeshInstance3D.new()
	line_mesh.mesh = ImmediateMesh.new()
	line_mesh.top_level = true

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.2, 0.2, 0.95)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.2, 0.2)
	line_mesh.material_override = material

	return line_mesh

func _set_arm_feedback_visible(is_visible: bool) -> void:
	if _feedback_left_arm_line:
		_feedback_left_arm_line.visible = is_visible
	if _feedback_right_arm_line:
		_feedback_right_arm_line.visible = is_visible

func _update_arm_feedback_polyline(
		line_mesh_instance: MeshInstance3D,
		points: Array,
		arm_confidence: float
	) -> void:
	if not arm_feedback_enabled or not line_mesh_instance:
		return
	if points.size() < 2:
		return

	var threshold: float = max(GestureConstants.CONFIDENCE_THRESHOLD, 0.001)
	var fill_ratio: float = clamp(arm_confidence / threshold, 0.0, 1.0)
	var color: Color = Color(1.0, 0.2, 0.2, 0.95).lerp(Color(0.2, 1.0, 0.2, 0.95), fill_ratio)
	var points_vec3: Array[Vector3] = []

	for point in points:
		if point is Vector3:
			points_vec3.append(point)
	if points_vec3.size() < 2:
		return

	var total_length: float = 0.0
	for i in range(points_vec3.size() - 1):
		total_length += points_vec3[i].distance_to(points_vec3[i + 1])
	if total_length <= 0.0001:
		return

	var target_length: float = total_length * fill_ratio
	var draw_points: Array[Vector3] = [points_vec3[0]]
	var accumulated_length: float = 0.0

	for i in range(points_vec3.size() - 1):
		var segment_start: Vector3 = points_vec3[i]
		var segment_end: Vector3 = points_vec3[i + 1]
		var segment_length: float = segment_start.distance_to(segment_end)
		if segment_length <= 0.0001:
			continue

		if accumulated_length + segment_length <= target_length:
			draw_points.append(segment_end)
			accumulated_length += segment_length
			continue

		var remaining: float = target_length - accumulated_length
		var segment_t: float = clamp(remaining / segment_length, 0.0, 1.0)
		draw_points.append(segment_start.lerp(segment_end, segment_t))
		break

	var immediate_mesh := line_mesh_instance.mesh as ImmediateMesh
	immediate_mesh.clear_surfaces()
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	immediate_mesh.surface_set_color(color)
	for draw_point in draw_points:
		immediate_mesh.surface_add_vertex(draw_point)
	immediate_mesh.surface_end()

	var material := line_mesh_instance.material_override as StandardMaterial3D
	if material:
		material.albedo_color = color
		material.emission = color


# CONFIRM HUD METHODS

func _setup_hud() -> void:
	if not confirm_hud_enabled:
		return

	_hud = LivingCaptionStandaloneHud.new()
	_hud.hud_offset = confirm_hud_offset
	_hud.hud_scale = confirm_hud_scale
	_hud.hud_font_size = confirm_hud_font_size
	_hud.hud_font_depth = confirm_hud_font_depth
	_hud.confirmed.connect(_on_hud_confirmed)
	add_child(_hud)

func _show_confirmation_hud(
		text: String,
		clickable: bool = true,
		auto_hide_after_s: float = -1.0,
		auto_confirm_on_timeout: bool = true
	) -> void:
	if not _can_continue():
		return
	_hud_timeout_serial += 1
	_hud_confirmed = not confirm_hud_enabled
	if not confirm_hud_enabled or not _hud:
		return

	_hud.hud_offset = _get_dynamic_hud_offset()
	var anchor: Node3D = camera if camera else xr_origin
	if not is_instance_valid(anchor) or not anchor.is_inside_tree():
		_hud_confirmed = true
		return
	if not _hud.show_prompt(anchor, text, clickable, auto_hide_after_s):
		# Se esiste gia' un prompt attivo (race tra auto-hide e nuovo show),
		# forziamo il refresh e riproviamo una volta.
		if _hud.has_active_prompt():
			_hud.hide_hud()
		if not _hud.show_prompt(anchor, text, clickable, auto_hide_after_s):
			_hud_confirmed = true
			return

	if not clickable and auto_hide_after_s > 0.0 and auto_confirm_on_timeout:
		_auto_hud_after_delay(auto_hide_after_s, _hud_timeout_serial)

func _wait_confirmation_hud() -> void:
	while not _hud_confirmed and is_inside_tree():
		await get_tree().process_frame

func _on_hud_confirmed() -> void:
	_hud_timeout_serial += 1
	_hud_confirmed = true
	if _hud:
		_hud.hide_hud()

func _auto_hud_after_delay(delay_s: float, serial: int) -> void:
	if not await _wait_seconds(delay_s):
		return
	if serial != _hud_timeout_serial:
		return
	if _hud_confirmed:
		return
	_on_hud_confirmed()

func _get_dynamic_hud_offset() -> Vector3:
	var dynamic_offset: Vector3 = confirm_hud_offset
	var scale_index: int = clampi(_current_size_index, 0, GestureConstants.SIZE_SCALES.size() - 1)
	var player_scale: float = GestureConstants.SIZE_SCALES[scale_index]

	# Quando il player e' molto grande, allontaniamo l'HUD per facilitare il click.
	if player_scale >= 1.5:
		var extra_distance: float = min((player_scale - 1.5) * 0.25, 0.9)
		dynamic_offset.z -= extra_distance

	return dynamic_offset

func _is_confirmation_hud_visible() -> bool:
	return _hud != null and _hud.has_active_prompt()
