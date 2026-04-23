extends Node
class_name PoseRecognizer

var left_controller: XRController3D
var right_controller: XRController3D

func _init(left: XRController3D, right: XRController3D) -> void:
	left_controller = left
	right_controller = right
	if not left_controller or not right_controller:
		push_error("PoseRecognizer: Controller non validi forniti!")

func calculate_pose_confidences(
		target_left: Vector3,
		target_right: Vector3,
		target_anchor: Vector3,
		player_anchor: Vector3,
	) -> Dictionary:
	
	if not left_controller or not right_controller:
		return {
			"player_left_confidence": 0.0,
			"player_right_confidence": 0.0,
			"total_confidence": 0.0
		}
		
	# 1. Vettori grezzi (Testa -> Mano) in base allo spazio 3D reale
	var target_l_vec: Vector3 = target_left - target_anchor
	var target_r_vec: Vector3 = target_right - target_anchor
	
	# 2. Specchio: invertiamo la Z
	target_l_vec.z = -target_l_vec.z
	target_r_vec.z = -target_r_vec.z
	
	# 3. Vettori player grezzi
	var player_l_vec: Vector3 = left_controller.global_position - player_anchor
	var player_r_vec: Vector3 = right_controller.global_position - player_anchor

	# .normalized() forza la lunghezza della freccia ad essere esattamente 1.0
	# Ora confrontiamo solo l'angolazione, ignorando la lunghezza delle braccia.
	var target_l_dir: Vector3 = target_l_vec.normalized()
	var target_r_dir: Vector3 = target_r_vec.normalized()
	var player_l_dir: Vector3 = player_l_vec.normalized()
	var player_r_dir: Vector3 = player_r_vec.normalized()

	# 4. Incrocio specchio: confrontiamo la mano sx player con la dx target e viceversa.
	# Su vettori normalizzati, la distanza va da 0.0 (identici) a 2.0 (opposti).
	var error_l: float = player_l_dir.distance_to(target_r_dir)
	var error_r: float = player_r_dir.distance_to(target_l_dir)
	
	# 5. Confidenza
	# Su una sfera unitaria, un errore di 0.5 equivale a circa 30 gradi.
	var max_tolerance: float = max(GestureConstants.POSE_MAX_TOLERANCE, 0.001)
	var conf_l: float = clamp(1.0 - (error_l / max_tolerance), 0.0, 1.0)
	var conf_r: float = clamp(1.0 - (error_r / max_tolerance), 0.0, 1.0)
	var total: float = (conf_l + conf_r) / 2.0
	
	return {
		"player_left_confidence": conf_l,
		"player_right_confidence": conf_r,
		"total_confidence": total
	}

func calculate_pose_confidence(
		target_left: Vector3,
		target_right: Vector3,
		target_anchor: Vector3,
		player_anchor: Vector3,
	) -> float:
	
	var confidences: Dictionary = calculate_pose_confidences(
		target_left,
		target_right,
		target_anchor,
		player_anchor
	)
	return float(confidences["total_confidence"])

func is_pose_correct(
		target_left: Vector3, target_right: Vector3,
		target_anchor: Vector3, player_anchor: Vector3
	) -> bool:
	
	var confidence: float = calculate_pose_confidence(target_left, target_right, target_anchor, player_anchor)
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


## Genera e restituisce la stringa di debug per l'HUD VR
func get_debug_pose_string(
	target_left: Vector3,
	target_right: Vector3,
	target_anchor: Vector3,
	player_anchor: Vector3,
	label: String = ""
) -> String:

	var left_pos: Vector3 = get_left_hand_position()
	var right_pos: Vector3 = get_right_hand_position()

	var confidence: float = calculate_pose_confidence(target_left, target_right, target_anchor, player_anchor)

	var target_l_vec: Vector3 = target_left - target_anchor
	var target_r_vec: Vector3 = target_right - target_anchor
	target_l_vec.z = -target_l_vec.z
	target_r_vec.z = -target_r_vec.z

	var player_l_vec: Vector3 = left_pos - player_anchor
	var player_r_vec: Vector3 = right_pos - player_anchor

	var target_l_dir: Vector3 = target_l_vec.normalized()
	var target_r_dir: Vector3 = target_r_vec.normalized()
	var player_l_dir: Vector3 = player_l_vec.normalized()
	var player_r_dir: Vector3 = player_r_vec.normalized()

	var error_l: float = player_l_dir.distance_to(target_r_dir)
	var error_r: float = player_r_dir.distance_to(target_l_dir)
	var max_tolerance: float = max(GestureConstants.POSE_MAX_TOLERANCE, 0.001)

	var format_vec = func(v: Vector3): return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]

	# Costruiamo il testo multiriga
	var text: String = "=== POSE DEBUG %s ===\n" % label
	text += "----------------------------------------\n"
	text += "Dir Mano SX Player: %s\n" % format_vec.call(player_l_dir)
	text += "Dir Mano DX Target: %s\n" % format_vec.call(target_r_dir)
	text += "--> Errore Angolare Sinistro: %.3f (Tol. %.3f)\n" % [error_l, max_tolerance]
	text += "----------------------------------------\n"
	text += "Dir Mano DX Player: %s\n" % format_vec.call(player_r_dir)
	text += "Dir Mano SX Target: %s\n" % format_vec.call(target_l_dir)
	text += "--> Errore Angolare Destro: %.3f (Tol. %.3f)\n" % [error_r, max_tolerance]
	text += "========================================\n"
	text += "Confidence Totale: %.1f%%\n" % [confidence * 100]

	print(text) # Lo teniamo anche in console per comodita'
	return text
