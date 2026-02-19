@tool
extends LivingItem

class_name LivingElement


@export_group("DESCRIPTION")
@export var long_description_center_height: float = 1.7
@export var long_description_max_width: float = 2.0
@export var long_description_max_height: float = 2.5
# Probabilmente conviene mettere globali queste variabili??
# Distanze per il controllo dinamico della visualizzazione dei caption
@export var hud_distance_m: float = 5.0
@export var long_distance_m: float = 3.0
@export var catalog_distance_m: float = 1.0
@export var hysteresis_m: float = 0.15

# HUD configuration
## Offset in fron of the calera (negative Z --> forward in camera space)
@export var hud_offset: Vector3 = Vector3(0, 1.5, -1.2)
## Font size for the floating HUD
@export var hud_font_size: float = 10
## If the text line goes above this size, the text object will be scaled down
@export var hud_max_width: float = 2.0
@export var hud_line_delay_s: float = 3

# @export var component1: TestNodeComponent 


# Set any of the given flags from the editor.
@export_flags(LivingConstants.ITEM_VISIBILITY_PRE_STR, LivingConstants.ITEM_VISIBILITY_POST_STR) var visibility: int = LivingConstants.ItemVisibility.PRE_EXPERIENCE | LivingConstants.ItemVisibility.POST_EXPERIENCE


# INTERNAL STATE FOR CAPTION CONTROL
enum CaptionMode { OFF, HUD, LONG, CATALOG}
var _caption_mode: CaptionMode = CaptionMode.OFF
var _xr_cam: Node3D = null
var _hud_text_3d: LivingText = null
var _hud_lines: PackedStringArray = []
var _hud_line_index: int = 0
var _hud_reveal_running: bool = false
var _hud_accumulated: String = ""
var _hud_timer: Timer = null



#func _init():
	#if component1 == null:
		#component1 = TestNodeComponent.new(self)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	print("LivingElement '%s' Ready." % [self.name])

	if not Engine.is_editor_hint():

		# timer HUD
		if _hud_timer == null:
			_hud_timer = Timer.new()
			_hud_timer.one_shot = false
			_hud_timer.autostart = false
			add_child(_hud_timer)
			_hud_timer.timeout.connect(_on_hud_timer_timeout)

		call_deferred("_resolve_living_camera") # Defer the camera resolution to ensure that all nodes are ready and in place, especially if the camera is added later in the scene tree.

# Forse conviene che ci sia un manager che tiene il riferimento alla camera, invece di cercarla ogni volta. Per ora, cerco la camera al ready e se non c'è, mostro un errore e disabilito l'HUD.
func _resolve_living_camera() -> void:
	_xr_cam = _find_living_camera()
	if _xr_cam == null:
		push_error("LivingCamera not found (group living_camera empty).")
		return
	set_process(true)

func _find_living_camera() -> Node3D:
	# Cerca un nodo con class_name LivingCamera
	var nodes := get_tree().get_nodes_in_group("living_camera")
	if nodes.size() > 0:
		return nodes[0] as Node3D
	return null


func _find_first_by_type(n: Node, type_name: String) -> Node:
	if n == null:
		return null
	if n.is_class(type_name):
		return n
	for c in n.get_children():
		var r := _find_first_by_type(c, type_name)
		if r != null:
			return r
	return null


func _process(_delta: float) -> void:
	
	# component1.test_function()
	
	if Engine.is_editor_hint():
		return
	if _xr_cam == null:
		return

	var projected_global_position = Vector3(global_position.x, 0.0, global_position.z)
	var projected_cam_position = Vector3(_xr_cam.global_position.x, 0.0, _xr_cam.global_position.z)
	var d := projected_global_position.distance_to(projected_cam_position)
	#if self.name.begins_with("Maciste sulla"):
		#print(global_position, _xr_cam.global_position)
		#print("Distance between %s and %s: \t%s" % [self.name, _xr_cam.name, str(d)])

	var hud_on := hud_distance_m
	var hud_off := hud_distance_m + hysteresis_m

	var long_on := long_distance_m
	var long_off := long_distance_m + hysteresis_m

	var catalog_on := catalog_distance_m
	var catalog_off := catalog_distance_m + hysteresis_m

	match _caption_mode:
		CaptionMode.OFF:
			if d <= catalog_on:
				_set_caption_mode(CaptionMode.CATALOG)
			elif d <= long_on:
				_set_caption_mode(CaptionMode.LONG)
			elif d <= hud_on:
				_set_caption_mode(CaptionMode.HUD)

		CaptionMode.HUD:
			_update_hud_transform()
			if d <= catalog_on:
				_set_caption_mode(CaptionMode.CATALOG)
			elif d <= long_on:
				_set_caption_mode(CaptionMode.LONG)
			elif d >= hud_off:
				_set_caption_mode(CaptionMode.OFF)

		CaptionMode.LONG:
			if d <= catalog_on:
				_set_caption_mode(CaptionMode.CATALOG)
			elif d > long_off and d <= hud_on:
				_set_caption_mode(CaptionMode.HUD)
			elif d > hud_off:
				_set_caption_mode(CaptionMode.OFF)

		CaptionMode.CATALOG:
			# se ti allontani un po' torna LONG, poi HUD, poi OFF
			if d > catalog_off and d <= long_on:
				_set_caption_mode(CaptionMode.LONG)
			elif d > long_off and d <= hud_on:
				_set_caption_mode(CaptionMode.HUD)
			elif d > hud_off:
				_set_caption_mode(CaptionMode.OFF)


