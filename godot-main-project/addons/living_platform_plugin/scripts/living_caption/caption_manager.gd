extends Resource

class_name CaptionManager


@export_group("DISTANCES")
## The max distance used for ray casting when looking for the objects in front of the viewer
@export var raycast_distance: float = 50.0
## range after which long caption disappears.
@export var long_caption_off_distance: float = 5.0

@export_group("OFFSETS")
## Offset in front of the camera (negative Z --> forward in camera space).
## X shifts the HUD laterally; Z sets the depth. Y is ignored — computed automatically from the camera FOV.
@export var hud_offset: Vector3 = Vector3(0, 0, -0.8)
## Extra gap (meters) between the HUD bottom and the screen bottom edge
@export var hud_bottom_margin: float = 0.02
## Offset of the caption, with respect to the _camera, at the moment of visualization
@export var long_caption_offset: Vector3 = Vector3(2, 0, -1)
## Y-rotation of the caption, with respect to the _camera, at the moment of visualization
@export var long_caption_rot_offset: float = -90.0  # degrees


@export_group("OFFSETS AND SIZES")
## The scale of the HUD, applied on instantiation to all axes
@export var hud_scale: float = 0.5
## The rotation (degrees) of the HUD around the X axis, to better oriant to the observer
@export var hud_x_rot_degs: float = 0.0
## Font size for the floating HUD
@export var hud_font_size: float = 8
## The depth of the font used on the HUD
@export var hud_font_depth: float = 0.002
## Time (seconds) before switching to the new line
@export var hud_line_delay_s: float = 3
## Time (seconds) to wait before switching the HUD to a new target (debounce)
@export var hud_switch_delay_s: float = 0.5

@export_group("")

@export var caption_font_color := Color(0.9, 0.9, 0.9)


## The camera in use. Needed to: i) append the HUD, ii) compute the absolute positions for the long caption.
var _camera: LivingCameraTextVision = null

## Keeps track of what was the last selected object at the previous _process() cycle
var _hud_closest_element: LivingItem = null
## The element described
var _captioned_element: LivingItem = null


## The object displaying the text and its background
var _long_caption_obj: LivingCaptionLong = null


## The actual instance of object showing the HUD. If this is null, no HUD is visible.
var _hud_text_3d: LivingCaptionHud = null
var _hud_lines: PackedStringArray = []
var _hud_line_index: int = 0
var _hud_reveal_running: bool = false
var _hud_accumulated: String = ""
var _hud_timer: Timer = null
var _hud_debounce_timer: Timer = null
## The element we want the HUD to show; may differ from _hud_closest_element during debounce
var _hud_desired_element: LivingItem = null


var _caption_starting_offset_pos: Vector3 = Vector3(0, 0, -1)
var _caption_starting_scale: Vector3 = Vector3(0.05, 0.05, 0.05)
var _caption_starting_offset_y_rot: float = 0.0


signal hud_clicked(LivingItem)


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

		# debounce timer — delays HUD show/hide on target change
		if _hud_debounce_timer == null:
			_hud_debounce_timer = Timer.new()
			_hud_debounce_timer.one_shot = true
			_hud_debounce_timer.autostart = false
			camera.add_child(_hud_debounce_timer)
			_hud_debounce_timer.timeout.connect(_on_hud_debounce_timeout)


