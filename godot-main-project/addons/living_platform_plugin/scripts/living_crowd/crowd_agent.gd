extends CharacterBody3D

enum State { WALKING, FADING_OUT }

var current_state: State
var is_inbound: bool = true
var clone_materials: Array[StandardMaterial3D] = []

@onready var nav_agent = $NavigationAgent3D

var avatar_node: Node3D
var anim_player: AnimationPlayer
var speed: float = 1
var base_anim_speed: float = 1.0 

# --- VARIABILI SCHIVATA  ---
var current_speed: float = 1.0
var current_nudge: Vector3 = Vector3.ZERO
# ----------------------------------

func _ready():
	speed = randf_range(0.8, 2.0)
	current_speed = speed # Inizializziamo alla velocità base
	
	for child in get_children():
		if child is Node3D and child.name.to_lower().begins_with("avatar-"):
			avatar_node = child
			avatar_node.rotation_degrees.y = 180 
			break
			
	anim_player = get_node_or_null("AnimationPlayer")
	if nav_agent: nav_agent.target_desired_distance = 3.0 

	setup_materials()
	_play_walk_animation()
	fade_in()


func setup_inbound(point_target: Vector3):
	is_inbound = true
	current_state = State.WALKING
	nav_agent.target_position = point_target


func setup_outbound(exit_target: Vector3):
	is_inbound = false
	current_state = State.WALKING
	nav_agent.target_position = exit_target


func _physics_process(delta):
	if current_state == State.FADING_OUT:
		return 

	if nav_agent.is_navigation_finished():
		fade_out()
		return

	var next_path_pos = nav_agent.get_next_path_position()
	var direction = global_position.direction_to(next_path_pos)
	
	var look_target = Vector3(next_path_pos.x, global_position.y, next_path_pos.z)
	if global_position.distance_to(look_target) > 0.05:
		look_at(look_target, Vector3.UP)
	
	# --- LOGICA SCHIVATA MORBIDA E RALLENTAMENTO ---
	var target_speed = speed
	var target_nudge = Vector3.ZERO
	
	for i in range(get_slide_collision_count()):
		var collision = get_slide_collision(i)
		var collider = collision.get_collider()
		
		if collider is CharacterBody3D:
			# 1. Frenata: il bersaglio della nostra velocità crolla al 40%
			target_speed = speed * 0.4 
			
			# 2. Scartamento: calcoliamo una spinta laterale
			var right_vector = Vector3(-direction.z, 0, direction.x).normalized()
			target_nudge = right_vector * 0.6
			break 
	
	# Interpolazione (Lerp): rendiamo fluida l'accelerazione/decelerazione
	# e ammorbidiamo l'ingresso e l'uscita dalla schivata laterale.
	current_speed = lerpf(current_speed, target_speed, delta * 4.0)
	current_nudge = current_nudge.lerp(target_nudge, delta * 3.0)
	
	# rallentiamo anche il passo delle gambe per non farli sembrare "scivolosi"
	if anim_player and speed > 0:
		anim_player.speed_scale = current_speed / speed
		
	# Applichiamo la velocità composita
	velocity = (direction * current_speed) + current_nudge
	# -----------------------------------------------

	move_and_slide()


func _play_walk_animation():
	if not anim_player or not avatar_node: 
		return
		
	var anim_speed_ratio = speed / base_anim_speed
	var available_anims = anim_player.get_animation_list()
	
	if available_anims.size() > 0:
		var anim_to_play = available_anims[0]
		for anim in available_anims:
			if "walk" in anim.to_lower():
				anim_to_play = anim
				break
				
		var anim_data = anim_player.get_animation(anim_to_play)
		anim_data.loop_mode = Animation.LOOP_LINEAR 
		anim_player.play(anim_to_play, -1.0, anim_speed_ratio)
	else:
		push_warning("Attenzione: Questo avatar non ha nessuna animazione associata!")

func setup_materials():
	var meshes = avatar_node.find_children("*", "MeshInstance3D", true, false)
	for mesh_instance in meshes:
		if not mesh_instance.mesh: continue
			
		var mat_count = mesh_instance.mesh.get_surface_count()
		for i in range(mat_count):
			var mat = mesh_instance.get_active_material(i)
			if mat is StandardMaterial3D:
				var unique_mat = mat.duplicate()
				unique_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				unique_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
				mesh_instance.set_surface_override_material(i, unique_mat)
				clone_materials.append(unique_mat)

func fade_in():
	if clone_materials.is_empty(): return
	var tween = create_tween()
	tween.set_parallel(true)
	
	for mat in clone_materials:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
		var color = mat.albedo_color
		color.a = 0.0 
		mat.albedo_color = color
		tween.tween_property(mat, "albedo_color:a", 1.0, 0.5)
	tween.chain().tween_callback(_make_materials_opaque)

func _make_materials_opaque():
	for mat in clone_materials:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY

func fade_out():
	current_state = State.FADING_OUT
	velocity = Vector3.ZERO
	var tween = create_tween()
	tween.set_parallel(true)
	
	for mat in clone_materials:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
		tween.tween_property(mat, "albedo_color:a", 0.0, 0.5)
		
	tween.chain().tween_callback(queue_free)
