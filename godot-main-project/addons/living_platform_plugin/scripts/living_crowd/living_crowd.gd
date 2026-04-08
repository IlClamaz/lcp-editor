@tool
extends Node3D

class_name LivingCrowd

@export var model_path: String = ""
@export var density: int = 20
@export var spawn_radius: float = 20.0

@export_tool_button("Load Crowd Model") var load_model_btn = load_model

# Variabili di stato per la simulazione
var templates: Array[Node3D] = []
var check_point_pos: Vector3 = Vector3.ZERO
var nav_region: NavigationRegion3D
var spawn_timer: Timer
var source_anim_player: AnimationPlayer
var clean_anim_players: Dictionary = {} # Dizionario per memorizzare gli AnimationPlayer puliti per ogni template

func _ready() -> void:
	if model_path != "":
		# Usa call_deferred per dare tempo all'editor/scena di inizializzarsi
		call_deferred("load_model")


# ==============================================================================
# 1. LOGICA DI CARICAMENTO E CONVERSIONE (Ereditata da Living3DModel)
# ==============================================================================

func load_model() -> Node3D:
	# Pulisce i figli esistenti e resetta lo stato della folla
	for child in get_children():
		child.queue_free()
	templates.clear()
	check_point_pos = Vector3.ZERO
	
	var model_root: Node3D = null
	
	if model_path.begins_with("res://"):
		print("Loading Crowd from resources ...")
		model_root = load_model_from_res()
	else:
		print("Loading Crowd from file ...")
		model_root = load_model_from_file()

	if model_root:
		print("Adding Crowd GLB obj ", model_root)
		add_child(model_root)
		model_root.position = Vector3.ZERO
		model_root.scale = Vector3.ONE
		
		# AVVIA LA LOGICA DELLA FOLLA
		_setup_crowd_from_glb(model_root)
	else:
		push_error("Failed to load Crowd model from path ", model_path)

	return model_root

func load_model_from_res() -> Node3D:
	if not ResourceLoader.exists(model_path):
		print("Error: File not found at ", model_path)
		return null

	var model_scene = load(model_path)
	var model_root = null
	
	if model_scene is PackedScene:
		model_root = model_scene.instantiate()
		print("Crowd Model loaded successfully!")
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

	var model_root := gltf_doc.generate_scene(gltf_state)
	_convert_to_runtime_glb_nodes(model_root)

	if not model_root:
		push_error("Failed to generate scene from GLTF state")
	
	return model_root

func _convert_to_runtime_glb_nodes(node: Node):
	if node is ImporterMeshInstance3D:
		var mesh_instance = MeshInstance3D.new()
		if node.mesh:
			mesh_instance.mesh = node.mesh.get_mesh() 
		
		mesh_instance.skin = node.skin
		mesh_instance.name = node.name
		mesh_instance.transform = node.transform
		
		var parent = node.get_parent()
		if parent:
			parent.add_child(mesh_instance)
			parent.remove_child(node)
			node.queue_free()
			node = mesh_instance 

	for child in node.get_children():
		_convert_to_runtime_glb_nodes(child)


# ==============================================================================
# 2. LOGICA DELLA FOLLA E SETUP DELL'AMBIENTE
# ==============================================================================

func _setup_crowd_from_glb(scene_root: Node3D) -> void:
	# 1. SETUP CHECKPOINT CON VISUALIZZAZIONE DEBUG
	var checkpoint = scene_root.find_child("CheckPoint*", true, false)
	if checkpoint:
		check_point_pos = checkpoint.global_position
		if Engine.is_editor_hint():
			_create_debug_marker(checkpoint, Color(1, 0, 0, 0.5)) # Rosso trasparente
		else:
			checkpoint.hide()

	# 2. SETUP WALKING AREA (NAVMESH) CON MATERIALE DEBUG
	var walking_area = scene_root.find_child("WalkingArea*", true, false)
	if walking_area:
		nav_region = NavigationRegion3D.new()
		var nav_mesh = NavigationMesh.new()
		nav_region.navigation_mesh = nav_mesh
		add_child(nav_region)
		
		walking_area.reparent(nav_region)
		nav_region.bake_navigation_mesh()
		
		if Engine.is_editor_hint():
			_apply_debug_material(walking_area, Color(0, 1, 0.6, 0.7)) # Ciano tipo Godot
		else:
			walking_area.hide()

	# 3. SETUP ANIMAZIONI E TEMPLATE
	var ap = scene_root.find_child("AnimationPlayer*", true, false)
	for child in scene_root.find_children("avatar-*", "Node3D", false, false):
		child.hide()
		templates.append(child)
		if ap:
			clean_anim_players[child.name] = _create_purified_anim_player(ap, child.name)

	if Engine.is_editor_hint():
		_generate_static_preview()
	else:
		_start_simulation()


