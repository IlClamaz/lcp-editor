extends Node3D

class_name LivingCamera

@export var player_fps_scene: PackedScene
@export var player_xr_scene: PackedScene

var _player_instance: Node3D
var _using_xr_last_state: bool = false

func _ready() -> void:
	_using_xr_last_state = _using_xr()
	_spawn_player(_using_xr_last_state)
	set_process(true)

# If the user connects the XR headset while the game is running, or disconnects it, 
# we want to switch between the FPS and XR player scenes accordingly.
func _process(delta: float) -> void:
	var xr_active := _using_xr()
	if xr_active != _using_xr_last_state:
		_spawn_player(xr_active)
		_using_xr_last_state = xr_active

# Choose which player scene to spawn based on XR state, and set it up
func _spawn_player(use_xr: bool) -> void:
	if _player_instance:
		_player_instance.queue_free()
		_player_instance = null

	var scene: PackedScene = player_xr_scene if use_xr else player_fps_scene
	if scene == null:
		push_warning("Missing player scene for %s" % ("XR" if use_xr else "FPS"))
		return

	_player_instance = scene.instantiate() as Node3D
	if not _player_instance:
		push_warning("Failed to instantiate player scene")
		return

	add_child(_player_instance)

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

func _using_xr() -> bool:
	var interface = XRServer.find_interface("OpenXR")

	if interface and interface.initialize():
		get_viewport().use_xr = true
		return true
	else:
		get_viewport().use_xr = false
		return false
