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
@export var xr_origin_height_offset: float = 0.0
@export var xr_left_hand_offset: Vector3 = Vector3.ZERO
@export var xr_right_hand_offset: Vector3 = Vector3.ZERO

## The instance to manage the floating HUDs
@export var hud_manager: HudManager
## The instance to manage the standing captions
@export var long_caption_manager: CaptionManager

# Variabili interne
var _move_input := Vector2.ZERO
var _pitch: float = 0.0
var _xr_interface: XRInterface

#
# Trigger collision memora and management
## The Area3D attached at the base of this camera block, used to intercept when entering/exiting triggers for caption visualization
@onready var _camera_feet: Area3D = $"CameraFeetArea3D"
@onready var _xr_origin: Node3D = get_node_or_null("XROrigin3D")
@onready var _xr_camera: Node3D = get_node_or_null("XROrigin3D/XRCamera3D")
@onready var _xr_left_controller: Node3D = get_node_or_null("XROrigin3D/XRController3D_left")
@onready var _xr_right_controller: Node3D = get_node_or_null("XROrigin3D/XRController3D_right")
@onready var _xr_left_hand: Node3D = get_node_or_null("XROrigin3D/XRController3D_left/LeftHand")
@onready var _xr_right_hand: Node3D = get_node_or_null("XROrigin3D/XRController3D_right/RightHand")


func get_default_eye_height() -> float:
	# TODO: should be taken from the camera sub-scene
	return 1.7

func _process(delta: float) -> void:

	hud_manager._process(delta)
	long_caption_manager._process(delta)


func _ready() -> void:

	if hud_manager == null:
		hud_manager = HudManager.new(self)
		hud_manager.hud_clicked.connect(self._on_hud_clicked)
		
	if long_caption_manager == null:
		long_caption_manager = CaptionManager.new(self)

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

	if _using_xr():
		_reset_xr_camera_and_hands_to_origin()
		call_deferred("_reset_xr_camera_and_hands_to_origin")


func _using_xr() -> bool:
	if not _xr_interface:
		_xr_interface = XRServer.find_interface("OpenXR")
	return _xr_interface and _xr_interface.is_initialized() and get_viewport().use_xr


func _reset_xr_camera_and_hands_to_origin() -> void:
	if _xr_origin:
		_xr_origin.position = Vector3(0.0, xr_origin_height_offset, 0.0)
		_xr_origin.rotation = Vector3.ZERO
	if _xr_camera:
		_xr_camera.position = Vector3.ZERO
		_xr_camera.rotation = Vector3.ZERO
	elif cam:
		cam.position = Vector3.ZERO
		cam.rotation = Vector3.ZERO
	if _xr_left_controller:
		_xr_left_controller.position = Vector3.ZERO
		_xr_left_controller.rotation = Vector3.ZERO
	if _xr_right_controller:
		_xr_right_controller.position = Vector3.ZERO
		_xr_right_controller.rotation = Vector3.ZERO
	if _xr_left_hand:
		_xr_left_hand.position = xr_left_hand_offset
		_xr_left_hand.rotation = Vector3.ZERO
	if _xr_right_hand:
		_xr_right_hand.position = xr_right_hand_offset
		_xr_right_hand.rotation = Vector3.ZERO
	

#
# STEPPING ON TRIGGERS MANAGEMENT
#

## Bidirectional mapping between LivingElement/LivingArea instances and their collision body nodes.
## Maps LivingElement/LivingArea → collision Node3D (the physics body that triggered the feet area).
var _feet_collision_item_to_node_dict: Dictionary[LivingItem, Node3D] = {}
## Maps collision Node3D → LivingElement/LivingArea (reverse lookup).
var _feet_collision_node_to_item_dict: Dictionary[Node3D, LivingItem] = {}


func _on_feet_entered_body(b: Node3D):

	print("Camera feet entered body ", b)

	# Retrieve the corresponding LivingElement by traversing up the hierarchy.
	var node: Node3D = b
	while node != null:
		if node is LivingElement:
			print("Camera entered LivingElement: ", node.name)
			break
		elif node is LivingArea:
			print("Camera entered LivingArea: ", node.name)
			break

		node = node.get_parent()

	assert ((node == null) or (node is LivingElement) or (node is LivingArea))
	var item: LivingItem = node as LivingItem

	_feet_collision_item_to_node_dict[item] = b
	_feet_collision_node_to_item_dict[b] = item

	assert (_feet_collision_item_to_node_dict.size() == _feet_collision_node_to_item_dict.size())

	# if node != null:
	# 	self.long_caption_manager.create_description_object(node)

	# print(_feet_collision_item_to_node_dict)