func _process(_delta: float):

	var ray_picked_list := _camera.raycast_all_in_group(LivingConstants.RAY_PICKABLE_GROUP_NAME, LivingConstants.RAY_PICK_BLOCK_VIEW_GROUP_NAME, self.raycast_distance)

	var ray_picked: LivingItem = null

	if not ray_picked_list.is_empty():

		var stepping_on_items = _camera.get_stepping_on_items().duplicate()

		# Remove ancestor items so only the most-derived (leaf) items remain.
		var i := 0
		while i < stepping_on_items.size():
			var candidate: LivingItem = stepping_on_items[i]
			var is_ancestor := false
			for other in stepping_on_items:
				if other == candidate:
					continue
				var node: Node = other.get_parent()
				while node != null:
					if node == candidate:
						is_ancestor = true
						break
					node = node.get_parent()
				if is_ancestor:
					break
			if is_ancestor:
				stepping_on_items.remove_at(i)
			else:
				i += 1

		for item in ray_picked_list:
			if item in stepping_on_items:
				ray_picked = item
				break

		# Special case: if the item is a playing video, treat as nothing.
		if ray_picked != null and ray_picked.medium_type == LivingItem.MediumType.VIDEO:
			var children = ray_picked.find_children("*", "LivingVideo", false, false)
			if children.size() == 1:
				var lv := children[0] as LivingVideo
				if not lv.is_paused():
					ray_picked = null
			else:
				assert(false, "There should be only 1 child of type LivingVideo in %s" % self.name)

	_set_desired_hud(ray_picked)

	# If a long caption is still visible
	if _is_long_caption_visible():

		var distance_from_caption = LivingUtils.floor_distance(self._long_caption_obj.global_position, self._camera.global_position)

		# If the camera walks too much away from the caption, remove it.
		if distance_from_caption > long_caption_off_distance:
			print("Off distance %s from %s --> Hiding CAPTION" % [distance_from_caption, self._long_caption_obj.name])
			_destroy_long_caption()


func _set_desired_hud(element: LivingItem) -> void:
	if element == _hud_desired_element:
		return
	_hud_desired_element = element
	if _hud_debounce_timer:
		_hud_debounce_timer.stop()
		_hud_debounce_timer.wait_time = hud_switch_delay_s
		_hud_debounce_timer.start()


func _on_hud_debounce_timeout() -> void:
	var target := _hud_desired_element

	if target == _hud_closest_element:
		return

	if _is_hud_visible():
		_hide_hud_3d()

	_hud_closest_element = target

	if target != null and _captioned_element == null:
		_show_hud_3d_and_reveal()
		# Mark the item as "visited" in the scene manager
		LivingSceneManager.get_current_scene().mark_item_as_visited(_hud_closest_element)


func _is_hud_visible() -> bool:

	return _hud_text_3d != null


func _show_hud_3d_and_reveal() -> void:

	if _hud_text_3d == null:

		_hud_text_3d = LivingCaptionHud.new(false)
		_hud_text_3d.name = "LivingCaptionHud"
		# Very small initial scale, but not 0 — otherwise internal AABB computation crashes.
		_hud_text_3d.scale = Vector3(0.01, 0.01, 0.01)
		_hud_text_3d.rotation_degrees = Vector3(self.hud_x_rot_degs, 0.0, 0.0)

		_camera.camera.add_child(_hud_text_3d)

		# set_font_size/set_font_depth call _update_geometries() → get_node_aabb(), which requires
		# the node to already be in the scene tree — so they must come after add_child().
		_hud_text_3d.set_font_size(hud_font_size)
		_hud_text_3d.set_font_depth(hud_font_depth)

		# Compute Y so the HUD bottom sits just above the screen bottom edge.
		# The formula uses perspective: at depth d the visible half-height = d * tan(fov/2).
		# Works for the default KEEP_HEIGHT projection; hud_offset.y is intentionally unused.
		# The formula assumes Camera3D.keep_aspect = KEEP_HEIGHT (vertical FOV = cam.fov),
		# which is Godot's default. If you ever switch to KEEP_WIDTH,
		# the vertical FOV would need to be derived from the aspect ratio — but for standard and XR use that's not needed.
		var d: float = absf(hud_offset.z)
		var half_screen_h: float = d * tan(deg_to_rad(_camera.camera.fov / 2.0))
		var bg_aabb: AABB = LivingUtils.get_node_aabb(_hud_text_3d.background)
		var hud_half_h: float = bg_aabb.size.y * hud_scale / 2.0
		
		if _camera.camera.name == "XRCamera3D": hud_bottom_margin = 0.3 # TO FIX!!!
		var target_pos := Vector3(hud_offset.x, -half_screen_h + hud_half_h + hud_bottom_margin, hud_offset.z)

		_hud_text_3d.position = target_pos

		_hud_text_3d._click_body.input_event.connect(_on_hud_input_event)

		# Play the dedicated sound
		LivingSceneManager.get_current_scene().play_sound(LivingConstants.AUDIO_SHORT_TEXT_IN)

		var tween := _hud_text_3d.create_tween().set_parallel(true)
		tween.tween_property(_hud_text_3d, "position", target_pos, 1.0)
		tween.tween_property(_hud_text_3d, "scale", Vector3(hud_scale, hud_scale, hud_scale), 1.0)


	var txt := _hud_closest_element.short_description
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


