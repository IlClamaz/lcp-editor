extends Node
class_name PoseRecognizer

var left_controller: XRController3D
var right_controller: XRController3D

func _init(left: XRController3D, right: XRController3D) -> void:
	left_controller = left
	right_controller = right
	if not left_controller or not right_controller:
		push_error("PoseRecognizer: Controller non validi forniti!")

func calculate_pose_confidence(
		target_left: Vector3,
		target_right: Vector3,
		target_anchor: Vector3,
		player_anchor: Vector3,
		character_scale: float = 1.0,
		player_scale: float = 1.0
	) -> float:
	
	if not left_controller or not right_controller: return 0.0
		
	# 1. Vettori grezzi (Testa -> Mano) in base allo spazio 3D reale
	var target_l_vec = target_left - target_anchor
	var target_r_vec = target_right - target_anchor
	
	# 2. Specchio: Invertiamo la Z
	target_l_vec.z = -target_l_vec.z
	target_r_vec.z = -target_r_vec.z
	
	# 3. Vettori Player grezzi
	var player_l_vec = left_controller.global_position - player_anchor
	var player_r_vec = right_controller.global_position - player_anchor

	# --- LA MAGIA DELLA SCALA INDIPENDENTE ---
	# .normalized() forza la lunghezza della "freccia" ad essere esattamente 1.0
	# Ora stiamo confrontando SOLO L'ANGOLAZIONE, ignorando quanto sono lunghe le braccia!
	var target_l_dir = target_l_vec.normalized()
	var target_r_dir = target_r_vec.normalized()
	var player_l_dir = player_l_vec.normalized()
	var player_r_dir = player_r_vec.normalized()

	# 4. Incrocio Specchio: Qual è la differenza tra le due direzioni?
	# Su vettori normalizzati, la distanza va da 0.0 (identici) a 2.0 (totalmente opposti)
	var error_l = player_l_dir.distance_to(target_r_dir) 
	var error_r = player_r_dir.distance_to(target_l_dir) 
	
	# 5. Confidenza
	# Su una sfera unitaria, un errore di 0.5 equivale a un margine di circa 30 gradi.
	# Aumentalo a 0.7 per essere più permissivo (circa 40 gradi di tolleranza)
	var max_tolerance = 0.5 
	var conf_l = clamp(1.0 - (error_l / max_tolerance), 0.0, 1.0)
	var conf_r = clamp(1.0 - (error_r / max_tolerance), 0.0, 1.0)
	
	return (conf_l + conf_r) / 2.0

func is_pose_correct(
		target_left: Vector3, target_right: Vector3, 
		target_anchor: Vector3, player_anchor: Vector3, 
		character_scale: float = 1.0, player_scale: float = 1.0
	) -> bool:
	
	var confidence = calculate_pose_confidence(target_left, target_right, target_anchor, player_anchor, character_scale, player_scale)
	return confidence >= GestureConstants.CONFIDENCE_THRESHOLD


## Ottiene la posizione attuale del controller sinistro
func get_left_hand_position() -> Vector3:
	if left_controller:
		return left_controller.global_position
	return Vector3.ZERO

## Ottiene la posizione attuale del controller destro
func get_right_hand_position() -> Vector3:
	if right_controller:
		return right_controller.global_position
	return Vector3.ZERO


func debug_pose_info(
		target_left: Vector3,
		target_right: Vector3,
		target_anchor: Vector3,
		player_anchor: Vector3,
		character_scale: float = 1.0,
		player_scale: float = 1.0,
		label: String = ""
	) -> void:
	
	var left_pos = get_left_hand_position()
	var right_pos = get_right_hand_position()
	
	var confidence = calculate_pose_confidence(
		target_left, target_right, target_anchor, player_anchor, character_scale, player_scale
	)
	
	var target_l_vec = target_left - target_anchor
	var target_r_vec = target_right - target_anchor
	target_l_vec.z = -target_l_vec.z
	target_r_vec.z = -target_r_vec.z
	
	var player_l_vec = left_pos - player_anchor
	var player_r_vec = right_pos - player_anchor
	
	var target_l_dir = target_l_vec.normalized()
	var target_r_dir = target_r_vec.normalized()
	var player_l_dir = player_l_vec.normalized()
	var player_r_dir = player_r_vec.normalized()
	
	var error_l = player_l_dir.distance_to(target_r_dir)
	var error_r = player_r_dir.distance_to(target_l_dir)
	
	print("\n=== POSE DEBUG %s ===" % label)
	print("Modo: INDIPENDENTE DALLA SCALA (Solo Direzione/Angolo)")
	var format_vec = func(v: Vector3): return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]
	
	print("Direzione Mano Sinistra Player : %s" % format_vec.call(player_l_dir))
	print("Direzione Mano Destra Target   : %s" % format_vec.call(target_r_dir))
	print("--> Errore Angolare Sinistro   : %.3f (Tol. 0.5)" % error_l)
	print("-----------------------------")
	print("Direzione Mano Destra Player   : %s" % format_vec.call(player_r_dir))
	print("Direzione Mano Sinistra Target : %s" % format_vec.call(target_l_dir))
	print("--> Errore Angolare Destro     : %.3f (Tol. 0.5)" % error_r)
	print("Confidence Totale: %.1f%%" % [confidence * 100])