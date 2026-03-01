extends Resource

class_name CaptionManager

## The camera controlling and updating this manager
var camera: LivingCamera = null

## The object displaying the text and its background
var caption_obj: LivingCaption = null


@export_group("DISTANCES")
## minimum distance from an object to activate the caption
@export var min_distance: float = 3.0
## hysteresis range to avoid jerky on/off effects
@export var hysteresis: float = 1.0

@export_group("OFFSETS")
## Offset of the caption, with respect to the camera, at the moment of visualization
@export var caption_offset_pos: Vector3 = Vector3(1, 0, -2)
## Y-rotation of the caption, with respect to the camera, at the moment of visualization
@export var caption_offset_y_rot: float = -30  # degrees


@export_group("DIMENSIONS")
@export var caption_center_height: float = 1.7
@export var caption_max_width: float = 2.0
@export var caption_max_height: float = 2.5


var _closest_element: LivingElement = null


func _init(camera: LivingCamera) -> void:
	self.camera = camera
	
	#self.caption_obj = living_caption_scene.instantiate()


func _process(delta: float):
	
	var res = camera.scan_for_closest_visible_element()
	var closest_element: LivingElement = res[0]
	var distance: float = res[1]

	if closest_element != _closest_element:
		print("New Closest element %s at distance %s  -> Hiding CAPTION" % [closest_element, distance])
		_closest_element = closest_element
		# _hide_description_node()

	var off_distance = min_distance + hysteresis

	if _is_caption_visible():
		
		if _closest_element == null:
			print("No closest element -> Hiding CAPTION")
			_destroy_description_node()
		# Check if we need to hide the HUD.
		elif distance >= off_distance:
			print("Off distance %s from %s --> Hiding CAPTION" % [distance, _closest_element.name])
			_destroy_description_node()
	else:
		# Check if we need to show the HUD
		if _closest_element != null:
			if distance <= min_distance:
				print("Showing CAPTION for %s at distance %s with text '%s'" % [_closest_element.name, distance, _closest_element.long_description])
				_create_description_node(_closest_element.long_description)


func _is_caption_visible():
	
	return caption_obj != null


func _create_description_node(text: String) -> void:

	if text == null:
		text = ""

	text = text.strip_edges()
	
	self.caption_obj = LivingCaptionLong.new(false)  #living_caption_scene.instantiate()
	camera.get_tree().root.add_child(self.caption_obj)

	caption_obj.set_text(text)
	caption_obj.set_text_color(Color(0.9, 0.9, 0.9))

	var description_aabb = LivingUtils.get_node_aabb(caption_obj)
	
	if description_aabb.size.x > caption_max_width or description_aabb.size.y > caption_max_height:
		var x_scale = caption_max_width / description_aabb.size.x
		var y_scale = caption_max_height / description_aabb.size.y
		var min_scale = min(x_scale, y_scale)
	
		description_aabb = LivingUtils.scale_aabb_around_center(description_aabb, min_scale)
		caption_obj.scale = Vector3(min_scale, min_scale, min_scale)
	
	#var caption_rotation := Vector3(0.0, caption_initial_y_rotation, 0.0)

	# Rotate the offset vector by the current camera global rotation
	var global_pos: Vector3 = camera.global_position + (camera.global_transform.basis) * caption_offset_pos
	# Elevate the description to the floor
	# Strong assumption that the floor is always at 0 height
	global_pos.y = global_pos.y + (description_aabb.size.y / 2.0)
	# Add the camera y-rotation offset
	var global_y_rot = camera.global_rotation_degrees.y + caption_offset_y_rot
	
	# print("CAM POS ", camera.global_position, " ROT ", camera.global_rotation)
	# print("COMPUTED CAPTION POS ", global_pos, " Y-ROT ", global_y_rot)
	#print("CAMERA GLOBAL ROT: ", camera.global_rotation_degrees.y)
	#print("SETTING: ", global_y_rot)
	
	caption_obj.global_position = global_pos
	caption_obj.global_rotation_degrees = Vector3(0.0, global_y_rot, 0.0)
	

func _destroy_description_node() -> void:

	if self.caption_obj != null:
		self.caption_obj.queue_free()
		self.caption_obj = null
