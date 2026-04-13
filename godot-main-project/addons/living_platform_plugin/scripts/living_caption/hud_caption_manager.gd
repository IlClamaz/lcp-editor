extends Resource

class_name HudManager

var camera: LivingCamera = null

@export_group("DISTANCES")
## The max distance used for ray casting when looking for the objects in front of the viewer
@export var raycast_distance: float = 7.0

@export_group("OFFSETS AND SIZES")
## Offset in fron of the calera (negative Z --> forward in camera space)
@export var hud_offset: Vector3 = Vector3(0, 1.4, -0.8)
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


## Keeps track of what was the last selected object at the previous process cycle
var _hud_closest_element: LivingItem = null

## The actual instance of object showing the HUD. If this is null, no HUD is visible.
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
	

	var ray_picked := camera.raycast_closest_in_group(LivingConstants.RAY_PICKABLE_GROUP_NAME, self.raycast_distance)

	if ray_picked != _hud_closest_element:
		# print("RAYCAST PICKED NEW OBJECT: ", ray_picked.name if ray_picked != null else "None")

		if _is_hud_visible():
			_hide_hud_3d()

		_hud_closest_element = ray_picked

	if _hud_closest_element != null:
		
		if not _is_hud_visible():
		
			# print("Showing HUD for %s with text '%s'" % [_hud_closest_element.name, _hud_closest_element.short_description])
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
		_hud_text_3d.scale = Vector3(hud_scale, hud_scale, hud_scale)
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
