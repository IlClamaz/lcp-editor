extends StaticBody3D


@onready var player: LivingVideo = $"../../"
@onready var _button_text_mesh_instance: MeshInstance3D = $"MeshInstance3D"

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	
	assert (player is LivingVideo, "The 2-level parent should be the video player")

	assert (_button_text_mesh_instance is MeshInstance3D)

	# Update button labels once the video player is ready.
	self.player.video_initialized.connect(_on_video_initialized)
	print("Connecting %s to _on_pause_toggled()" % name)
	self.player.pause_toggled.connect(_on_pause_toggled)


func _on_video_initialized():

	_update_button_names()


func _on_pause_toggled():

	# print("_on_pause_toggled() on %s" % name )
	_update_button_names()


func _input_event(_camera: Node, event: InputEvent, event_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	
	# print("Input for Video Control: ", event)
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var my_name = self.name
		# print("(%s) was clicked at %s." % [my_name, event_position])

		if my_name == "PlayPauseButton":
			print("Video Control: button name is PlayPauseButton")
			player.toggle_pause()
		elif my_name == "SkipBackButton":
			print("Video Control: button name is SkipBackButton")
			player.seek_video(0)
	
	_update_button_names()

## Update the text of the buttons accoridng to standard symbols
## See: https://en.wikipedia.org/wiki/Media_control_symbols
func _update_button_names():

	var text_mesh = _button_text_mesh_instance.mesh as TextMesh

	if self.name == "PlayPauseButton":
		
		var play_icon := find_child("play_icon", false) as MeshInstance3D
		var pause_icon := find_child("pause_icon", false) as MeshInstance3D

		if player.is_paused():
			# text_mesh.text = ">"
			# text_mesh.text = "\u23F5"
			play_icon.visible = true
			pause_icon.visible = false
		else:
			# text_mesh.text = "||"
			# text_mesh.text = "\u23F8"
			play_icon.visible = false
			pause_icon.visible = true

		
	elif self.name == "SkipBackButton":
		# text_mesh.text = "|<<"
		# text_mesh.text = "\u23EE"
		
		var skipback_icon := find_child("skipback_icon", false) as MeshInstance3D
		skipback_icon.visible = true
