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

# Variabili interne
var _move_input := Vector2.ZERO
var _pitch: float = 0.0


# The instance to manage the floating HUDs
@export var hud_manager: HudManager

# The instance to manage the standing captions
@export var caption_manager: CaptionManager


func _process(delta: float) -> void:

	hud_manager._process(delta)

	caption_manager._process(delta)


func _ready() -> void:
	# TODO --  remove?
	add_to_group("living_camera")

	if hud_manager == null:
		hud_manager = HudManager.new(self)
		
	if caption_manager == null:
		caption_manager = CaptionManager.new(self)

	# Catturiamo il mouse all'avvio
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	if input_reader:
		input_reader.connect("move_event", _on_move_event)
		input_reader.connect("camera_move_event", _on_camera_move_event)

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
## First we select objects by distance from the camera (self)
## TODO Second, we select the object only if it is in the field of view of teh camera
##
## Returns a 2-element array [element: LivingElement, distance: float]
## If no object is eligible for the selection, the returned array contains [null, -1.0]
func scan_for_closest_visible_element() -> Array:
	
	var camera := self
	
		# SCAN ALL OBJECTS IN THE SCENE AND FIND THE CLOSEST ONE
	var living_elements_in_scene := camera.get_tree().get_nodes_in_group(LivingConstants.LIVING_ELEMENTS_GROUP_NAME)

	var distances: Array[float] = []

	# print("LivingElements in scene: ", living_elements_in_scene.size())
	for element in living_elements_in_scene:
		# By construvtion, this must be a LivingElement
		assert (element is LivingElement)
		# print(element.name)
		
		var projected_global_position = Vector3(element.global_position.x, 0.0, element.global_position.z)
		var projected_cam_position = Vector3(camera.global_position.x, 0.0, camera.global_position.z)
		var d := projected_global_position.distance_to(projected_cam_position)

		distances.append(d)
	
	assert (living_elements_in_scene.size() == distances.size())
	
	# Get reference to the closest LivingElement
	var closest_id := LivingUtils.argmin(distances)
	var closest_element = null
	var distance: float = -1.0
	if closest_id != -1:
		closest_element = living_elements_in_scene[closest_id]
		distance = distances[closest_id]
	
	return [closest_element, distance]
