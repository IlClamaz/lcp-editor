extends Node3D

class_name LivingCamera

@export var player_fps_scene: PackedScene
@export var player_xr_scene: PackedScene
@export var movement_enabled: bool = true
@export var gravity_enabled: bool = true

var _player_instance: Node3D
var _using_xr_last_state: bool = false
var _camera: Node3D
var using_xr: bool

const FADE_COLOR := Color.BLACK
const FADE_OUT_DURATION_SECS: float = 0.45
const FADE_HOLD_DURATION_SECS: float = 0.12
const FADE_IN_DURATION_SECS: float = 0.45

var _fade_mesh: MeshInstance3D = null
var _fade_material: StandardMaterial3D = null
var _fade_tween: Tween = null
var _fade_generation: int = 0


func _ready() -> void:
	using_xr = _using_xr()
	_spawn_player(using_xr)
	_apply_xr_player_world_scale()
	set_process(true)
	if using_xr:
		_camera = self.find_child("XRCamera3D", true, false)
	else:
		_camera = self.find_child("Camera3D", true, false)


func get_real_camera_node() -> Node3D:
	return self._camera


func set_player_movement_enabled(enabled: bool) -> void:
	movement_enabled = enabled
	_apply_player_runtime_flags()


func set_player_gravity_enabled(enabled: bool) -> void:
	gravity_enabled = enabled
	_apply_player_runtime_flags()


func set_player_motion_and_gravity_enabled(enabled: bool) -> void:
	movement_enabled = enabled
	gravity_enabled = enabled
	_apply_player_runtime_flags()


func is_player_movement_enabled() -> bool:
	return movement_enabled


func is_player_gravity_enabled() -> bool:
	return gravity_enabled


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
	_apply_player_runtime_flags()


func _apply_xr_player_world_scale() -> void:
	if not using_xr:
		return
	if not is_instance_valid(_player_instance):
		return
	if "world_scale" in _player_instance:
		_player_instance.set("world_scale", 1.0)


func _apply_player_runtime_flags() -> void:
	if not is_instance_valid(_player_instance):
		return

	if using_xr:
		_apply_xr_movement_state(movement_enabled)
		_apply_xr_gravity_state(gravity_enabled)
	else:
		_apply_fps_movement_state(movement_enabled)
		_apply_fps_gravity_state(gravity_enabled)


func _apply_fps_movement_state(enabled: bool) -> void:
	var fps_player := _player_instance as PlayerFPS
	if not fps_player:
		return

	if enabled:
		fps_player.set_movement_enabled(true)
	else:
		fps_player.set_movement_enabled(false)
		fps_player.velocity = Vector3.ZERO


func _apply_fps_gravity_state(enabled: bool) -> void:
	var fps_player := _player_instance as PlayerFPS
	if not fps_player:
		return
	fps_player.set_gravity_enabled(enabled)
	if not enabled and fps_player.velocity.y < 0.0:
		fps_player.velocity.y = 0.0


func _apply_xr_movement_state(enabled: bool) -> void:
	_set_group_nodes_enabled("movement_providers", enabled)
	_set_nodes_enabled_by_class("XRToolsFunctionTeleport", enabled)
	_set_xr_player_body_enabled(enabled and gravity_enabled)


func _apply_xr_gravity_state(enabled: bool) -> void:
	# XRToolsPlayerBody non espone un toggle separato per sola gravità:
	# per congelare la caduta disabilitiamo il body.
	_set_xr_player_body_enabled(enabled and movement_enabled)


func _set_group_nodes_enabled(group_name: StringName, enabled: bool) -> void:
	var nodes: Array[Node] = _player_instance.find_children("*", "Node", true, false)
	for node in nodes:
		if not node.is_in_group(group_name):
			continue
		if "enabled" in node:
			node.set("enabled", enabled)


func _set_nodes_enabled_by_class(name: String, enabled: bool) -> void:
	var nodes: Array[Node] = _player_instance.find_children("*", name, true, false)
	for node in nodes:
		if "enabled" in node:
			node.set("enabled", enabled)


func _set_xr_player_body_enabled(enabled: bool) -> void:
	var player_body := _player_instance.find_child("PlayerBody", true, false)
	if not player_body:
		return
	if "enabled" in player_body:
		player_body.set("enabled", enabled)
	if "velocity" in player_body and not enabled:
		player_body.set("velocity", Vector3.ZERO)

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

## Fade to opaque, run `call_back`, then fade back to clear.
func fade_out(fade_color: Color, call_back: Callable) -> void:
	fade_transition(fade_color, FADE_OUT_DURATION_SECS, FADE_HOLD_DURATION_SECS, FADE_IN_DURATION_SECS, call_back)


