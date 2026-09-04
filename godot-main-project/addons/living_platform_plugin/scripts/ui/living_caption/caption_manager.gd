extends Resource

class_name CaptionManager

## Offset with respect to the viewpoint (circle) center
## X shifts the HUD laterally; Z sets the depth. Y+ is up.
const HUD_OFFSET: Vector3 = Vector3(0, 1.3, 1.0)
## The scale of the HUD, applied on instantiation to all axes
const HUD_SCALE: float = 1.5
## Font size for the floating HUD (short caption)
const HUD_FONT_SIZE: int = 8
## Depth of the font used on the HUD
const HUD_FONT_DEPTH: float = LivingCaption.DEFAULT_FONT_DEPTH
## Default color of caption text
const CAPTION_FONT_COLOR := LivingCaption.DEFAULT_TEXT_COLOR

## Offset of the caption, with respect to the _camera, at the moment of visualization
const LONG_CAPTION_OFFSET: Vector3 = Vector3(-2, 1.4, 0)
## Y-rotation of the caption, with respect to the _camera, at the moment of visualization
const LONG_CAPTION_Y_ROT_OFFSET: float = 90.0  # degrees

## Time used by the short caption to reach its target position
const SHORT_CAPTION_TWEENING_TIME: float = 1.5
## Time used by the long caption to reach its target position
const LONG_CAPTION_TWEENING_TIME: float = 1.8

@export_group("DISTANCES")
## The max distance used for ray casting when looking for the objects in front of the viewer
@export var raycast_distance: float = 50.0
## Minimum distance from the object viewpoint to activate the text
@export var text_activation_distance: float = 1.0
## range after which long caption disappears.
@export var text_deactivation_distance: float = 1.5


@export_group("OFFSETS AND SIZES")
## Font size for the floating HUD
@export var hud_font_size: float = HUD_FONT_SIZE
## The depth of the font used on the HUD
@export var hud_font_depth: float = HUD_FONT_DEPTH
## Time (seconds) before switching to the new line
@export var hud_line_delay_s: float = 3
## Time (seconds) to wait before switching the HUD to a new target (debounce)
@export var hud_switch_delay_s: float = 0.5

@export_group("")

@export var caption_font_color := CAPTION_FONT_COLOR


## The camera in use. Needed to: i) append the HUD, ii) compute the absolute positions for the long caption.
var _camera: LivingCameraTextVision = null

## The element described
var _captioned_element: LivingItem = null



func _init(camera: LivingCameraTextVision) -> void:
	_camera = camera
	
	if not Engine.is_editor_hint():

		# timer HUD
		if _hud_timer == null:
			_hud_timer = Timer.new()
			_hud_timer.one_shot = false
			_hud_timer.autostart = false
			camera.add_child(_hud_timer)
			_hud_timer.timeout.connect(_on_hud_timer_timeout)


func _process(_delta: float):

	# If not element captions are visible, then look for one.
	if _captioned_element == null:

		var ray_picked_list := _camera.raycast_all_in_group(LivingConstants.RAY_PICKABLE_GROUP_NAME, LivingConstants.RAY_PICK_BLOCK_VIEW_GROUP_NAME, self.raycast_distance)

		var ray_picked: LivingItem = null

		if not ray_picked_list.is_empty():

			# raycast_all_in_group() excludes each hit RID before re-casting, so hits
			# are returned in increasing distance order — the first entry is the closest.
			ray_picked = ray_picked_list[0]

		# Special case: if the item is a playing video, treat as nothing.
		if ray_picked != null and ray_picked.participatory_item_type == LivingConstants.PARTICIPATORY_TYPE_VIDEO:
			var children = ray_picked.find_children("*", "LivingVideo", false, false)
			if children.size() == 1:
				var lv := children[0] as LivingVideo
				if not lv.is_paused():
					ray_picked = null
			else:
				assert(false, "There should be only 1 child of type LivingVideo in %s" % self.name)

		if ray_picked != null:

			if ray_picked is not LivingVisitableObject: return
			var visitable_target = ray_picked as LivingVisitableObject

			var visit_center := visitable_target.get_visit_transform().origin
			var dist = LivingUtils.floor_distance(visit_center, self._camera.global_position)

			if dist < text_activation_distance:

				var target = ray_picked

				if not target.short_description.strip_edges().is_empty() and target.visible and _item_allows_short_caption(target):

					_captioned_element = target

					# Reveal the short textr
					_show_hud_3d_and_reveal(visitable_target)

					# Reveal also the LONG text
					self.create_long_caption(visitable_target)

					# Mark the item as "visited" in the event manager
					LivingEventManager.notify_item_visited(target.item_id)

	else:
		# A caption is already visible
		# Check the distance to see if we have to hide something

		assert (_captioned_element != null)

		assert (_captioned_element is LivingVisitableObject)
		var visitable_target = _captioned_element as LivingVisitableObject
		var visit_center := visitable_target.get_visit_transform().origin

		var distance_from_visit_point = LivingUtils.floor_distance(visit_center, self._camera.global_position)

		# If the camera walks too much away from the caption, remove it.
		if distance_from_visit_point > text_deactivation_distance:
			print("Off distance %s from %s --> Hiding CAPTION" % [distance_from_visit_point, _captioned_element.name])

			_captioned_element = null

			# Close the long text description
			_destroy_long_caption()

			# And close also the HUD
			_hide_hud_3d()