func _on_hud_input_event(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _hud_closest_element:
			print("HUD clicked for: ", _hud_closest_element.name)

			self.hud_clicked.emit(_hud_closest_element)



#
# LONG CAPTION MANAGEMENT
#

func _on_long_caption_closing_event():
	_destroy_long_caption()


func _is_long_caption_visible():
	
	return self._long_caption_obj != null


func create_long_caption(item: LivingItem) -> void:

	# If the item is already described, just leave it.
	if item == _captioned_element:
		return

	# If another description was already visible, eliminate it.
	if _is_long_caption_visible():
		_destroy_long_caption()

	_captioned_element = item


	var text = _captioned_element.long_description
	var catalog_text = _captioned_element.catalog_description

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
	# Rotate the offset vector by the current _camera global rotation
	var start_global_pos: Vector3
	if _hud_text_3d != null:
		start_global_pos = _hud_text_3d.global_position
		print("LONG text start pos ", start_global_pos)
	else:
		start_global_pos = real_cam.global_position + (_camera.global_transform.basis) * _caption_starting_offset_pos

	# Compute the global y rotation
	var start_global_y_rot = real_cam.global_rotation_degrees.y + _caption_starting_offset_y_rot

	_long_caption_obj.global_position = start_global_pos
	_long_caption_obj.global_rotation_degrees = Vector3(0.0, start_global_y_rot, 0.0)
	_long_caption_obj.scale = _caption_starting_scale

	#
	# Compute the global ending position and rotation of the panel
	# Rotate the offset vector by the current _camera global rotation
	var global_pos: Vector3 = real_cam.global_position + (real_cam.global_transform.basis) * long_caption_offset
	# Add the _camera y-rotation offset
	var global_y_rot = real_cam.global_rotation_degrees.y + long_caption_rot_offset
	
	# print("COMPUTED CAPTION POS ", global_pos, " Y-ROT ", global_y_rot)
	# print("CAMERA GLOBAL ROT: ", _camera.global_rotation_degrees.y)
	# print("ROTATION FROM: ", start_global_y_rot, " --> " , global_y_rot)
	
	# _long_caption_obj.global_position = global_pos
	# _long_caption_obj.global_rotation_degrees = Vector3(0.0, global_y_rot, 0.0)

	# If we show a long text, we must be sure that the short one disappears
	_hide_hud_3d()

	# Play the dedicated sound
	LivingSceneManager.get_current_scene().play_sound(LivingConstants.AUDIO_LONG_TEXT_IN)

	#
	# Start the tweenings (all run in parallel)
	var tween = _long_caption_obj.create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_parallel(true)
	tween.tween_property(_long_caption_obj, "global_position", global_pos, 1.0)
	tween.tween_property(_long_caption_obj, "scale", Vector3(1,1,1), 1.0)
	tween.tween_property(_long_caption_obj, "global_rotation_degrees", Vector3(0, global_y_rot, 0), 1.0)


func _destroy_long_caption() -> void:

	if self._long_caption_obj != null:
		# Play the dedicated sound
		LivingSceneManager.get_current_scene().play_sound(LivingConstants.AUDIO_LONG_TEXT_OUT)
		self._long_caption_obj.fade_out()
		self._long_caption_obj = null
		self._captioned_element = null
