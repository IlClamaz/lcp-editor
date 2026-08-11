extends CharacterBody3D

class_name PlayerFPS

# Riferimenti ai nodi e risorse
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

# Input Reader variables
const A_MOVE_LEFT        := "ui_left"
const A_MOVE_RIGHT       := "ui_right"
const A_MOVE_UP          := "ui_up"
const A_MOVE_DOWN        := "ui_down"
var _gameplay_enabled := true
var _look_axis := Vector2.ZERO
var _gravity_enabled := true
var _movement_enabled := true
var _look_enabled := true


func _ready() -> void:
	# Catturiamo il mouse all'avvio
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func enable_gameplay_input() -> void:
	_gameplay_enabled = true
	_movement_enabled = true
	_look_enabled = true


func disable_all_input() -> void:
	_gameplay_enabled = false
	_movement_enabled = false
	_look_enabled = false
	_move_input = Vector2.ZERO
	_look_axis = Vector2.ZERO


func set_gravity_enabled(enabled: bool) -> void:
	_gravity_enabled = enabled
	if not _gravity_enabled and velocity.y < 0.0:
		velocity.y = 0.0


func set_movement_enabled(enabled: bool) -> void:
	_movement_enabled = enabled
	if not _movement_enabled:
		_move_input = Vector2.ZERO


func set_look_enabled(enabled: bool) -> void:
	_look_enabled = enabled
	if not _look_enabled:
		_look_axis = Vector2.ZERO


func set_view_pitch_degrees(pitch_degrees: float) -> void:
	_pitch = clamp(pitch_degrees, max_look_down_deg, max_look_up_deg)
	cam.rotation_degrees.x = _pitch


## Align body yaw and camera pitch so the view looks along `world_direction`.
## The visit-point arrow points along local +Z; pass `target.basis.z` from `get_visit_transform()`.
func set_view_to_direction(world_direction: Vector3) -> void:
	if world_direction.length_squared() < 0.0001:
		return

	var look_dir := world_direction.normalized()
	global_rotation.y = atan2(-look_dir.x, -look_dir.z)

	var horiz_len := Vector2(look_dir.x, look_dir.z).length()
	var pitch_deg := rad_to_deg(atan2(-look_dir.y, horiz_len))
	set_view_pitch_degrees(pitch_deg)


func _process(_dt: float) -> void:
	# Logica Desktop
	if _movement_enabled and _gameplay_enabled:
		var move := Input.get_vector(A_MOVE_LEFT, A_MOVE_RIGHT, A_MOVE_UP, A_MOVE_DOWN)
		_on_move_event(move)
	elif _move_input != Vector2.ZERO:
		_move_input = Vector2.ZERO

	if _look_axis != Vector2.ZERO:
		_on_camera_move_event(_look_axis)
		_look_axis = Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if not _look_enabled:
		return

	# Camera (mouse)
	if event is InputEventMouseMotion:
		_on_camera_move_event(event.relative)


func _physics_process(delta: float) -> void:
	# 1. Gravità
	if _gravity_enabled and not is_on_floor():
		velocity += get_gravity() * delta

	# 2. Calcolo Direzione
	# Usiamo il basis globale per includere eventuali rotazioni del parent all'avvio.
	# Nota: In Godot Input Vector solitamente è (X=Side, Y=Forward/Back)
	var direction := Vector3.ZERO
	direction = global_transform.basis * Vector3(_move_input.x, 0.0, _move_input.y)
	direction.y = 0.0
	direction = direction.normalized()
	
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
