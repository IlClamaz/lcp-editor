extends Node3D
class_name GestureGameController


@export var animated_character: LivingElement
@export var moloch: LivingElement
@export var tutorial: LivingElement
@export var living_camera: LivingCamera


## Array di pose da imparare (in ordine di difficoltà)
@export var gestures: Array[String] = ["idle-2", "idle-3", "idle-4"]

## Abilitato per il debug
@export var debug_mode: bool = true

# Player Nodes
var camera: XRCamera3D
var xr_origin: XROrigin3D
var left_controller: XRController3D
var right_controller: XRController3D

# Other nodes
var character: Living3DModelAnimated
var video: LivingVideo
var moloch_model: Living3DModel

# Stato interno
var _current_level: int = 0
var _current_size_index: int = 3  # [0.1, 0.25, 0.5, 1.0, 1.5, 2.5, 3.5]
var _pose_recognizer: PoseRecognizer
var _is_playing: bool = false
var _vr_debug_label: Label3D



# Siccome il LivingCamera al momento istanzia la scena nel ready,
# dovremmo aspettare che tutto sia pronto prima di cercare i nodi necessari.
# Possiamo mettere una callback che ascolta la LivingCamera
# Potrebbe essere utile anche per altre cose...
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
	else:
		push_error("GestureGameController: living_camera not found")
		return
	
	if moloch:
		moloch_model = moloch.find_child("Living3DModel*", true, false)
		moloch_model.find_child("Trigger", true, false).queue_free()
	else:
		push_error("GestureGameController: Moloch not found")
		return
	
	if tutorial:
		video = tutorial.find_child("LivingVideo*", true, false)
	else:
		push_error("GestureGameController: video tutorial not found")
		return	

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

	if debug_mode and camera:
		_vr_debug_label = Label3D.new()
		camera.add_child(_vr_debug_label)
		
		_vr_debug_label.position = Vector3(-0.6, -0.2, -0.8)
		_vr_debug_label.pixel_size = 0.0012
		_vr_debug_label.font_size = 16
		_vr_debug_label.outline_size = 3
		_vr_debug_label.modulate = Color(1, 1, 1, 0.4)
		_vr_debug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_vr_debug_label.text = "HUD VR Pronto..."
	
	# Imposta lo stato iniziale
	_current_size_index = 3  # 1.0
	_set_node_scale(xr_origin, GestureConstants.SIZE_SCALES[_current_size_index])
	_current_level = 0
	
	# ==========================================
	# GESTIONE FLUSSO INIZIALE
	# ==========================================

	# 1. Nascondiamo il character e il moloch, mostriamo solo il tutorial
	animated_character.visible = false
	moloch.visible = false
	tutorial.visible = true

	# 2. Ci iscriviamo al segnale di fine video per sapere quando ha terminato
	if video and video.player:
		if not video.player.finished.is_connected(_on_tutorial_video_finished):
			video.player.finished.connect(_on_tutorial_video_finished)
	else:
		push_error("GestureGameController: VideoPlayer non trovato in LivingVideo!")


## Chiamata automaticamente quando il video tutorial arriva alla fine
func _on_tutorial_video_finished() -> void:
	if debug_mode:
		print("[GAME] Tutorial video terminato. Transizione in corso...")

	# L'azione da fare quando lo schermo è completamente nero
	var swap_visibility = func():
		if tutorial: tutorial.visible = false
		if animated_character: animated_character.visible = true
		if moloch: moloch.visible = true
	
	
	if living_camera:
		# 1.5s per scurire, 0.5s di pausa nel buio, 1.5s per riaccendere
		await living_camera.fade_transition(Color.BLACK, 1.5, 0.5, 1.5, swap_visibility)

		# Aspettiamo il resto dei 10 secondi promessi prima di far partire il gioco
		var remaining_wait: float = 10.0 - (1.5 + 0.5 + 1.5)
		if debug_mode: print("[GAME] Attesa di %.1f secondi prima di iniziare le pose..." % remaining_wait)
		if remaining_wait > 0:
			await get_tree().create_timer(remaining_wait).timeout

	else:
		# Fallback di sicurezza se per qualche motivo la camera non è connessa
		swap_visibility.call()
		await get_tree().create_timer(10.0).timeout

	# Avvia il gioco
	start_game()


## Avvia il gioco
func start_game() -> void:
	print("Starting Gesture Game...")
	if _is_playing:
		return
	
	_is_playing = true
	
	_game_loop()


## Ferma il gioco
func stop_game() -> void:
	_is_playing = false


