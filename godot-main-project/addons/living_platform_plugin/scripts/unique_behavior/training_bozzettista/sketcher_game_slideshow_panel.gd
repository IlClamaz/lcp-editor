extends StaticBody3D

var sketcher_game: SketcherGameController


func _ready() -> void:
	input_ray_pickable = true


func _input_event(_camera: Node, event: InputEvent, _event_position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return
	if sketcher_game == null:
		return
	sketcher_game.handle_slideshow_panel_click()