func _set_caption_mode(new_mode: CaptionMode) -> void:
	if new_mode == _caption_mode:
		return

	# exit
	match _caption_mode:
		CaptionMode.HUD:
			_hide_hud_3d()
		CaptionMode.LONG, CaptionMode.CATALOG:
			_destroy_description_node()

	_caption_mode = new_mode

	# enter
	match _caption_mode:
		CaptionMode.OFF:
			pass

		CaptionMode.HUD:
			# print("HUD MODE")
			_destroy_description_node()
			_show_hud_3d_and_reveal()

		CaptionMode.LONG:
			# print("LONG DESCRIPTION MODE")
			_hide_hud_3d()
			create_description_node(long_description, DESCRIPTION_SIDE_RIGHT) # sinistra

		CaptionMode.CATALOG:
			# print("CATALOG MODE")
			_hide_hud_3d()
			create_description_node(catalog_description, DESCRIPTION_SIDE_RIGHT) # destra

	

func set_visible(v: bool):
	for c in get_children():
		if c is LivingItem:
			(c as LivingItem).visible = v


#var description_text: LivingText = null
var description_text: LivingCaption = null


#
# LONG + CATALOG TEXT VISUALIZATION
#
const DESCRIPTION_SIDE_LEFT := -1
const DESCRIPTION_SIDE_RIGHT := +1

func create_description_node(text: String, side: int) -> void:

	_destroy_description_node()	
	assert (description_text == null)

	# print("CREATING LONG DESCRIPTION FOR ", self.name)

	if text == null or text.strip_edges() == "":
		return

	# This will be the AABB of this self object
	var combined_aabb: AABB = LivingUtils.get_node_aabb(self)
	var combined_aabb_center: Vector3 = combined_aabb.position + combined_aabb.size * 0.5

	# description_text = LivingText.new(false)
	description_text = living_caption_scene.instantiate()
	
	add_child(description_text)
	description_text.set_text(text)
	description_text.set_text_color(Color(0.9, 0.9, 0.9))
	# description_text.set_background_color(Color(0.18, 0.18, 0.18, 1.0))


	# var description_aabb = description_text.get_aabb()
	var description_aabb = LivingUtils.get_node_aabb(description_text)
	
	if description_aabb.size.x > long_description_max_width or description_aabb.size.y > long_description_max_height:
		var x_scale = long_description_max_width / description_aabb.size.x
		var y_scale = long_description_max_height / description_aabb.size.y
		var min_scale = min(x_scale, y_scale)
	
		description_aabb = LivingUtils.scale_aabb_around_center(description_aabb, min_scale)
		description_text.scale = Vector3(min_scale, min_scale, min_scale)
	
	# Compute to watch the text ortogonal on the right side
	# Strong assumption that the floor is always at 0 height
	var description_offset := Vector3(
		combined_aabb_center.x + (combined_aabb.size.x / 2.0) ,
		long_description_center_height - self.position.y,
		combined_aabb_center.z + (combined_aabb.size.z / 2.0) + (description_aabb.size.x / 2)
	)
	var description_rotation := Vector3(0.0, -90.0, 0)

	# Adjust for the left/right side
	description_offset.x = float(side) * description_offset.x
	description_rotation.y = float(side) * description_rotation.y

	# print("COMBINED AABB: ", combined_aabb)
	# print("COMBINED CENTER: ", combined_aabb_center)
	# print("OFFSET: ", description_offset)
	# print("ROT: ", description_rotation)
	
	description_text.position = description_offset
	description_text.rotation_degrees = description_rotation


func _destroy_description_node() -> void:

	if description_text:
		# print("DESTROYING LONG DESCRIPTION FOR ", self.name)
		description_text.free()
		description_text = null


#
# SHORT TEXT (HUD) VISUALIZATION
#

func _show_hud_3d_and_reveal() -> void:
	if _xr_cam == null:
		# se non c'è camera, niente HUD
		return

	if _hud_text_3d == null:
		_hud_text_3d = LivingText.new(false)
		_hud_text_3d.name = "LivingHUDText"
		_xr_cam.add_child(_hud_text_3d)
		
		_hud_text_3d.set_font_size(hud_font_size)
		_hud_text_3d.set_alpha(1.0)
		_hud_text_3d.set_depth(0.03)
		_update_hud_transform()
		_hud_text_3d.position = hud_offset

	var txt := short_description
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


func _update_hud_transform() -> void:
	if _hud_text_3d == null:
		return

	# Not really needed.
	# Reminder, if we need to transform the hud position in real-time, it might fight with the rescaling due to text width.
	# _hud_text_3d.transform = Transform3D(Basis.IDENTITY, hud_offset)


func _on_hud_timer_timeout() -> void:
	if not _hud_reveal_running:
		return
	if _caption_mode != CaptionMode.HUD:
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
