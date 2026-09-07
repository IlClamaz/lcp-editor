extends Node3D

@export var enabled: bool = true
@export var click_action: StringName = &"select_button"
@export var ray_length: float = 12.0
@export_flags_3d_physics var collision_mask: int = 2147483647
@export var laser_thickness: float = 0.004
@export var laser_idle_color: Color = Color(0.85, 0.85, 0.85, 0.85)
@export var laser_hit_color: Color = Color(0.2, 0.95, 1.0, 0.95)

@onready var _ray_cast: RayCast3D = $RayCast3D
@onready var _laser: MeshInstance3D = $Laser

var _controller: XRController3D
var _laser_mesh: BoxMesh
var _laser_material: StandardMaterial3D
var _last_hit: Dictionary = {}

const _IGNORED_NAME_FRAGMENTS: PackedStringArray = ["epd target"]


func _ready() -> void:
	_controller = _find_controller()
	_connect_controller_signals()
	_setup_laser()
	_update_ray_properties()
	_update_laser(ray_length, false)


func _enter_tree() -> void:
	if _controller == null:
		_controller = _find_controller()
	_connect_controller_signals()


func _exit_tree() -> void:
	_disconnect_controller_signals()


func _connect_controller_signals() -> void:
	if not _controller:
		return
	if not _controller.button_pressed.is_connected(_on_button_pressed):
		_controller.button_pressed.connect(_on_button_pressed)
	if not _controller.button_released.is_connected(_on_button_released):
		_controller.button_released.connect(_on_button_released)


func _disconnect_controller_signals() -> void:
	if not _controller:
		return
	if _controller.button_pressed.is_connected(_on_button_pressed):
		_controller.button_pressed.disconnect(_on_button_pressed)
	if _controller.button_released.is_connected(_on_button_released):
		_controller.button_released.disconnect(_on_button_released)


func _process(_delta: float) -> void:
	if not enabled:
		_laser.visible = false
		_last_hit = {}
		return

	_update_ray_properties()
	_last_hit = _get_first_valid_hit()

	if not _last_hit.is_empty():
		var hit_point: Vector3 = _last_hit["position"]
		var hit_distance := global_position.distance_to(hit_point)
		_update_laser(max(hit_distance, 0.02), true)
	else:
		_update_laser(ray_length, false)


func _find_controller() -> XRController3D:
	var node: Node = self
	while node != null:
		if node is XRController3D:
			return node as XRController3D
		node = node.get_parent()
	return null


func _setup_laser() -> void:
	_laser_mesh = _laser.mesh as BoxMesh
	if _laser_mesh == null:
		_laser_mesh = BoxMesh.new()
		_laser.mesh = _laser_mesh

	_laser_material = StandardMaterial3D.new()
	_laser_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_laser_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_laser_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_laser.material_override = _laser_material


func _update_ray_properties() -> void:
	_ray_cast.target_position = Vector3(0.0, 0.0, -ray_length)
	_ray_cast.collision_mask = collision_mask
	_ray_cast.collide_with_bodies = true
	_ray_cast.collide_with_areas = true


func _update_laser(length: float, hit: bool) -> void:
	_laser.visible = enabled
	_laser_mesh.size = Vector3(laser_thickness, laser_thickness, length)
	_laser.position = Vector3(0.0, 0.0, -length * 0.5)
	_laser_material.albedo_color = laser_hit_color if hit else laser_idle_color


func _on_button_pressed(button_name: StringName) -> void:
	if not enabled:
		return
	if button_name != click_action:
		return
	_emit_mouse_button_event(true)


func _on_button_released(button_name: StringName) -> void:
	if not enabled:
		return
	if button_name != click_action:
		return
	_emit_mouse_button_event(false)


func _emit_mouse_button_event(pressed: bool) -> void:
	if _last_hit.is_empty():
		return

	var collider := _last_hit.get("collider") as Node
	if collider == null:
		return

	var point: Vector3 = _last_hit.get("position", Vector3.ZERO)
	var normal: Vector3 = _last_hit.get("normal", Vector3.UP)
	var shape = _last_hit.get("shape", -1)

	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0

	var target := _resolve_input_event_target(collider)
	if target != null:
		target.call("_input_event", null, event, point, normal, shape)
		return

	if collider.has_signal("input_event"):
		collider.emit_signal("input_event", null, event, point, normal, shape)


func _resolve_input_event_target(start_node: Node) -> Node:
	var node: Node = start_node
	while node != null:
		if node.has_method("_input_event"):
			return node
		node = node.get_parent()
	return null


func _get_first_valid_hit() -> Dictionary:
	var space_state := get_world_3d().direct_space_state
	var from := _ray_cast.global_position
	var to := from + (-_ray_cast.global_transform.basis.z * ray_length)
	var excludes: Array[RID] = []

	for _i in range(32):
		var query := PhysicsRayQueryParameters3D.create(from, to, collision_mask, excludes)
		query.collide_with_bodies = true
		query.collide_with_areas = true
		var hit: Dictionary = space_state.intersect_ray(query)
		if hit.is_empty():
			return {}

		var collider := hit.get("collider") as Node
		if collider != null and _should_ignore_hit(collider):
			var rid: RID = hit.get("rid", RID())
			if rid.is_valid():
				excludes.append(rid)
				continue
		return hit

	return {}


func _should_ignore_hit(node: Node) -> bool:
	if _is_ignored_by_name(node):
		return true
	return _is_area_only_collision(node)


func _is_ignored_by_name(node: Node) -> bool:
	var current: Node = node
	while current != null:
		var lowered := String(current.name).to_lower()
		for fragment in _IGNORED_NAME_FRAGMENTS:
			if lowered.contains(fragment):
				return true
		current = current.get_parent()
	return false


func _is_area_only_collision(node: Node) -> bool:
	var collision_obj := _find_collision_object(node)
	if collision_obj == null:
		return false

	var layer: int = collision_obj.collision_layer
	var interactive_mask: int = (
		LivingConstants.LIVING_3DMODEL_FRONT_FACE_COLLISION_LAYER
		| 1
	)
	if (layer & interactive_mask) != 0:
		return false

	var area_mask: int = (
		LivingConstants.LIVING_3DMODEL_TRIGGER_COLLISION_LAYER
		| LivingConstants.LIVING_3DMODEL_VOLUME_COLLISION_LAYER
	)
	return (layer & area_mask) != 0


func _find_collision_object(node: Node) -> CollisionObject3D:
	var current: Node = node
	while current != null:
		if current is CollisionObject3D:
			return current as CollisionObject3D
		current = current.get_parent()
	return null
