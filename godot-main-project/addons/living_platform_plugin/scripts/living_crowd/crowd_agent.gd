extends CharacterBody3D

enum State { WANDERING, GOING_TO_POINT, FADING_OUT }

var current_state: State
var is_inbound: bool = true
var point_pos: Vector3
var wander_target: Vector3
var wander_count: int = 0
var max_wanders: int = 3
var speed: float = 2.5
var clone_materials: Array[StandardMaterial3D] = []

@onready var nav_agent = $NavigationAgent3D

var avatar_node: Node3D
var anim_player: AnimationPlayer

func _ready():
	# 1. Trova dinamicamente chi sono cercando "avatar-"
	for child in get_children():
		if child is Node3D and child.name.to_lower().begins_with("avatar-"):
			avatar_node = child
			# Ruotiamo di 180 gradi per farlo camminare nella direzione giusta (-Z)
			avatar_node.rotation_degrees.y = 180 
			break
			
	anim_player = get_node_or_null("AnimationPlayer")

	setup_materials()
	_play_walk_animation()
	fade_in()

func setup_inbound(point_target: Vector3):
	is_inbound = true
	point_pos = point_target
	current_state = State.WANDERING
	
	max_wanders = randi_range(3, 8) 
	wander_count = 0
	
	pick_random_wander_target()

func setup_outbound(exit_target: Vector3):
	is_inbound = false
	current_state = State.WANDERING
	nav_agent.target_position = exit_target

func _physics_process(delta):
	if current_state == State.FADING_OUT:
		return 

	if nav_agent.is_navigation_finished():
		handle_destination_reached()
		return

	var next_path_pos = nav_agent.get_next_path_position()
	var direction = global_position.direction_to(next_path_pos)
	
	var look_target = Vector3(next_path_pos.x, global_position.y, next_path_pos.z)
	
	if global_position.distance_to(look_target) > 0.05:
		look_at(look_target, Vector3.UP)
	
	velocity = direction * speed
	move_and_slide()

func handle_destination_reached():
	if current_state == State.WANDERING:
		if is_inbound:
			wander_count += 1
			if wander_count >= max_wanders:
				current_state = State.GOING_TO_POINT
				nav_agent.target_position = point_pos
			else:
				pick_random_wander_target()
		else:
			fade_out()
			
	elif current_state == State.GOING_TO_POINT:
		fade_out()

func pick_random_wander_target():
	var random_offset = Vector3(randf_range(-15, 15), 0, randf_range(-15, 15))
	var desired_pos = global_position + random_offset
	
	# OBBLIGHIAMO il target a stare sulla WalkingArea
	var map = nav_agent.get_navigation_map()
	var safe_pos = NavigationServer3D.map_get_closest_point(map, desired_pos)
	
	nav_agent.target_position = safe_pos



func _play_walk_animation():
	if not anim_player or not avatar_node: 
		return

	# Sappiamo esattamente cosa stiamo cercando
	var expected_anim_name = avatar_node.name + "-walk"
	
	# Metodo veloce e diretto
	if anim_player.has_animation(expected_anim_name):
		var anim = anim_player.get_animation(expected_anim_name)
		anim.loop_mode = Animation.LOOP_LINEAR 
		anim_player.play(expected_anim_name)
	else:
		# in caso i modellatori scrivano "Avatar-1-Walk" (con le maiuscole)
		for anim_name in anim_player.get_animation_list():
			if expected_anim_name.to_lower() == anim_name.to_lower():
				var anim = anim_player.get_animation(anim_name)
				anim.loop_mode = Animation.LOOP_LINEAR 
				anim_player.play(anim_name)
				return
				
		push_warning("Attenzione: Non ho trovato l'animazione ", expected_anim_name)


func setup_materials():
	# Trova TUTTI i nodi MeshInstance3D all'interno del nodo Avatar
	var meshes = avatar_node.find_children("*", "MeshInstance3D", true, false)
	
	for mesh_instance in meshes:
		if not mesh_instance.mesh:
			continue
			
		# Controlla quanti slot materiale ha la mesh reale
		var mat_count = mesh_instance.mesh.get_surface_count()
		
		for i in range(mat_count):
			var mat = mesh_instance.get_active_material(i)
			
			if mat is StandardMaterial3D:
				var unique_mat = mat.duplicate()
				
				# TRANSPARENCY_ALPHA garantisce una sfumatura pulita invece del dither "a pallini" dell'HASH
				unique_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				
				mesh_instance.set_surface_override_material(i, unique_mat)
				clone_materials.append(unique_mat)

func fade_in():
	if clone_materials.is_empty():
		return
		
	var tween = create_tween()
	tween.set_parallel(true)
	
	for mat in clone_materials:
		# Assicuriamoci che partano trasparenti
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var color = mat.albedo_color
		color.a = 0.0 
		mat.albedo_color = color
		
		# Animiamo l'alpha fino a 1.0
		tween.tween_property(mat, "albedo_color:a", 1.0, 1.5)
	
	# Quando TUTTE le animazioni parallele finiscono, blocchiamo i materiali in modalità solida
	tween.chain().tween_callback(_make_materials_opaque)


func _make_materials_opaque():
	for mat in clone_materials:
		# Spegnendo la trasparenza, riattiviamo il Depth Buffer: niente più z-fighting!
		mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED


func fade_out():
	current_state = State.FADING_OUT
	velocity = Vector3.ZERO
	
	var tween = create_tween()
	tween.set_parallel(true)
	
	for mat in clone_materials:
		# Riattiviamo l'alpha un attimo prima di iniziare a svanire
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tween.tween_property(mat, "albedo_color:a", 0.0, 1.5)
		
	tween.chain().tween_callback(queue_free)
