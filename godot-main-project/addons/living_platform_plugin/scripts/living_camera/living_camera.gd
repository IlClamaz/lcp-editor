extends Node3D

class_name LivingCamera

@export var player_fps_scene: PackedScene
@export var player_xr_scene: PackedScene

var _player_instance: Node3D
var _using_xr_last_state: bool = false
var _camera: Node3D
var using_xr: bool

const FADE_OUT_DURATION_SECS: float = 0.5


func _ready() -> void:
	using_xr = _using_xr()
	_spawn_player(using_xr)
	set_process(true)
	if using_xr:
		_camera = self.find_child("XRCamera3D", true, false)
	else:
		_camera = self.find_child("Camera3D", true, false)


func get_real_camera_node() -> Node3D:
	return self._camera


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

	# Cliccando nella finestra con il tasto destro, si ricattura o libera il mouse
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			elif Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _using_xr() -> bool:
	var interface: XRInterface = XRServer.find_interface("OpenXR")

	if interface and interface.initialize():
		get_viewport().use_xr = true
		return true
	else:
		get_viewport().use_xr = false
		return false

func fade_out(fade_color: Color, call_back: Callable) -> void:
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 0.5
	sphere_mesh.height = 0.5
	sphere_mesh.flip_faces = true

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = sphere_mesh

	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(fade_color.r, fade_color.g, fade_color.b, 0.0)
	mesh_instance.material_override = material

	_camera.add_child(mesh_instance)

	var tween := create_tween()
	tween.tween_property(material, "albedo_color:a", 1.0, FADE_OUT_DURATION_SECS)
	tween.tween_callback(func():
		call_back.call()
		mesh_instance.queue_free()
	)

## Esegue una transizione completa Fade Out -> Azione -> Hold -> Fade In
func fade_transition(fade_color: Color, fade_out_time: float, hold_time: float, fade_in_time: float, hidden_action: Callable) -> void:
	if not _camera:
		hidden_action.call()
		return

	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 0.5
	sphere_mesh.height = 0.5
	sphere_mesh.flip_faces = true

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = sphere_mesh

	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(fade_color.r, fade_color.g, fade_color.b, 0.0)
	material.no_depth_test = true
	material.render_priority = 100
	mesh_instance.material_override = material

	_camera.add_child(mesh_instance)

	# 1. Fade Out
	var tween := create_tween()
	tween.tween_property(material, "albedo_color:a", 1.0, fade_out_time)
	await tween.finished

	# 2. Eseguiamo una funzione mentre lo schermo è nero
	hidden_action.call()

	# 3. Pausa nel buio (Hold)
	if hold_time > 0:
		await get_tree().create_timer(hold_time).timeout

	# 4. Fade In
	tween = create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, fade_in_time)
	await tween.finished

	# 5. Pulizia
	mesh_instance.queue_free()
