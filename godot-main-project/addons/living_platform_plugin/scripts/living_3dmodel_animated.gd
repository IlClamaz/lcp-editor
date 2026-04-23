@tool
extends CharacterBody3D
class_name Living3DModelAnimated

enum State { IDLE, WALKING }

@export var model_path: String = ""
@export var move_speed: float = 2
@export var random_poses_playing: bool = true
@export var moving: bool = true

@export_tool_button("Visualize 3D model") var load_model_btn: Callable = load_model

var ap: AnimationPlayer = null
var collision_shapes_created: bool = false

var pose_anims: Array[String] = []
var walk_anim: String = ""
var idle_anim: String = ""

# --- VARIABILI FISICA E SCHIVATA ---
var current_state: State = State.IDLE
var target_pos: Vector3 = Vector3.ZERO
var current_speed: float = 2.5
var current_nudge: Vector3 = Vector3.ZERO

# --- VARIABILI AI AUTONOMA ---
var _ai_routine_active: bool = false
# -----------------------------------

func _ready() -> void:
	var scene_root := load_model()
	if scene_root:
		ap = scene_root.get_node_or_null("AnimationPlayer")
		if ap:
			for anim_name in ap.get_animation_list():
				if "walk" in anim_name.to_lower():
					walk_anim = anim_name
				elif "idle" in anim_name.to_lower():
					idle_anim = anim_name
				else:
					pose_anims.append(anim_name)
		scene_root.rotation_degrees.y = 180
		if idle_anim != "":
			play_pose(idle_anim, false)
		if pose_anims.size() == 0:
			print("No pose animations found, autonomous behavior will be limited to movement only.")

	if not Engine.is_editor_hint():
		# 1. CREIAMO IL COLLIDER DINAMICAMENTE
		var collider = CollisionShape3D.new()
		var shape = CapsuleShape3D.new()

		shape.radius = self.scale.x * 0.4
		shape.height = self.scale.y * 1.8
		collider.shape = shape
		collider.position = Vector3(0, shape.height / 2.0, 0)
		add_child(collider)

		current_speed = move_speed

		# Avvia l'AI solo se richiesto
		if random_poses_playing or moving:
			start_autonomous_behavior()

func _exit_tree() -> void:
	# During scene switches, stop AI immediately to prevent resumed awaits
	# from touching transforms while the node is outside the tree.
	_ai_routine_active = false


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint(): return

	if current_state == State.IDLE:
		# Rallenta dolcemente fino a fermarsi
		velocity = velocity.move_toward(Vector3.ZERO, delta * 15.0)
		move_and_slide()
		return

	# --- LOGICA DI MOVIMENTO E SCHIVATA ---
	var direction: Vector3    = global_position.direction_to(target_pos)
	var target_speed: float   = move_speed
	var target_nudge: Vector3 = Vector3.ZERO

	for i in range(get_slide_collision_count()):
		var collision: KinematicCollision3D = get_slide_collision(i)
		var collider_obj: Object = collision.get_collider()

		# Evita altri Character (Folla)
		if collider_obj is CharacterBody3D:
			target_speed = move_speed * 0.4
			var right_vector: Vector3 = Vector3(-direction.z, 0, direction.x).normalized()
			target_nudge = right_vector * 0.6
			break

	current_speed = lerpf(current_speed, target_speed, delta * 4.0)
	current_nudge = current_nudge.lerp(target_nudge, delta * 3.0)

	if ap and move_speed > 0:
		ap.speed_scale = current_speed / move_speed

	velocity = (direction * current_speed) + current_nudge
	move_and_slide()


# ========================================
# API - AZIONI FISICHE (IL "CORPO")
# ========================================

## Comanda al character di camminare verso una coordinata precisa
func move_to(target: Vector3) -> void:
	if not is_inside_tree():
		return

	target_pos = Vector3(target.x, global_position.y, target.z)

	if global_position.distance_to(target_pos) > 0.1:
		look_at(target_pos, Vector3.UP)

	if walk_anim != "" and ap:
		var w_data: Animation = ap.get_animation(walk_anim)
		w_data.loop_mode = Animation.LOOP_LINEAR
		ap.play(walk_anim, 0.5)

	current_state = State.WALKING

## Comanda al character di fermarsi sul posto
func stop_movement() -> void:
	current_state = State.IDLE
	if ap and walk_anim != "" and ap.current_animation == walk_anim:
		ap.stop()

## Pesca un'animazione idle a caso, la riproduce e restituisce quanto dura
func play_random_pose() -> float:
	if pose_anims.is_empty() or not ap: return 2.0

	var random_pose = pose_anims.pick_random()
	var anim_data: Animation = ap.get_animation(random_pose)
	anim_data.loop_mode = Animation.LOOP_NONE
	ap.play(random_pose, 0.5)

	var duration: float = anim_data.length
	return duration if duration > 0.0 else 2.0

