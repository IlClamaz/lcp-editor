extends Node3D
class_name GestureGameController


@export var animated_character: LivingElement
@export var moloch: LivingElement
@export var tutorial: LivingElement
@export var living_camera: LivingCamera


## Array di pose, mostrate in ordine
@export var gestures: Array[String]

## Abilitato per il debug
@export var debug_mode: bool = false
@export var arm_feedback_enabled: bool = true

# Confirmation HUD settings
var confirm_hud_enabled: bool = true
var confirm_hud_offset: Vector3 = Vector3(0.0, -0.35, -0.8)
var confirm_hud_scale: float = 0.35
var confirm_hud_font_size: int = 8
var confirm_hud_font_depth: float = 0.002

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
var _feedback_left_arm_line: MeshInstance3D
var _feedback_right_arm_line: MeshInstance3D
var _confirm_hud: GestureConfirmHud
var _confirm_hud_confirmed: bool = false



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
		video.find_child("Trigger", true, false).queue_free()
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
	_setup_arm_feedback()
	_setup_confirm_hud()

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
	_current_size_index = 3  # 1.0 di scala
	_set_node_scale(xr_origin, GestureConstants.SIZE_SCALES[_current_size_index])
	_current_level = 0

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
	if _is_confirmation_hud_visible():
		if debug_mode:
			print("[GAME] Confirmation HUD already visible. Skip duplicated tutorial-end flow.")
		return

	_show_confirmation_hud("Inizia training")
	await _wait_confirmation_hud()

	# L'azione da fare quando lo schermo è completamente nero
	var swap_visibility = func():
		if tutorial: tutorial.visible = false
		if animated_character: animated_character.visible = true
		if moloch: moloch.visible = true
	
	
	if living_camera:
		# 1.5s per scurire, 0.5s di pausa nel buio, 1.5s per riaccendere
		await living_camera.fade_transition(Color.BLACK, 1.5, 0.5, 1.5, swap_visibility)

		# Aspettiamo un paio di secondi prima di far partire il gioco
		var remaining_wait: float =  5.0 - (1.5 + 0.5 + 1.5)
		if debug_mode: print("[GAME] Attesa di %.1f secondi prima di iniziare le pose..." % remaining_wait)
		if remaining_wait > 0:
			await get_tree().create_timer(remaining_wait).timeout

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
	_confirm_hud_confirmed = true
	_set_arm_feedback_visible(false)
	if _confirm_hud:
		_confirm_hud.hide_hud()


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
			_show_confirmation_hud("Corretto!")
			await character.await_animation_finish()
			await _wait_confirmation_hud()
		
		# 5. FEEDBACK E PROGRESSIONE
		if success:
			_on_success()
		else:
			_on_failure()
			_show_confirmation_hud("Tempo scaduto! Riprova")
			await _wait_confirmation_hud()
		
		# 6. ATTESA PRIMA DI CONTINUARE
		var wait_time: float = 0.0
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
	_set_arm_feedback_visible(true)
	
	while Time.get_ticks_msec() / 1000.0 - start_time < recognition_duration:
		var player_anchor: Vector3 = camera.global_position if camera else xr_origin.global_position
		var confidence_data: Dictionary = _pose_recognizer.calculate_pose_confidences(
			target_left,
			target_right,
			target_anchor,
			player_anchor
		)
		var confidence: float = float(confidence_data["total_confidence"])
		var left_confidence: float = float(confidence_data["player_left_confidence"])
		var right_confidence: float = float(confidence_data["player_right_confidence"])

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
			_set_arm_feedback_visible(false)
			return true

		await get_tree().create_timer(sample_step).timeout

	if debug_mode:
		print("[GAME] [NO] Pose not recognized (window expired)")
	if _vr_debug_label: _vr_debug_label.text = "TEMPO SCADUTO!"
	_set_arm_feedback_visible(false)
	return false


## Eseguito quando il player supera una posa
func _on_success() -> void:
	if debug_mode:
		print("[GAME] SUCCESS! Level up!")
	
	if _confirm_hud:
		_confirm_hud.hide_hud()

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
		print("[GAME] FAILURE! Retry level.")
	
	if _confirm_hud:
		_confirm_hud.hide_hud()

	# Diminuisci la grandezza del player
	if _current_size_index > 0:
		_current_size_index -= 1
		_set_node_scale(xr_origin, GestureConstants.SIZE_SCALES[_current_size_index])
		
		if debug_mode:
			print("[GAME] Player scale decreased to: %.1f" % GestureConstants.SIZE_SCALES[_current_size_index])


## Termina il gioco
func _on_game_end() -> void:
	_is_playing = false
	_confirm_hud_confirmed = true
	_set_arm_feedback_visible(false)
	if _confirm_hud:
		_confirm_hud.hide_hud()
	_set_node_scale(moloch, 0.1)
	_set_node_scale(animated_character, 0.1)
	# Poi dovrebbe apparire uno stargate!!
	# Dobbiamo dispatchare l'evento di tipo condition 
	# Apparizione dello Stargate ZGT-ZGE, che porta da dall'ambiente Zootropio Gigantismo Training 
	# a all'ambiente Zootropio Gigantismo Experience
	# Devo mantenere uno stato globale che mi dica se il giocatore ha completato il training, 
	# così da differenziare se abbiamo completato il training o se stiamo semplicemente tornando indietro
	# 

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

func _setup_confirm_hud() -> void:
	if not confirm_hud_enabled:
		return

	_confirm_hud = GestureConfirmHud.new()
	_confirm_hud.hud_offset = confirm_hud_offset
	_confirm_hud.hud_scale = confirm_hud_scale
	_confirm_hud.hud_font_size = confirm_hud_font_size
	_confirm_hud.hud_font_depth = confirm_hud_font_depth
	_confirm_hud.confirmed.connect(_on_confirm_hud_confirmed)
	add_child(_confirm_hud)

func _show_confirmation_hud(text: String) -> void:
	_confirm_hud_confirmed = not confirm_hud_enabled
	if not confirm_hud_enabled or not _confirm_hud:
		return

	_confirm_hud.hud_offset = _get_dynamic_confirm_hud_offset()
	var anchor: Node3D = camera if camera else xr_origin
	if not _confirm_hud.show_prompt(anchor, text):
		_confirm_hud_confirmed = true

func _wait_confirmation_hud() -> void:
	while not _confirm_hud_confirmed and is_inside_tree():
		await get_tree().process_frame

func _on_confirm_hud_confirmed() -> void:
	_confirm_hud_confirmed = true
	if _confirm_hud:
		_confirm_hud.hide_hud()

func _get_dynamic_confirm_hud_offset() -> Vector3:
	var dynamic_offset: Vector3 = confirm_hud_offset
	var scale_index: int = clampi(_current_size_index, 0, GestureConstants.SIZE_SCALES.size() - 1)
	var player_scale: float = GestureConstants.SIZE_SCALES[scale_index]

	# Quando il player e' molto grande, allontaniamo l'HUD per facilitare il click.
	if player_scale >= 1.5:
		var extra_distance: float = min((player_scale - 1.5) * 0.25, 0.9)
		dynamic_offset.z -= extra_distance

	return dynamic_offset

func _is_confirmation_hud_visible() -> bool:
	return _confirm_hud != null and _confirm_hud.has_active_prompt()
