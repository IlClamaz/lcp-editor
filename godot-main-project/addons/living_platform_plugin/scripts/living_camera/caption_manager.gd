extends Resource

class_name CaptionManager

@export_group("DISTANCES")
## hysteresis range to avoid jerky on/off effects
@export var caption_off_distance: float = 10.0

@export_group("OFFSETS")
## Offset of the caption, with respect to the _camera, at the moment of visualization
@export var caption_offset_pos: Vector3 = Vector3(2.5, 0, -3)
## Y-rotation of the caption, with respect to the _camera, at the moment of visualization
@export var caption_offset_y_rot: float = -30  # degrees

@export_group("")

@export var font_color := Color(0.9, 0.9, 0.9)



## The _camera controlling and updating this manager
var _camera: LivingCamera = null
## The object displaying the text and its background
var _caption_obj: LivingCaption = null
## The element described
var _captioned_element: LivingElement = null


func _init(camera: LivingCamera) -> void:
	self._camera = camera
	
	#self._caption_obj = living_caption_scene.instantiate()


func _process(delta: float):

	# If a caption is still visible
	if _is_caption_visible():

		var distance_from_caption = LivingUtils.floor_distance(self._caption_obj.global_position, self._camera.global_position)

		# If the camera walks too much away from the caption, remove it.
		if distance_from_caption > caption_off_distance:
			print("Off distance %s from %s --> Hiding CAPTION" % [distance_from_caption, self._caption_obj.name])
			_destroy_description_object()


func _is_caption_visible():
	
	assert ((self._caption_obj == null and self._captioned_element == null)
			or (self._caption_obj != null and self._captioned_element != null))
			
	return self._caption_obj != null


func create_description_object(living_element: LivingElement) -> void:

	# If the descriptino for this element is already present, just keep it
	if living_element == _captioned_element:
		return

	# If another description was already visible, eli inate it.
	if _is_caption_visible():
		_destroy_description_object()


	var text = living_element.long_description

	if text == null:
		text = ""

	text = text.strip_edges()
	
	_captioned_element = living_element
	_caption_obj = LivingCaptionLong.new(false)

	# Add the object to the scene at top level
	_camera.get_tree().root.add_child(self._caption_obj)

	_caption_obj.set_text(text)
	_caption_obj.set_text_color(font_color)

	# Rotate the offset vector by the current _camera global rotation
	var global_pos: Vector3 = _camera.global_position + (_camera.global_transform.basis) * caption_offset_pos
	# Vertically align the description background to lay on the floor.
	# Strong assumption that the floor is always at 0 height.
	var description_aabb = LivingUtils.get_node_aabb(_caption_obj)
	global_pos.y = global_pos.y + (description_aabb.size.y / 2.0)
	# Add the _camera y-rotation offset
	var global_y_rot = _camera.global_rotation_degrees.y + caption_offset_y_rot
	
	# print("CAM POS ", _camera.global_position, " ROT ", _camera.global_rotation)
	# print("COMPUTED CAPTION POS ", global_pos, " Y-ROT ", global_y_rot)
	#print("CAMERA GLOBAL ROT: ", _camera.global_rotation_degrees.y)
	#print("SETTING: ", global_y_rot)
	
	_caption_obj.global_position = global_pos
	_caption_obj.global_rotation_degrees = Vector3(0.0, global_y_rot, 0.0)
	

func _destroy_description_object() -> void:

	if self._caption_obj != null:
		self._caption_obj.suicide()
		self._caption_obj = null
		self._captioned_element = null
