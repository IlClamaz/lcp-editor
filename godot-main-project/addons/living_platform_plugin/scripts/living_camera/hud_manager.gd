extends Resource

class_name HudManager

var camera: LivingCamera = null

## minimum distance from an object to activate the hud
@export var hud_distance_m: float = 5.0
## hysteresis range to avoid jerky on/off effects
@export var hysteresis_m: float = 1.0


# HUD configuration
## Offset in fron of the calera (negative Z --> forward in camera space)
@export var hud_offset: Vector3 = Vector3(0, 1.5, -1.2)
## Font size for the floating HUD
@export var hud_font_size: float = 10
## Time (seconds) before switching to the new line
@export var hud_line_delay_s: float = 3
## If the text line goes above this size, the text object will be scaled down
@export var hud_max_width: float = 2.0


var _hud_closest_element: LivingElement = null

var _hud_text_3d: LivingText = null
var _hud_lines: PackedStringArray = []
var _hud_line_index: int = 0
var _hud_reveal_running: bool = false
var _hud_accumulated: String = ""
var _hud_timer: Timer = null



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
	
	#
	# SCAN ALL OBJECTS IN THE SCENE AND FIND THE CLOSEST ONE
	var living_elements_in_scene := camera.get_tree().get_nodes_in_group(LivingConstants.LIVING_ELEMENTS_GROUP_NAME)

	var distances: Array[float] = []

	# print("LivingElements in scene: ", living_elements_in_scene.size())
	for element in living_elements_in_scene:
		# By construvtion, this must be a LivingElement
		assert (element is LivingElement)
		# print(element.name)
		
		var projected_global_position = Vector3(element.global_position.x, 0.0, element.global_position.z)
		var projected_cam_position = Vector3(camera.global_position.x, 0.0, camera.global_position.z)
		var d := projected_global_position.distance_to(projected_cam_position)

		distances.append(d)
	
	assert (living_elements_in_scene.size() == distances.size())
	
	# Get reference to the closest LivingElement
	var closest_id := LivingUtils.argmin(distances)
	var closest_element = null
	var distance = -1
	if closest_id != -1:
		closest_element = living_elements_in_scene[closest_id]
		distance = distances[closest_id]
		
	# print("Closest Element is %s at distance %s" % [_hud_closest_element.name, distance])

	if closest_element != _hud_closest_element:
		print("New Closest element %s at distance %s  -> Hiding HUD" % [closest_element, distance])
		_hud_closest_element = closest_element
		_hide_hud_3d()

	#
	# SHOW/HIDE THE HUD ACCORDING THE THE DISTANCES
	var hud_on_dist := hud_distance_m
	var hud_off_dist := hud_distance_m + hysteresis_m
	
	if _is_hud_visible():
		
		if _hud_closest_element == null:
			print("No closest element -> Hiding HUD")
			_hide_hud_3d()
		# Check if we need to hide the HUD.
		elif distance >= hud_off_dist:
			print("Off distance %s from %s --> Hiding HUD" % [distance, _hud_closest_element.name])
			_hide_hud_3d()
	else:
		# Check if we need to show the HUD
		if _hud_closest_element != null:
			if distance <= hud_on_dist:
				print("Showing HUD for %s at distance %s with text '%s'" % [_hud_closest_element.name, distance, _hud_closest_element.short_description])
				_show_hud_3d_and_reveal()

func _is_hud_visible() -> bool:
	return _hud_text_3d != null

func _show_hud_3d_and_reveal() -> void:

	if _hud_text_3d == null:
		_hud_text_3d = LivingText.new(false)
		_hud_text_3d.name = "LivingHUDText"
		camera.add_child(_hud_text_3d)
		
		_hud_text_3d.set_font_size(hud_font_size)
		_hud_text_3d.set_alpha(1.0)
		_hud_text_3d.set_depth(0.03)
		_hud_text_3d.position = hud_offset

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
		_hud_text_3d.queue_free()
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
	
	# After setting the text, we can know its size
	_hud_text_3d.scale = Vector3(1.0, 1.0, 1.0)
	var hud_text_aabb = LivingUtils.get_node_aabb(_hud_text_3d)
	if hud_text_aabb.size.x > self.hud_max_width:
		var text_scale = self.hud_max_width / hud_text_aabb.size.x
		_hud_text_3d.scale.x = text_scale # = Vector3(text_scale, text_scale, text_scale)
