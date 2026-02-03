extends StaticBody3D


var player: LivingVideo = null

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var p = get_parent()
	if p is LivingVideo:
		player = p
	else:
		push_error("Parent is not of type LivingVideo.")


func _input_event(_camera: Node, event: InputEvent, event_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	
	print("Input for Video Control: ", event)
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var my_name = self.name
		print("I (%s) was clicked at %s." % [my_name, event_position])

		if my_name == "PlayButton":
			print("Play")
			player.play_media_video()
		elif my_name == "PauseButton":
			print("Pause")
			player.toggle_pause()
		elif my_name == "StopButton":
			print("Stop")
			player.stop_video()
