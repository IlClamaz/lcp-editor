extends Area3D
class_name TransferGameReceiver

@export var receiver_group: StringName = &"transfer_game_receiver"
@export var receiver_key: String = ""


func _ready() -> void:
	add_to_group(receiver_group)
