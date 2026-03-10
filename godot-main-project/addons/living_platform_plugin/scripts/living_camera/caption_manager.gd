extends Resource

class_name CaptionManager

## The camera controlling and updating this manager
var camera: LivingCamera = null

## The object displaying the text and its background
var caption_obj: LivingCaption = null


@export_group("DISTANCES")
## minimum distance from an object to activate the caption
@export var min_distance: float = 5.0
## hysteresis range to avoid jerky on/off effects
@export var caption_off_distance: float = 5.0
## The angle, in degrees, of the frontal slice where objects must be to be considered for captions.
@export var scan_angle_degs: float = 35.0

@export_group("OFFSETS")
## Offset of the caption, with respect to the camera, at the moment of visualization
@export var caption_offset_pos: Vector3 = Vector3(2.5, 0, -3)
## Y-rotation of the caption, with respect to the camera, at the moment of visualization
@export var caption_offset_y_rot: float = -30  # degrees

@export_group("")

@export var font_color := Color(0.9, 0.9, 0.9)



var _closest_element: LivingElement = null


func _init(camera: LivingCamera) -> void:
	self.camera = camera
	
	#self.caption_obj = living_caption_scene.instantiate()


func _process(delta: float):

	var res = camera.scan_for_closest_visible_element(deg_to_rad(scan_angle_degs))
	var new_closest_element: LivingElement = res[0]
	var distance_from_element: float = res[1]


	# Object changed
	#if new_closest_element != null and new_closest_element != _closest_element:
		#_destroy_description_node()

	if _is_caption_visible():
		# If a caption is still visible
		
		#if new_closest_element == null:
		#	print("No closest element -> Hiding CAPTION")
		#	_destroy_description_node()
		# Check if we need to hide the HUD.
		
		var caption_floor_pos = Vector3(self.caption_obj.global_position.x, 0.0, self.caption_obj.global_position.z)
		var camera_floor_pos = Vector3(self.camera.global_position.x, 0.0, self.camera.global_position.z)
		var distance_from_caption = caption_floor_pos.distance_to(camera_floor_pos)

		if distance_from_caption > caption_off_distance:
			print("Off distance %s from %s --> Hiding CAPTION" % [distance_from_caption, self.caption_obj.name])
			_destroy_description_node()
			_closest_element = null
	else:
		# Check if we need to show the HUD
		if new_closest_element != null:
			if distance_from_element < min_distance:
				print("Showing CAPTION for %s at distance %s with text '%s'" % [new_closest_element.name, distance_from_element, new_closest_element.long_description])
				_create_description_node(new_closest_element.long_description)
				_closest_element = new_closest_element

	#_closest_element = new_closest_element
	


func _is_caption_visible():
	
	return self.caption_obj != null


func _create_description_node(text: String) -> void:

	if text == null:
		text = ""

	text = text.strip_edges()
	
	self.caption_obj = LivingCaptionLong.new(false)  #living_caption_scene.instantiate()
	camera.get_tree().root.add_child(self.caption_obj)

	caption_obj.set_text(text)
	caption_obj.set_text_color(font_color)

	# Rotate the offset vector by the current camera global rotation
	var global_pos: Vector3 = camera.global_position + (camera.global_transform.basis) * caption_offset_pos
	# Vertically align the description background to lay on the floor.
	# Strong assumption that the floor is always at 0 height.
	var description_aabb = LivingUtils.get_node_aabb(caption_obj)
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
