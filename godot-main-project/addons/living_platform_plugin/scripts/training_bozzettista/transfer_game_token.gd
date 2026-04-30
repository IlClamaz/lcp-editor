extends Area3D
class_name TransferGameToken

signal consumed(receiver: Node)

@export var hold_anchor: Node3D
@export var hold_distance: float = 1.8
@export var visual_scale: float = 0.35
@export var source_key: String = ""
@export var receiver_group: StringName = &"transfer_game_receiver"
@export_flags_3d_physics var collision_layer_value: int = 1
@export_flags_3d_physics var collision_mask_value: int = 1

var _visual: MeshInstance3D
var _collision: CollisionShape3D
var _is_consumed: bool = false
var _touching_receivers: Dictionary = {}


func _ready() -> void:
	collision_layer = collision_layer_value
	collision_mask = collision_mask_value
	monitoring = true
	monitorable = true
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _physics_process(_delta: float) -> void:
	if _is_consumed:
		return
	if hold_anchor == null or not is_instance_valid(hold_anchor):
		return

	var target_pos := hold_anchor.global_position + (-hold_anchor.global_transform.basis.z * hold_distance)
	global_position = target_pos
	global_basis = hold_anchor.global_basis


func configure_from_source(source_image: LivingImage) -> void:
	if source_image == null:
		return

	_visual = MeshInstance3D.new()
	_visual.name = "Visual"
	if source_image.mesh != null:
		_visual.mesh = source_image.mesh.duplicate(true)
	if source_image.material_override != null:
		_visual.material_override = source_image.material_override.duplicate(true)
	_visual.scale = Vector3.ONE * visual_scale
	add_child(_visual)

	_collision = CollisionShape3D.new()
	_collision.name = "Collision"
	var shape := BoxShape3D.new()
	shape.size = _estimate_box_size()
	_collision.shape = shape
	add_child(_collision)


func _estimate_box_size() -> Vector3:
	if _visual == null or _visual.mesh == null:
		return Vector3.ONE * 0.35

	var aabb: AABB = _visual.mesh.get_aabb()
	var size := aabb.size * visual_scale
	size.x = max(size.x, 0.1)
	size.y = max(size.y, 0.1)
	size.z = max(size.z, 0.08)
	return size


func _on_area_entered(area: Area3D) -> void:
	_register_receiver_touch(area)


func _on_body_entered(body: Node3D) -> void:
	_register_receiver_touch(body)


func _on_area_exited(area: Area3D) -> void:
	_unregister_receiver_touch(area)


func _on_body_exited(body: Node3D) -> void:
	_unregister_receiver_touch(body)


func _register_receiver_touch(candidate: Node) -> void:
	if candidate == null:
		return

	var receiver := _find_receiver_node(candidate)
	if receiver == null:
		return

	_touching_receivers[receiver.get_instance_id()] = receiver


func _unregister_receiver_touch(candidate: Node) -> void:
	if candidate == null:
		return

	var receiver := _find_receiver_node(candidate)
	if receiver == null:
		return

	_touching_receivers.erase(receiver.get_instance_id())


func try_consume_if_touching() -> bool:
	if _is_consumed:
		return false

	for receiver in _touching_receivers.values():
		if receiver is Node and is_instance_valid(receiver):
			_consume(receiver)
			return true

	return false


func get_first_touching_receiver() -> TransferGameReceiver:
	for receiver in _touching_receivers.values():
		if receiver is TransferGameReceiver and is_instance_valid(receiver):
			return receiver as TransferGameReceiver
	return null


func consume_on_receiver(receiver: Node) -> void:
	if receiver == null:
		return
	_consume(receiver)


func _find_receiver_node(candidate: Node) -> Node:
	var node: Node = candidate
	while node != null:
		if node.is_in_group(receiver_group):
			return node
		node = node.get_parent()
	return null


func _consume(receiver: Node) -> void:
	if _is_consumed:
		return
	_is_consumed = true
	consumed.emit(receiver)
	queue_free()