## Ciclo principale del gioco
func _game_loop() -> void:
	while _is_playing and _current_level < GestureConstants.MAX_LEVEL:
		# 1. MOSTRA LA POSA
		var pose_name: String = gestures[_current_level % gestures.size()]
		_show_pose(pose_name)
		
		# 2. ASPETTA CHE L'ANIMAZIONE ARRIVI A META' E METTILA IN PAUSA
		await _wait_until_animation_halfway()
		character.pause_animation()
		
		# 3. ATTESA PLAYER PRIMA DI INIZIARE RICONOSCIMENTO
		await get_tree().create_timer(0.5).timeout
		
		# 4. RICONOSCIMENTO POSA
		var success = await _recognize_pose()
		if success:
			character.resume_animation()
			await character.await_animation_finish()
		
		# 5. FEEDBACK E PROGRESSIONE
		if success:
			_on_success()
		else:
			_on_failure()
		
		# 6. ATTESA PRIMA DI CONTINUARE
		var wait_time: float = GestureConstants.SUCCESS_WAIT_TIME if success \
			else GestureConstants.RETRY_WAIT_TIME
		await get_tree().create_timer(wait_time).timeout
	
	# Fine gioco
	_on_game_end()


func _wait_until_animation_halfway() -> void:
	while _is_playing and character.is_animation_playing():
		if character.get_current_animation_position() >= 0.5:
			return
		await get_tree().create_timer(0.05).timeout


## Mostra una posa specifica
func _show_pose(pose_name: String) -> void:
	if debug_mode:
		print("[GAME] Showing pose: %s (Level %d)" % [pose_name, _current_level + 1])
	character.play_pose(pose_name, false)


## Riconosce se il player ha riprodotto la posa correttamente
func _recognize_pose() -> bool:
	if debug_mode:
		print("[GAME] Starting pose recognition...")
	
	# Leggi le posizioni target dal character
	var target_left: Vector3   = character.get_hand_position(false)
	var target_right: Vector3  = character.get_hand_position(true)
	var target_anchor: Vector3 = character.get_pose_anchor_position()
	
	# Finestra totale di riconoscimento
	var recognition_duration: float = GestureConstants.RECOGNITION_DURATION
	# Tempo continuo necessario in posa corretta
	var required_hold_duration: float = GestureConstants.REQUIRED_HOLD
	var current_hold_duration: float  = 0.0
	var sample_step: float            = 0.1
	var start_time: float             = Time.get_ticks_msec() / 1000.0
	
	while Time.get_ticks_msec() / 1000.0 - start_time < recognition_duration:
		var player_anchor: Vector3 = camera.global_position if camera else xr_origin.global_position
		var confidence: float = _pose_recognizer.calculate_pose_confidence(
			target_left,
			target_right,
			target_anchor,
			player_anchor
		)
		var is_correct: bool  = _pose_recognizer.is_pose_correct(
			target_left,
			target_right,
			target_anchor,
			player_anchor
		)


		if debug_mode:
			var debug_text: String = _pose_recognizer.get_debug_pose_string(
								 target_left,
								 target_right,
								 target_anchor,
								 player_anchor,
								 "Level %d - Confidence: %.1f%% - Hold: %.1fs/%.1fs" % [
								 _current_level + 1,
								 confidence * 100,
								 current_hold_duration,
								 required_hold_duration
								 ]
							 )
			if _vr_debug_label:
				_vr_debug_label.text = debug_text

		# Conta solo il tempo continuo in cui la posa e' corretta
		if is_correct:
			current_hold_duration += sample_step
		else:
			current_hold_duration = 0.0

		# Se mantiene la posa per il tempo richiesto, successo
		if current_hold_duration >= required_hold_duration:
			if debug_mode:
				print("[GAME] [OK] Pose recognized (hold completed)!")
			if _vr_debug_label: _vr_debug_label.text = "CORRETTO!"
			return true

		await get_tree().create_timer(sample_step).timeout

	if debug_mode:
		print("[GAME] [NO] Pose not recognized (window expired)")
	if _vr_debug_label: _vr_debug_label.text = "TEMPO SCADUTO!"
	return false


## Eseguito quando il player supera una posa
func _on_success() -> void:
	if debug_mode:
		print("[GAME] ✓ SUCCESS! Level up!")
	
	_current_level += 1

	# Aumenta la grandezza del player
	if _current_size_index < GestureConstants.SIZE_SCALES.size() - 1:
		_current_size_index += 1
		_set_node_scale(xr_origin, GestureConstants.SIZE_SCALES[_current_size_index])
	if debug_mode:
		print("[GAME] Player scale increased to: %.1f" % GestureConstants.SIZE_SCALES[_current_size_index])


## Eseguito quando il player non supera una posa
func _on_failure() -> void:
	if debug_mode:
		print("[GAME] ✗ FAILURE! Retry level.")
	
	# Diminuisci la grandezza del player
	if _current_size_index > 0:
		_current_size_index -= 1
		_set_node_scale(xr_origin, GestureConstants.SIZE_SCALES[_current_size_index])
		
		if debug_mode:
			print("[GAME] Player scale decreased to: %.1f" % GestureConstants.SIZE_SCALES[_current_size_index])


## Termina il gioco
func _on_game_end() -> void:
	_is_playing = false
	_set_node_scale(moloch, 0.1)
	_set_node_scale(animated_character, 0.1)
	# Poi dovrebbe apparire uno stargate!!
	
	if debug_mode:
		print("[GAME] Game ended! Final level: %d | Final size: %.1f" % [
			_current_level, GestureConstants.SIZE_SCALES[_current_size_index]
		])


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