func _on_feet_exited_body(b: Node3D):
	print("Camera feet left body ", b)

	if b in _feet_collision_node_to_item_dict:
		var n: LivingItem = _feet_collision_node_to_item_dict[b]
		_feet_collision_node_to_item_dict.erase(b)
		_feet_collision_item_to_node_dict.erase(n)

	assert (_feet_collision_item_to_node_dict.size() == _feet_collision_node_to_item_dict.size())

	# print(_feet_collision_item_to_node_dict)


## Returns the list of LivingItems on which the camera is currently stepping.
func get_stepping_on_items() -> Array[LivingItem]:

	return _feet_collision_item_to_node_dict.keys()


#
#
#

func _on_hud_clicked(item: LivingItem):

	self.long_caption_manager.create_description_object(item)


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



## Casts a ray from the camera along its view axis (-Z) and returns the closest
## LivingItem whose collider (or any of its ancestors) belongs to [param group_name].
## Iteratively excludes non-matching colliders so group members occluded by other
## physics bodies are still reachable.
## Returns [code]null[/code] if no object in the group is hit.
func raycast_closest_in_group(group_name: String, ray_length: float = 1000.0) -> LivingItem:
	var space_state := get_world_3d().direct_space_state
	var ray_origin: Vector3 = cam.global_position
	var ray_target: Vector3 = ray_origin + cam.global_transform.basis * Vector3(0.0, 0.0, -ray_length)

	var exclude: Array[RID] = []

	while true:
		# print("Casting from ", ray_origin, " to ", ray_target)
		var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_target)
		query.exclude = exclude
		query.collide_with_bodies = true
		query.collide_with_areas = false  # We know that the fron faces are not areas
		query.collision_mask = LivingConstants.LIVING_3DMODEL_FRONT_FACE_COLLISION_LAYER | LivingConstants.LIVING_3DMODEL_VOLUME_COLLISION_LAYER
		var result: Dictionary = space_state.intersect_ray(query)

		if result.is_empty():
			return null

		# Walk up the scene tree from the collider looking for a group member
		var node: Node = result["collider"]
		while node != null:
			# print("Raycast SCANNING node ", node.name)
			if node.is_in_group(group_name):
				assert(node is LivingItem)
				return node as LivingItem
			node = node.get_parent()

		# This collider is not in the group — skip it and cast again
		exclude.append(result["rid"])

	return null


## Casts a ray from the camera along its view axis (-Z) and returns the list of all
## LivingItems whose collider (or any of its ancestors) belongs to [param group_name].
## Iteratively excludes non-matching colliders so group members occluded by other
## physics bodies are still reachable.
## Returned elements are sorted from the closest to the farhest.
## Returns an empty string if no object in the group is hit.
func raycast_all_in_group(group_name: String, ray_length: float = 1000.0) -> Array[LivingItem]:
	var space_state := get_world_3d().direct_space_state
	var ray_origin: Vector3 = cam.global_position
	var ray_target: Vector3 = ray_origin + cam.global_transform.basis * Vector3(0.0, 0.0, -ray_length)

	var exclude: Array[RID] = []
	var found: Array[LivingItem] = []
	var seen_items: Dictionary = {}

	while true:
		var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_target)
		query.exclude = exclude
		query.collide_with_bodies = true
		query.collide_with_areas = false
		query.collision_mask = LivingConstants.LIVING_3DMODEL_FRONT_FACE_COLLISION_LAYER | LivingConstants.LIVING_3DMODEL_VOLUME_COLLISION_LAYER
		var result: Dictionary = space_state.intersect_ray(query)

		if result.is_empty():
			break

		exclude.append(result["rid"])

		var node: Node = result["collider"]
		while node != null:
			if node.is_in_group(group_name):
				assert(node is LivingItem)
				if not seen_items.has(node):
					found.append(node as LivingItem)
					seen_items[node] = true
				break
			node = node.get_parent()

	return found


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
