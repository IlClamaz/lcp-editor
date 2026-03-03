extends Resource

class_name HudManager

var camera: LivingCamera = null

@export_group("DISTANCES")
## minimum distance from an object to activate the hud
@export var hud_distance_m: float = 10.0
## hysteresis range to avoid jerky on/off effects
@export var hysteresis_m: float = 1.0
## The angle, in degrees, of the frontal slice where objects must be to be considered for captions.
@export var scan_angle_degs: float = 30.0



@export_group("OFFSETS AND SIZES")
## Offset in fron of the calera (negative Z --> forward in camera space)
@export var hud_offset: Vector3 = Vector3(0, 1.4, -0.8)
## The rotation (degrees) of the HUD around the X axis, to better oriant to the observer
@export var hud_x_rot_degs: float = -30.0
## Font size for the floating HUD
@export var hud_font_size: float = 8
## The depth of the font used on the HUD
@export var hud_font_depth: float = 0.002
## Time (seconds) before switching to the new line
@export var hud_line_delay_s: float = 3


var _hud_closest_element: LivingElement = null

var _hud_text_3d: LivingCaptionHud = null
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
	
	var res = camera.scan_for_closest_visible_element(deg_to_rad(scan_angle_degs))
	var closest_element: LivingElement = res[0]
	var distance: float = res[1]
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
		_hud_text_3d = LivingCaptionHud.new(false)
		_hud_text_3d.name = "LivingCaptionHud"
		camera.add_child(_hud_text_3d)
		
		_hud_text_3d.set_font_size(hud_font_size)
		_hud_text_3d.set_font_depth(hud_font_depth)
		_hud_text_3d.position = hud_offset
		
		_hud_text_3d.rotation_degrees = Vector3(self.hud_x_rot_degs, 0.0, 0.0)

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