## Full transition: fade out -> hidden action -> hold -> fade in.
func fade_transition(fade_color: Color, fade_out_time: float, hold_time: float, fade_in_time: float, hidden_action: Callable) -> void:
	if not is_instance_valid(_camera):
		if hidden_action.is_valid():
			hidden_action.call()
		return

	_fade_generation += 1
	var gen := _fade_generation
	var material := _ensure_fade_overlay(fade_color)

	if _fade_tween != null and is_instance_valid(_fade_tween):
		_fade_tween.kill()

	_fade_tween = create_tween()
	_fade_tween.tween_property(material, "albedo_color:a", 1.0, maxf(fade_out_time, 0.0))
	await _fade_tween.finished
	if gen != _fade_generation:
		return

	if hidden_action.is_valid():
		hidden_action.call()

	if gen != _fade_generation or not is_inside_tree() or not is_instance_valid(material):
		return

	if hold_time > 0.0:
		await get_tree().create_timer(hold_time).timeout
		if gen != _fade_generation or not is_inside_tree() or not is_instance_valid(material):
			return

	_fade_tween = create_tween()
	_fade_tween.tween_property(material, "albedo_color:a", 0.0, maxf(fade_in_time, 0.0))
	await _fade_tween.finished
	if gen != _fade_generation:
		return

	_clear_fade_overlay()


func _ensure_fade_overlay(fade_color: Color) -> StandardMaterial3D:
	var rgb := Color(fade_color.r, fade_color.g, fade_color.b, 0.0)
	if _fade_mesh != null and is_instance_valid(_fade_mesh) and _fade_material != null:
		var current_a := _fade_material.albedo_color.a
		_fade_material.albedo_color = Color(rgb.r, rgb.g, rgb.b, current_a)
		return _fade_material

	_clear_fade_overlay()

	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 0.35
	sphere_mesh.height = 0.7
	sphere_mesh.radial_segments = 32
	sphere_mesh.rings = 16
	sphere_mesh.flip_faces = true

	_fade_material = StandardMaterial3D.new()
	_fade_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fade_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fade_material.albedo_color = rgb
	_fade_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fade_material.no_depth_test = true
	_fade_material.render_priority = 127
	_fade_material.disable_receive_shadows = true
	_fade_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_fade_material.disable_fog = true

	_fade_mesh = MeshInstance3D.new()
	_fade_mesh.name = "LivingCameraFade"
	_fade_mesh.mesh = sphere_mesh
	_fade_mesh.material_override = _fade_material
	_fade_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fade_mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_fade_mesh.extra_cull_margin = 16384.0
	_camera.add_child(_fade_mesh)
	return _fade_material


func _clear_fade_overlay() -> void:
	if _fade_tween != null and is_instance_valid(_fade_tween):
		_fade_tween.kill()
	_fade_tween = null
	if _fade_mesh != null and is_instance_valid(_fade_mesh):
		_fade_mesh.queue_free()
	_fade_mesh = null
	_fade_material = null


func teleport_player_to(target: Transform3D) -> void:
	if not is_instance_valid(_player_instance):
		push_warning("LivingCamera.teleport_player_to: player instance is not valid.")
		return

	var do_teleport := func():
		if using_xr:
			_teleport_xr_player(target)
		else:
			_teleport_fps_player(target)

	if _camera == null:
		do_teleport.call()
		return
	fade_out(FADE_COLOR, do_teleport)


func _teleport_fps_player(target: Transform3D) -> void:
	var fps_player := _player_instance as PlayerFPS
	if fps_player == null:
		push_warning("LivingCamera.teleport_player_to: FPS player not found.")
		return

	var adjusted_target := target
	adjusted_target.origin.y = fps_player.global_position.y

	fps_player.global_position = adjusted_target.origin
	fps_player.velocity = Vector3.ZERO
	# Visit-point arrow points along local +Z; camera looks along -local Z.
	fps_player.set_view_to_direction(adjusted_target.basis.z)


func _teleport_xr_player(target: Transform3D) -> void:
	var player_body := _player_instance.find_child("PlayerBody", true, false)
	if player_body == null:
		push_warning("LivingCamera.teleport_player_to: XR PlayerBody not found.")
		return
	if not player_body.has_method("teleport"):
		push_warning("LivingCamera.teleport_player_to: XR PlayerBody has no teleport method.")
		return

	var look_dir := target.basis.z
	var flat := Vector3(look_dir.x, 0.0, look_dir.z)
	var basis := target.basis
	if flat.length_squared() > 0.0001:
		flat = flat.normalized()
		var yaw := atan2(-flat.x, -flat.z)
		basis = Basis(Vector3.UP, yaw)

	var adjusted_target := Transform3D(basis, target.origin)
	adjusted_target.origin.y = player_body.global_transform.origin.y
	player_body.teleport(adjusted_target)