## Mette in pausa il ciclo normale e mostra una posa specifica
func play_pose(pose_name: String, loop: bool = false) -> void:
	# Spegne l'AI quando gli chiedi di fare una posa!
	stop_autonomous_behavior()

	if not ap: return
	if not ap.has_animation(pose_name):
		push_error("Animation not found: ", pose_name)
		return

	var anim_data: Animation = ap.get_animation(pose_name)
	anim_data.loop_mode = Animation.LOOP_NONE if not loop else Animation.LOOP_LINEAR

	stop_movement()
	ap.play(pose_name, 0.5)

## Forza il character in idle in modo consistente.
## Ritorna true se un'animazione idle e' stata trovata e avviata.
func play_idle_pose(loop: bool = true) -> bool:
	if not ap:
		return false

	if idle_anim != "" and ap.has_animation(idle_anim):
		play_pose(idle_anim, loop)
		return true

	for anim_name in ap.get_animation_list():
		if "idle" in anim_name.to_lower():
			idle_anim = anim_name
			play_pose(idle_anim, loop)
			return true

	return false


# ========================================
# API - LOGICA AUTONOMA (IL "CERVELLO")
# ========================================

## Accende l'Intelligenza Artificiale che fa girovagare il character
func start_autonomous_behavior() -> void:
	if _ai_routine_active: return
	_ai_routine_active = true
	_autonomous_routine()

## Spegne l'Intelligenza Artificiale
func stop_autonomous_behavior() -> void:
	_ai_routine_active = false
	stop_movement()

## Il ciclo vitale dell'AI aggiornato per differenziare i comportamenti
func _autonomous_routine() -> void:
	while is_inside_tree() and _ai_routine_active:

		# --- COMPORTAMENTO 1: POSE SUL POSTO ---
		if random_poses_playing:
			# Il personaggio esegue una posa e aspetta che finisca
			var duration: float = play_random_pose()
			await get_tree().create_timer(duration).timeout
			if not is_inside_tree() or not _ai_routine_active:
				break

		if not _ai_routine_active: break

		# --- COMPORTAMENTO 2: MOVIMENTO ---
		if moving:
			if not is_inside_tree():
				break
			# Calcola un punto a caso nel raggio di 8 metri
			var random_target: Vector3 = Vector3(randf_range(-8, 8), global_position.y, randf_range(-8, 8))
			move_to(random_target)

			# Aspetta di arrivare a destinazione prima di fare altro
			while current_state == State.WALKING and _ai_routine_active:
				if not is_inside_tree():
					break
				await get_tree().physics_frame	
				if not is_inside_tree() or not _ai_routine_active:
					break
				if global_position.distance_to(target_pos) < 0.2:
					stop_movement()
					break
		else:
			# Se non deve muoversi, aggiungiamo una piccola pausa tra una posa e l'altra
			await get_tree().create_timer(1.0).timeout
			if not is_inside_tree() or not _ai_routine_active:
				break


# ========================================
# CORE E UTILITA' (Caricamento, Ossa, ecc.)
# ========================================

func load_model() -> Node3D:
	for child in get_children():
		child.queue_free()

	var model_root: Node3D = null
	if model_path.begins_with("res://"):
		print("Loading from resources ...")
		model_root = load_model_from_res()
	else:
		print("Loading from file ...")
		model_root = load_model_from_file()

	if model_root:
		add_child(model_root)
		model_root.position = Vector3.ZERO
		model_root.scale = Vector3.ONE
	else:
		push_error("Failed to load 3D model from path ", model_path)
	return model_root

func load_model_from_res() -> Node3D:
	if not ResourceLoader.exists(model_path): return null
	var model_scene = load(model_path)
	if model_scene is PackedScene:
		return model_scene.instantiate()
	return null

func load_model_from_file() -> Node3D:
	var gltf_doc := GLTFDocument.new()
	var gltf_state := GLTFState.new()
	var error := gltf_doc.append_from_file(model_path, gltf_state)
	if error != OK: return null
	var model_root := gltf_doc.generate_scene(gltf_state)
	_convert_to_runtime_glb_nodes(model_root)
	return model_root

func _convert_to_runtime_glb_nodes(node: Node):
	if node is ImporterMeshInstance3D:
		var mesh_instance = MeshInstance3D.new()
		if node.mesh: mesh_instance.mesh = node.mesh.get_mesh()
		mesh_instance.skin = node.skin
		mesh_instance.name = node.name
		mesh_instance.transform = node.transform
		var parent: Node = node.get_parent()
		if parent:
			parent.add_child(mesh_instance)
			parent.remove_child(node)
			node.queue_free()
			node = mesh_instance
	for child in node.get_children():
		_convert_to_runtime_glb_nodes(child)

