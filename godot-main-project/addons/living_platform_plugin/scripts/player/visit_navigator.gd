@tool
extends Node

## Unified visit navigator.
## Desktop: N/P
## XR: right controller by_button / ax_button

const DEFAULT_VISIT_OFFSET_M := 1.8

@export var living_camera_node: Node3D

# Desktop physical key names (Godot Key enum), e.g. "N", "P".
@export var desktop_next_key: String = "N"
@export var desktop_prev_key: String = "P"

# XR right controller button names.
@export var xr_next_button: StringName = &"by_button"
@export var xr_prev_button: StringName = &"ax_button"

var _using_xr := false
var _right_controller: XRController3D = null
var _living_camera: LivingCamera = null


var _cached_env_item_id: int = -1
var _cached_nodes_by_item_id: Dictionary = {} # int -> LivingObject
## False until the first N/P of the current environment: first Next goes to
## index 0 instead of skipping it with +1.
var _visit_tour_started := false
var _visit_tour_env_id: int = -1

func _ready() -> void:
	_living_camera = living_camera_node as LivingCamera
	if _living_camera == null:
		push_warning("VisitNavigator: living_camera_node is not a LivingCamera.")
		set_process(false)
		return

	# Attendi che LivingCamera completi _ready() (i nodi figli eseguono _ready prima del genitore)
	if not _living_camera.is_node_ready():
		await _living_camera.ready

	var raw_using_xr := _living_camera.get("using_xr")
	_using_xr = raw_using_xr if typeof(raw_using_xr) == TYPE_BOOL else false
	if _using_xr:
		_find_and_connect_right_controller()
		set_process(true)
	else:
		set_process(false)


func _find_and_connect_right_controller() -> void:
	if not is_instance_valid(_living_camera):
		return
	var controller := _living_camera.find_child("XRController3D_right", true, false) as XRController3D
	if controller != null and controller != _right_controller:
		_disconnect_controller()
		_right_controller = controller
		_connect_controller()


func _connect_controller() -> void:
	if not _right_controller:
		return
	if not _right_controller.button_pressed.is_connected(_on_controller_button_pressed):
		_right_controller.button_pressed.connect(_on_controller_button_pressed)


func _disconnect_controller() -> void:
	if not _right_controller:
		return
	if _right_controller.button_pressed.is_connected(_on_controller_button_pressed):
		_right_controller.button_pressed.disconnect(_on_controller_button_pressed)


func _exit_tree() -> void:
	_disconnect_controller()


func _on_controller_button_pressed(button_name: StringName) -> void:
	if button_name == xr_next_button:
		_step_visit(1)
	elif button_name == xr_prev_button:
		_step_visit(-1)


func _process(_delta: float) -> void:
	if not _using_xr:
		return

	# Se il controller non era ancora pronto o è stato re-istanziato
	if not is_instance_valid(_right_controller):
		_find_and_connect_right_controller()


func _unhandled_input(event: InputEvent) -> void:
	if event is not InputEventKey:
		return

	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	if key_event.keycode == _string_to_key(desktop_next_key):
		_step_visit(1)
	elif key_event.keycode == _string_to_key(desktop_prev_key):
		_step_visit(-1)


func _string_to_key(k: String) -> Key:
	var upper := k.strip_edges().to_upper()
	match upper:
		"N":
			return KEY_N
		"P":
			return KEY_P
		_:
			return KEY_N


func _step_visit(delta: int) -> void:
	var env := LivingSceneManager.get_current_scene()
	if env == null:
		return

	var path := _get_visit_path(env)
	if path.is_empty():
		return

	var current_index := LivingSessionManager.get_tour_index(env.item_id)
	var path_size := path.size()
	var current_mod_index := current_index % path_size
	var target_index: int

	if env.item_id != _visit_tour_env_id:
		_visit_tour_started = false
		_visit_tour_env_id = env.item_id

	if not _visit_tour_started:
		# First Next lands on stop 0; first Prev lands on the last stop.
		target_index = 0 if delta > 0 else path_size - 1
		_visit_tour_started = true
	else:
		var raw_index := current_mod_index + delta
		target_index = raw_index % path_size
		if target_index < 0:
			target_index += path_size
		if target_index == current_mod_index:
			return

	LivingSessionManager.set_tour_index(env.item_id, target_index)

	_ensure_cache(env)
	var target_item_id := path[target_index]
	var target_node := _cached_nodes_by_item_id.get(target_item_id, null)
	if target_node == null:
		return

	var visit_transform := _get_visit_transform(target_node)

	_living_camera.teleport_player_to(visit_transform)


func _ensure_cache(env: LivingEnvironment) -> void:
	if env == null:
		return
	if env.item_id == _cached_env_item_id:
		return

	_cached_env_item_id = env.item_id
	_cached_nodes_by_item_id.clear()

	var nodes := env.find_children("*", "LivingObject", true, false)
	for n in nodes:
		if n == null:
			continue
		var obj := n as LivingObject
		var id: int = obj.item_id
		if obj is LivingTargetObject:
			id = (obj as LivingTargetObject).get_effective_item_id()
		if id <= 0:
			continue
		# Scene targets always own their bound Area/Env id for teleport.
		if obj is LivingTargetObject and (obj as LivingTargetObject).is_scene_target():
			_cached_nodes_by_item_id[id] = obj
		elif not _cached_nodes_by_item_id.has(id):
			_cached_nodes_by_item_id[id] = obj


func _get_visit_path(env: LivingEnvironment) -> Array[int]:
	if env.visit_path.size() > 0:
		return env.visit_path

	var ids: Array[int] = []
	var seen: Dictionary = {}
	var nodes := env.find_children("*", "LivingObject", true, false)
	for n in nodes:
		if n == null:
			continue
		var obj := n as LivingObject
		var id: int = obj.item_id
		if obj is LivingTargetObject:
			id = (obj as LivingTargetObject).get_effective_item_id()
		if id > 0 and not seen.has(id):
			ids.append(id)
			seen[id] = true
	return ids


func _get_visit_transform(node: Node3D) -> Transform3D:
	if node.has_method("get_visit_transform"):
		return node.get_visit_transform()
	return _compute_generic_visit_transform(node)


func _compute_generic_visit_transform(node: Node3D) -> Transform3D:
	var visit_pos_world := node.global_transform.origin + node.global_transform.basis * Vector3(0.0, 0.0, DEFAULT_VISIT_OFFSET_M)

	var to_obj := node.global_transform.origin - visit_pos_world
	to_obj.y = 0.0

	var dir := to_obj
	if dir.length_squared() < 0.0001:
		dir = node.global_transform.basis * Vector3(0.0, 0.0, 1.0)
		dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = Vector3.FORWARD
		dir.y = 0.0

	dir = dir.normalized()
	var yaw_base := atan2(dir.x, dir.z)
	var basis := Basis(Vector3.UP, yaw_base)
	return Transform3D(basis, visit_pos_world)
