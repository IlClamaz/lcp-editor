extends Resource

class_name CaptionManager

@export_group("DISTANCES")
## hysteresis range to avoid jerky on/off effects
@export var caption_off_distance: float = 10.0

@export_group("OFFSETS")
## Offset of the caption, with respect to the _camera, at the moment of visualization
@export var caption_offset_pos: Vector3 = Vector3(3.5, 0, -2.5)
## Y-rotation of the caption, with respect to the _camera, at the moment of visualization
@export var caption_offset_y_rot: float = -90.0  # degrees

@export_group("")

@export var font_color := Color(0.9, 0.9, 0.9)

var _caption_starting_offset_pos: Vector3 = Vector3(0, 0, -3)
var _caption_starting_scale: Vector3 = Vector3(0.1, 0.1, 0.1)
var _caption_starting_offset_y_rot: float = 0.0

## The _camera controlling and updating this manager
var _camera: LivingCameraTextVision = null
## The object displaying the text and its background
var _caption_obj: LivingCaption = null
## The element described
var _captioned_element: LivingItem = null


func _init(camera: LivingCameraTextVision) -> void:
	self._camera = camera


func _process(delta: float):

	# If a caption is still visible
	if _is_caption_visible():

		var distance_from_caption = LivingUtils.floor_distance(self._caption_obj.global_position, self._camera.global_position)

		# print("Caption distance from camera: ", distance_from_caption)

		# If the camera walks too much away from the caption, remove it.
		if distance_from_caption > caption_off_distance:
			print("Off distance %s from %s --> Hiding CAPTION" % [distance_from_caption, self._caption_obj.name])
			_destroy_description_object()


func _is_caption_visible():
	
	assert ((self._caption_obj == null and self._captioned_element == null)
			or (self._caption_obj != null and self._captioned_element != null))
			
	return self._caption_obj != null


func create_description_object(living_item: LivingItem) -> void:

	# If the description for this element is already present, just keep it
	if living_item == _captioned_element:
		return

	# If another description was already visible, eliminate it.
	if _is_caption_visible():
		_destroy_description_object()


	var text = living_item.long_description
	var catalog_text = living_item.catalog_description

	if text == null:
		text = ""

	text = text.strip_edges()
	
	_captioned_element = living_item
	_caption_obj = LivingCaptionLong.new(false, catalog_text)

	# Add the object to the scene at top level
	_camera.get_tree().root.add_child(self._caption_obj)

	# Set text and other properties
	_caption_obj.set_text(text)
	_caption_obj.set_text_color(font_color)

	#
	# Compute the global starting position and rotation according to the camera pos/rot
	# Rotate the offset vector by the current _camera global rotation
	var start_global_pos: Vector3 = _camera.global_position + (_camera.global_transform.basis) * _caption_starting_offset_pos
	# Vertically align the description background to stay on front of the camera.
	# Strong assumption that the floor is always at 0 height.
	var description_aabb = LivingUtils.get_node_aabb(_caption_obj)
	start_global_pos.y = start_global_pos.y + (description_aabb.size.y / 2.0)
	# Compute the global y rotation
	var start_global_y_rot = _camera.global_rotation_degrees.y + _caption_starting_offset_y_rot

	_caption_obj.global_position = start_global_pos
	_caption_obj.global_rotation_degrees = Vector3(0.0, start_global_y_rot, 0.0)
	_caption_obj.scale = _caption_starting_scale

	#
	# Comput the global ending position and rotation of the panel
	# Rotate the offset vector by the current _camera global rotation
	var global_pos: Vector3 = _camera.global_position + (_camera.global_transform.basis) * caption_offset_pos
	# Put the panel center at the height of the camera position on the floor + gthe eyes standard height.
	global_pos.y = _camera.global_position.y + _camera.get_default_eye_height()
	# Add the _camera y-rotation offset
	var global_y_rot = _camera.global_rotation_degrees.y + caption_offset_y_rot
	
	# print("COMPUTED CAPTION POS ", global_pos, " Y-ROT ", global_y_rot)
	# print("CAMERA GLOBAL ROT: ", _camera.global_rotation_degrees.y)
	# print("ROTATION FROM: ", start_global_y_rot, " --> " , global_y_rot)
	
	# _caption_obj.global_position = global_pos
	# _caption_obj.global_rotation_degrees = Vector3(0.0, global_y_rot, 0.0)

	#
	# Start the tweenings (all run in parallel)
	var tween = _caption_obj.create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_parallel(true)
	tween.tween_property(_caption_obj, "global_position", global_pos, 1.0)
	tween.tween_property(_caption_obj, "scale", Vector3(1,1,1), 1.0)
	tween.tween_property(_caption_obj, "global_rotation_degrees", Vector3(0, global_y_rot, 0), 1.0)


func _destroy_description_object() -> void:

	if self._caption_obj != null:
		self._caption_obj.fade_out()
		self._caption_obj = null
		self._captioned_element = null