func _create_purified_anim_player(source_ap: AnimationPlayer, target_name: String) -> AnimationPlayer:
	var clean_ap = source_ap.duplicate()
	clean_ap.name = "AnimationPlayer"
	
	# Il nome esatto che ci aspettiamo, es: "avatar-1-walk"
	var expected_anim_name = target_name + "-walk" 
	
	if clean_ap.has_animation_library(""):
		var lib = clean_ap.get_animation_library("").duplicate()
		clean_ap.remove_animation_library("")
		
		for anim_name in lib.get_animation_list():
			# 1. Se il nome dell'animazione NON è quello esatto, la eliminiamo
			if anim_name.to_lower() != expected_anim_name.to_lower():
				lib.remove_animation(anim_name)
			else:
				# 2. Abbiamo trovato l'animazione giusta. Puliamo le tracce interne
				var anim = lib.get_animation(anim_name)
				for i in range(anim.get_track_count() - 1, -1, -1):
					if not str(anim.track_get_path(i)).begins_with(target_name + "/"):
						anim.remove_track(i) # Rimuoviamo le ossa degli altri avatar
						
		clean_ap.add_animation_library("", lib)
		
	return clean_ap

# ==============================================================================
# 3. EDITOR PREVIEW E SIMULAZIONE RUNTIME
# ==============================================================================

# Helper per vedere il Checkpoint nell'editor
func _create_debug_marker(parent: Node, color: Color):
	var mesh_instance = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	mesh_instance.mesh = sphere
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_instance.material_override = mat
	
	parent.add_child(mesh_instance)
	mesh_instance.add_to_group("editor_debug_vis")

# Helper per il materiale stile NavMesh/Collider
func _apply_debug_material(node: Node, color: Color):
	var meshes = node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D: meshes.append(node)
	
	var debug_mat = StandardMaterial3D.new()
	debug_mat.albedo_color = color
	debug_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	debug_mat.cull_mode = BaseMaterial3D.CULL_DISABLED # Visibile da entrambi i lati
	
	for m in meshes:
		m.material_override = debug_mat
		m.add_to_group("editor_debug_vis")

# Preview che "snappa" sulla WalkingArea
func _generate_static_preview() -> void:
	for child in get_children():
		if child.is_in_group("editor_preview_ghost"): child.queue_free()
			
	var preview_count = mini(density, 15)
	for i in range(preview_count):
		var template_source = templates[randi() % templates.size()]
		var ghost = template_source.duplicate()
		ghost.show()
		
		# Proiettiamo la posizione sulla NavMesh
		var raw_pos = _get_random_circle_position()
		var snapped_pos = NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, raw_pos)
		
		var dummy_body = Node3D.new()
		dummy_body.add_to_group("editor_preview_ghost")
		dummy_body.add_child(ghost)
		add_child(dummy_body)
		
		dummy_body.global_position = snapped_pos
		if dummy_body.global_position.distance_to(check_point_pos) > 0.1:
			dummy_body.look_at(Vector3(check_point_pos.x, dummy_body.global_position.y, check_point_pos.z), Vector3.UP)

func _start_simulation() -> void:
	print("Avvio simulazione folla viva...")
	spawn_timer = Timer.new()
	spawn_timer.wait_time = maxf(1.0, 50.0 / float(density)) # Regola la velocità di spawn in base alla densità desiderata
	spawn_timer.autostart = true
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	add_child(spawn_timer)

func _on_spawn_timer_timeout() -> void:
	if templates.is_empty(): return
	
	var agent_body = CharacterBody3D.new()
	agent_body.set_script(preload("crowd_agent.gd"))
	
	var nav = NavigationAgent3D.new()
	nav.name = "NavigationAgent3D"
	agent_body.add_child(nav)
	
	var collider = CollisionShape3D.new()
	var shape = CapsuleShape3D.new()
	collider.shape = shape
	collider.position = Vector3(0, 1, 0)
	agent_body.add_child(collider)
	
	# Cloniamo l'avatar MA MANTENIAMO IL SUO NOME ORIGINALE (es. avatar-2)
	var random_template = templates[randi() % templates.size()].duplicate()
	random_template.show()
	agent_body.add_child(random_template)
	
	# Gli assegniamo il suo AnimationPlayer già pulito!
	var template_name = random_template.name
	if clean_anim_players.has(template_name):
		var my_perfect_ap = clean_anim_players[template_name].duplicate()
		my_perfect_ap.root_node = NodePath("..")
		agent_body.add_child(my_perfect_ap)
	
	add_child(agent_body)
	
	# Recuperiamo la mappa di navigazione del mondo
	var map = get_world_3d().navigation_map
	
	var is_inbound = randf() > 0.5
	if is_inbound:
		var raw_spawn_pos = _get_random_circle_position()
		# Forziamo il punto iniziale sulla WalkingArea
		var safe_spawn_pos = NavigationServer3D.map_get_closest_point(map, raw_spawn_pos)
		
		agent_body.global_position = safe_spawn_pos
		agent_body.setup_inbound(check_point_pos)
	else:
		# Se vogliamo essere sicuri al 100%, snappiamo anche l'uscita
		var safe_start = NavigationServer3D.map_get_closest_point(map, check_point_pos)
		agent_body.global_position = safe_start
		
		var raw_exit = _get_random_circle_position()
		var safe_exit = NavigationServer3D.map_get_closest_point(map, raw_exit)
		
		agent_body.setup_outbound(safe_exit)

func _get_random_circle_position() -> Vector3:
	var angle = randf() * TAU
	var radius = randf_range(2.0, spawn_radius)
	return global_position + Vector3(cos(angle) * radius, 0, sin(angle) * radius)
