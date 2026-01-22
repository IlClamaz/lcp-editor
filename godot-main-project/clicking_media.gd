extends StaticBody3D

func _input_event(_camera: Node, event: InputEvent, event_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		print("Cube clicked at ", event_position)  # Replace with your action, e.g., queue_free()

		# Instantiate a new Living object
		var new_item: LivingMedia = LivingMedia.new()
		get_tree().current_scene.add_child(new_item, true)

		# Set the ID and get main info
		new_item.media_id = 6
		print("Fetching omeka info for media ID ", new_item.media_id)
		new_item.fetch_omeka_info()
		

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass
