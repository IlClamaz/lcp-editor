extends Node3D
class_name GestureGameController

## Character che farà le pose
@export var character: Living3DModelAnimated

## Array di pose da imparare (in ordine di difficoltà)
@export var gestures: Array[String] = ["idle-1", "idle-2", "idle-3"]

## Abilitato per il debug
@export var debug_mode: bool = true

# Nodi trovati a runtime
var camera: XRCamera3D
var xr_origin: XROrigin3D
var left_controller: XRController3D
var right_controller: XRController3D

# Stato interno
var _current_level: int = 0
var _current_size_index: int = 1  # 0=piccolo, 1=medio, 2=grande
var _pose_recognizer: PoseRecognizer
var _is_playing: bool = false



# Siccome il LivingCamera al momento istanzia la scena nel ready,
# dovremmo aspettare che tutto sia pronto prima di cercare i nodi necessari.
# Possiamo mettere una callback che ascolta la LivingCamera
# Potrebbe essere utile anche per altre cose...
func _ready() -> void:
	# Cerca il character nel tree se non è assegnato
	if not character:
		character = get_tree().root.find_child("Living3DModelAnimated", true, false)
		if not character:
			push_error("GestureGameController: Living3DModelAnimated non trovato!")
			return
	
	# Cerca XRCamera3D nel tree
	camera = get_tree().root.find_child("XRCamera3D", true, false)
	if not camera:
		push_error("GestureGameController: XRCamera3D non trovato!")
		return
	
	# Cerca XROrigin3D nel tree
	xr_origin = get_tree().root.find_child("XROrigin3D", true, false)
	if not xr_origin:
		push_error("GestureGameController: XROrigin3D non trovato!")
		return
	
	# Cerca i controller
	left_controller = get_tree().root.find_child("XRController3D_left", true, false)
	if not left_controller:
		push_error("GestureGameController: XRController3D_left non trovato!")
		return
	
	right_controller = get_tree().root.find_child("XRController3D_right", true, false)
	if not right_controller:
		push_error("GestureGameController: XRController3D_right non trovato!")
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
	
	# Imposta lo stato iniziale
	_current_size_index = 1  # Medium
	_set_player_scale(GestureConstants.SIZE_SCALES[_current_size_index])

	await get_tree().create_timer(10).timeout  # Attendi un secondo per essere sicuri che tutto sia pronto
	start_game()


## Avvia il gioco
func start_game() -> void:
	print("Starting Gesture Game...")
	if _is_playing:
		return
	
	_is_playing = true
	_current_level = 0
	_current_size_index = 1
	
	_set_player_scale(GestureConstants.SIZE_SCALES[_current_size_index])
	
	_game_loop()


## Ferma il gioco
func stop_game() -> void:
	_is_playing = false


## Ciclo principale del gioco
func _game_loop() -> void:
	while _is_playing and _current_level < GestureConstants.MAX_LEVEL:
		# 1. MOSTRA LA POSA
		var pose_name = gestures[_current_level % gestures.size()]
		_show_pose(pose_name)
		
		# 2. ASPETTA CHE L'ANIMAZIONE ARRIVI A META' E METTILA IN PAUSA
		await _wait_until_animation_halfway()
		character.pause_animation()
		
		# 3. ATTESA PLAYER PRIMA DI INIZIARE RICONOSCIMENTO
		await get_tree().create_timer(0.5).timeout
		
		# 4. RICONOSCIMENTO POSA (30s max, 5s continui corretti)
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
		var wait_time = GestureConstants.SUCCESS_WAIT_TIME if success \
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
	var target_left = character.get_hand_position(false)
	var target_right = character.get_hand_position(true)
	var target_anchor = character.get_pose_anchor_position()
	var player_anchor = camera.global_position if camera else xr_origin.global_position
	
	# Ottieni le scale per la normalizzazione
	var character_scale = character.scale.x
	var player_scale = xr_origin.scale.x
	
	# Finestra totale di riconoscimento
	var recognition_duration = 30.0
	# Tempo continuo necessario in posa corretta
	var required_hold_duration = 5.0
	var current_hold_duration = 0.0
	var sample_step = 0.1
	var start_time = Time.get_ticks_msec() / 1000.0
	
	while Time.get_ticks_msec() / 1000.0 - start_time < recognition_duration:
		var confidence = _pose_recognizer.calculate_pose_confidence(
			target_left,
			target_right,
			target_anchor,
			player_anchor,
			character_scale,
			player_scale
		)
		var is_correct = _pose_recognizer.is_pose_correct(
			target_left,
			target_right,
			target_anchor,
			player_anchor,
			character_scale,
			player_scale
		)
		
		if debug_mode:
			_pose_recognizer.debug_pose_info(
				target_left,
				target_right,
				target_anchor,
				player_anchor,
				character_scale,
				player_scale,
				"Level %d - Confidence: %.1f%% - Hold: %.1fs/%.1fs" % [
					_current_level + 1,
					confidence * 100,
					current_hold_duration,
					required_hold_duration
				]
			)
		
		# Conta solo il tempo continuo in cui la posa e' corretta
		if is_correct:
			current_hold_duration += sample_step
		else:
			current_hold_duration = 0.0
		
		# Se mantiene la posa per il tempo richiesto, successo
		if current_hold_duration >= required_hold_duration:
			if debug_mode:
				print("[GAME] [OK] Pose recognized (hold completed)!")
			return true
		
		await get_tree().create_timer(sample_step).timeout
	
	if debug_mode:
		print("[GAME] [NO] Pose not recognized (window expired)")
	return false


## Eseguito quando il player supera una posa
func _on_success() -> void:
	if debug_mode:
		print("[GAME] ✓ SUCCESS! Level up!")
	
	_current_level += 1
	
	# # Aumenta la grandezza del player
	# if _current_size_index < GestureConstants.SIZE_SCALES.size() - 1:
	# 	_current_size_index += 1
	# 	_set_player_scale(GestureConstants.SIZE_SCALES[_current_size_index])
		
	# 	if debug_mode:
	# 		print("[GAME] Player scale increased to: %.1f" % GestureConstants.SIZE_SCALES[_current_size_index])


## Eseguito quando il player non supera una posa
func _on_failure() -> void:
	if debug_mode:
		print("[GAME] ✗ FAILURE! Retry level.")
	
	# # Diminuisci la grandezza del player
	# if _current_size_index > 0:
	# 	_current_size_index -= 1
	# 	_set_player_scale(GestureConstants.SIZE_SCALES[_current_size_index])
		
	# 	if debug_mode:
	# 		print("[GAME] Player scale decreased to: %.1f" % GestureConstants.SIZE_SCALES[_current_size_index])


## Termina il gioco
func _on_game_end() -> void:
	_is_playing = false
	
	if debug_mode:
		print("[GAME] Game ended! Final level: %d | Final size: %.1f" % [
			_current_level, GestureConstants.SIZE_SCALES[_current_size_index]
		])


## Imposta la scala del player tramite XROrigin
func _set_player_scale(scale: float) -> void:
	if xr_origin:
		xr_origin.scale = Vector3(scale, scale, scale)


## Debug: stampa stato attuale
func debug_print_state() -> void:
	print("\n=== GAME STATE ===")
	print("Level: %d / %d" % [_current_level + 1, GestureConstants.MAX_LEVEL])
	print("Player Size: %.1f (Index: %d)" % [
		GestureConstants.SIZE_SCALES[_current_size_index], 
		_current_size_index
	])
	print("Current Gesture: %s" % gestures[_current_level % gestures.size()])
	print("Is Playing: %s" % _is_playing)