func _item_allows_short_caption(item: LivingItem) -> bool:
	if item is LivingVisitableObject:
		return (item as LivingVisitableObject).show_caption
	return true


#
# SHORT caption management
#

## The actual instance of object showing the HUD. If this is null, no HUD is visible.
var _hud_text_3d: LivingCaptionHud = null
var _hud_lines: PackedStringArray = []
var _hud_line_index: int = 0
var _hud_reveal_running: bool = false
var _hud_accumulated: String = ""
var _hud_timer: Timer = null


## Function computing the absolute position of the short text (ex-HUD) visualizing the item info.
## Returns a 2-size array with [global_pos: Vector3, global_y_rot_degrees: float]
static func compute_short_caption_abs_position(item: LivingVisitableObject):
	var visit_transform := item.get_visit_transform()
	var global_pos: Vector3 = visit_transform * HUD_OFFSET
	var global_y_rot: float = rad_to_deg(visit_transform.basis.get_euler().y) + 180
	return [global_pos, global_y_rot]


## Function computing the absolute position of the long text visualizing the item info.
## Returns a 2-size array with [global_pos: Vector3, global_y_rot_degrees: float]
static func compute_long_caption_abs_position(item: LivingVisitableObject):
	var visit_transform := item.get_visit_transform()
	var global_pos: Vector3 = visit_transform * LONG_CAPTION_OFFSET
	var global_y_rot: float = rad_to_deg(visit_transform.basis.get_euler().y) + LONG_CAPTION_Y_ROT_OFFSET
	return [global_pos, global_y_rot]


func _is_hud_visible() -> bool:

	return _hud_text_3d != null


func _show_hud_3d_and_reveal(item: LivingVisitableObject) -> void:

	# And close also the HUD
	if _is_hud_visible():
		_hide_hud_3d()

	assert (_hud_text_3d == null)


	_hud_text_3d = LivingCaptionHud.new(false)
	_hud_text_3d.name = "LivingCaptionHud"
	# Very small initial scale, but not 0 — otherwise internal AABB computation crashes.
	_hud_text_3d.scale = Vector3(0.01, 0.01, 0.01)
	
	#
	# Short text as standing sign

	# Reference to the actual rendering camera. To get the exact position of the viewer.
	var real_cam: Node3D = _camera.camera
	var start_global_pos = real_cam.global_position + (_camera.global_transform.basis) * _caption_starting_offset_pos
	# Compute the global y rotation
	var start_global_y_rot = real_cam.global_rotation_degrees.y + _caption_starting_offset_y_rot

	# Add as child now, so we can get/set global coords.
	_camera.get_tree().current_scene.add_child(_hud_text_3d)
	# set_font_size/set_font_depth call _update_geometries() → get_node_aabb(), which requires
	# the node to already be in the scene tree — so they must come after add_child().
	_hud_text_3d.set_font_size(hud_font_size)
	_hud_text_3d.set_font_depth(hud_font_depth)

	_hud_text_3d.clicked.connect(_on_hud_input_event)

	#
	_hud_text_3d.global_position = start_global_pos
	_hud_text_3d.global_rotation_degrees = Vector3(0.0, start_global_y_rot, 0.0)


	#
	# Compute the global ending position and rotation of the panel
	var target_global_location = compute_short_caption_abs_position(item)
	var target_global_pos: Vector3 = target_global_location[0]
	var target_global_y_rot: float = target_global_location[1]


	# Play the dedicated sound
	LivingSceneManager.get_current_scene().play_sound(LivingConstants.AUDIO_SHORT_TEXT_IN)

	# Perform the tweening
	var tween := _hud_text_3d.create_tween().set_parallel(true)
	tween.tween_property(_hud_text_3d, "position", target_global_pos, SHORT_CAPTION_TWEENING_TIME)
	tween.tween_property(_hud_text_3d, "scale", Vector3(HUD_SCALE, HUD_SCALE, HUD_SCALE), SHORT_CAPTION_TWEENING_TIME)
	tween.tween_property(_hud_text_3d, "global_rotation_degrees", Vector3(0, target_global_y_rot, 0), SHORT_CAPTION_TWEENING_TIME)


	#
	# Get the short description text and initilize the rendering timer
	var txt := item.short_description
	_hud_lines = txt.split("\n", false)
	_hud_line_index = 0

	_hud_reveal_running = true

	# mostra subito la prima riga/frase
	_on_hud_timer_timeout()

	# avvia loop
	if _hud_timer:
		_hud_timer.stop()
		_hud_timer.wait_time = hud_line_delay_s
		_hud_timer.start()


