@tool
extends CharacterBody3D
class_name Living3DModelAnimated

enum State { IDLE, WALKING }

@export var model_path: String = ""
@export var move_speed: float = 1.5

@export_tool_button("Visualize 3D model") var load_model_btn = load_model

var ap: AnimationPlayer = null
var collision_shapes_created: bool = false

var idle_anims: Array[String] = []
var walk_anim: String = ""

# --- VARIABILI FISICA E SCHIVATA ---
var current_state: State = State.IDLE
var target_pos: Vector3 = Vector3.ZERO
var current_speed: float = 2.5
var current_nudge: Vector3 = Vector3.ZERO
# -----------------------------------

func _ready() -> void:
	var scene_root := load_model()
	if scene_root:
		ap = scene_root.get_node_or_null("AnimationPlayer")
		if ap:
			for anim_name in ap.get_animation_list():
				if "walk" in anim_name.to_lower():
					walk_anim = anim_name
				else:
					idle_anims.append(anim_name)
		scene_root.rotation_degrees.y = 180 

	if not Engine.is_editor_hint():
		# 1. CREIAMO IL COLLIDER DINAMICAMENTE
		var collider = CollisionShape3D.new()
		var shape = CapsuleShape3D.new()
		
		# Impostiamo le dimensioni basandoci sulla scala
		shape.radius = self.scale.x * 0.4
		shape.height = self.scale.y * 1.8
		collider.shape = shape
		
		collider.position = Vector3(0, shape.height / 2.0, 0) 
		
		add_child(collider)
		
		current_speed = move_speed
		_start_movement_cycle()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint(): return # Nessuna fisica nell'editor!
	
	if current_state == State.IDLE:
		# Se è fermo, azzeriamo la velocità (ma applichiamo gravità/scivolamento se serve in futuro)
		velocity = Vector3.ZERO
		move_and_slide()
		return
		
	# --- LOGICA DI MOVIMENTO E SCHIVATA ---
	var direction = global_position.direction_to(target_pos)
	var target_speed = move_speed
	var target_nudge = Vector3.ZERO
	
	for i in range(get_slide_collision_count()):
		var collision = get_slide_collision(i)
		var collider_obj = collision.get_collider()
		
		# Se sbatte contro qualcuno della folla (o un altro Animated Model)
		if collider_obj is CharacterBody3D:
			target_speed = move_speed * 0.4 
			var right_vector = Vector3(-direction.z, 0, direction.x).normalized()
			target_nudge = right_vector * 0.6
			break 
			
	current_speed = lerpf(current_speed, target_speed, delta * 4.0)
	current_nudge = current_nudge.lerp(target_nudge, delta * 3.0)
	
	if ap and move_speed > 0:
		ap.speed_scale = current_speed / move_speed
		
	velocity = (direction * current_speed) + current_nudge
	move_and_slide()


func _start_movement_cycle() -> void:
	while is_inside_tree():
		# ==========================================
		# FASE 1: DA FERMO
		# ==========================================
		current_state = State.IDLE
		
		if idle_anims.size() > 0:
			var random_idle = idle_anims.pick_random() 
			var anim_data = ap.get_animation(random_idle)
			anim_data.loop_mode = Animation.LOOP_NONE 
			ap.play(random_idle, 0.5)
			
			var idle_duration = anim_data.length
			if idle_duration <= 0.0: idle_duration = 2.0 
			await get_tree().create_timer(idle_duration).timeout
		else:
			await get_tree().create_timer(2.0).timeout 
			
		if not is_inside_tree(): break
		
		# ==========================================
		# FASE 2: PREPARAZIONE VIAGGIO
		# ==========================================
		var random_x = randf_range(-8.0, 8.0)
		var random_z = randf_range(-8.0, 8.0)
		target_pos = Vector3(random_x, global_position.y, random_z)
		
		if global_position.distance_to(target_pos) > 0.1:
			look_at(Vector3(target_pos.x, global_position.y, target_pos.z), Vector3.UP)

		if walk_anim != "":
			var w_data = ap.get_animation(walk_anim)
			w_data.loop_mode = Animation.LOOP_LINEAR 
			ap.play(walk_anim, 0.5)
			
		# Sblocchiamo il _physics_process
		current_state = State.WALKING
		
		# ==========================================
		# FASE 3: ATTESA DELL'ARRIVO
		# ==========================================
		# Invece di un Tween, mettiamo in pausa il ciclo finché il _physics_process 
		# non porta fisicamente il personaggio vicino alla destinazione
		while current_state == State.WALKING and is_inside_tree():
			await get_tree().physics_frame
			
			# Se siamo arrivati a meno di 20 cm dal bersaglio, ci fermiamo!
			if global_position.distance_to(target_pos) < 0.2:
				break