func _get_named_node_or_bone_position(root: Node, candidate_names: Array[Variant], default_value: Vector3) -> Vector3:
	for candidate_name in candidate_names:
		var scene_node: Node = root.find_child(candidate_name, true, false)
		if scene_node:
			return scene_node.global_position

	var skeleton: Skeleton3D = _find_model_skeleton(root)
	if skeleton:
		for candidate_name in candidate_names:
			var bone_idx: int = skeleton.find_bone(candidate_name)
			if bone_idx != -1:
				var bone_transform: Transform3D = skeleton.get_bone_global_pose(bone_idx)
				return (skeleton.global_transform * bone_transform).origin

	return default_value

func get_chest_position() -> Vector3:
	if not ap or not ap.get_parent():
		return global_position

	var root: Node = ap.get_parent()
	var chest_names: Array[Variant] = [
		"UpperChest", "mixamorig_Spine2", "Chest", "mixamorig_Spine1",
		"Spine2", "Spine1", "Spine", "Torso", "Hips", "mixamorig_Hips"
	]
	return _get_named_node_or_bone_position(root, chest_names, global_position)

func get_shoulder_position(is_right: bool = true) -> Vector3:
	if not ap or not ap.get_parent():
		return global_position

	var root: Node = ap.get_parent()
	var shoulder_names: Array[Variant] = [
		"Shoulder.R", "Shoulder_R", "RightShoulder", "mixamorig_RightShoulder",
		"UpperArm.R", "UpperArm_R", "RightArm", "mixamorig_RightArm"
	] if is_right else [
		"Shoulder.L", "Shoulder_L", "LeftShoulder", "mixamorig_LeftShoulder",
		"UpperArm.L", "UpperArm_L", "LeftArm", "mixamorig_LeftArm"
	]
	return _get_named_node_or_bone_position(root, shoulder_names, get_chest_position())

func get_elbow_position(is_right: bool = true) -> Vector3:
	if not ap or not ap.get_parent():
		return global_position

	var root: Node = ap.get_parent()
	var elbow_names: Array[Variant] = [
		"ForeArm.R", "ForeArm_R", "RightForeArm", "mixamorig_RightForeArm",
		"LowerArm.R", "LowerArm_R", "RightLowerArm"
	] if is_right else [
		"ForeArm.L", "ForeArm_L", "LeftForeArm", "mixamorig_LeftForeArm",
		"LowerArm.L", "LowerArm_L", "LeftLowerArm"
	]
	return _get_named_node_or_bone_position(root, elbow_names, get_shoulder_position(is_right))

func get_arm_feedback_points(is_right: bool = true) -> Dictionary:
	var chest: Vector3 = get_chest_position()
	var shoulder: Vector3 = get_shoulder_position(is_right)
	var elbow: Vector3 = get_elbow_position(is_right)
	var hand: Vector3 = get_hand_position(is_right)

	return {
		"chest": chest,
		"shoulder": shoulder,
		"elbow": elbow,
		"hand": hand
	}

func get_hand_position(is_right: bool = true) -> Vector3:
	if not ap or not ap.get_parent():
		return Vector3.ZERO

	var bone_names: Array[Variant] = ["Hand.R", "Hand_R", "RightHand", "mixamorig_RightHand", "hand_right"] if is_right \
									 else ["Hand.L", "Hand_L", "LeftHand", "mixamorig_LeftHand", "hand_left"]
	var root: Node = ap.get_parent()
	return _get_named_node_or_bone_position(root, bone_names, global_position)

func get_pose_anchor_position() -> Vector3:
	if not ap or not ap.get_parent():
		return global_position

	var root: Node = ap.get_parent()
	var anchor_names: Array[Variant] = ["Head", "mixamorig_Head", "Neck", "mixamorig_Neck", "UpperChest", "Chest", "Spine2", "Spine1", "Spine", "Hips", "mixamorig_Hips", "Pelvis"]
	return _get_named_node_or_bone_position(root, anchor_names, global_position)

func _find_model_skeleton(root: Node) -> Skeleton3D:
	var skeleton_nodes: Array[Node] = root.find_children("*", "Skeleton3D", true, false)
	if skeleton_nodes.size() > 0: return skeleton_nodes[0] as Skeleton3D
	return null

func get_current_animation() -> String:
	return ap.current_animation if ap and ap.is_playing() else ""

func is_animation_playing() -> bool:
	return ap != null and ap.is_playing()

func await_animation_finish() -> void:
	if ap: await ap.animation_finished

func pause_animation() -> void:
	if ap and ap.is_playing(): ap.pause()

func resume_animation() -> void:
	if ap and not ap.is_playing(): ap.play()

func set_animation_position(position: float) -> void:
	if ap and ap.current_animation != "":
		ap.seek(clamp(position, 0.0, 1.0) * ap.get_animation(ap.current_animation).length)

func get_current_animation_length() -> float:
	if ap and ap.current_animation != "":
		var anim: Animation = ap.get_animation(ap.current_animation)
		if anim: return anim.length
	return 0.0

func get_current_animation_position() -> float:
	if ap and ap.current_animation != "":
		var anim: Animation = ap.get_animation(ap.current_animation)
		if anim and anim.length > 0: return ap.current_animation_position / anim.length
	return 0.0