func _hide_hud_3d() -> void:
	_hud_reveal_running = false
	if _hud_timer:
		_hud_timer.stop()
	if _hud_text_3d:

		# Play the dedicated sound
		LivingSceneManager.get_current_scene().play_sound(LivingConstants.AUDIO_SHORT_TEXT_OUT)

		# start hiding the object
		# _hud_text_3d.queue_free()
		_hud_text_3d.fade_out()
		_hud_text_3d = null


func _on_hud_timer_timeout() -> void:

	if not _hud_reveal_running:
		return
	if not _is_hud_visible:
		return
	if _hud_text_3d == null:
		return
	if _hud_lines.size() == 0:
		_hud_text_3d.set_text("")
		return

	# loop continuo
	if _hud_line_index >= _hud_lines.size():
		_hud_line_index = 0

	var line := _hud_lines[_hud_line_index].strip_edges()
	_hud_line_index += 1

	# mostra SOLO la riga corrente (no concatenazione)
	_hud_text_3d.set_text(line)


func _on_hud_input_event() -> void:
	print("HUD input")
	if _captioned_element:
		print("HUD clicked for: ", _captioned_element.name)

		# self.hud_clicked.emit(_hud_closest_element)
		self.create_long_caption(_captioned_element)



#
# LONG CAPTION MANAGEMENT
#

## The object displaying the text and its background
var _long_caption_obj: LivingCaptionLong = null

## Variables for the Long Caption animation
var _caption_starting_offset_pos: Vector3 = Vector3(0, 0, -1)
var _caption_starting_scale: Vector3 = Vector3(0.05, 0.05, 0.05)
var _caption_starting_offset_y_rot: float = 0.0


func _on_long_caption_closing_event():
	_destroy_long_caption()


func _is_long_caption_visible():
	
	return self._long_caption_obj != null


func create_long_caption(item: LivingVisitableObject) -> void:

	# If another description was already visible, eliminate it.
	if _is_long_caption_visible():
		_destroy_long_caption()


	var text = item.long_description
	var catalog_text = item.catalog_description

	if text == null:
		text = ""

	text = text.strip_edges()
	
	_long_caption_obj = LivingCaptionLong.new(false, catalog_text)

	# Register the callback when user wants to close the long caption
	_long_caption_obj.closing_requested.connect(_on_long_caption_closing_event)

	# Add the object to the current scene so it is freed when the scene changes
	_camera.get_tree().current_scene.add_child(self._long_caption_obj)

	# Set text and other properties
	_long_caption_obj.set_text(text)
	_long_caption_obj.set_text_color(caption_font_color)

	# Reference to the actual rendering camera. To get the exact position of the viewer.
	var real_cam: Node3D = _camera.camera

	#
	# Compute the global starting position and rotation according to the camera pos/rot
	var start_global_pos: Vector3 = real_cam.global_position + (_camera.global_transform.basis) * _caption_starting_offset_pos

	# Compute the global y rotation
	var start_global_y_rot = real_cam.global_rotation_degrees.y + _caption_starting_offset_y_rot

	_long_caption_obj.global_position = start_global_pos
	_long_caption_obj.global_rotation_degrees = Vector3(0.0, start_global_y_rot, 0.0)
	_long_caption_obj.scale = _caption_starting_scale

	#
	# Compute the global ending position and rotation of the panel
	var target_global_location = compute_long_caption_abs_position(item)
	var target_global_pos: Vector3 = target_global_location[0]
	var target_global_y_rot: float = target_global_location[1]


	# Play the dedicated sound
	LivingSceneManager.get_current_scene().play_sound(LivingConstants.AUDIO_LONG_TEXT_IN)

	#
	# Start the tweenings (all run in parallel)
	var tween = _long_caption_obj.create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_parallel(true)
	tween.tween_property(_long_caption_obj, "global_position", target_global_pos, LONG_CAPTION_TWEENING_TIME)
	tween.tween_property(_long_caption_obj, "scale", Vector3(1,1,1), LONG_CAPTION_TWEENING_TIME)
	tween.tween_property(_long_caption_obj, "global_rotation_degrees", Vector3(0, target_global_y_rot, 0), LONG_CAPTION_TWEENING_TIME)


func _destroy_long_caption() -> void:

	if self._long_caption_obj != null:
		# Play the dedicated sound
		LivingSceneManager.get_current_scene().play_sound(LivingConstants.AUDIO_LONG_TEXT_OUT)
		self._long_caption_obj.fade_out()
		self._long_caption_obj = null
