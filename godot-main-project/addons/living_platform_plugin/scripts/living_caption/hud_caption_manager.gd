extends Resource

class_name HudManager

var camera: LivingCamera = null

@export_group("DISTANCES")
## The max distance used for ray casting when looking for the objects in front of the viewer
@export var raycast_distance: float = 50.0

@export_group("OFFSETS AND SIZES")
## Offset in front of the camera (negative Z --> forward in camera space)
## The y axis is measured from the floor
@export var hud_offset: Vector3 = Vector3(0, 1.5, -0.8)
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


## Keeps track of what was the last selected object at the previous _process() cycle
var _hud_closest_element: LivingItem = null

## The actual instance of object showing the HUD. If this is null, no HUD is visible.
var _hud_text_3d: LivingCaptionHud = null
var _hud_lines: PackedStringArray = []
var _hud_line_index: int = 0
var _hud_reveal_running: bool = false
var _hud_accumulated: String = ""
var _hud_timer: Timer = null


signal hud_clicked(LivingItem)


func _init(camera: LivingCamera) -> void:
	self.camera = camera
	
	if not Engine.is_editor_hint():

		# timer HUD
		if _hud_timer == null:
			_hud_timer = Timer.new()
			_hud_timer.one_shot = false
			_hud_timer.autostart = false
			camera.add_child(_hud_timer)
			_hud_timer.timeout.connect(_on_hud_timer_timeout)


func _process(delta: float):
	

	var ray_picked_list := camera.raycast_all_in_group(LivingConstants.RAY_PICKABLE_GROUP_NAME, self.raycast_distance)
	# print("Ray cast on (%s)" % ray_picked_list.size(), ray_picked_list)

	# If we watch nothing, just hide the HUD
	if ray_picked_list.is_empty():

		if _is_hud_visible():
			_hide_hud_3d()

		_hud_closest_element = null

	else:

		var stepping_on_items = camera.get_stepping_on_items().duplicate()  # Get a copyof the list of items on which we are stepping
		# print("BEFORE Steppping on items (%s): " % stepping_on_items.size(), stepping_on_items)

		## Remove from stepping_on_items all parent objects up in the hierarchy
		## Use the function get_parent() to understand if an item in the list is parent of another.
		## So that, after removal, none of the remaning items is ancestor of another
		# The implementation iterates stepping_on_items and for each candidate checks whether any other item in the list has it as an ancestor (by walking up get_parent() chains). If so, the candidate is removed; only the most-derived (leaf) items remain.
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

		# print("AFTER Steppping on items (%s): " % stepping_on_items.size(), stepping_on_items)

		# Scan the ray_picked_list and select the first element that is also in the stepping_on_items list
		var ray_picked: LivingItem = null
		for item in ray_picked_list:
			if item in stepping_on_items:
				ray_picked = item
				break

		if ray_picked == null:

			if _is_hud_visible():
				_hide_hud_3d()
			
			_hud_closest_element = null

		else:
			assert (ray_picked in stepping_on_items)

			if ray_picked != _hud_closest_element:

				if _is_hud_visible():
					_hide_hud_3d()

				_hud_closest_element = ray_picked
				# print("Showing HUD for %s with text '%s'" % [_hud_closest_element.name, _hud_closest_element.short_description])
				_show_hud_3d_and_reveal()

			else:
				# Nothing to do. The currently shown HUD is for the object still ray picked on which the camera is stepping
				assert (ray_picked != null)
				assert (ray_picked == _hud_closest_element)
				assert (_hud_closest_element in stepping_on_items)


func _old_process(delta: float):
	

	var ray_picked := camera.raycast_closest_in_group(LivingConstants.RAY_PICKABLE_GROUP_NAME, self.raycast_distance)
	# print("Ray cast on %s" % (ray_picked.name if ray_picked != null else "none"))

	# If we watch nothing, just hide the HUD
	if ray_picked == null:

		if _is_hud_visible():
			_hide_hud_3d()

		_hud_closest_element = null

	else:

		var stepping_on_items = camera.get_stepping_on_items()

		if ray_picked not in stepping_on_items:

			if _is_hud_visible():
				_hide_hud_3d()
			
			_hud_closest_element = null

		else:

			if ray_picked != _hud_closest_element:

				if _is_hud_visible():
					_hide_hud_3d()

				_hud_closest_element = ray_picked
				# print("Showing HUD for %s with text '%s'" % [_hud_closest_element.name, _hud_closest_element.short_description])
				_show_hud_3d_and_reveal()

			else:
				# Nothing to do. The currently shown HUD is for the object still ray picked on which the camera is stepping
				assert (ray_picked != null)
				assert (ray_picked == _hud_closest_element)
				assert (_hud_closest_element in stepping_on_items)


func _is_hud_visible() -> bool:
	return _hud_text_3d != null


func _show_hud_3d_and_reveal() -> void:

	if _hud_text_3d == null:

		# we will first position the HUD on the camera hirizonal level,
		# and later animate it to go to the desired offset.
		# Otherwise its reveal might be missed
		var frontal_hud_offset = Vector3(hud_offset.x, 1.7, hud_offset.z)

		_hud_text_3d = LivingCaptionHud.new(false)
		_hud_text_3d.name = "LivingCaptionHud"
		#_hud_text_3d.position = hud_offset
		_hud_text_3d.position = frontal_hud_offset
		# _hud_text_3d.scale = Vector3(hud_scale, hud_scale, hud_scale)
		_hud_text_3d.scale = Vector3(0.01, 0.01, 0.01)  # Very small, but not 0.0, otherwise the automatic computation of the internal text scale crashes.
		_hud_text_3d.rotation_degrees = Vector3(self.hud_x_rot_degs, 0.0, 0.0)

		camera.add_child(_hud_text_3d)

		# set_font_size/set_font_depth call _update_geometries() → get_node_aabb(), which requires
		# the node to already be in the scene tree — so they must come after add_child().
		_hud_text_3d.set_font_size(hud_font_size)
		_hud_text_3d.set_font_depth(hud_font_depth)

		_hud_text_3d._click_area.input_event.connect(_on_hud_input_event)

		# Start the tweening to move the HUD to the hud_offset position
		#  and a second parallel tweening to scale the hud to the specified hud_scale
		var tween := camera.create_tween().set_parallel(true)
		tween.tween_property(_hud_text_3d, "position", hud_offset, 1.0)
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
