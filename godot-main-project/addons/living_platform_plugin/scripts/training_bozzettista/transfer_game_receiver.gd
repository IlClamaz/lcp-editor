extends Area3D
class_name TransferGameReceiver

@export var receiver_group: StringName = &"transfer_game_receiver"
@export var receiver_key: String = ""

var transfer_game: TransferGameController
var _receiving_disabled: bool = false


func _ready() -> void:
	add_to_group(receiver_group)
	input_ray_pickable = true


func _input_event(_camera: Node, event: InputEvent, _event_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if _receiving_disabled or transfer_game == null:
		return
	if not (event is InputEventMouseButton):
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return
	transfer_game.handle_receiver_click(self)


func is_receiving_enabled() -> bool:
	return not _receiving_disabled


func disable_receiving() -> void:
	if _receiving_disabled:
		return
	_receiving_disabled = true
	monitoring = false
	monitorable = false
	collision_layer = 0
	collision_mask = 0
	var parent := get_parent()
	if parent != null:
		parent.visible = false
	for child in get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = true
