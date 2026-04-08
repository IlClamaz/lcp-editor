extends CharacterBody3D

class_name LivingCamera

# Riferimenti ai nodi e risorse
@export var input_reader: InputReader
@export var cam: Camera3D

# Impostazioni Movimento
@export var move_speed: float = 5.0
@export var acceleration: float = 10.0 # Per rendere il movimento meno "scivoloso"
@export var friction: float = 10.0

# Impostazioni Camera
@export var mouse_sensitivity: float = 0.1
@export var max_look_up_deg: float = 85.0
@export var max_look_down_deg: float = -85.0

## The instance to manage the floating HUDs
@export var hud_manager: HudManager
## The instance to manage the standing captions
@export var caption_manager: CaptionManager

# Variabili interne
var _move_input := Vector2.ZERO
var _pitch: float = 0.0

## The Area3D attached at the base of this camera block, used to intercept when entering/exiting triggers for caption visualization
@onready var _camera_feet: Area3D = $"CameraFeetArea3D"


func _process(delta: float) -> void:

	hud_manager._process(delta)

	caption_manager._process(delta)


func _ready() -> void:

	if hud_manager == null:
		hud_manager = HudManager.new(self)
		
	if caption_manager == null:
		caption_manager = CaptionManager.new(self)

	# Catturiamo il mouse all'avvio
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	if input_reader:
		input_reader.connect("move_event", _on_move_event)
		input_reader.connect("camera_move_event", _on_camera_move_event)
	
	# Ensure to interact with the correct layer
	_camera_feet.collision_layer = LivingConstants.LIVING_3DMODEL_TRIGGER_COLLISION_LAYER
	_camera_feet.collision_mask = LivingConstants.LIVING_3DMODEL_TRIGGER_COLLISION_LAYER
	_camera_feet.body_entered.connect(_on_feet_entered_body)
	_camera_feet.body_exited.connect(_on_feet_exited_body)
	

func _on_feet_entered_body(b: Node3D):
	print("Camera feet entered body ", b)

	# Retrieve the corresponding LivingElement by traversing up the hierarchy.
	var node: Node = b
	while node != null:
		if node is LivingElement:
			print("Camera entered LivingElement: ", node.name)
			# TODO: handle entry
			break
		node = node.get_parent()

	assert ((node == null) or (node is LivingElement))

	if node != null:
		self.caption_manager.create_description_object(node)


func _on_feet_exited_body(b: Node3D):
	print("Camera feet left body ", b)


func _unhandled_input(event: InputEvent) -> void:
	# Gestione visualizzazione mouse
	if event.is_action_pressed("ui_cancel"): # Tasto ESC
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	## Cliccando nella finestra, ri-cattura il mouse
	#if event is InputEventMouseButton and event.pressed:
		#if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
			#Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Cliccando nella finestra con il tasto destro, si ricattura o libera il mouse
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			elif Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _physics_process(delta: float) -> void:
	# 1. Gravità
	if not is_on_floor():
		velocity += get_gravity() * delta

	# 2. Calcolo Direzione
	# Usiamo transform.basis per muoverci relativamente a dove guarda il corpo
	# Nota: In Godot Input Vector solitamente è (X=Side, Y=Forward/Back)
	var direction := Vector3.ZERO
	direction = (transform.basis * Vector3(_move_input.x, 0, _move_input.y)).normalized()
	
	# 3. Applicazione Velocità (con accelerazione/frizione per feeling migliore)
	if direction:
		velocity.x = move_toward(velocity.x, direction.x * move_speed, acceleration * delta * move_speed)
		velocity.z = move_toward(velocity.z, direction.z * move_speed, acceleration * delta * move_speed)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta * move_speed)
		velocity.z = move_toward(velocity.z, 0.0, friction * delta * move_speed)

	move_and_slide()

# --- INPUT SIGNALS ---

func _on_move_event(dir: Vector2) -> void:
	_move_input = dir

func _on_camera_move_event(delta: Vector2) -> void:
	# Se il mouse è visibile (menu/pausa), non ruotare la camera
	if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
		return
		
	# 1. Ruota il CORPO sull'asse Y (Yaw) - Destra/Sinistra
	# Ruotiamo l'intero CharacterBody, così se premi W vai avanti nella nuova direzione
	rotate_y(-deg_to_rad(delta.x * mouse_sensitivity))
	
	# 2. Ruota la CAMERA sull'asse X (Pitch) - Su/Giù
	_pitch -= delta.y * mouse_sensitivity
	_pitch = clamp(_pitch, max_look_down_deg, max_look_up_deg)
	cam.rotation_degrees.x = _pitch


#
#
# LivingElement proximity search

