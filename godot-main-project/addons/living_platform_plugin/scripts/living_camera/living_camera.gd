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

func _ready() -> void:
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
