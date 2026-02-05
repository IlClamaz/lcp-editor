extends StaticBody3D


var player: LivingVideo = null

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var p = get_parent()
	assert (p is Node3D, "Parent node should be a simple Node3D")
	assert (p.name == "Controls", "Parent node should be the Controls node")
	
	p = p.get_parent()
	
	assert (p is LivingVideo, "The 2-level paretn should be the video player")

	player = p


func _input_event(_camera: Node, event: InputEvent, event_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	
	# print("Input for Video Control: ", event)
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var my_name = self.name
		print("(%s) was clicked at %s." % [my_name, event_position])

		if my_name == "PlayButton":
			print("Play")
			player.play_media_video()
		elif my_name == "PauseButton":
			print("Pause")
			player.toggle_pause()
		elif my_name == "StopButton":
			print("Stop")
			player.stop_video()