## Scan the scene for a LivingElement that will be considered for HUD / Caption visualization.
## The objects considered in the selection will be taken from the group LivingConstants.LIVING_ELEMENTS_GROUP_NAME
##
## * First, we select the object only if the center of its bounding box is within a scan angle with respect to the camera watching direction.
## * Second, we discard an element if the camera is inside its bounding box
## * Third, from the remaining objects, select the one with minimal distance from the camera (self)
## 
## Returns a 2-element array [element: LivingElement, distance: float]
## If no object is eligible for the selection, the returned array contains [null, -1.0]
func scan_for_closest_visible_element(scan_angle: float) -> Array:
	
	var camera := self

	# Needed camera info
	var camera_floor_position = Vector3(camera.global_position.x, 0.0, camera.global_position.z)
	var camera_front_vector: Vector3 = global_transform.basis * Vector3(0, 0, -1)
	var camera_floor_front_vector := Vector3(camera_front_vector.x, 0.0, camera_front_vector.z)

	#
	# Retrieves the list of all LivingElements registered in the group
	var living_elements_in_scene := camera.get_tree().get_nodes_in_group(LivingConstants.LIVING_ELEMENTS_GROUP_NAME)
	# print("LivingElements in scene: ", living_elements_in_scene.size())

	#
	# Filter out objects outside the field of scan
	
	# Will contain only elements in front of the camera
	var living_elements_in_front = []
	# Distance of all objects
	var distances: Array[float] = []

	for element: LivingElement in living_elements_in_scene:
		assert (element is LivingElement)

		# Get the transformed AABB of the element
		# print("GETTING AABB FOR ", element.name)
		var aabb := LivingUtils.get_node_aabb(element)

		# Skip if the object has not an AABB
		if aabb.get_volume() == 0.0:
			continue

		var transformed_aabb: AABB = element.global_transform * aabb
		var transformed_aabb_center = transformed_aabb.get_center()
		var element_floor_position = Vector3(transformed_aabb_center.x, 0.0, transformed_aabb_center.z)

		var aabb_floor_pos = Vector3(aabb.position.x, 0.0, aabb.position.z)
		var aabb_floor_center = Vector3(aabb.get_center().x, 0.0, aabb.get_center().z)
		var element_floor_radius: float = aabb_floor_pos.distance_to(aabb_floor_center)
		
		# Compute the distance to the AABB center
		var dist := element_floor_position.distance_to(camera_floor_position)
		# Subtract the distance to the bounding circle
		dist -= element_floor_radius

		# The vector between the camera and the object
		#var element_aabb = LivingUtils.get_node_aabb(element)
		var to_element_vect: Vector3 = element_floor_position - camera_floor_position
		# Project on the floor
		assert (to_element_vect.y == 0.0)  # Granted that those vectors were already projected on the floor

		# Skip if the element is outside the scan angle
		var to_element_angle: float = camera_floor_front_vector.angle_to(to_element_vect)
		if to_element_angle > scan_angle:
			continue
			
		# Skip if the element contains the camera
		#if transformed_aabb.has_point(camera_floor_position):
		if dist < 0:
			# print("Camera contained by ", element.name, "\tAABB ", transformed_aabb, "\tcam pos: ", camera_floor_position)
			continue

		living_elements_in_front.append(element)
		distances.append(dist)

	assert (living_elements_in_front.size() == distances.size())

	# print("LivingElements in front: ", living_elements_in_front.size(), living_elements_in_front)


	# Get reference to the closest LivingElement
	var closest_id := LivingUtils.argmin(distances)
	var closest_element = null
	var distance: float = -1.0
	if closest_id != -1:
		closest_element = living_elements_in_front[closest_id]
		distance = distances[closest_id]
	
	#
	# Return best candidate
	return [closest_element, distance]


## Casts a ray from the camera along its view axis (-Z) and returns the closest
## Node3D whose collider (or any of its ancestors) belongs to [param group_name].
## Iteratively excludes non-matching colliders so group members occluded by other
## physics bodies are still reachable.
## Returns [code]null[/code] if no object in the group is hit.
func raycast_closest_in_group(group_name: String, ray_length: float = 1000.0) -> LivingElement:
	var space_state := get_world_3d().direct_space_state
	var ray_origin: Vector3 = cam.global_position
	var ray_target: Vector3 = ray_origin + cam.global_transform.basis * Vector3(0.0, 0.0, -ray_length)

	var exclude: Array[RID] = []

	while true:
		# print("Casting from ", ray_origin, " to ", ray_target)
		var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_target)
		query.exclude = exclude
		query.collide_with_bodies = true
		query.collide_with_areas = false  # We know that the fron fdaces are not areas
		query.collision_mask = LivingConstants.LIVING_3DMODEL_FRONT_FACE_COLLISION_LAYER | LivingConstants.LIVING_3DMODEL_VOLUME_COLLISION_LAYER
		var result: Dictionary = space_state.intersect_ray(query)

		if result.is_empty():
			return null

		# Walk up the scene tree from the collider looking for a group member
		var node: Node = result["collider"]
		while node != null:
			# print("Raycast SCANNING node ", node.name)
			if node.is_in_group(group_name):
				assert(node is LivingElement)
				return node as LivingElement
			node = node.get_parent()

		# This collider is not in the group — skip it and cast again
		exclude.append(result["rid"])

	return null


const FADE_OUT_DURATION_SECS: float = 0.5

func fade_out(fade_color: Color, call_back: Callable) -> void:

	# Creates a 0.1 radius sphere around the "cam" object
	# with inverted normals
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 0.1
	sphere_mesh.height = 0.2
	sphere_mesh.flip_faces = true
	# The mesh instance for the sphere
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = sphere_mesh
	# Set a transparent material with the color set to fade_color and transparency to maximum (invisible)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(fade_color.r, fade_color.g, fade_color.b, 0.0)
	mesh_instance.material_override = material

	# Add teh sphere around the actual Camera3D
	cam.add_child(mesh_instance)

	# Starts a tweening of 3 seconds to interpolate the material transparency from full transparent to full opaue
	# When the tweening ends, invoke the provided call_back and destroy the surrounding sphere
	var tween := create_tween()
	tween.tween_property(material, "albedo_color:a", 1.0, FADE_OUT_DURATION_SECS)
	tween.tween_callback(func():
		call_back.call()
		mesh_instance.queue_free()
	)