func load_model() -> Node3D:
	
	# Remove all children first
	for child in get_children():
		child.queue_free()
	
	# Internal vs. External: Use load() or preload() for files already inside your res:// folder. If you are trying to load a file from the user's desktop (outside the game folder) at runtime, you'll need to use GLTFDocument and GLTFState classes instead.
	var model_root: Node3D = null
	if model_path.begins_with("res://"):
		print("Loading from resources ...")
		model_root = load_model_from_res()
	else:
		print("Loading from file ...")
		model_root = load_model_from_file()

	if model_root:
		print("Adding GLTF obj ", model_root)
		add_child(model_root)
		# Optional: Position or scale the model
		model_root.position = Vector3.ZERO
		model_root.scale = Vector3.ONE
		
	else:
		push_error("Failed to load 3D model from path ", model_path)

	return model_root


func load_model_from_res() -> Node3D:
	# 1. Check if the file exists to avoid errors
	if not ResourceLoader.exists(model_path):
		print("Error: File not found at ", model_path)
		return

	# 2. Load the resource as a PackedScene
	var model_scene = load(model_path)
	
	var model_root = null
	
	if model_scene is PackedScene:
		# 3. Instance the scene
		model_root = model_scene.instantiate()
		print("Model loaded successfully!")
		
	else:
		print("Error: Resource at path is not a 3D scene.")
	
	return model_root


func load_model_from_file() -> Node3D:

	var gltf_doc := GLTFDocument.new()
	var gltf_state := GLTFState.new()
		
	var error := gltf_doc.append_from_file(model_path, gltf_state)
	if error != OK:
		push_error("Failed to load GLB: " + gltf_state.get_message() if gltf_state.has_method("get_message") else "Error code: " + str(error))
		return null

	# print("State: ")
	# _print_state_info(gltf_state)
	
	var model_root := gltf_doc.generate_scene(gltf_state)
	
	# Traverse the tree and convert ImporterMeshes to standard Meshes
	_convert_to_runtime_glb_nodes(model_root)

	if not model_root:
		push_error("Failed to generate scene from GLTF state")
	
	return model_root


# This function recursively finds ImporterMeshInstance3D and replaces it 
# with a standard MeshInstance3D that the renderer can see.
func _convert_to_runtime_glb_nodes(node: Node):
	print("Converting meshes for node ", node.name)
	if node is ImporterMeshInstance3D:
		var mesh_instance = MeshInstance3D.new()
		
		# Get the actual renderable Mesh from the ImporterMesh
		if node.mesh:
			mesh_instance.mesh = node.mesh.get_mesh() 
		
		mesh_instance.skin = node.skin
		# mesh_instance.skeleton = node.skeleton
		mesh_instance.name = node.name
		mesh_instance.transform = node.transform
		
		# Swap the nodes
		var parent = node.get_parent()
		if parent:
			parent.add_child(mesh_instance)
			parent.remove_child(node)
			node.queue_free()
			# Continue traversing from the new node
			node = mesh_instance 

	# Continue down the tree
	for child in node.get_children():
		_convert_to_runtime_glb_nodes(child)
